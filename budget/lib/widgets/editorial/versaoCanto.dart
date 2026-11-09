import 'package:budget/struct/settings.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/widgets/editorial/layoutDesktop.dart'
    show ehDesktop, mbRotaEmpilhada;
import 'package:flutter/material.dart';

const String mbCompilado =
    String.fromEnvironment('MB_COMPILADO', defaultValue: 'dev');

String textoVersao(String versionName, String compilado) =>
    'v$versionName · $compilado';

class VersaoCanto extends StatelessWidget {
  const VersaoCanto({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final desktop = ehDesktop(context);
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        child,
        // No desktop a lateral mostra a versão; com página empilhada ela fica coberta e o canto volta.
        ValueListenableBuilder<bool>(
          valueListenable: mbRotaEmpilhada,
          builder: (context, empilhada, _) => desktop && !empilhada
              ? const SizedBox.shrink()
              : Positioned(
                  bottom: MediaQuery.paddingOf(context).bottom + 4,
                  right: 10,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: Text(
                        textoVersao(
                            packageInfoGlobal?.version ?? '?', mbCompilado),
                        textDirection: TextDirection.ltr,
                        style: EdTexto.mono(context).copyWith(
                          color: cores(context).mu.withOpacity(.7),
                          fontSize: 10,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
