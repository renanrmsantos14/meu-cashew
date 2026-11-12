import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/detectar.dart';
import 'package:budget/struct/mbSync/mapeamento.dart';
import 'package:budget/struct/mbSync/metas.dart';
import 'package:budget/struct/mbSync/orcamentos.dart';
import 'package:budget/struct/mbSync/registro.dart';

String? mbEditadoEm(DateTime? d) => d == null || d.year < 2001 ? null : isoMs(d);

Projetado mbProjCategoria(TransactionCategory c) => Projetado(
    'categorias',
    idDoPk(c.categoryPk),
    projetarCategoria(CatLocal(
        pk: c.categoryPk,
        nome: c.name,
        receita: c.income,
        cor: c.colour,
        icone: c.iconName,
        paiPk: c.mainCategoryPk,
        ordem: c.order)),
    mbEditadoEm(c.dateTimeModified));

Projetado mbProjOrcamento(Budget b) => Projetado(
    'orcamentos',
    idDoPk(b.budgetPk),
    projetarOrcamento(OrcLocal(
        pk: b.budgetPk,
        nome: b.name,
        valor: b.amount,
        categoriaPks: b.categoryFks)),
    mbEditadoEm(b.dateTimeModified));

Projetado mbProjObjetivo(Objective o, {List<String> aplicacoes = const []}) {
  final divida = o.type == ObjectiveType.loan;
  return Projetado(
      divida ? 'dividas' : 'metas',
      idDoPk(o.objectivePk),
      projetarObjetivo(ObjLocal(
          pk: o.objectivePk,
          nome: o.name,
          divida: divida,
          receita: o.income,
          valor: o.amount,
          prazo: o.endDate,
          aplicacaoIds: aplicacoes)),
      mbEditadoEm(o.dateTimeModified));
}

Projetado mbProjLancamento(Transaction t, String carteiraNome,
        {Set<String>? orcamentos, bool limparOrcamentos = false}) =>
    Projetado(
    'lancamentos',
    idDoPk(t.transactionPk),
    projetarLancamento(LancLocal(
        pk: t.transactionPk,
        nome: t.name,
        nota: t.note,
        valor: t.amount,
        categoriaPk: t.categoryFk,
        carteiraNome: carteiraNome,
        data: t.dateCreated,
        metaPk: t.objectiveFk,
        dividaPk: t.objectiveLoanFk,
        orcamentoPks: orcamentos,
        limparOrcamentos: limparOrcamentos)),
    mbEditadoEm(t.dateTimeModified));

Projetado mbProjAssinatura(Transaction t) => Projetado(
    'assinaturas',
    idDoPk(t.transactionPk),
    projetarAssinatura(AssinLocal(
        pk: t.transactionPk,
        nome: t.name,
        valor: t.amount,
        dia: t.dateCreated.day,
        categoriaPk: t.categoryFk)),
    mbEditadoEm(t.dateTimeModified));

Projetado? mbProjRegra(
    TransactionAssociatedTitle a, Map<String, dynamic>? base) {
  final dados = projetarRegra(
      RegraLocal(
          pk: a.associatedTitlePk,
          titulo: a.title,
          categoriaPk: a.categoryFk,
          exato: a.isExactMatch),
      base);
  return dados == null
      ? null
      : Projetado('regras', idDoPk(a.associatedTitlePk), dados,
          mbEditadoEm(a.dateTimeModified));
}

// Ids remotos sem o prefixo `cashew:` (criados no painel) viram o pk local sem mudança (D2).
// Na projeção eles precisam voltar ao id original, senão o objeto pareceria novo e o original, excluído.
Set<String> mbIdsSemPrefixo(Iterable<Registro> registros) => {
      for (final r in registros)
        if (!r.id.startsWith(prefixoCashew)) r.id
    };

String mbIdLocal(String pk, Set<String> semPrefixo) =>
    semPrefixo.contains(pk) ? pk : idDoPk(pk);

Projetado mbReescreverIds(Projetado p, Set<String> semPrefixo) {
  if (semPrefixo.isEmpty) return p;
  String? ref(Object? v) => v is String ? mbIdLocal(pkDoId(v), semPrefixo) : null;
  final dados = {
    for (final e in p.dados.entries)
      e.key: switch (e.key) {
        'pai_id' || 'categoria_id' || 'meta_id' || 'divida_id' =>
          ref(e.value) ?? e.value,
        'categoria_ids' || 'orcamento_ids' when e.value is List => [
            for (final v in e.value as List) ref(v) ?? v
          ],
        _ => e.value,
      }
  };
  final id = p.tabela == 'ajustes' ? p.id : mbIdLocal(pkDoId(p.id), semPrefixo);
  return Projetado(p.tabela, id, dados, p.editadoEm);
}

bool mbEhLancamentoManual(Transaction t) =>
    !t.transactionPk.startsWith('mb:') &&
    (t.type == null ||
        t.type == TransactionSpecialType.credit ||
        t.type == TransactionSpecialType.debt);

// Projeta o estado atual do Drift. `espelho` fornece o padrão já conhecido das regras;
// `aplicado` (tx_pk -> categoria aplicada pelo sync) alimenta os ajustes de transações `mb:`.
// `existentes` recebe as chaves que continuam no Drift mas ficam fora da projeção (orçamento
// arquivado, transação de outro tipo): ausência nelas não pode virar tombstone.
Future<Map<String, Projetado>> mbProjetarLocal(
    Map<String, Espelho> espelho, Map<String, String> aplicado,
    {required String agora, Set<String>? existentes}) async {
  final out = <String, Projetado>{};
  final semPrefixo = mbIdsSemPrefixo([for (final e in espelho.values) e.registro]);
  void add(Projetado? p) {
    if (p != null) {
      final q = mbReescreverIds(p, semPrefixo);
      out[q.chave] = q;
    }
  }

  final carteiras = {
    for (final w in await database.select(database.wallets).get())
      w.walletPk: w.name
  };
  final cats = await database.select(database.categories).get();
  final catPorPk = {for (final c in cats) c.categoryPk: c};
  cats.forEach((c) => add(mbProjCategoria(c)));
  for (final a in await database.select(database.associatedTitles).get()) {
    add(mbProjRegra(a, espelho['regras/${mbIdLocal(a.associatedTitlePk, semPrefixo)}']?.registro.dados));
  }
  for (final b in await database.select(database.budgets).get()) {
    if (b.archived) {
      existentes?.add('orcamentos/${mbIdLocal(b.budgetPk, semPrefixo)}');
    } else {
      add(mbProjOrcamento(b));
    }
  }
  final aplicacoesPorMeta = await mbAplicacoesPorMeta();
  for (final o in await database.select(database.objectives).get()) {
    add(mbProjObjetivo(o, aplicacoes: aplicacoesPorMeta[o.objectivePk] ?? const []));
  }

  final escolhas = await mbTodasEscolhasDeOrcamento();
  // O servidor ainda guarda uma escolha que o padrão apagou: manda `orcamento_ids: null`.
  bool servidorTemEscolha(String tabela, String id) {
    final r = espelho['$tabela/$id']?.registro;
    return r != null && r.deletedAt == null && r.dados?['orcamento_ids'] != null;
  }

  final txs = await database.select(database.transactions).get();
  final mbPresentes = <String, Transaction>{};
  for (final t in txs) {
    if (t.transactionPk.startsWith('mb:')) {
      mbPresentes[t.transactionPk] = t;
    } else if (t.type == TransactionSpecialType.subscription) {
      add(mbProjAssinatura(t));
    } else if (mbEhLancamentoManual(t)) {
      add(mbProjLancamento(t, carteiras[t.walletFk] ?? '',
          orcamentos: escolhas[t.transactionPk],
          limparOrcamentos: escolhas[t.transactionPk] == null &&
              servidorTemEscolha('lancamentos', mbIdLocal(t.transactionPk, semPrefixo))));
    } else {
      final id = mbIdLocal(t.transactionPk, semPrefixo);
      existentes?.addAll(['lancamentos/$id', 'assinaturas/$id']);
    }
  }
  for (final pk in {...mbPresentes.keys, ...aplicado.keys}) {
    final t = mbPresentes[pk];
    final vigente = espelho['ajustes/${pk.substring(pk.startsWith('mb:') ? 3 : 0)}'];
    add(projetarAjuste(
        ajusteDeCategoriaVigente: vigente != null &&
            vigente.registro.deletedAt == null &&
            vigente.registro.dados?['categoria_id'] != null,
        txPk: pk,
        categoriaPkAtual: t?.categoryFk,
        categoriaPkAplicada: aplicado[pk],
        existeLocal: t != null,
        nomeCategoria: catPorPk[t?.categoryFk]?.name ?? '',
        orcamentoPks: escolhas[pk],
        limparOrcamentos: escolhas[pk] == null &&
            servidorTemEscolha('ajustes', pk.startsWith('mb:') ? pk.substring(3) : pk),
        editadoEm: t == null ? agora : mbEditadoEm(t.dateTimeModified)));
  }
  return out;
}
