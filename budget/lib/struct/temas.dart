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

/// Cor de acento escolhida na tela Aparência, com variante para cada modo.
class Acento {
  final String id;
  final String nome;
  final Color claro;
  final Color escuro;
  const Acento(this.id, this.nome, this.claro, this.escuro);
  Color doBrilho(Brightness b) => b == Brightness.dark ? escuro : claro;
}

// Contraste testado em test/temas_test.dart (>= 4,5:1 sobre bg e surf).
const List<Acento> acentos = [
  Acento('verde', 'Verde', Color(0xFF1F7A4C), Color(0xFF5CC783)),
  Acento('azul', 'Azul', Color(0xFF2340D8), Color(0xFF8EA4FF)),
  Acento('grafite', 'Grafite', Color(0xFF2B2B2E), Color(0xFFD4D4D8)),
  Acento('terracota', 'Terracota', Color(0xFFB0481F), Color(0xFFF0936A)),
];

Acento acentoPorId(String? id) =>
    acentos.firstWhere((a) => a.id == id, orElse: () => acentos.first);

Acento acentoSalvo() => acentoPorId(appStateSettings["acento"]);

TemaPronto _comAcento(TemaPronto t, Acento a) {
  final acc = a.doBrilho(t.brilho);
  return TemaPronto(
      id: t.id,
      nome: t.nome,
      brilho: t.brilho,
      cores: t.cores.copyWith(acc: acc, accCartao: a.escuro));
}

// Modos fixos. Os ids antigos ficam para não perder a escolha de quem já usava.
final List<TemaPronto> temasProntos = List.unmodifiable(const [
  TemaPronto(
      id: 'padrao-claro',
      nome: 'Claro',
      brilho: Brightness.light,
      cores: EditorialCores.claro),
  TemaPronto(
      id: 'padrao-escuro',
      nome: 'Escuro',
      brilho: Brightness.dark,
      cores: EditorialCores.escuro),
]);

// Opção "Seguir o sistema": fica fora de temasProntos.
const temaSistema = TemaPronto(
    id: 'sistema',
    nome: 'Sistema',
    brilho: Brightness.light,
    cores: EditorialCores.claro);

TemaPronto temaPorId(String id) => id == 'sistema'
    ? temaSistema
    : temasProntos.firstWhere((t) => t.id == id,
        orElse: () => temasProntos.first);

/// Id salvo; um dos 18 temas antigos (removidos) vira "sistema".
String idTemaSalvo() {
  final id = appStateSettings["temaPronto"];
  return temasProntos.any((t) => t.id == id) ? id as String : 'sistema';
}

TemaPronto temaAtivo(Brightness plataforma) {
  final id = idTemaSalvo();
  final base = id == 'sistema'
      ? temaPorId(
          plataforma == Brightness.dark ? 'padrao-escuro' : 'padrao-claro')
      : temaPorId(id);
  return _comAcento(base, acentoSalvo());
}

/// Acento do modo em uso, para o "accentColor" dos widgets herdados do Cashew.
/// Em "Sistema" segue o brilho atual do aparelho.
Color acentoEmUso() =>
    temaAtivo(WidgetsBinding.instance.platformDispatcher.platformBrightness)
        .cores
        .acc;

ThemeMode modoDoTema(String? id) => switch (id) {
      'padrao-claro' => ThemeMode.light,
      'padrao-escuro' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

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
    // Gasto em tom neutro; só renda ganha cor (verde).
    "expenseAmount": e.tx,
    // Estouro de orçamento/limite continua em alerta.
    "overspentAmount": e.warn,
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
  final container = Color.alphaBlend(e.acc.withOpacity(.12), e.bg);
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
        // Botão principal na cor do texto, como o Button do app.
        backgroundColor: e.tx,
        foregroundColor: e.bg,
        minimumSize: const Size(64, 48),
        textStyle: const TextStyle(
            fontFamily: 'Geist', fontWeight: FontWeight.w600, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: e.tx,
        side: BorderSide(color: e.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: e.tx,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      backgroundColor: e.tx,
      foregroundColor: e.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: e.surf,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: e.line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: e.line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: e.acc, width: 1.5)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: e.bg,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: e.bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: e.chip,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: TextStyle(fontFamily: 'Geist', fontSize: 13, color: e.tx),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: e.acc,
      linearTrackColor: e.line,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
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
