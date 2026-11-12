import 'package:budget/colors.dart';
import 'package:budget/struct/mbSync/emprestimos.dart' show meuBancoEmprestimos;
import 'package:budget/struct/mbSync/estadoInicio.dart';
import 'package:budget/struct/mbSync/revisao.dart' show meuBancoRevisar;
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/util/keepAliveClientMixin.dart';
import 'package:flutter/material.dart';

/// Dados dos cartões "Fatura" e "Patrimônio". Recarregam quando `mbAtualizarRevisar` roda
/// (após cada sincronização e ao mexer na fila), que também alimenta o "Para revisar".
class _CarregaInicio extends StatefulWidget {
  const _CarregaInicio({required this.construir});
  final Widget Function(BuildContext, PatrimonioInicio) construir;

  @override
  State<_CarregaInicio> createState() => _CarregaInicioState();
}

class _CarregaInicioState extends State<_CarregaInicio> {
  PatrimonioInicio? _dados;
  late final Listenable _gatilho = Listenable.merge([meuBancoRevisar, meuBancoEmprestimos]);
  late final RecargaColapsada _recarga = RecargaColapsada(_carregar);

  @override
  void initState() {
    super.initState();
    _gatilho.addListener(_recarga.pedir);
    _recarga.pedir();
  }

  @override
  void dispose() {
    _gatilho.removeListener(_recarga.pedir);
    _recarga.fechar();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final d = await mbCarregarPatrimonioInicio(DateTime.now());
      if (mounted) setState(() => _dados = d);
    } catch (_) {
      // Dados guardados ilegíveis: mantém o que já está na tela.
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _dados;
    if (d == null || d.semDados) return const SizedBox.shrink();
    return widget.construir(context, d);
  }
}

Widget _cartao(BuildContext context, List<Widget> filhos) => KeepAliveClientMixin(
      child: Container(
        margin: const EdgeInsetsDirectional.only(start: 13, end: 13, bottom: 13),
        padding: const EdgeInsetsDirectional.all(15),
        decoration: BoxDecoration(
          color: getColor(context, "lightDarkAccentHeavyLight"),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: filhos),
      ),
    );

Widget _linha(String rotulo, String valor, Color suave, {bool forte = false}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Expanded(
            child: TextFont(
                text: rotulo,
                fontSize: forte ? 16 : 14,
                fontWeight: forte ? FontWeight.bold : FontWeight.normal,
                textColor: forte ? null : suave)),
        TextFont(
            text: valor,
            fontSize: forte ? 16 : 14,
            fontWeight: forte ? FontWeight.bold : FontWeight.normal),
      ]),
    );

/// Fatura aberta de cada cartão e vencimento; destaque quando faltam 3 dias ou menos.
class HomePageFatura extends StatelessWidget {
  const HomePageFatura({super.key});

  @override
  Widget build(BuildContext context) => _CarregaInicio(construir: (context, d) {
        if (d.faturas.isEmpty) return const SizedBox.shrink();
        final suave = getColor(context, "textLight");
        const alerta = Color(0xFFD64545);
        return _cartao(context, [
          TextFont(text: 'Fatura do cartão', fontSize: 18, fontWeight: FontWeight.bold),
          for (final f in d.faturas) ...[
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextFont(text: f.nome, fontSize: 15, fontWeight: FontWeight.bold),
                  TextFont(
                      text: f.vence == null
                          ? 'Vencimento não informado'
                          : '${f.destaque ? (f.dias! < 0 ? 'Venceu' : f.dias == 0 ? 'Vence hoje' : 'Vence em ${f.dias} ${f.dias == 1 ? 'dia' : 'dias'}') : 'Vence'} · ${diaMes(f.vence!)}',
                      fontSize: 13,
                      fontWeight: f.destaque ? FontWeight.bold : FontWeight.normal,
                      textColor: f.destaque ? alerta : suave),
                ]),
              ),
              TextFont(
                  text: brl(f.valor),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  textColor: f.destaque ? alerta : null),
            ]),
          ],
        ]);
      });
}

/// Patrimônio = Inter (conta) + investimentos − fatura atual. Empréstimos ficam de fora; as carteiras aparecem abaixo.
class HomePagePatrimonio extends StatelessWidget {
  const HomePagePatrimonio({super.key});

  @override
  Widget build(BuildContext context) => _CarregaInicio(construir: (context, d) {
        final suave = getColor(context, "textLight");
        final p = d.patrimonio;
        return _cartao(context, [
          TextFont(text: 'Patrimônio', fontSize: 18, fontWeight: FontWeight.bold),
          const SizedBox(height: 2),
          TextFont(text: brl(p.total), fontSize: 26, fontWeight: FontWeight.bold),
          const SizedBox(height: 4),
          _linha('Conta Inter', brl(p.inter), suave),
          _linha('Investimentos', brl(p.investimentos), suave),
          _linha('Fatura atual', '− ${brl(p.fatura)}', suave),
          if (d.carteiras.isNotEmpty) ...[
            const SizedBox(height: 10),
            TextFont(text: 'Carteiras', fontSize: 14, fontWeight: FontWeight.bold, textColor: suave),
            for (final c in d.carteiras) _linha(c.nome, brl(c.saldo), suave),
          ],
        ]);
      });
}
