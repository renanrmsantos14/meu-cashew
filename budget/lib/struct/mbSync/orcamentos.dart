import 'dart:convert';

import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/armazem.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show DateTimeRange;

// Orçamentos do Meu Banco.
//
// Modelo: orçamento "todas as transações" do RenanCash (`addedTransactionsOnly = false`) com os filtros
// padrão (sem renda nem ajuste de saldo) + pertencimento aditivo N:N em `mb_orcamento_tx`.
// - `budgetFksExclude` do RenanCash é subtrativo: um orçamento novo engoliria todas as transações.
// - `sharedReferenceBudgetPk` é único por transação: não permite "em vários orçamentos".
// Sem linhas para a transação, ela pertence ao Geral (e aos orçamentos por categoria). Com linhas, só aos escolhidos.

/// Orçamento padrão. Pk fixo: dois aparelhos que o criem juntos não duplicam (o registro sincronizado vence por LWW).
const String mbOrcamentoGeralPk = 'mb:orc:geral';
const String mbOrcamentoNome = 'Geral';
const String _nenhum = '';

String _aspas(String s) => s.replaceAll("'", "''");

/// Filtro SQL de pertencimento. Só vale para orçamento "todas as transações" não compartilhado.
/// Geral e orçamentos com categorias também recebem a transação sem escolha explícita.
Expression<bool> mbPertenceAoOrcamento($TransactionsTable tbl, Budget? b) {
  if (b == null || b.addedTransactionsOnly || b.sharedKey != null) {
    return const Constant(true);
  }
  final tx = '${tbl.aliasedName}.transaction_pk';
  final propria = "EXISTS (SELECT 1 FROM mb_orcamento_tx m WHERE m.tx_pk = $tx "
      "AND m.orcamento_pk = '${_aspas(b.budgetPk)}')";
  final semEscolha = 'NOT EXISTS (SELECT 1 FROM mb_orcamento_tx m WHERE m.tx_pk = $tx)';
  final recebePadrao =
      b.budgetPk == mbOrcamentoGeralPk || (b.categoryFks?.isNotEmpty ?? false);
  return CustomExpression<bool>(
      recebePadrao ? '($propria OR $semEscolha)' : propria);
}

// ---------------------------------------------------------------------------------------------
// Período = ciclo do salário

/// Ciclo atual do Worker (`ciclo.inicio`/`ciclo.fim`), em memória para `getBudgetDate` (síncrona).
DateTimeRange? mbCicloCache;

DateTimeRange? mbCicloDeJson(Object? ciclo) {
  if (ciclo is! Map) return null;
  final ini = DateTime.tryParse('${ciclo['inicio']}');
  final fim = DateTime.tryParse('${ciclo['fim']}');
  if (ini == null || fim == null || fim.isBefore(ini)) return null;
  return DateTimeRange(
      start: DateTime(ini.year, ini.month, ini.day),
      end: DateTime(fim.year, fim.month, fim.day));
}

Future<void> mbCarregarCicloCache() async {
  try {
    final texto = await mbLerEstado('ciclo');
    mbCicloCache = texto == null ? null : mbCicloDeJson(jsonDecode(texto));
  } catch (_) {
    mbCicloCache = null;
  }
}

DateTime _somarMeses(DateTime d, int meses) {
  final ultimo = DateTime(d.year, d.month + meses + 1, 0).day;
  return DateTime(d.year, d.month + meses, d.day > ultimo ? ultimo : d.day);
}

/// Período (início e fim, só datas) do ciclo que contém [ref]. O ciclo atual é o do Worker; os outros
/// são aproximados em passos de um mês a partir dele (o Worker só informa o ciclo atual).
DateTimeRange mbPeriodoDoCiclo(DateTimeRange ciclo, DateTime ref) {
  final dia = DateTime(ref.year, ref.month, ref.day);
  if (!dia.isBefore(ciclo.start) && !dia.isAfter(ciclo.end)) return ciclo;
  final proximo = ciclo.end.add(const Duration(days: 1));
  // Fronteiras: ... início-1m, início, [fim+1], fim+1+1m, ...
  DateTime fronteira(int k) =>
      k <= 0 ? _somarMeses(ciclo.start, k) : _somarMeses(proximo, k - 1);
  var k = dia.isBefore(ciclo.start) ? -1 : 1;
  final passo = k;
  while (passo < 0 ? dia.isBefore(fronteira(k)) : !dia.isBefore(fronteira(k + 1))) {
    k += passo;
  }
  return DateTimeRange(
      start: fronteira(k),
      end: fronteira(k + 1).subtract(const Duration(days: 1)));
}

// ---------------------------------------------------------------------------------------------
// Escolha de orçamentos por transação

/// Orçamentos escolhidos para a transação; `null` = padrão (nenhuma linha). Vazio = nenhum orçamento.
Future<Set<String>?> mbOrcamentosDaTransacao(String txPk) async {
  final l = await database.customSelect(
      'SELECT orcamento_pk FROM mb_orcamento_tx WHERE tx_pk = ?',
      variables: [Variable.withString(txPk)]).get();
  if (l.isEmpty) return null;
  return {
    for (final r in l)
      if (r.read<String>('orcamento_pk') != _nenhum) r.read<String>('orcamento_pk')
  };
}

Future<Map<String, Set<String>>> mbTodasEscolhasDeOrcamento() async {
  final out = <String, Set<String>>{};
  for (final r in await database
      .customSelect('SELECT tx_pk, orcamento_pk FROM mb_orcamento_tx')
      .get()) {
    final s = out.putIfAbsent(r.read<String>('tx_pk'), () => {});
    if (r.read<String>('orcamento_pk') != _nenhum) s.add(r.read<String>('orcamento_pk'));
  }
  return out;
}

/// Grava as linhas sem tocar a transação (usado também ao aplicar o que veio do servidor).
Future<void> mbGravarEscolhaDeOrcamento(String txPk, Set<String>? escolha) async {
  await database.customStatement(
      'DELETE FROM mb_orcamento_tx WHERE tx_pk = ?', [txPk]);
  if (escolha == null) return;
  for (final pk in escolha.isEmpty ? {_nenhum} : escolha) {
    await database.customStatement(
        'INSERT OR IGNORE INTO mb_orcamento_tx (tx_pk, orcamento_pk) VALUES (?, ?)',
        [txPk, pk]);
  }
}

/// Define os orçamentos da transação. Só o Geral (ou `null`) volta ao padrão (sem linhas).
/// Atualiza `dateTimeModified`: é o que avisa os streams do Drift e marca a edição para a sincronização.
Future<void> mbDefinirOrcamentosDaTransacao(String txPk, Set<String>? escolha,
    {DateTime? agora}) async {
  final padrao = escolha == null ||
      (escolha.length == 1 && escolha.first == mbOrcamentoGeralPk);
  await database.transaction(() async {
    await mbGravarEscolhaDeOrcamento(txPk, padrao ? null : escolha);
    await mbTocarTransacao(txPk, agora ?? DateTime.now());
  });
}

Future<void> mbTocarTransacao(String txPk, DateTime quando) =>
    (database.update(database.transactions)
          ..where((t) => t.transactionPk.equals(txPk)))
        .write(TransactionsCompanion(dateTimeModified: Value(quando)));

/// Orçamentos que uma transação pode escolher (os compartilhados e os "só adicionadas" têm seus próprios fluxos).
Stream<List<Budget>> mbWatchOrcamentosEscolhiveis() => (database.select(database.budgets)
      ..where((b) =>
          b.sharedKey.isNull() &
          b.addedTransactionsOnly.equals(false) &
          b.archived.equals(false))
      ..orderBy([(b) => OrderingTerm.asc(b.order)]))
    .watch();

// ---------------------------------------------------------------------------------------------
// Orçamento padrão (Geral)

/// Cria o Geral se faltar: valor 0 ("Definir valor"), fixado, todas as transações e filtros padrão
/// (sem renda, dívida/crédito nem ajuste de saldo). Devolve o orçamento.
Future<Budget> mbGarantirOrcamentoGeral({DateTime? agora}) async {
  final existente = await (database.select(database.budgets)
        ..where((b) => b.budgetPk.equals(mbOrcamentoGeralPk)))
      .getSingleOrNull();
  if (existente != null) return existente;
  final hoje = agora ?? DateTime.now();
  final ciclo = mbCicloCache == null
      ? DateTimeRange(
          start: DateTime(hoje.year, hoje.month, 1),
          end: DateTime(hoje.year, hoje.month + 1, 0))
      : mbPeriodoDoCiclo(mbCicloCache!, hoje);
  await database.into(database.budgets).insert(
      BudgetsCompanion.insert(
        budgetPk: Value(mbOrcamentoGeralPk),
        name: mbOrcamentoNome,
        amount: 0,
        startDate: ciclo.start,
        endDate: ciclo.end,
        periodLength: 1,
        reoccurrence: const Value(BudgetReoccurence.monthly),
        pinned: const Value(true),
        order: await _proximaOrdem(),
        budgetTransactionFilters: const Value([
          BudgetTransactionFilters.defaultBudgetTransactionFilters,
        ]),
        dateTimeModified: Value(hoje),
      ),
      mode: InsertMode.insertOrIgnore); // chamadas simultâneas (widget + sync) não estouram a chave
  return (database.select(database.budgets)
        ..where((b) => b.budgetPk.equals(mbOrcamentoGeralPk)))
      .getSingle();
}

Future<int> _proximaOrdem() async => (await database
        .customSelect('SELECT COUNT(*) AS n FROM budgets')
        .getSingle())
    .read<int>('n');

// ---------------------------------------------------------------------------------------------
// Alertas de 80% e 100% (só no Geral). O PR 7 usa [mbAlertaOrcamento] para decidir o push.

enum MbAlertaOrcamento { nenhum, oitenta, cem }

/// 0 = abaixo de 80%, 1 = de 80% até o valor, 2 = acima do valor (mesma regra do Worker: >100% estoura).
int mbNivelOrcamento({required double valor, required double gasto}) {
  if (valor <= 0) return 0;
  if (gasto > valor) return 2;
  return gasto >= valor * 0.8 ? 1 : 0;
}

/// Alerta a disparar quando o gasto passa de [gastoAntes] para [gastoDepois]: o limiar mais alto cruzado
/// agora (100% vence 80% se os dois forem cruzados de uma vez) ou `nenhum` se nenhum foi cruzado.
MbAlertaOrcamento mbAlertaOrcamento(
    {required double valor,
    required double gastoAntes,
    required double gastoDepois}) {
  final antes = mbNivelOrcamento(valor: valor, gasto: gastoAntes);
  final depois = mbNivelOrcamento(valor: valor, gasto: gastoDepois);
  if (depois <= antes) return MbAlertaOrcamento.nenhum;
  return depois == 2 ? MbAlertaOrcamento.cem : MbAlertaOrcamento.oitenta;
}
