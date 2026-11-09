import 'package:budget/colors.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/settings.dart';
import 'package:flutter/material.dart';

class TemaPronto {
  final String id;
  final String nome;
  final Brightness brilho;
  final EditorialCores cores;
  const TemaPronto(
      {required this.id,
      required this.nome,
      required this.brilho,
      required this.cores});
}

Color _opaco(Color fg, double alfa, Color bg) =>
    Color.alphaBlend(fg.withOpacity(alfa), bg);

TemaPronto _tema(
  String id,
  String nome,
  Brightness brilho, {
  required int bg,
  required int surf,
  required int tx,
  required int mu,
  required int acc,
  required int warn,
  required int pos,
  bool altoContraste = false,
}) {
  final claro = brilho == Brightness.light;
  final b = Color(0xFF000000 | bg);
  final w = Color(0xFF000000 | warn);
  final a = Color(0xFF000000 | acc);
  final Color line = altoContraste
      ? (claro
          ? const Color.fromRGBO(0, 0, 0, .6)
          : const Color.fromRGBO(255, 255, 255, .6))
      : (claro
          ? const Color.fromRGBO(20, 20, 30, .08)
          : const Color.fromRGBO(255, 255, 255, .08));
  return TemaPronto(
    id: id,
    nome: nome,
    brilho: brilho,
    cores: EditorialCores(
      bg: b,
      surf: Color(0xFF000000 | surf),
      tx: Color(0xFF000000 | tx),
      mu: Color(0xFF000000 | mu),
      line: line,
      acc: a,
      warn: w,
      warnbg: _opaco(w, .12, b),
      warntx: w,
      pos: Color(0xFF000000 | pos),
      chip: _opaco(a, .12, b),
    ),
  );
}

final List<TemaPronto> temasProntos = List.unmodifiable([
  const TemaPronto(
      id: 'padrao-claro',
      nome: 'Padrão claro',
      brilho: Brightness.light,
      cores: EditorialCores.claro),
  const TemaPronto(
      id: 'padrao-escuro',
      nome: 'Padrão escuro',
      brilho: Brightness.dark,
      cores: EditorialCores.escuro),
  _tema('azul-outlook', 'Azul Outlook', Brightness.light,
      bg: 0xF3F2F1, surf: 0xFFFFFF, tx: 0x201F1E, mu: 0x605E5C, acc: 0x0F6CBD, warn: 0xB42318, pos: 0x2F6B3A),
  _tema('grafite', 'Grafite', Brightness.dark,
      bg: 0x1C1C1E, surf: 0x252527, tx: 0xEDEDED, mu: 0x9A9A9E, acc: 0xA8B8D8, warn: 0xF0726B, pos: 0x7FCB92),
  _tema('meia-noite', 'Meia-noite', Brightness.dark,
      bg: 0x0E1230, surf: 0x151A3D, tx: 0xE6E8F5, mu: 0x9AA0C4, acc: 0x8FA2FF, warn: 0xF0726B, pos: 0x7FCB92),
  _tema('sepia-papel', 'Sépia / Papel', Brightness.light,
      bg: 0xF4ECD8, surf: 0xFBF6E9, tx: 0x3B2F1E, mu: 0x6E5E45, acc: 0x8A4B14, warn: 0xA3261B, pos: 0x3C6B2F),
  _tema('floresta', 'Floresta', Brightness.light,
      bg: 0xF1F5EF, surf: 0xFAFCF9, tx: 0x1E2A1F, mu: 0x566356, acc: 0x2F6B3A, warn: 0xB42318, pos: 0x2F6B3A),
  _tema('oceano', 'Oceano', Brightness.dark,
      bg: 0x0B1F24, surf: 0x10292F, tx: 0xE3F1F2, mu: 0x8FB0B4, acc: 0x5CC8D0, warn: 0xF0726B, pos: 0x7FCB92),
  _tema('lavanda', 'Lavanda', Brightness.light,
      bg: 0xF3F0FA, surf: 0xFBFAFE, tx: 0x241F33, mu: 0x645E78, acc: 0x5B3FC4, warn: 0xB42318, pos: 0x2F6B3A),
  _tema('rose', 'Rosé', Brightness.light,
      bg: 0xFBF0F2, surf: 0xFFF8F9, tx: 0x2E1D22, mu: 0x6F5A60, acc: 0xB4234A, warn: 0x9A3412, pos: 0x2F6B3A),
  _tema('ambar', 'Âmbar', Brightness.dark,
      bg: 0x211A10, surf: 0x2A2216, tx: 0xF2E8D8, mu: 0xB3A386, acc: 0xF0B44C, warn: 0xF0726B, pos: 0x9BCF7F),
  _tema('nord', 'Nord', Brightness.dark,
      bg: 0x2E3440, surf: 0x3B4252, tx: 0xECEFF4, mu: 0xC2C9D6, acc: 0x88C0D0, warn: 0xF2A0A8, pos: 0xA3D98C),
  _tema('solarized-claro', 'Solarized claro', Brightness.light,
      bg: 0xFDF6E3, surf: 0xFFFBF0, tx: 0x073642, mu: 0x4F6670, acc: 0x1A6FA8, warn: 0xB5281F, pos: 0x4D6B00),
  _tema('solarized-escuro', 'Solarized escuro', Brightness.dark,
      bg: 0x002B36, surf: 0x073642, tx: 0xEEE8D5, mu: 0xA3B1B1, acc: 0x4FB3E8, warn: 0xF2867F, pos: 0xA8C94A),
  _tema('dracula', 'Dracula', Brightness.dark,
      bg: 0x282A36, surf: 0x343746, tx: 0xF8F8F2, mu: 0xB4B8D6, acc: 0xBD93F9, warn: 0xFF7878, pos: 0x50FA7B),
  _tema('oled-preto', 'OLED preto', Brightness.dark,
      bg: 0x000000, surf: 0x0A0A0A, tx: 0xEDEDED, mu: 0x9A9A9A, acc: 0x8EA4FF, warn: 0xF0726B, pos: 0x7FCB92),
  _tema('alto-contraste-claro', 'Alto contraste claro', Brightness.light,
      bg: 0xFFFFFF, surf: 0xFFFFFF, tx: 0x000000, mu: 0x2B2B2B, acc: 0x0030B8, warn: 0x9E0000, pos: 0x004D1A,
      altoContraste: true),
  _tema('alto-contraste-escuro', 'Alto contraste escuro', Brightness.dark,
      bg: 0x000000, surf: 0x000000, tx: 0xFFFFFF, mu: 0xDADADA, acc: 0xA8BCFF, warn: 0xFF9A90, pos: 0x8BEB99,
      altoContraste: true),
]);

// Opção "Seguir o sistema": fica fora de temasProntos (são os 18 temas fixos).
const temaSistema = TemaPronto(
    id: 'sistema',
    nome: 'Seguir o sistema',
    brilho: Brightness.light,
    cores: EditorialCores.claro);

TemaPronto temaPorId(String id) => id == 'sistema'
    ? temaSistema
    : temasProntos.firstWhere((t) => t.id == id,
        orElse: () => temasProntos.first);

String idTemaSalvo() {
  final id = appStateSettings["temaPronto"];
  return id is String ? id : 'sistema';
}

TemaPronto _padraoDoBrilho(Brightness b) =>
    temaPorId(b == Brightness.dark ? 'padrao-escuro' : 'padrao-claro');

TemaPronto temaAtivo(Brightness plataforma) {
  final id = appStateSettings["temaPronto"];
  if (id is! String || id == 'sistema') return _padraoDoBrilho(plataforma);
  for (final t in temasProntos) {
    if (t.id == id) return t;
  }
  return _padraoDoBrilho(plataforma);
}

ThemeMode modoDoTema(String? id) {
  if (id == null || id == 'sistema') return ThemeMode.system;
  for (final t in temasProntos) {
    if (t.id == id) {
      return t.brilho == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
    }
  }
  return ThemeMode.system;
}

AppColors coresCashew(TemaPronto t) {
  final e = t.cores;
  final claro = t.brilho == Brightness.light;
  return AppColors(colors: {
    "white": e.surf,
    "black": e.tx,
    "textLight": e.mu,
    "lightDarkAccent": Color.lerp(e.bg, e.tx, .03),
    "lightDarkAccentHeavyLight": e.surf,
    "canvasContainer": Color.lerp(e.bg, e.tx, .08),
    "lightDarkAccentHeavy": Color.lerp(e.bg, e.tx, .08),
    "shadowColor": e.tx.withOpacity(.22),
    "shadowColorLight": e.tx.withOpacity(.08),
    "unPaidUpcoming": e.acc,
    "unPaidOverdue": e.warn,
    "incomeAmount": e.pos,
    "expenseAmount": e.warn,
    "warningOrange": claro ? const Color(0xFF9A5B00) : const Color(0xFFE0A15E),
    "starYellow": claro ? const Color(0xFFB98900) : const Color(0xFFFFD54F),
    "dividerColor": e.line,
    "standardContainerColor": e.surf,
  });
}

Color _melhorSobre(Color fundo, List<Color> candidatos) {
  double contraste(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
  }

  return candidatos.reduce(
      (a, b) => contraste(a, fundo) >= contraste(b, fundo) ? a : b);
}

ThemeData temaFlutter(TemaPronto t) {
  final e = t.cores;
  final b = t.brilho;
  final cashew = coresCashew(t);
  final container = Color.alphaBlend(e.chip, e.bg);
  final sobreAcc = _melhorSobre(e.acc, [Colors.white, e.bg]);
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Geist',
    fontFamilyFallback: const ['Inter'],
    scaffoldBackgroundColor: e.bg,
    // fromSeed preenche os papéis de container (primaryContainer, secondaryContainer…)
    // usados pelas telas herdadas do Cashew; sem isso viram primário/branco.
    colorScheme: ColorScheme.fromSeed(seedColor: e.acc, brightness: b).copyWith(
      primary: e.acc,
      onPrimary: sobreAcc,
      secondary: e.acc,
      onSecondary: sobreAcc,
      error: e.warn,
      onError: _melhorSobre(e.warn, [Colors.white, e.bg]),
      surface: e.bg,
      onSurface: e.tx,
      onSurfaceVariant: e.mu,
      // `background` é deprecado, mas as telas herdadas do Cashew ainda o usam
      // (cabeçalhos); sem isso ficaria a cor gerada pelo fromSeed.
      // ignore: deprecated_member_use
      background: e.bg,
      // ignore: deprecated_member_use
      onBackground: e.tx,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: e.surf,
      surfaceContainerLow: e.surf,
      surfaceContainer: e.surf,
      surfaceContainerHigh: Color.lerp(e.bg, e.tx, .06),
      surfaceContainerHighest: Color.lerp(e.bg, e.tx, .10),
      primaryContainer: container,
      onPrimaryContainer: e.tx,
      secondaryContainer: container,
      onSecondaryContainer: e.tx,
      tertiary: e.pos,
      onTertiary: _melhorSobre(e.pos, [Colors.white, e.bg]),
      tertiaryContainer: Color.alphaBlend(e.pos.withOpacity(.12), e.bg),
      onTertiaryContainer: e.tx,
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
  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[cashew, e],
    appBarTheme: AppBarTheme(
      systemOverlayStyle: getSystemUiOverlayStyle(cashew, b),
    ),
  );
}
