import 'package:budget/colors.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart' show brl;
import 'package:budget/struct/mbSync/metas.dart';
import 'package:budget/struct/meuBancoSync.dart' show meuBancoUltimaSync;
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/lineGraph.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';

const _meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
];

String _nomeDoMes(String mes) {
  final p = mes.split('-');
  final m = p.length == 2 ? int.tryParse(p[1]) : null;
  return m == null || m < 1 || m > 12 ? mes : '${_meses[m - 1]} de ${p[0]}';
}

String _mesAtual(DateTime hoje) =>
    '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}';

/// Saldo atual dos investimentos (Inter e Santander juntos) e a evolução mês a mês.
/// A série vem do Worker (um retrato por mês: saldo no fim do mês, ou o último até agora no mês corrente).
class InvestimentosEvolucaoPage extends StatefulWidget {
  const InvestimentosEvolucaoPage({super.key});

  @override
  State<InvestimentosEvolucaoPage> createState() => _InvestimentosEvolucaoPageState();
}

class _InvestimentosEvolucaoPageState extends State<InvestimentosEvolucaoPage> {
  List<MbAplicacao> aplicacoes = const [];
  List<MbRetratoMes> serie = const [];
  Map<String, String> nomesDasMetas = {};
  bool carregou = false;

  @override
  void initState() {
    super.initState();
    meuBancoUltimaSync.addListener(_carregar);
    _carregar();
  }

  @override
  void dispose() {
    meuBancoUltimaSync.removeListener(_carregar);
    super.dispose();
  }

  Future<void> _carregar() async {
    final a = await mbAplicacoes();
    final s = await mbLerSerieMensal();
    final metas = await database.select(database.objectives).get();
    if (!mounted) return;
    setState(() {
      aplicacoes = a;
      serie = s;
      nomesDasMetas = {for (final m in metas) m.objectivePk: m.name};
      carregou = true;
    });
  }

  Widget _cartao(BuildContext context, Widget child) => Container(
        margin: const EdgeInsetsDirectional.only(start: 13, end: 13, bottom: 13),
        padding: const EdgeInsetsDirectional.all(15),
        decoration: BoxDecoration(
          color: getColor(context, "lightDarkAccentHeavyLight"),
          borderRadius: BorderRadius.circular(15),
        ),
        child: child,
      );

  Widget _variacao(BuildContext context, double? v, {double fontSize = 14}) {
    if (v == null) return const SizedBox.shrink();
    final sinal = v > 0 ? '+' : v < 0 ? '-' : '';
    return TextFont(
        text: '$sinal${brl(v.abs())}',
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        textColor: v > 0
            ? getColor(context, "incomeAmount")
            : v < 0
                ? getColor(context, "expenseAmount")
                : getColor(context, "textLight"));
  }

  Widget _saldoAtual(BuildContext context) {
    final suave = getColor(context, "textLight");
    final total = aplicacoes.fold(0.0, (s, a) => s + a.saldo);
    final variacoes = mbSerieComVariacao(serie);
    final ultima = variacoes.isEmpty ? null : variacoes.last;
    return _cartao(
      context,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextFont(text: 'Saldo atual', fontSize: 14, textColor: suave),
        TextFont(text: brl(total), fontSize: 32, fontWeight: FontWeight.bold),
        if (ultima?.variacao != null && ultima!.mes.mes == _mesAtual(DateTime.now()))
          Row(children: [
            _variacao(context, ultima.variacao),
            TextFont(text: ' sobre ${_nomeDoMes(variacoes[variacoes.length - 2].mes.mes)}', fontSize: 13, textColor: suave),
          ]),
        if (aplicacoes.isNotEmpty) const SizedBox(height: 10),
        for (final a in aplicacoes)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextFont(text: a.nome, fontSize: 15, maxLines: 2),
                  TextFont(
                      text: [
                        if (a.banco != null) a.banco!,
                        if (a.metaPk != null && nomesDasMetas[a.metaPk] != null) 'Meta ${nomesDasMetas[a.metaPk]}',
                      ].join(' · '),
                      fontSize: 12.5,
                      textColor: suave),
                ]),
              ),
              TextFont(text: brl(a.saldo), fontSize: 15, fontWeight: FontWeight.bold),
            ]),
          ),
      ]),
    );
  }

  Widget _grafico(BuildContext context) {
    if (serie.length < 2) {
      return _cartao(
          context,
          TextFont(
              text: 'O gráfico aparece quando houver pelo menos dois meses de histórico. '
                  'O primeiro retrato foi guardado no mês de ${_nomeDoMes(serie.isEmpty ? _mesAtual(DateTime.now()) : serie.first.mes)}.',
              fontSize: 14,
              maxLines: 6,
              textColor: getColor(context, "textLight")));
    }
    final hoje = DateTime.now();
    // Cada ponto no último dia do mês; o mês corrente, em hoje (é o saldo até agora).
    final datas = [
      for (final m in serie)
        m.mes == _mesAtual(hoje)
            ? DateTime(hoje.year, hoje.month, hoje.day)
            : () {
                final p = m.mes.split('-').map(int.parse).toList();
                return DateTime(p[0], p[1] + 1, 0);
              }()
    ];
    final pontos = [
      for (var i = 0; i < serie.length; i++)
        Pair(datas[i].difference(datas.first).inDays.toDouble(), serie[i].total, dateTime: datas[i])
    ];
    return _cartao(
      context,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextFont(text: 'Total por mês', fontSize: 16, fontWeight: FontWeight.bold),
        LineChartWrapper(
          points: [pontos],
          isCurved: true,
          endDate: datas.last,
          color: Theme.of(context).colorScheme.primary,
        ),
      ]),
    );
  }

  Widget _lista(BuildContext context) {
    final suave = getColor(context, "textLight");
    final hoje = _mesAtual(DateTime.now());
    final meses = mbSerieComVariacao(serie).reversed.toList();
    if (meses.isEmpty) return const SizedBox.shrink();
    return _cartao(
      context,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextFont(text: 'Mês a mês', fontSize: 16, fontWeight: FontWeight.bold),
        const SizedBox(height: 6),
        for (final e in meses)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: ValueKey('mes-${e.mes.mes}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsetsDirectional.only(bottom: 8),
              initiallyExpanded: e.mes.mes == hoje,
              title: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextFont(text: _nomeDoMes(e.mes.mes), fontSize: 15, fontWeight: FontWeight.bold),
                    if (e.mes.mes == hoje) TextFont(text: 'até agora', fontSize: 12.5, textColor: suave),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  TextFont(text: brl(e.mes.total), fontSize: 15, fontWeight: FontWeight.bold),
                  _variacao(context, e.variacao, fontSize: 12.5),
                ]),
              ]),
              children: [
                for (final i in e.mes.itens)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 4),
                    child: Row(children: [
                      Expanded(
                          child: TextFont(
                              text: [i.nome, if (i.banco != null) i.banco!].join(' · '),
                              fontSize: 13.5,
                              maxLines: 2,
                              textColor: suave)),
                      TextFont(text: brl(i.saldo), fontSize: 13.5, textColor: suave),
                    ]),
                  ),
              ],
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      dragDownToDismiss: true,
      title: 'Investimentos',
      horizontalPaddingConstrained: true,
      slivers: [
        SliverToBoxAdapter(
          child: !carregou
              ? const SizedBox.shrink()
              : aplicacoes.isEmpty && serie.isEmpty
                  ? _cartao(
                      context,
                      TextFont(
                          text: 'Nenhum investimento sincronizado ainda. Sincronize com o Meu Banco para ver o saldo e a evolução.',
                          fontSize: 14,
                          maxLines: 4,
                          textColor: getColor(context, "textLight")))
                  : Column(children: [
                      _saldoAtual(context),
                      _grafico(context),
                      _lista(context),
                    ]),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 50)),
      ],
    );
  }
}
