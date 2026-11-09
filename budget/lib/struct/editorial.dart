import 'package:budget/colors.dart';
import 'package:flutter/material.dart';

class EditorialCores extends ThemeExtension<EditorialCores> {
  final Color bg, surf, tx, mu, line, acc, warn, warnbg, warntx, pos, chip;

  const EditorialCores({
    required this.bg,
    required this.surf,
    required this.tx,
    required this.mu,
    required this.line,
    required this.acc,
    required this.warn,
    required this.warnbg,
    required this.warntx,
    required this.pos,
    required this.chip,
  });

  static const claro = EditorialCores(
      bg: Color(0xFFF7F6F3),
      surf: Color(0xFFFBFBFA),
      tx: Color(0xFF17181C),
      mu: Color(0xFF6B6A6E),
      line: Color.fromRGBO(20, 20, 30, .08),
      acc: Color(0xFF2340D8),
      warn: Color(0xFFB42318),
      warnbg: Color(0xFFFDEBEC),
      warntx: Color(0xFF9F2F2D),
      pos: Color(0xFF2F6B3A),
      chip: Color(0xFFE8ECFB));

  static const escuro = EditorialCores(
      bg: Color(0xFF0F1114),
      surf: Color(0xFF15181C),
      tx: Color(0xFFECEDEF),
      mu: Color(0xFF8D9097),
      line: Color.fromRGBO(255, 255, 255, .08),
      acc: Color(0xFF8EA4FF),
      warn: Color(0xFFF0726B),
      warnbg: Color.fromRGBO(240, 114, 107, .12),
      warntx: Color(0xFFF59A94),
      pos: Color(0xFF7FCB92),
      chip: Color.fromRGBO(142, 164, 255, .12));

  @override
  EditorialCores copyWith({
    Color? bg,
    Color? surf,
    Color? tx,
    Color? mu,
    Color? line,
    Color? acc,
    Color? warn,
    Color? warnbg,
    Color? warntx,
    Color? pos,
    Color? chip,
  }) =>
      EditorialCores(
        bg: bg ?? this.bg,
        surf: surf ?? this.surf,
        tx: tx ?? this.tx,
        mu: mu ?? this.mu,
        line: line ?? this.line,
        acc: acc ?? this.acc,
        warn: warn ?? this.warn,
        warnbg: warnbg ?? this.warnbg,
        warntx: warntx ?? this.warntx,
        pos: pos ?? this.pos,
        chip: chip ?? this.chip,
      );

  @override
  EditorialCores lerp(ThemeExtension<EditorialCores>? other, double t) {
    if (other is! EditorialCores) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return EditorialCores(
      bg: l(bg, other.bg),
      surf: l(surf, other.surf),
      tx: l(tx, other.tx),
      mu: l(mu, other.mu),
      line: l(line, other.line),
      acc: l(acc, other.acc),
      warn: l(warn, other.warn),
      warnbg: l(warnbg, other.warnbg),
      warntx: l(warntx, other.warntx),
      pos: l(pos, other.pos),
      chip: l(chip, other.chip),
    );
  }
}

EditorialCores cores(BuildContext c) =>
    Theme.of(c).extension<EditorialCores>() ??
    (Theme.of(c).brightness == Brightness.dark
        ? EditorialCores.escuro
        : EditorialCores.claro);

const _numerosTabulares = [FontFeature.tabularFigures()];

class EdTexto {
  static TextStyle h1(BuildContext c) => TextStyle(
        fontFamily: 'SerifEditorial',
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w400,
        fontSize: 26,
        height: 1.1,
        letterSpacing: -0.52,
        color: cores(c).tx,
      );

  static TextStyle h2(BuildContext c) => TextStyle(
        fontFamily: 'Geist',
        fontWeight: FontWeight.w500,
        fontSize: 12,
        letterSpacing: 0.96,
        color: cores(c).mu,
      );

  static TextStyle rotulo(BuildContext c) => TextStyle(
        fontFamily: 'Geist',
        fontWeight: FontWeight.w500,
        fontSize: 11.5,
        height: 1.2,
        color: cores(c).mu,
      );

  static TextStyle numeroGrande(BuildContext c, {bool desktop = false}) {
    final tamanho = desktop ? 64.0 : 50.0;
    return TextStyle(
      fontFamily: 'Geist',
      fontWeight: FontWeight.w300,
      fontSize: tamanho,
      height: 1,
      letterSpacing: -.045 * tamanho,
      fontFeatures: _numerosTabulares,
      color: cores(c).tx,
    );
  }

  static TextStyle corpo(BuildContext c) => TextStyle(
        fontFamily: 'Geist',
        fontWeight: FontWeight.w400,
        fontSize: 14,
        fontFeatures: _numerosTabulares,
        color: cores(c).tx,
      );

  static TextStyle mono(BuildContext c) => TextStyle(
        fontFamily: 'GeistMono',
        fontSize: 10.5,
        color: cores(c).mu,
      );
}

ThemeData temaEditorial(Brightness b) {
  final claro = b == Brightness.light;
  final e = claro ? EditorialCores.claro : EditorialCores.escuro;
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Geist',
    fontFamilyFallback: const ['Inter'],
    scaffoldBackgroundColor: e.bg,
    // fromSeed preenche os papéis de container (primaryContainer, secondaryContainer…)
    // usados pelas telas herdadas do Cashew; sem isso viram primário/branco.
    colorScheme: ColorScheme.fromSeed(seedColor: e.acc, brightness: b).copyWith(
      primary: e.acc,
      onPrimary: claro ? Colors.white : e.bg,
      secondary: e.acc,
      onSecondary: claro ? Colors.white : e.bg,
      error: e.warn,
      onError: claro ? Colors.white : e.bg,
      surface: e.bg,
      onSurface: e.tx,
      surfaceContainerLowest: e.surf,
      outline: e.line,
      outlineVariant: e.line,
    ),
    dividerTheme: DividerThemeData(color: e.line, thickness: 1, space: 1),
    cardTheme: const CardTheme(
      elevation: 0,
      color: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    splashFactory: NoSplash.splashFactory,
    typography: Typography.material2021(),
  );
  final tema = generateThemeDataWithExtension(
      themeData: base, brightness: b, accentColor: e.acc);
  return tema.copyWith(extensions: [...tema.extensions.values, e]);
}
