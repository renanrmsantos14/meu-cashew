import 'package:budget/colors.dart';
import 'package:budget/struct/mbSync/emprestimos.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart' show brl, diaMes;
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/util/keepAliveClientMixin.dart';
import 'package:flutter/material.dart';

/// Cartão "Empréstimos em aberto" da Início: cada empréstimo ao pai com o que falta e o total devido.
/// Some quando não há nenhum em aberto (ou o app não está pareado com o Meu Banco).
/// Os dados vêm de `mbAtualizarRevisar` (chamada pelo cartão "Para revisar" e após cada sincronização).
class HomePageEmprestimos extends StatelessWidget {
  const HomePageEmprestimos({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MbEmprestimos>(
      valueListenable: meuBancoEmprestimos,
      builder: (context, emprestimos, _) {
        if (emprestimos.abertos.isEmpty) return const SizedBox.shrink();
        final suave = getColor(context, "textLight");
        return KeepAliveClientMixin(
          child: Container(
            margin: const EdgeInsetsDirectional.only(start: 13, end: 13, bottom: 13),
            padding: const EdgeInsetsDirectional.all(15),
            decoration: BoxDecoration(
              color: getColor(context, "lightDarkAccentHeavyLight"),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFont(text: 'Empréstimos em aberto', fontSize: 18, fontWeight: FontWeight.bold),
                const SizedBox(height: 2),
                TextFont(text: 'Devido: ${brl(emprestimos.devido)}', fontSize: 14, textColor: suave),
                for (final e in emprestimos.abertos) ...[
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        TextFont(
                            text: e.data == null
                                ? 'Empréstimo'
                                : 'Emprestado em ${diaMes(DateTime.parse(e.data!))}',
                            fontSize: 15,
                            fontWeight: FontWeight.bold),
                        TextFont(
                            text: e.parcial ? 'Valor original ${brl(e.original)}' : 'Nada devolvido ainda',
                            fontSize: 13,
                            textColor: suave),
                      ]),
                    ),
                    TextFont(
                        text: 'Falta ${brl(e.restante)}', fontSize: 15, fontWeight: FontWeight.bold),
                  ]),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
