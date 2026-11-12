import 'dart:convert';
import 'dart:ffi';

import 'package:budget/database/initializeDefaultDatabase.dart' show defaultWallet;
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/budgetPage.dart' show determineBudgetPolarity;
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/armazem.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart';
import 'package:budget/struct/mbSync/inicioOrdem.dart';
import 'package:budget/struct/mbSync/orcamentos.dart';
import 'package:budget/struct/meuBancoMapping.dart' show mbCarteiraInvestimentos;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';

final _ciclo = DateTimeRange(start: DateTime(2026, 10, 26), end: DateTime(2026, 11, 25));

Future<void> _tx(String pk, double valor,
    {String carteira = '0',
    DateTime? data,
    bool income = false,
    String categoria = 'c1',
    String? loan}) =>
    database.into(database.transactions).insert(TransactionsCompanion.insert(
        transactionPk: Value(pk),
        name: pk,
        amount: valor,
        note: '',
        categoryFk: categoria,
        walletFk: Value(carteira),
        dateCreated: Value(data ?? DateTime(2026, 11, 5)),
        income: Value(income),
        paid: const Value(true),
        objectiveLoanFk: Value(loan),
        dateTimeModified: Value(DateTime(2026, 11, 5))));

Future<Budget> _orc(String pk, {List<String>? categorias}) async {
  await database.into(database.budgets).insert(BudgetsCompanion.insert(
      budgetPk: Value(pk),
      name: pk,
      amount: 1000,
      startDate: _ciclo.start,
      endDate: _ciclo.end,
      periodLength: 1,
      reoccurrence: const Value(BudgetReoccurence.monthly),
      order: 3,
      categoryFks: Value(categorias),
      budgetTransactionFilters: const Value(
          [BudgetTransactionFilters.defaultBudgetTransactionFilters]),
      dateTimeModified: Value(DateTime.now())));
  return database.getBudgetInstance(pk);
}

Future<Set<String>> _doOrcamento(Budget b) async => {
      for (final t in await (database.select(database.transactions)
            ..where((t) => mbPertenceAoOrcamento(t, b)))
          .get())
        t.transactionPk
    };

/// Gasto do orçamento no ciclo, pelo mesmo caminho de consulta da Início.
Future<double> _gasto(Budget b) async {
  final lista = await database.getAllWallets();
  final total = await database
      .watchTotalSpentInTimeRangeFromCategories(
        allWallets: AllWallets(list: lista, indexedByPk: {for (final w in lista) w.walletPk: w}),
        start: _ciclo.start,
        end: _ciclo.end,
        categoryFks: b.categoryFks,
        categoryFksExclude: b.categoryFksExclude,
        budgetTransactionFilters: b.budgetTransactionFilters,
        memberTransactionFilters: b.memberTransactionFilters,
        budget: b,
      )
      .first;
  return (total ?? 0) * determineBudgetPolarity(b);
}

void main() {
  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    database = FinanceDatabase(NativeDatabase.memory());
    mbCicloCache = null;
    await database.createOrUpdateWallet(defaultWallet());
    await database.createOrUpdateWallet(
        defaultWallet().copyWith(walletPk: mbCarteiraInvestimentos, name: 'Investimentos'));
    await database.into(database.categories).insert(CategoriesCompanion.insert(
        categoryPk: const Value('c1'), name: 'Mercado', order: 0,
        dateTimeModified: Value(DateTime.now())));
  });

  tearDown(() => database.close());

  group('período = ciclo', () {
    test('o ciclo atual é o do Worker; os vizinhos não deixam lacuna nem sobreposição', () {
      expect(mbPeriodoDoCiclo(_ciclo, DateTime(2026, 11, 10)), _ciclo);
      expect(mbPeriodoDoCiclo(_ciclo, DateTime(2026, 10, 26)), _ciclo);
      expect(mbPeriodoDoCiclo(_ciclo, DateTime(2026, 11, 25, 23, 59)), _ciclo);
      final seg = mbPeriodoDoCiclo(_ciclo, DateTime(2026, 11, 26));
      expect(seg.start, DateTime(2026, 11, 26));
      expect(seg.end, DateTime(2026, 12, 25));
      final ant = mbPeriodoDoCiclo(_ciclo, DateTime(2026, 10, 25));
      expect(ant.end, DateTime(2026, 10, 25));
      expect(ant.start, DateTime(2026, 9, 26));
      final longe = mbPeriodoDoCiclo(_ciclo, DateTime(2027, 3, 1));
      expect(longe.start.isAfter(DateTime(2027, 2, 24)), true);
      expect(!DateTime(2027, 3, 1).isBefore(longe.start) && !DateTime(2027, 3, 1).isAfter(longe.end), true);
    });

    test('getBudgetDate usa o ciclo no orçamento mensal e preserva os demais', () async {
      final b = await _orc('o1');
      final antes = getBudgetDate(b, DateTime(2026, 11, 10));
      expect(antes.start, DateTime(2026, 10, 26)); // sem ciclo: dia de início do próprio orçamento
      final outro = DateTimeRange(start: DateTime(2026, 11, 5), end: DateTime(2026, 12, 4));
      mbCicloCache = outro;
      expect(getBudgetDate(b, DateTime(2026, 11, 10)), outro);
      final dois = b.copyWith(periodLength: 2);
      expect(getBudgetDate(dois, DateTime(2026, 11, 10)), isNot(outro));
    });

    test('mbCicloDeJson aceita o formato do Worker e rejeita lixo', () {
      expect(mbCicloDeJson({'inicio': '2026-10-26', 'fim': '2026-11-25'}), _ciclo);
      expect(mbCicloDeJson({'inicio': '2026-11-25', 'fim': '2026-10-26'}), isNull);
      expect(mbCicloDeJson(null), isNull);
    });

    test('o ciclo salvo é carregado no cache', () async {
      await mbCriarTabelas();
      await mbGravarEstado({'ciclo': jsonEncode({'inicio': '2026-10-26', 'fim': '2026-11-25'})});
      await mbCarregarCicloCache();
      expect(mbCicloCache, _ciclo);
    });
  });

  group('Geral e pertencimento', () {
    test('o Geral nasce sem valor, fixado e com filtros padrão; criar de novo não duplica', () async {
      mbCicloCache = _ciclo;
      final g = await mbGarantirOrcamentoGeral(agora: DateTime(2026, 11, 10));
      expect(g.budgetPk, mbOrcamentoGeralPk);
      expect(g.amount, 0);
      expect(g.pinned, true);
      expect(g.startDate, _ciclo.start);
      expect(g.endDate, _ciclo.end);
      expect(g.budgetTransactionFilters, [BudgetTransactionFilters.defaultBudgetTransactionFilters]);
      await mbGarantirOrcamentoGeral();
      expect(await database.select(database.budgets).get(), hasLength(1));
    });

    test('transação sem escolha cai no Geral e não em orçamento novo', () async {
      final g = await mbGarantirOrcamentoGeral();
      final casa = await _orc('casa');
      await _tx('t1', -50);
      expect(await _doOrcamento(g), {'t1'});
      expect(await _doOrcamento(casa), isEmpty);
    });

    test('uma transação pode estar em vários orçamentos', () async {
      final g = await mbGarantirOrcamentoGeral();
      final casa = await _orc('casa');
      final viagem = await _orc('viagem');
      await _tx('t1', -50);
      await _tx('t2', -30);
      await mbDefinirOrcamentosDaTransacao('t1', {mbOrcamentoGeralPk, 'casa'});
      await mbDefinirOrcamentosDaTransacao('t2', {'viagem'});
      expect(await _doOrcamento(g), {'t1'});
      expect(await _doOrcamento(casa), {'t1'});
      expect(await _doOrcamento(viagem), {'t2'});
      expect(await mbOrcamentosDaTransacao('t1'), {mbOrcamentoGeralPk, 'casa'});
    });

    test('só o Geral volta ao padrão; vazio tira de todos', () async {
      final g = await mbGarantirOrcamentoGeral();
      await _tx('t1', -50);
      await mbDefinirOrcamentosDaTransacao('t1', {'casa'});
      expect(await _doOrcamento(g), isEmpty);
      await mbDefinirOrcamentosDaTransacao('t1', {mbOrcamentoGeralPk});
      expect(await mbOrcamentosDaTransacao('t1'), isNull);
      expect(await _doOrcamento(g), {'t1'});
      await mbDefinirOrcamentosDaTransacao('t1', <String>{});
      expect(await mbOrcamentosDaTransacao('t1'), isEmpty);
      expect(await _doOrcamento(g), isEmpty);
    });

    test('mudar o vínculo atualiza dateTimeModified (avisa streams e sync)', () async {
      await _tx('t1', -50);
      await mbDefinirOrcamentosDaTransacao('t1', {'casa'}, agora: DateTime(2030));
      final t = await (database.select(database.transactions)
            ..where((t) => t.transactionPk.equals('t1')))
          .getSingle();
      expect(t.dateTimeModified, DateTime(2030));
    });

    test('orçamento por categoria também recebe transação sem escolha, mas não a que saiu dele', () async {
      final mercado = await _orc('mercado', categorias: ['c1']);
      await _tx('t1', -50);
      await _tx('t2', -20);
      await mbDefinirOrcamentosDaTransacao('t2', {'outro'});
      expect(await _doOrcamento(mercado), {'t1'});
    });
  });

  group('o que conta no gasto', () {
    test('gasto, estorno e cashback abatem; renda, transferência de investimento e empréstimo ficam de fora', () async {
      final g = await mbGarantirOrcamentoGeral();
      await _tx('gasto', -200);
      await _tx('estorno', 50); // positivo em despesa abate
      await _tx('salario', 5000, income: true);
      await _tx('inv', -300, carteira: mbCarteiraInvestimentos, categoria: '0');
      await _tx('emp', -100, loan: 'obj1');
      expect(await _gasto(g), 150);
    });

    test('fora do período não conta; pendente da fila (importada) conta no Geral', () async {
      final g = await mbGarantirOrcamentoGeral();
      await _tx('antigo', -999, data: DateTime(2026, 9, 1));
      await _tx('pendente', -80, data: DateTime(2026, 11, 20));
      expect(await _gasto(g), 80);
    });

    test('transação que só está em outro orçamento não conta no Geral', () async {
      final g = await mbGarantirOrcamentoGeral();
      final casa = await _orc('casa');
      await _tx('t1', -100);
      await _tx('t2', -40);
      await mbDefinirOrcamentosDaTransacao('t2', {'casa'});
      expect(await _gasto(g), 100);
      expect(await _gasto(casa), 40);
    });
  });

  group('alerta de 80% e 100% (função do PR 7)', () {
    test('níveis', () {
      expect(mbNivelOrcamento(valor: 1000, gasto: 799), 0);
      expect(mbNivelOrcamento(valor: 1000, gasto: 800), 1);
      expect(mbNivelOrcamento(valor: 1000, gasto: 1000), 1);
      expect(mbNivelOrcamento(valor: 1000, gasto: 1000.01), 2);
      expect(mbNivelOrcamento(valor: 0, gasto: 500), 0);
    });

    test('só dispara ao cruzar, e o limiar mais alto vence', () {
      MbAlertaOrcamento a(double antes, double depois) =>
          mbAlertaOrcamento(valor: 1000, gastoAntes: antes, gastoDepois: depois);
      expect(a(700, 790), MbAlertaOrcamento.nenhum);
      expect(a(700, 800), MbAlertaOrcamento.oitenta);
      expect(a(800, 900), MbAlertaOrcamento.nenhum);
      expect(a(900, 1100), MbAlertaOrcamento.cem);
      expect(a(100, 1100), MbAlertaOrcamento.cem);
      expect(a(1100, 1200), MbAlertaOrcamento.nenhum);
      expect(a(900, 700), MbAlertaOrcamento.nenhum); // estorno que reduz não alerta
      expect(mbAlertaOrcamento(valor: 0, gastoAntes: 0, gastoDepois: 50), MbAlertaOrcamento.nenhum);
    });
  });

  group('fatura e patrimônio', () {
    final agora = DateTime(2026, 11, 9, 15);
    List<Map<String, dynamic>> contas() => [
          {'id': 'd', 'type': 'CREDIT', 'name': 'Cartão Gold ·1950', 'balance': 607.65, 'due_date': '2026-11-05'},
        ];

    test('vencimento em até 3 dias destaca; mais longe não; sem valor não', () {
      FaturaAberta f(String due, double v) => mbFaturasAbertas(contas: contas(), agora: agora, faturas: {
            'd': {'open_bill': {'total_amount': v, 'due_date': due}}
          }).single;
      expect(f('2026-11-12', 300).destaque, true);
      expect(f('2026-11-12', 300).dias, 3);
      expect(f('2026-11-13', 300).destaque, false);
      expect(f('2026-11-09', 300).dias, 0);
      expect(f('2026-11-08', 300).destaque, true); // vencida
      expect(f('2026-11-10', 0).destaque, false);
      expect(f('2026-11-10', 300).nome, 'Cartão Gold');
    });

    test('sem fatura aberta usa o saldo e o próximo vencimento da conta', () {
      final f = mbFaturasAbertas(contas: contas(), faturas: {}, agora: agora).single;
      expect(f.valor, 607.65);
      expect(f.vence, DateTime(2026, 12, 5));
    });

    test('patrimônio = Inter + investimentos − fatura, sem empréstimos', () {
      final p = mbPatrimonio(inter: 1000, investimentos: 500, fatura: 300);
      expect(p.total, 1200);
      expect(mbPatrimonio(inter: 100, investimentos: 0, fatura: -50).total, 50);
    });

    test('carrega do que está no aparelho: conta corrente, investimentos, fatura e carteiras', () async {
      await mbCriarTabelas();
      await mbGravarEstado({
        'contas': jsonEncode([
          {'id': 'a', 'type': 'BANK', 'subtype': 'CHECKING_ACCOUNT', 'name': 'Conta Inter', 'balance': 1000.0},
          {'id': 'b', 'type': 'BANK', 'subtype': 'SAVINGS_ACCOUNT', 'name': 'Poupança', 'balance': 700.0},
          {'id': 'd', 'type': 'CREDIT', 'name': 'Cartão ·1', 'balance': 300.0, 'due_date': '2026-11-20'},
        ]),
        'faturas': jsonEncode({}),
      });
      await _tx('i1', 400, carteira: mbCarteiraInvestimentos, categoria: '0');
      await _tx('i2', 100, carteira: mbCarteiraInvestimentos, categoria: '0');
      await _tx('d1', 50, carteira: '0', categoria: 'c1');
      final r = await mbCarregarPatrimonioInicio(agora);
      expect(r.semDados, false);
      expect(r.patrimonio.inter, 1000);
      expect(r.patrimonio.investimentos, 500);
      expect(r.patrimonio.fatura, 300);
      expect(r.patrimonio.total, 1200);
      expect(r.carteiras.map((c) => c.saldo), [50.0]);
    });

    test('sem contas guardadas marca semDados', () async {
      await mbCriarTabelas();
      expect((await mbCarregarPatrimonioInicio(agora)).semDados, true);
    });
  });

  group('ordem da Início', () {
    test('padrão: orçamento, revisar, fatura, patrimônio, metas, empréstimos, transações', () {
      const esperado = ['orcamentoPadrao', 'paraRevisar', 'faturaCartao', 'patrimonio', 'objectives', 'emprestimos'];
      expect(mbOrdemInicio.take(6), esperado);
      expect(mbOrdemInicio.last, 'transactionsList');
      expect(mbOrdemInicioTelaGrande.take(4), esperado.take(4));
      expect(mbOrdemInicioTelaGrande.last, 'transactionsList');
      expect(mbOrdemInicioTelaGrande.where((e) => e.startsWith('ORDER:')), ['ORDER:LEFT', 'ORDER:RIGHT']);
      expect({...mbOrdemInicio}.length, mbOrdemInicio.length);
    });

    test('quem tinha a ordem padrão antiga recebe a nova; ordem personalizada fica intacta', () {
      final antigo = {
        'homePageOrder': ['wallets', 'walletsList', 'budgets', 'paraRevisar', 'objectives', 'allSpendingSummary', 'netWorth', 'emprestimos', 'overdueUpcoming', 'creditDebts', 'objectiveLoans', 'spendingGraph', 'pieChart', 'heatMap', 'transactionsList'],
        'homePageOrderFullScreen': ['transactionsList', 'wallets'],
        'showWalletSwitcher': true,
        'showPinnedBudgets': true,
        'showSpendingGraph': true,
      };
      expect(mbMigrarOrdemInicio(antigo), true);
      expect(antigo['homePageOrder'], mbOrdemInicio);
      expect(antigo['showWalletSwitcher'], false);
      expect(antigo['showObjectives'], true); // metas também na Início do celular
      expect(antigo['homePageOrderFullScreen'], ['transactionsList', 'wallets']); // personalizada
      expect(antigo['showWalletSwitcherFullScreen'], isNull);
      final de = Map<String, dynamic>.from(antigo);
      expect(mbMigrarOrdemInicio(de), false); // idempotente
    });
  });
}
