import 'package:budget/struct/settings.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/widgets/editorial/layoutDesktop.dart'
    show ehDesktop, mbRotaEmpilhada;
import 'package:budget/widgets/openBottomSheet.dart' show getIsFullScreen;
import 'package:flutter/material.dart';

const String mbCompilado =
    String.fromEnvironment('MB_COMPILADO', defaultValue: 'dev');

String textoVersao(String versionName, String compilado) =>
    'v$versionName · $compilado';

const double mbAlturaFaixaVersao = 16;

TextStyle _estiloVersao(BuildContext context) => EdTexto.mono(context).copyWith(
      color: cores(context).mu.withOpacity(.7),
      fontSize: 10,
      decoration: TextDecoration.none,
    );

String _versaoAtual() =>
    textoVersao(packageInfoGlobal?.version ?? '?', mbCompilado);

/// No celular a versão fica numa faixa própria entre o conteúdo e a barra inferior (nunca sobre ela).
class FaixaVersao extends StatelessWidget {
  const FaixaVersao({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: Container(
            height: mbAlturaFaixaVersao,
            color: cores(context).bg,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 10),
            child: Text(_versaoAtual(),
                textDirection: TextDirection.ltr,
                style: _estiloVersao(context)),
          ),
        ),
      );
}

class VersaoCanto extends StatelessWidget {
  const VersaoCanto({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Desktop (lateral) e celular com barra inferior mostram a versão no próprio chrome.
    final noChrome = ehDesktop(context) || !getIsFullScreen(context);
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        child,
        // Com página empilhada o chrome fica coberto e o canto volta.
        ValueListenableBuilder<bool>(
          valueListenable: mbRotaEmpilhada,
          builder: (context, empilhada, _) => noChrome && !empilhada
              ? const SizedBox.shrink()
              : Positioned(
                  bottom: MediaQuery.paddingOf(context).bottom + 4,
                  right: 10,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: Text(
                        _versaoAtual(),
                        textDirection: TextDirection.ltr,
                        style: _estiloVersao(context),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
