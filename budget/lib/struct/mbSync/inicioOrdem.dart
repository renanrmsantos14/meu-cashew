// Ordem da Início do Meu Banco (celular e computador).
//
// Padrão: orçamento padrão, Para revisar, fatura do cartão, patrimônio, metas (PR 6; usa o espaço de
// "objectives"), empréstimos, transações. Seções desligadas por padrão ficam entre os empréstimos e as transações.

const List<String> _ocultas = [
  "wallets",
  "walletsList",
  "budgets",
  "allSpendingSummary",
  "netWorth",
  "overdueUpcoming",
  "creditDebts",
  "objectiveLoans",
  "spendingGraph",
  "pieChart",
  "heatMap",
];

const List<String> mbOrdemInicio = [
  "orcamentoPadrao",
  "paraRevisar",
  "faturaCartao",
  "patrimonio",
  "objectives",
  "emprestimos",
  ..._ocultas,
  "transactionsList",
];

// Duas colunas no computador. Esquerda: o que se olha primeiro e sempre cabe (orçamento padrão, fila, fatura,
// patrimônio). Direita: o que cresce com o uso (metas, empréstimos, lista de transações), como a Início do Cashew.
const List<String> mbOrdemInicioTelaGrande = [
  "ORDER:LEFT",
  "orcamentoPadrao",
  "paraRevisar",
  "faturaCartao",
  "patrimonio",
  "ORDER:RIGHT",
  "objectives",
  "emprestimos",
  ..._ocultas,
  "transactionsList",
];

/// Ordem padrão anterior (PR 4). Quem ainda a tem não personalizou: recebe a nova.
const List<String> _ordemAnterior = [
  "wallets", "walletsList", "budgets", "paraRevisar", "objectives",
  "allSpendingSummary", "netWorth", "emprestimos", "overdueUpcoming",
  "creditDebts", "objectiveLoans", "spendingGraph", "pieChart", "heatMap",
  "transactionsList",
];

const List<String> _ordemAnteriorTelaGrande = [
  "wallets", "walletsList", "budgets", "paraRevisar", "ORDER:LEFT",
  "objectives", "allSpendingSummary", "netWorth", "emprestimos",
  "overdueUpcoming", "creditDebts", "objectiveLoans", "spendingGraph",
  "pieChart", "heatMap", "ORDER:RIGHT", "transactionsList",
];

bool _igual(Object? a, List<String> b) =>
    a is List && a.length == b.length && [for (final x in a) '$x'].join('|') == b.join('|');

/// Troca a ordem padrão antiga pela nova (e liga/desliga as seções do padrão novo) uma única vez.
/// Ordem personalizada fica intacta; as chaves novas entram depois por `fixHomePageOrder`.
/// Devolve true se mudou algo.
bool mbMigrarOrdemInicio(Map<String, dynamic> ajustes) {
  var mudou = false;
  if (_igual(ajustes["homePageOrder"], _ordemAnterior)) {
    ajustes["homePageOrder"] = [...mbOrdemInicio];
    for (final k in ["showWalletSwitcher", "showPinnedBudgets", "showSpendingGraph"]) {
      ajustes[k] = false;
    }
    mudou = true;
  }
  if (_igual(ajustes["homePageOrderFullScreen"], _ordemAnteriorTelaGrande)) {
    ajustes["homePageOrderFullScreen"] = [...mbOrdemInicioTelaGrande];
    for (final k in [
      "showWalletSwitcherFullScreen",
      "showPinnedBudgetsFullScreen",
      "showSpendingGraphFullScreen"
    ]) {
      ajustes[k] = false;
    }
    mudou = true;
  }
  return mudou;
}
