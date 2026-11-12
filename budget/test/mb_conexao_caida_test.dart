import 'package:budget/pages/homePage/homePageConexaoCaida.dart';
import 'package:budget/struct/editorial.dart' show temaEditorial;
import 'package:budget/struct/settings.dart' show appStateSettings;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> montar(WidgetTester t, List<Map<String, dynamic>> avisos) async {
  appStateSettings = {
    'materialYou': false,
    'accentSystemColor': false,
    'batterySaver': false,
    'increaseTextContrast': false,
    'forceFullDarkBackground': false,
  };
  await t.pumpWidget(MaterialApp(
      theme: temaEditorial(Brightness.light),
      home: Scaffold(body: HomePageConexaoCaida(carregar: () async => avisos))));
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('sem aviso a faixa não aparece', (t) async {
    await montar(t, []);
    expect(find.text('Reconectar'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('banco desconectado mostra a faixa com o botão Reconectar', (t) async {
    await montar(t, [
      {'item_id': 'i1', 'banco': 'Inter', 'mensagem': 'x', 'reconnect_url': 'https://meu.pluggy.ai'}
    ]);
    expect(find.text('Inter desconectou'), findsOneWidget);
    expect(find.text('Reconectar'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
