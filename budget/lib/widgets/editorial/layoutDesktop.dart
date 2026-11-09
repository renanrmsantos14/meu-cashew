import 'package:budget/main.dart' show pageNavigationFrameworkKey;
import 'package:budget/struct/editorial.dart';
import 'package:budget/widgets/editorial/detalheTransacao.dart';
import 'package:budget/widgets/editorial/lateralEditorial.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:flutter/material.dart';

const double mbLarguraDesktop = 1100;
const double mbLarguraLateral = 232;
const double mbLarguraDetalhe = 360;

bool ehDesktop(BuildContext c) => MediaQuery.sizeOf(c).width >= mbLarguraDesktop;

// transactionPk da transação com o detalhe aberto na coluna 3.
final ValueNotifier<String?> mbTransacaoSelecionada = ValueNotifier(null);

// Índice da página do PageNavigationFramework que está em primeiro plano (marca o item ativo da lateral).
final ValueNotifier<int> mbPaginaAtual = ValueNotifier(0);

// transactionPk das transações visíveis na ordem da tela, para J/K.
final ValueNotifier<List<String>> mbListaVisivel = ValueNotifier(const []);

// Troca de página vinda do teclado ou da lateral: fecha rotas empilhadas e não anima.
void mbIrParaPagina(int pagina) {
  navigatorKey.currentState?.popUntil((r) => r.isFirst);
  pageNavigationFrameworkKey.currentState
      ?.changePage(pagina, switchNavbar: true, animar: false);
}

void mbSelecionarVizinha(int passo) {
  final lista = mbListaVisivel.value;
  if (lista.isEmpty) return;
  final i = lista.indexOf(mbTransacaoSelecionada.value ?? '');
  final novo = i < 0 ? (passo > 0 ? 0 : lista.length - 1) : i + passo;
  if (novo < 0 || novo >= lista.length) return;
  mbTransacaoSelecionada.value = lista[novo];
}

class LayoutDesktop extends StatelessWidget {
  const LayoutDesktop({
    super.key,
    required this.conteudo,
    this.lateral,
    this.carregarDetalhe = mbCarregarDetalhe,
    this.aoMudarCategoria,
  });

  final Widget conteudo;
  final Widget? lateral;
  final Future<DetalheModelo?> Function(String pk) carregarDetalhe;
  final Future<void> Function(DetalheModelo)? aoMudarCategoria;

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    return Row(
      children: [
        Container(
          width: mbLarguraLateral,
          decoration: BoxDecoration(
            color: e.bg,
            border: Border(right: BorderSide(color: e.line)),
          ),
          child: lateral ?? const LateralEditorial(),
        ),
        Expanded(child: conteudo),
        ValueListenableBuilder<String?>(
          valueListenable: mbTransacaoSelecionada,
          builder: (context, pk, _) => pk == null
              ? const SizedBox.shrink()
              : Container(
                  width: mbLarguraDetalhe,
                  decoration: BoxDecoration(
                    color: e.surf,
                    border: Border(left: BorderSide(color: e.line)),
                  ),
                  child: DetalheTransacao(
                    key: ValueKey(pk),
                    pk: pk,
                    carregar: carregarDetalhe,
                    aoMudarCategoria: aoMudarCategoria,
                  ),
                ),
        ),
      ],
    );
  }
}
