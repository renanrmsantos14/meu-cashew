import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/editorial/versaoCanto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    appStateSettings = {
      "materialYou": false,
      "accentSystemColor": false,
      "batterySaver": false,
      "increaseTextContrast": false,
      "forceFullDarkBackground": false,
    };
  });

  test('textoVersao', () {
    expect(
        textoVersao('5.4.4', '09/11/2026 14:20'), 'v5.4.4 · 09/11/2026 14:20');
  });

  testWidgets('versão aparece e não bloqueia toques', (tester) async {
    var toques = 0;
    await tester.pumpWidget(MaterialApp(
      theme: temaEditorial(Brightness.light),
      home: VersaoCanto(
        child: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => toques++,
              child: const SizedBox(width: 300, height: 60),
            ),
          ),
        ),
      ),
    ));
    final texto = find.textContaining('· dev');
    expect(texto, findsOneWidget);
    await tester.tap(texto, warnIfMissed: false);
    expect(toques, 1);
  });
}
