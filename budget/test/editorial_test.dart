import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/editorial/movimento.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool reduzir = false}) => MaterialApp(
      theme: temaEditorial(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduzir),
        child: Scaffold(body: child),
      ),
    );

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

  test('tokens iguais aos do spec (22 valores)', () {
    const c = EditorialCores.claro;
    expect([
      c.bg,
      c.surf,
      c.tx,
      c.mu,
      c.line,
      c.acc,
      c.warn,
      c.warnbg,
      c.warntx,
      c.pos,
      c.chip
    ], [
      const Color(0xFFF7F6F3),
      const Color(0xFFFBFBFA),
      const Color(0xFF17181C),
      const Color(0xFF77767A),
      const Color.fromRGBO(20, 20, 30, .08),
      const Color(0xFF2340D8),
      const Color(0xFFB42318),
      const Color(0xFFFDEBEC),
      const Color(0xFF9F2F2D),
      const Color(0xFF2F6B3A),
      const Color(0xFFE8ECFB),
    ]);
    const d = EditorialCores.escuro;
    expect([
      d.bg,
      d.surf,
      d.tx,
      d.mu,
      d.line,
      d.acc,
      d.warn,
      d.warnbg,
      d.warntx,
      d.pos,
      d.chip
    ], [
      const Color(0xFF0F1114),
      const Color(0xFF15181C),
      const Color(0xFFECEDEF),
      const Color(0xFF8D9097),
      const Color.fromRGBO(255, 255, 255, .08),
      const Color(0xFF8EA4FF),
      const Color(0xFFF0726B),
      const Color.fromRGBO(240, 114, 107, .12),
      const Color(0xFFF59A94),
      const Color(0xFF7FCB92),
      const Color.fromRGBO(142, 164, 255, .12),
    ]);
  });

  test('temaEditorial carrega a extensão e o fundo certos', () {
    final escuro = temaEditorial(Brightness.dark);
    expect(escuro.extension<EditorialCores>()!.acc, const Color(0xFF8EA4FF));
    expect(escuro.scaffoldBackgroundColor, const Color(0xFF0F1114));
    expect(temaEditorial(Brightness.light).scaffoldBackgroundColor,
        const Color(0xFFF7F6F3));
  });

  testWidgets('EntradaEditorial sem movimento mostra o filho direto',
      (t) async {
    await t.pumpWidget(_app(
        const EntradaEditorial(indice: 3, child: Text('oi')),
        reduzir: true));
    expect(find.text('oi'), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets('EntradaEditorial anima e termina opaca', (t) async {
    await t
        .pumpWidget(_app(const EntradaEditorial(indice: 1, child: Text('oi'))));
    expect(t.widget<Opacity>(find.byType(Opacity)).opacity, 0);
    await t.pump(const Duration(milliseconds: 500));
    expect(t.widget<Opacity>(find.byType(Opacity)).opacity, 1);
  });

  testWidgets('ContagemValor chega ao texto final após 900ms', (t) async {
    await t.pumpWidget(
        _app(ContagemValor(valor: 100, formatar: (v) => 'R\$ ${v.round()}')));
    expect(find.text('R\$ 0'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 900));
    expect(find.text('R\$ 100'), findsOneWidget);
  });

  testWidgets('MedidorEditorial limita a fração em 1', (t) async {
    await t.pumpWidget(_app(const MedidorEditorial(fracao: 1.4)));
    await t.pump(const Duration(milliseconds: 900));
    final m = t
        .widgetList<Transform>(find.descendant(
            of: find.byType(MedidorEditorial),
            matching: find.byType(Transform)))
        .first;
    expect(m.transform.storage[0], 1.0);
  });
}
