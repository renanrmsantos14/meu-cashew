import 'dart:math';

import 'package:budget/colors.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/temas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double f(double v) =>
      v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.red / 255) + 0.7152 * f(c.green / 255) + 0.0722 * f(c.blue / 255);
}

double contraste(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (max(x, y) + 0.05) / (min(x, y) + 0.05);
}

const _idsEsperados = [
  'padrao-claro',
  'padrao-escuro',
  'azul-outlook',
  'grafite',
  'meia-noite',
  'sepia-papel',
  'floresta',
  'oceano',
  'lavanda',
  'rose',
  'ambar',
  'nord',
  'solarized-claro',
  'solarized-escuro',
  'dracula',
  'oled-preto',
  'alto-contraste-claro',
  'alto-contraste-escuro',
];

const _nomesEsperados = [
  'Padrão claro',
  'Padrão escuro',
  'Azul Outlook',
  'Grafite',
  'Meia-noite',
  'Sépia / Papel',
  'Floresta',
  'Oceano',
  'Lavanda',
  'Rosé',
  'Âmbar',
  'Nord',
  'Solarized claro',
  'Solarized escuro',
  'Dracula',
  'OLED preto',
  'Alto contraste claro',
  'Alto contraste escuro',
];

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

  test('ids e nomes exatos e na ordem', () {
    expect(temasProntos.map((t) => t.id).toList(), _idsEsperados);
    expect(temasProntos.map((t) => t.nome).toList(), _nomesEsperados);
  });

  test('padrões são as paletas editoriais atuais', () {
    expect(temaPorId('padrao-claro').cores, same(EditorialCores.claro));
    expect(temaPorId('padrao-escuro').cores, same(EditorialCores.escuro));
    expect(temaPorId('xyz').id, 'padrao-claro');
  });

  for (final t in temasProntos) {
    final minimo = t.id.startsWith('alto-contraste') ? 7.0 : 4.5;

    test('contraste de ${t.id} (mín. $minimo)', () {
      final e = t.cores;
      final falhas = <String>[];
      void par(String nome, Color a, Color b, [double? min]) {
        final c = contraste(a, b);
        if (c < (min ?? minimo)) falhas.add('$nome ${c.toStringAsFixed(2)}');
      }

      for (final fundo in {'bg': e.bg, 'surf': e.surf}.entries) {
        par('tx/${fundo.key}', e.tx, fundo.value);
        par('mu/${fundo.key}', e.mu, fundo.value);
        par('acc/${fundo.key}', e.acc, fundo.value);
        par('warn/${fundo.key}', e.warn, fundo.value);
        par('pos/${fundo.key}', e.pos, fundo.value);
        par('warntx/${fundo.key}', e.warntx, fundo.value);
      }
      final cs = temaFlutter(t).colorScheme;
      par('onPrimary/primary', cs.onPrimary, cs.primary);
      par('onPrimaryContainer/primaryContainer', cs.onPrimaryContainer,
          cs.primaryContainer);
      par('onSecondaryContainer/secondaryContainer', cs.onSecondaryContainer,
          cs.secondaryContainer);
      par('onSurface/surfaceContainerHigh', cs.onSurface,
          cs.surfaceContainerHigh);
      par('onSurface/surfaceContainerHighest', cs.onSurface,
          cs.surfaceContainerHighest);
      par('onTertiary/tertiary', cs.onTertiary, cs.tertiary);
      expect(falhas, isEmpty);
    });

    test('coresCashew e temaFlutter de ${t.id}', () {
      final a = coresCashew(t);
      for (final k in _chaves) {
        expect(a.colors.containsKey(k), isTrue, reason: k);
        expect(a.colors[k], isNotNull, reason: k);
      }
      final th = temaFlutter(t);
      expect(th.brightness, t.brilho);
      expect(th.extension<AppColors>(), isNotNull);
      expect(th.extension<EditorialCores>(), same(t.cores));
      expect(th.scaffoldBackgroundColor, t.cores.bg);
      // Cabeçalhos herdados do Cashew usam colorScheme.background.
      // ignore: deprecated_member_use
      expect(th.colorScheme.background, t.cores.bg);
      expect(
          contraste(th.colorScheme.onTertiaryContainer,
              th.colorScheme.tertiaryContainer),
          greaterThanOrEqualTo(4.5));
    });
  }

  test('temaAtivo', () {
    appStateSettings["temaPronto"] = "sistema";
    expect(temaAtivo(Brightness.light).id, 'padrao-claro');
    expect(temaAtivo(Brightness.dark).id, 'padrao-escuro');
    appStateSettings.remove("temaPronto");
    expect(temaAtivo(Brightness.dark).id, 'padrao-escuro');
    appStateSettings["temaPronto"] = "nord";
    expect(temaAtivo(Brightness.light).id, 'nord');
    expect(temaAtivo(Brightness.dark).id, 'nord');
    appStateSettings["temaPronto"] = "xyz";
    expect(temaAtivo(Brightness.light).id, 'padrao-claro');
    expect(temaAtivo(Brightness.dark).id, 'padrao-escuro');
  });

  test('modoDoTema', () {
    expect(modoDoTema('sistema'), ThemeMode.system);
    expect(modoDoTema('nord'), ThemeMode.dark);
    expect(modoDoTema('sepia-papel'), ThemeMode.light);
    expect(modoDoTema(null), ThemeMode.system);
    expect(modoDoTema('xyz'), ThemeMode.system);
  });
}
