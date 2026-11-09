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
  testWidgets('mostra os 19 nomes e marca o selecionado', (t) async {
    await _monta(t, 'nord', (_) {});
    for (final tema in temasProntos) {
      expect(find.text(tema.nome), findsOneWidget, reason: tema.nome);
    }
    expect(
        t
            .getSemantics(find.bySemanticsLabel('Nord'))
            .hasFlag(SemanticsFlag.isSelected),
        isTrue);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('tocar em Nord chama aoEscolher', (t) async {
    String? id;
    await _monta(t, 'sistema', (v) => id = v);
    await t.tap(find.text('Nord'));
    expect(id, 'nord');
  });

  testWidgets('colunas: 2 abaixo de 600 px, 3 acima', (t) async {
    await _monta(t, 'sistema', (_) {});
    final a = t.getTopLeft(find.text('Padrão claro')).dx;
    final b = t.getTopLeft(find.text('Padrão escuro')).dx;
    expect(b, greaterThan(a));
    final c = t.getTopLeft(find.text('Azul Outlook')).dx;
    expect(c, a);
    await _monta(t, 'sistema', (_) {}, largura: 900);
    final d = t.getTopLeft(find.text('Azul Outlook')).dx;
    expect(d, greaterThan(t.getTopLeft(find.text('Padrão escuro')).dx));
  });
}
