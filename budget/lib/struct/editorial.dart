import 'package:budget/struct/temas.dart';
import 'package:flutter/material.dart';

class EditorialCores extends ThemeExtension<EditorialCores> {
  final Color bg, surf, tx, mu, line, acc, warn, warnbg, warntx, pos, chip;
  // Cartão de saldo: fundo e acento (variante escura), iguais nos dois modos.
  final Color card, accCartao;

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
    required this.card,
    required this.accCartao,
  });

  static const claro = EditorialCores(
      bg: Color(0xFFFFFFFF),
      surf: Color(0xFFF6F6F5),
      tx: Color(0xFF111111),
      mu: Color(0xFF6E6E73),
      line: Color(0xFFEDEDED),
      acc: Color(0xFF1F7A4C),
      warn: Color(0xFFB42318),
      warnbg: Color(0xFFFDEBEC),
      warntx: Color(0xFF9F2F2D),
      pos: Color(0xFF2F7A4A),
      chip: Color(0xFFF2F2F1),
      card: Color(0xFF111111),
      accCartao: Color(0xFF5CC783));

  static const escuro = EditorialCores(
      bg: Color(0xFF0B0B0C),
      surf: Color(0xFF151516),
      tx: Color(0xFFF2F2F2),
      mu: Color(0xFF8E8E93),
      line: Color.fromRGBO(255, 255, 255, .07),
      acc: Color(0xFF5CC783),
      warn: Color(0xFFF0726B),
      warnbg: Color.fromRGBO(240, 114, 107, .12),
      warntx: Color(0xFFF59A94),
      pos: Color(0xFF6FD394),
      chip: Color(0xFF1C1C1E),
      card: Color(0xFF1A1A1C),
      accCartao: Color(0xFF5CC783));

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
    Color? card,
    Color? accCartao,
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
        card: card ?? this.card,
        accCartao: accCartao ?? this.accCartao,
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
      card: l(card, other.card),
      accCartao: l(accCartao, other.accCartao),
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
        fontFamily: 'Geist',
        fontWeight: FontWeight.w600,
        fontSize: 24,
        height: 1.15,
        letterSpacing: -0.48,
        color: cores(c).tx,
      );

  static TextStyle h2(BuildContext c) => TextStyle(
        fontFamily: 'Geist',
        fontWeight: FontWeight.w500,
        fontSize: 13,
        letterSpacing: 0,
        color: cores(c).mu,
      );

  static TextStyle rotulo(BuildContext c) => TextStyle(
        fontFamily: 'Geist',
        fontWeight: FontWeight.w400,
        fontSize: 12.5,
        height: 1.3,
        color: cores(c).mu,
      );

  static TextStyle numeroGrande(BuildContext c, {bool desktop = false}) {
    final tamanho = desktop ? 52.0 : 40.0;
    return TextStyle(
      fontFamily: 'Geist',
      fontWeight: FontWeight.w600,
      fontSize: tamanho,
      height: 1,
      letterSpacing: -.03 * tamanho,
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

/// Cartão escuro de destaque (saldo). Dentro dele vale a paleta escura do app
/// com o fundo do cartão e o acento escuro, nos dois modos.
class CartaoEscuro extends StatelessWidget {
  const CartaoEscuro({super.key, required this.padding, required this.child});
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final e = cores(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: e.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: e.line),
      ),
      child: Theme(
        data: t.copyWith(extensions: [
          ...t.extensions.values.where((x) => x is! EditorialCores),
          EditorialCores.escuro.copyWith(
              bg: e.card,
              surf: e.card,
              acc: e.accCartao,
              line: const Color.fromRGBO(255, 255, 255, .12),
              chip: const Color.fromRGBO(255, 255, 255, .08)),
        ]),
        child: child,
      ),
    );
  }
}

ThemeData temaEditorial(Brightness b) => temaFlutter(
    temaPorId(b == Brightness.light ? 'padrao-claro' : 'padrao-escuro'));
