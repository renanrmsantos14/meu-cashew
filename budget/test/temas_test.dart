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

const _idsEsperados = ['padrao-claro', 'padrao-escuro'];

const _nomesEsperados = ['Claro', 'Escuro'];

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

  TemaPronto ativo(String id, String acento) {
    appStateSettings["temaPronto"] = id;
    appStateSettings["acento"] = acento;
    return temaAtivo(Brightness.light);
  }

  for (final base in temasProntos) {
   for (final acento in acentos) {
    const minimo = 4.5;
    final nome = '${base.id}/${acento.id}';

    test('contraste de $nome (mín. $minimo)', () {
      final t = ativo(base.id, acento.id);
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

    test('coresCashew e temaFlutter de $nome', () {
      final t = ativo(base.id, acento.id);
      expect(t.cores.acc, acento.doBrilho(t.brilho));
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
  }

  test('temaAtivo', () {
    appStateSettings["temaPronto"] = "sistema";
    expect(temaAtivo(Brightness.light).id, 'padrao-claro');
    expect(temaAtivo(Brightness.dark).id, 'padrao-escuro');
    appStateSettings.remove("temaPronto");
    expect(temaAtivo(Brightness.dark).id, 'padrao-escuro');
    appStateSettings["temaPronto"] = "padrao-escuro";
    expect(temaAtivo(Brightness.light).id, 'padrao-escuro');
    // Tema antigo removido (um dos 18) segue o sistema.
    appStateSettings["temaPronto"] = "nord";
    expect(temaAtivo(Brightness.light).id, 'padrao-claro');
    expect(temaAtivo(Brightness.dark).id, 'padrao-escuro');
    expect(idTemaSalvo(), 'sistema');
    appStateSettings["temaPronto"] = "xyz";
    expect(temaAtivo(Brightness.light).id, 'padrao-claro');
    expect(temaAtivo(Brightness.dark).id, 'padrao-escuro');
  });

  test('acento salvo, padrão verde e id inválido', () {
    expect(temaAtivo(Brightness.light).cores.acc, acentos.first.claro);
    appStateSettings["acento"] = "azul";
    expect(temaAtivo(Brightness.dark).cores.acc, acentoPorId('azul').escuro);
    appStateSettings["acento"] = "roxo";
    expect(acentoSalvo().id, 'verde');
  });

  test('modoDoTema', () {
    expect(modoDoTema('sistema'), ThemeMode.system);
    expect(modoDoTema('padrao-escuro'), ThemeMode.dark);
    expect(modoDoTema('padrao-claro'), ThemeMode.light);
    expect(modoDoTema('nord'), ThemeMode.system);
    expect(modoDoTema(null), ThemeMode.system);
    expect(modoDoTema('xyz'), ThemeMode.system);
  });
}
