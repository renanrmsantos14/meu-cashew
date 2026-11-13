import 'package:budget/colors.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/temas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _chaves = [
  'white',
  'black',
  'textLight',
  'lightDarkAccent',
  'lightDarkAccentHeavyLight',
  'canvasContainer',
  'lightDarkAccentHeavy',
  'shadowColor',
  'shadowColorLight',
  'unPaidUpcoming',
  'unPaidOverdue',
  'incomeAmount',
  'expenseAmount',
  'warningOrange',
  'starYellow',
  'dividerColor',
  'standardContainerColor',
];

void _config(String id) {
  appStateSettings = {
    'temaPronto': id,
    'materialYou': false,
    'batterySaver': false,
    'increaseTextContrast': false,
    'accentColor': '0xFF2340D8',
    'accentSystemColor': false,
    'font': 'Geist',
  };
}

void main() {
  for (final t in temasProntos) {
    testWidgets('app com tema ${t.id}', (tester) async {
      _config(t.id);
      expect(() => getLightTheme(), returnsNormally);
      expect(() => getDarkTheme(), returnsNormally);
      final cores = <String, Color>{};
      await tester.pumpWidget(MaterialApp(
        theme: getLightTheme(),
        darkTheme: getDarkTheme(),
        themeMode: modoDoTema(t.id),
        home: Builder(builder: (context) {
          for (final k in _chaves) {
            cores[k] = getColor(context, k);
          }
          return const SizedBox();
        }),
      ));
      for (final k in _chaves) {
        expect(cores[k], isNotNull, reason: k);
        expect(cores[k], isNot(Colors.red), reason: k);
      }
    });
  }

  test('getSettingConstants usa o modo do tema pronto', () {
    final s = getSettingConstants({
      'theme': 'system',
      'temaPronto': 'padrao-escuro',
      'accentColor': '0xFF000000',
    });
    expect(s['theme'], ThemeMode.dark);
  });

  test('getLightTheme/getDarkTheme usam o tema ativo', () {
    _config('padrao-escuro');
    expect(getLightTheme().scaffoldBackgroundColor,
        temaPorId('padrao-escuro').cores.bg);
    _config('sistema');
    expect(getDarkTheme().scaffoldBackgroundColor,
        temaPorId('padrao-escuro').cores.bg);
  });
}
