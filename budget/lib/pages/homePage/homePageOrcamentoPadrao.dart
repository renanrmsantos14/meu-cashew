import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/pages/addBudgetPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart' show brl;
import 'package:budget/struct/mbSync/orcamentos.dart';
import 'package:budget/struct/meuBancoSync.dart' show meuBancoPareado;
import 'package:budget/pages/budgetPage.dart' show determineBudgetPolarity;
import 'package:budget/widgets/openPopup.dart' show RoutesToPopAfterDelete;
import 'package:budget/widgets/navigationSidebar.dart' show enableDoubleColumn;
import 'package:budget/widgets/pieChart.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/util/keepAliveClientMixin.dart';
import 'package:budget/functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Cartão "Orçamento padrão" da Início: "Gastei X de Y" no ciclo do salário e a pizza por categoria.
/// Sem valor definido mostra "Definir valor". Amarelo a partir de 80% e vermelho acima de 100%.
class HomePageOrcamentoPadrao extends StatefulWidget {
  const HomePageOrcamentoPadrao({super.key});

  @override
  State<HomePageOrcamentoPadrao> createState() => _HomePageOrcamentoPadraoState();
}

class _HomePageOrcamentoPadraoState extends State<HomePageOrcamentoPadrao> {
  @override
  void initState() {
    super.initState();
    // Pareado: o Geral vem da sincronização (criar aqui poderia sobrescrever o valor definido em outro aparelho).
    if (!meuBancoPareado.value) mbGarantirOrcamentoGeral();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Budget>(
      stream: database.getBudget(mbOrcamentoGeralPk),
      builder: (context, snap) {
        // `getBudget` termina em erro quando o Geral ainda não existe: nada a mostrar.
        if (!snap.hasData) return const SizedBox.shrink();
        return _Cartao(budget: snap.data!);
      },
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.budget});
  final Budget budget;

  @override
  Widget build(BuildContext context) {
    final periodo = getBudgetDate(budget, DateTime.now());
    final suave = getColor(context, "textLight");
    return KeepAliveClientMixin(
      child: StreamBuilder<List<CategoryWithTotal>>(
        stream: database.watchTotalSpentInEachCategoryInTimeRangeFromCategories(
          allWallets: Provider.of<AllWallets>(context),
          start: periodo.start,
          end: periodo.end,
          categoryFks: budget.categoryFks,
          categoryFksExclude: budget.categoryFksExclude,
          budgetTransactionFilters: budget.budgetTransactionFilters,
          memberTransactionFilters: budget.memberTransactionFilters,
          onlyShowTransactionsBelongingToBudgetPk: null,
          budget: budget,
        ),
        builder: (context, snap) {
          final dados = snap.data ?? const <CategoryWithTotal>[];
          final soma = dados.fold<double>(0, (s, c) => s + c.total);
          // Sem gasto, 0 × polaridade daria -0,0 e o texto sairia "-R$ 0,00".
          final gasto = soma == 0 ? 0.0 : soma * determineBudgetPolarity(budget);
          final valor = budget.amount;
          final nivel = mbNivelOrcamento(valor: valor, gasto: gasto);
          final cor = nivel == 2
              ? const Color(0xFFD64545)
              : nivel == 1
                  ? const Color(0xFFE0A100)
                  : getColor(context, "black");
          final pct = valor > 0 ? (gasto / valor).clamp(0.0, 1.0) : 0.0;
          return Container(
            margin: const EdgeInsetsDirectional.only(start: 13, end: 13, bottom: 13),
            padding: const EdgeInsetsDirectional.all(15),
            decoration: BoxDecoration(
              color: getColor(context, "lightDarkAccentHeavyLight"),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: TextFont(
                        text: budget.name, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (nivel > 0)
                    TextFont(
                        text: nivel == 2 ? 'Estourou' : 'Passou de 80%',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        textColor: cor),
                ]),
                const SizedBox(height: 2),
                if (valor > 0)
                  TextFont(
                      text: 'Gastei ${brl(gasto)} de ${brl(valor)}',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      textColor: cor)
                else
                  Row(children: [
                    TextFont(text: 'Gastei ${brl(gasto)} · ', fontSize: 15, textColor: suave),
                    Tappable(
                      color: Colors.transparent,
                      onTap: () => pushRoute(
                          context,
                          AddBudgetPage(
                              budget: budget,
                              routesToPopAfterDelete: RoutesToPopAfterDelete.None)),
                      child: TextFont(
                          text: 'Definir valor',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          textColor: Theme.of(context).colorScheme.primary),
                    ),
                  ]),
                if (valor > 0) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 8,
                      color: nivel == 0 ? Theme.of(context).colorScheme.primary : cor,
                      backgroundColor: getColor(context, "lightDarkAccent"),
                    ),
                  ),
                ],
                if (dados.any((c) => c.total != 0)) ...[
                  const SizedBox(height: 12),
                  _pizzaELegenda(context, dados, gasto, determineBudgetPolarity(budget)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

Widget _pizzaELegenda(
    BuildContext context, List<CategoryWithTotal> dados, double gasto, num polaridade) {
  final pizza = SizedBox(
    height: 190,
    child: PieChartWrapper(
      disableLarge: true,
      pieChartDisplayStateKey: null,
      data: dados,
      totalSpent: gasto,
      setSelectedCategory: (_, __) {},
      middleColor: getColor(context, "lightDarkAccentHeavyLight"),
    ),
  );
  // Celular: só a pizza (compacto). Computador: legenda por categoria ao lado, senão sobra espaço vazio.
  if (!enableDoubleColumn(context)) return pizza;
  final itens = [for (final c in dados) if (c.total != 0) c]
    ..sort((a, b) => b.total.abs().compareTo(a.total.abs()));
  return Row(children: [
    SizedBox(width: 260, child: pizza),
    const SizedBox(width: 24),
    Expanded(
      child: Column(children: [
        for (final c in itens)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: HexColor(c.category.colour,
                        defaultColor: Theme.of(context).colorScheme.primary),
                    shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(child: TextFont(text: c.category.name, fontSize: 14)),
              TextFont(
                  text: brl(c.total * polaridade),
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ]),
          ),
      ]),
    ),
  ]);
}
