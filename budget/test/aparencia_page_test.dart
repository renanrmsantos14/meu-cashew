import 'package:budget/pages/aparenciaPage.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/temas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _monta(WidgetTester t, String sel, ValueChanged<String> aoEscolher,
    {double largura = 400}) async {
  appStateSettings = {
    'temaPronto': sel,
    'materialYou': false,
    'batterySaver': false,
    'increaseTextContrast': false,
    'accentColor': '0xFF2340D8',
    'accentSystemColor': false,
    'font': 'Geist',
  };
  t.view.physicalSize = Size(largura, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: temaFlutter(temaPorId('padrao-claro')),
    home: Scaffold(
        body: SingleChildScrollView(
            child: GradeTemas(selecionado: sel, aoEscolher: aoEscolher))),
  ));
}

void main() {
  testWidgets('mostra os 3 modos e marca o selecionado', (t) async {
    await _monta(t, 'padrao-escuro', (_) {});
    for (final tema in [temaSistema, ...temasProntos]) {
      expect(find.text(tema.nome), findsOneWidget, reason: tema.nome);
    }
    expect(
        t
            .getSemantics(find.bySemanticsLabel('Escuro'))
            .hasFlag(SemanticsFlag.isSelected),
        isTrue);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('tocar em Escuro chama aoEscolher', (t) async {
    String? id;
    await _monta(t, 'sistema', (v) => id = v);
    await t.tap(find.text('Escuro'));
    expect(id, 'padrao-escuro');
  });

  testWidgets('os 3 modos ficam na mesma linha', (t) async {
    await _monta(t, 'sistema', (_) {});
    final a = t.getTopLeft(find.text('Sistema'));
    final b = t.getTopLeft(find.text('Claro'));
    final c = t.getTopLeft(find.text('Escuro'));
    expect(b.dx, greaterThan(a.dx));
    expect(c.dx, greaterThan(b.dx));
    expect((c.dy - a.dy).abs(), lessThan(4));
  });

  testWidgets('seletor de acento mostra 4 cores e escolhe', (t) async {
    String? id;
    await t.pumpWidget(MaterialApp(
      theme: temaFlutter(temaPorId('padrao-claro')),
      home: Scaffold(
          body: SeletorAcento(selecionado: 'verde', aoEscolher: (v) => id = v)),
    ));
    for (final a in acentos) {
      expect(find.text(a.nome), findsOneWidget);
    }
    expect(
        t
            .getSemantics(find.bySemanticsLabel('Verde'))
            .hasFlag(SemanticsFlag.isSelected),
        isTrue);
    await t.tap(find.text('Terracota'));
    expect(id, 'terracota');
  });
}
