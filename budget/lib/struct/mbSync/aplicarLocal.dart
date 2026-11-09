import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/armazem.dart';
import 'package:budget/struct/mbSync/detectar.dart';
import 'package:budget/struct/mbSync/mapeamento.dart';
import 'package:budget/struct/mbSync/projetarLocal.dart';
import 'package:budget/struct/mbSync/registro.dart';
import 'package:drift/drift.dart';

const List<String> _ordemAplicar = [
  'categorias',
  'regras',
  'orcamentos',
  'metas',
  'dividas',
  'lancamentos',
  'assinaturas'
];

DateTime _proximoDia(int dia, DateTime hoje) {
  DateTime em(int ano, int mes) {
    final ultimo = DateTime(ano, mes + 1, 0).day;
    return DateTime(ano, mes, dia > ultimo ? ultimo : dia, 12);
  }

  final deste = em(hoje.year, hoje.month);
  return deste.isBefore(DateTime(hoje.year, hoje.month, hoje.day))
      ? em(hoje.year, hoje.month + 1)
      : deste;
}

// Grava os registros remotos vencedores direto no Drift (sem createOrUpdate*, para não
// gerar efeitos de orçamento compartilhado nem marcar a categoria como editada) e
// atualiza o espelho. Inclusões na ordem de dependência; exclusões na ordem inversa.
Future<void> mbAplicarRegistros(
    List<Registro> vencedores, Map<String, Espelho> espelho,
    {DateTime? agora}) async {
  final hoje = agora ?? DateTime.now();
  final ordenados = [...vencedores]
    ..sort((a, b) => _ordemAplicar
        .indexOf(a.tabela)
        .compareTo(_ordemAplicar.indexOf(b.tabela)));
  final vivos = ordenados.where((r) => r.deletedAt == null);
  final mortos = ordenados.where((r) => r.deletedAt != null).toList().reversed;
  final novos = <Espelho>[];
  final semPrefixo = mbIdsSemPrefixo([
    for (final e in espelho.values) e.registro,
    ...vencedores,
  ]);
  await database.transaction(() async {
    for (final r in vivos) {
      Projetado? p;
      final d = r.dados;
      if (d != null) {
        try {
          p = await _aplicar(r, d, espelho, hoje);
          if (p != null) p = mbReescreverIds(p, semPrefixo);
        } catch (e) {
          // Registro remoto inaplicável (dados fora do formato esperado): fica só no espelho.
          p = null;
        }
      }
      novos.add(Espelho(r, p?.dados, false, null));
    }
    for (final r in mortos) {
      await _apagar(r);
      novos.add(Espelho(r, null, false, null));
    }
    await mbGravarEspelho(novos);
  });
}

Future<Projetado?> _aplicar(Registro r, Map<String, dynamic> d,
    Map<String, Espelho> espelho, DateTime hoje) async {
  final modificado = Value<DateTime?>(DateTime.parse(r.updatedAt).toLocal());
  switch (r.tabela) {
    case 'categorias':
      return _categoria(r, d, modificado);
    case 'regras':
      return _regra(r, d, espelho, modificado);
    case 'orcamentos':
      return _orcamento(r, d, hoje, modificado);
    case 'metas':
    case 'dividas':
      return _objetivo(r, d, modificado);
    case 'lancamentos':
      return _lancamento(r, d, modificado);
    case 'assinaturas':
      return _assinatura(r, d, hoje, modificado);
  }
  return null;
}

Future<Projetado?> _categoria(
    Registro r, Map<String, dynamic> d, Value<DateTime?> modificado) async {
  final c = categoriaDeDados(r.id, d);
  final existente = await database.getCategoryInstanceOrNull(c.pk);
  final ordem = d['ordem'] != null
      ? c.ordem
      : existente?.order ?? await database.getAmountOfCategories();
  await database.into(database.categories).insertOnConflictUpdate(
      CategoriesCompanion(
        categoryPk: Value(c.pk),
        name: Value(c.nome),
        income: Value(c.receita),
        colour: Value(c.cor ?? existente?.colour),
        iconName: Value(c.icone ?? existente?.iconName ?? 'image.png'),
        mainCategoryPk: Value(c.paiPk),
        order: Value(ordem),
        dateTimeModified: modificado,
      ));
  return mbProjCategoria((await database.getCategoryInstanceOrNull(c.pk))!);
}

Future<Projetado?> _regra(Registro r, Map<String, dynamic> d,
    Map<String, Espelho> espelho, Value<DateTime?> modificado) async {
  final g = regraDeDados(r.id, d);
  if (g == null || await database.getCategoryInstanceOrNull(g.categoriaPk) == null) {
    return null;
  }
  final existente = await (database.select(database.associatedTitles)
        ..where((a) => a.associatedTitlePk.equals(g.pk)))
      .getSingleOrNull();
  await database.into(database.associatedTitles).insertOnConflictUpdate(
      AssociatedTitlesCompanion(
        associatedTitlePk: Value(g.pk),
        categoryFk: Value(g.categoriaPk),
        title: Value(g.titulo),
        isExactMatch: Value(g.exato),
        order: Value(existente?.order ??
            (await database.select(database.associatedTitles).get()).length),
        dateTimeModified: modificado,
      ));
  final gravado = await (database.select(database.associatedTitles)
        ..where((a) => a.associatedTitlePk.equals(g.pk)))
      .getSingle();
  return mbProjRegra(gravado, d);
}

Future<Projetado?> _orcamento(Registro r, Map<String, dynamic> d, DateTime hoje,
    Value<DateTime?> modificado) async {
  final o = orcamentoDeDados(r.id, d);
  final existente = await (database.select(database.budgets)
        ..where((b) => b.budgetPk.equals(o.pk)))
      .getSingleOrNull();
  final fks = o.categoriaPks == null || o.categoriaPks!.isEmpty
      ? null
      : o.categoriaPks;
  await database.into(database.budgets).insertOnConflictUpdate(BudgetsCompanion(
        budgetPk: Value(o.pk),
        name: Value(o.nome),
        amount: Value(o.valor),
        categoryFks: Value(fks),
        startDate: Value(existente?.startDate ?? DateTime(hoje.year, hoje.month, 1)),
        endDate: Value(existente?.endDate ??
            DateTime(hoje.year, hoje.month + 1, 0, 23, 59, 59)),
        periodLength: Value(existente?.periodLength ?? 1),
        reoccurrence: Value(existente?.reoccurrence ?? BudgetReoccurence.monthly),
        colour: Value(existente?.colour),
        order: Value(existente?.order ??
            (await database.select(database.budgets).get()).length),
        walletFk: Value(existente?.walletFk ?? '0'),
        dateTimeModified: modificado,
      ));
  return mbProjOrcamento((await (database.select(database.budgets)
        ..where((b) => b.budgetPk.equals(o.pk)))
      .getSingle()));
}

Future<Projetado?> _objetivo(
    Registro r, Map<String, dynamic> d, Value<DateTime?> modificado) async {
  final o = objetivoDeDados(r.id, d, divida: r.tabela == 'dividas');
  final existente = await (database.select(database.objectives)
        ..where((x) => x.objectivePk.equals(o.pk)))
      .getSingleOrNull();
  await database.into(database.objectives).insertOnConflictUpdate(
      ObjectivesCompanion(
        objectivePk: Value(o.pk),
        type: Value(o.divida ? ObjectiveType.loan : ObjectiveType.goal),
        name: Value(o.nome),
        amount: Value(o.valor),
        income: Value(o.receita),
        endDate: Value(o.prazo),
        order: Value(existente?.order ??
            (await database.select(database.objectives).get()).length),
        walletFk: Value(existente?.walletFk ?? '0'),
        dateTimeModified: modificado,
      ));
  return mbProjObjetivo((await (database.select(database.objectives)
        ..where((x) => x.objectivePk.equals(o.pk)))
      .getSingle()));
}

Future<String?> _primeiraCategoria(bool receita) async {
  final l = await (database.select(database.categories)
        ..where((c) => c.income.equals(receita) & c.mainCategoryPk.isNull())
        ..orderBy([(c) => OrderingTerm.asc(c.order)])
        ..limit(1))
      .get();
  return l.isEmpty ? null : l.first.categoryPk;
}

Future<Projetado?> _lancamento(
    Registro r, Map<String, dynamic> d, Value<DateTime?> modificado) async {
  final valor = (d['valor'] as num).toDouble();
  final receita = valor > 0;
  final padrao = await _primeiraCategoria(receita);
  final l = lancamentoDeDados(r.id, d, categoriaPadrao: padrao ?? '');
  var categoria = l.categoriaPk;
  if (await database.getCategoryInstanceOrNull(categoria) == null) {
    if (padrao == null) return null;
    categoria = padrao;
  }
  final carteiras = await database.select(database.wallets).get();
  final carteira = carteiras
          .where((w) => w.name == l.carteiraNome)
          .map((w) => w.walletPk)
          .firstOrNull ??
      '0';
  await database.into(database.transactions).insertOnConflictUpdate(
      TransactionsCompanion(
        transactionPk: Value(l.pk),
        name: Value(l.nome),
        amount: Value(l.valor),
        note: Value(l.nota),
        categoryFk: Value(categoria),
        walletFk: Value(carteira),
        dateCreated: Value(l.data),
        originalDateDue: Value(l.data),
        income: Value(receita),
        paid: const Value(true),
        objectiveFk: Value(l.metaPk),
        objectiveLoanFk: Value(l.dividaPk),
        dateTimeModified: modificado,
      ));
  final t = await (database.select(database.transactions)
        ..where((x) => x.transactionPk.equals(l.pk)))
      .getSingle();
  final nomeCarteira =
      carteiras.where((w) => w.walletPk == carteira).map((w) => w.name).firstOrNull ?? '';
  return mbProjLancamento(t, nomeCarteira);
}

Future<Projetado?> _assinatura(Registro r, Map<String, dynamic> d, DateTime hoje,
    Value<DateTime?> modificado) async {
  final padrao = await _primeiraCategoria(false);
  final a = assinaturaDeDados(r.id, d, categoriaPadrao: padrao ?? '');
  if (a == null) return null;
  var categoria = a.categoriaPk;
  if (await database.getCategoryInstanceOrNull(categoria) == null) {
    if (padrao == null) return null;
    categoria = padrao;
  }
  final existente = await (database.select(database.transactions)
        ..where((x) => x.transactionPk.equals(a.pk)))
      .getSingleOrNull();
  final data = existente != null && existente.dateCreated.day == a.dia
      ? existente.dateCreated
      : _proximoDia(a.dia, hoje);
  await database.into(database.transactions).insertOnConflictUpdate(
      TransactionsCompanion(
        transactionPk: Value(a.pk),
        name: Value(a.nome),
        amount: Value(-a.valor.abs()),
        note: Value(existente?.note ?? ''),
        categoryFk: Value(categoria),
        walletFk: Value(existente?.walletFk ?? '0'),
        dateCreated: Value(data),
        originalDateDue: Value(existente?.originalDateDue ?? data),
        income: const Value(false),
        paid: const Value(false),
        type: const Value(TransactionSpecialType.subscription),
        reoccurrence: const Value(BudgetReoccurence.monthly),
        periodLength: const Value(1),
        dateTimeModified: modificado,
      ));
  final t = await (database.select(database.transactions)
        ..where((x) => x.transactionPk.equals(a.pk)))
      .getSingle();
  return mbProjAssinatura(t);
}

Future<void> _apagar(Registro r) async {
  final pk = pkDoId(r.id);
  switch (r.tabela) {
    case 'categorias':
      if ((await database.getAllTransactionsFromCategory(pk)).isEmpty) {
        await (database.delete(database.categories)
              ..where((c) => c.categoryPk.equals(pk)))
            .go();
      }
    case 'regras':
      await (database.delete(database.associatedTitles)
            ..where((a) => a.associatedTitlePk.equals(pk)))
          .go();
    case 'orcamentos':
      await (database.delete(database.budgets)..where((b) => b.budgetPk.equals(pk)))
          .go();
    case 'metas':
    case 'dividas':
      await (database.update(database.transactions)
            ..where((t) => t.objectiveFk.equals(pk)))
          .write(const TransactionsCompanion(objectiveFk: Value(null)));
      await (database.update(database.transactions)
            ..where((t) => t.objectiveLoanFk.equals(pk)))
          .write(const TransactionsCompanion(objectiveLoanFk: Value(null)));
      await (database.delete(database.objectives)
            ..where((o) => o.objectivePk.equals(pk)))
          .go();
    case 'lancamentos':
    case 'assinaturas':
      await (database.delete(database.transactions)
            ..where((t) => t.transactionPk.equals(pk)))
          .go();
  }
}
