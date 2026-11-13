import 'package:budget/main.dart' show pageNavigationFrameworkKey;
import 'package:budget/struct/editorial.dart';
import 'package:budget/widgets/editorial/detalheTransacao.dart';
import 'package:budget/widgets/editorial/lateralEditorial.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:flutter/material.dart';

const double mbLarguraDesktop = 1100;
const double mbLarguraLateral = 232;
const double mbLarguraDetalhe = 360;

bool ehDesktop(BuildContext c) =>
    MediaQuery.sizeOf(c).width >= mbLarguraDesktop;

// transactionPk da transação com o detalhe aberto na coluna 3.
final ValueNotifier<String?> mbTransacaoSelecionada = ValueNotifier(null);

// Índice da página do PageNavigationFramework que está em primeiro plano (marca o item ativo da lateral).
final ValueNotifier<int> mbPaginaAtual = ValueNotifier(0);

// Há página empilhada cobrindo a lateral (a versão do canto precisa reaparecer).
final ValueNotifier<bool> mbRotaEmpilhada = ValueNotifier(false);

// Conta páginas empilhadas (PageRoute acima da raiz) de um Navigator; diálogos não contam.
class ObservadorPaginas extends NavigatorObserver {
  static int _total = 0;

  void _mudou(int delta) {
    _total = (_total + delta).clamp(0, 1 << 20);
    Future.microtask(() => mbRotaEmpilhada.value = _total > 0);
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    if (route is PageRoute && previousRoute != null) _mudou(1);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    if (route is PageRoute) _mudou(-1);
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    if (route is PageRoute && previousRoute != null) _mudou(-1);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {}
}

// transactionPk das transações visíveis na ordem da tela, para J/K.
final ValueNotifier<List<String>> mbListaVisivel = ValueNotifier(const []);

// Troca de página vinda do teclado ou da lateral: fecha rotas empilhadas e não anima.
void mbIrParaPagina(int pagina) {
  navigatorKey.currentState?.popUntil((r) => r.isFirst);
  pageNavigationFrameworkKey.currentState
      ?.changePage(pagina, switchNavbar: true, animar: false);
}

void mbSelecionarVizinha(int passo) {
  if (mbPaginaAtual.value != 0) return;
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
    return Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            Container(
              width: mbLarguraLateral,
              decoration: BoxDecoration(
                color: e.bg,
                border: Border(right: BorderSide(color: e.line)),
              ),
              child: lateral ?? const LateralEditorial(),
            ),
            // Limite semântico: uma rota modal no conteúdo (BlockSemantics) não some com a lateral
            // dos leitores de tela.
            Expanded(child: Semantics(container: true, child: conteudo)),
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
        ));
  }
}
