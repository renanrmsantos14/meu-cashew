import 'package:budget/struct/editorial.dart';
import 'package:flutter/material.dart';

const Curve curvaEditorial = Cubic(.23, 1, .32, 1);

bool semMovimento(BuildContext c) => MediaQuery.of(c).disableAnimations;

class EntradaEditorial extends StatelessWidget {
  const EntradaEditorial(
      {super.key, required this.indice, required this.child});

  final int indice;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (semMovimento(context)) return child;
    final atraso = 55 * indice;
    const duracao = 420;
    final total = atraso + duracao;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(atraso / total, 1, curve: curvaEditorial),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
    );
  }
}

class ContagemValor extends StatefulWidget {
  const ContagemValor(
      {super.key, required this.valor, required this.formatar, this.estilo});

  final double valor;
  final String Function(double) formatar;
  final TextStyle? estilo;

  @override
  State<ContagemValor> createState() => _ContagemValorState();
}

class _ContagemValorState extends State<ContagemValor> {
  double _anterior = 0;

  @override
  void didUpdateWidget(ContagemValor antigo) {
    super.didUpdateWidget(antigo);
    _anterior = antigo.valor;
  }

  @override
  Widget build(BuildContext context) {
    if (semMovimento(context)) {
      return Text(widget.formatar(widget.valor), style: widget.estilo);
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.valor),
      tween: Tween(begin: _anterior, end: widget.valor),
      duration: const Duration(milliseconds: 900),
      curve: curvaEditorial,
      builder: (context, v, _) =>
          Text(widget.formatar(v), style: widget.estilo),
    );
  }
}

class MedidorEditorial extends StatelessWidget {
  const MedidorEditorial(
      {super.key, required this.fracao, this.alerta = false});

  final double fracao;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    final alvo = fracao.clamp(0.0, 1.0);
    Widget preenchimento(double v) => Transform(
          alignment: Alignment.centerLeft,
          transform: Matrix4.diagonal3Values(v, 1, 1),
          child: ColoredBox(color: alerta ? e.warn : e.acc),
        );
    return SizedBox(
      height: 2,
      child: ColoredBox(
        color: e.line,
        child: SizedBox.expand(
          child: semMovimento(context)
              ? preenchimento(alvo)
              : TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: alvo),
                  duration: const Duration(milliseconds: 900),
                  curve: curvaEditorial,
                  builder: (context, v, _) => preenchimento(v),
                ),
        ),
      ),
    );
  }
}

class BarrasDias extends StatelessWidget {
  const BarrasDias(
      {super.key,
      required this.valores,
      required this.indiceHoje,
      this.altura = 40});

  final List<double> valores;
  final int indiceHoje;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    final maior = valores.fold<double>(0, (m, v) => v > m ? v : m);
    final passado = e.tx.withOpacity(.12);
    final n = valores.length;
    const passo = 28;
    final total = 420 + passo * n;

    Widget barras(double Function(int) escala) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                child: i > indiceHoje
                    ? const SizedBox.shrink()
                    : Transform(
                        alignment: Alignment.bottomCenter,
                        transform: Matrix4.diagonal3Values(1, escala(i), 1),
                        child: SizedBox(
                          height: maior <= 0
                              ? 1
                              : (altura * valores[i] / maior)
                                  .clamp(1.0, altura),
                          child: ColoredBox(
                              color: i == indiceHoje ? e.acc : passado),
                        ),
                      ),
              ),
            ],
          ],
        );

    return SizedBox(
      height: altura,
      child: semMovimento(context)
          ? barras((_) => 1)
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: total),
              builder: (context, t, _) => barras((i) =>
                  Interval(passo * i / total, 1, curve: curvaEditorial)
                      .transform(t)),
            ),
    );
  }
}

class ToqueEscala extends StatefulWidget {
  const ToqueEscala({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<ToqueEscala> createState() => _ToqueEscalaState();
}

class _ToqueEscalaState extends State<ToqueEscala> {
  bool _pressionado = false;

  void _definir(bool v) {
    if (_pressionado != v) setState(() => _pressionado = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _definir(true),
      onPointerUp: (_) => _definir(false),
      onPointerCancel: (_) => _definir(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressionado && !semMovimento(context) ? .97 : 1,
          duration: const Duration(milliseconds: 150),
          curve: curvaEditorial,
          child: widget.child,
        ),
      ),
    );
  }
}
