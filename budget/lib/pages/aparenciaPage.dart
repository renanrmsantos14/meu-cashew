import 'package:budget/colors.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/temas.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/util/checkWidgetLaunch.dart';
import 'package:flutter/material.dart';

class AparenciaPage extends StatefulWidget {
  const AparenciaPage({super.key});

  @override
  State<AparenciaPage> createState() => _AparenciaPageState();
}

class _AparenciaPageState extends State<AparenciaPage> {
  Future<void> _escolher(String id) async {
    await updateSettings("temaPronto", id, updateGlobalState: true);
    await updateSettings(
        "accentColor", toHexString(temaPorId(id).cores.acc),
        updateGlobalState: true);
    if (mounted) updateWidgetColorsAndText(context);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "Aparência",
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      listWidgets: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Tema", style: EdTexto.h2(context)),
              const SizedBox(height: 4),
              Text(
                  "Troca na hora e fica salvo. Alto contraste usa texto AAA (7:1).",
                  style: EdTexto.rotulo(context)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 24),
          child: GradeTemas(
            selecionado: appStateSettings["temaPronto"] is String
                ? appStateSettings["temaPronto"]
                : "sistema",
            aoEscolher: _escolher,
          ),
        ),
      ],
    );
  }
}

class GradeTemas extends StatelessWidget {
  const GradeTemas(
      {super.key, required this.selecionado, required this.aoEscolher});
  final String selecionado;
  final ValueChanged<String> aoEscolher;

  @override
  Widget build(BuildContext context) {
    final c = cores(context);
    return LayoutBuilder(builder: (context, box) {
      final colunas = MediaQuery.sizeOf(context).width < 600 ? 2 : 3;
      const espaco = 12.0;
      final largura = (box.maxWidth - espaco * (colunas - 1)) / colunas;
      return Wrap(
        spacing: espaco,
        runSpacing: espaco,
        children: [
          for (final t in temasProntos)
            SizedBox(
              width: largura,
              child: _CartaoTema(
                  tema: t,
                  selecionado: t.id == selecionado,
                  corTexto: c.tx,
                  aoTocar: () => aoEscolher(t.id)),
            ),
        ],
      );
    });
  }
}

class _CartaoTema extends StatelessWidget {
  const _CartaoTema(
      {required this.tema,
      required this.selecionado,
      required this.corTexto,
      required this.aoTocar});
  final TemaPronto tema;
  final bool selecionado;
  final Color corTexto;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = cores(context);
    return Semantics(
      button: true,
      selected: selecionado,
      label: tema.nome,
      excludeSemantics: true,
      onTap: aoTocar,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: aoTocar,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selecionado ? c.acc : c.line,
                width: selecionado ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(children: [
                _Miniatura(tema: tema),
                if (selecionado)
                  PositionedDirectional(
                    top: 6,
                    end: 6,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration:
                          BoxDecoration(color: c.acc, shape: BoxShape.circle),
                      child: Icon(Icons.check, size: 12, color: c.bg),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(tema.nome,
                  style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: corTexto)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Miniatura extends StatelessWidget {
  const _Miniatura({required this.tema});
  final TemaPronto tema;

  @override
  Widget build(BuildContext context) {
    if (tema.id != 'sistema') return _Desenho(tema.cores);
    return SizedBox(
      height: 76,
      child: Row(children: [
        Expanded(
            child: ClipRect(
                child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: .5,
                    child: _Desenho(temaPorId('padrao-claro').cores)))),
        Expanded(
            child: ClipRect(
                child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    widthFactor: .5,
                    child: _Desenho(temaPorId('padrao-escuro').cores)))),
      ]),
    );
  }
}

class _Desenho extends StatelessWidget {
  const _Desenho(this.c);
  final EditorialCores c;

  Widget _traco(Color cor, double w) => Container(
      width: w,
      height: 4,
      margin: const EdgeInsets.only(bottom: 4),
      decoration:
          BoxDecoration(color: cor, borderRadius: BorderRadius.circular(2)));

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.line)),
      child: Row(children: [
        Container(
          width: 18,
          color: c.bg,
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Column(children: [
            for (var i = 0; i < 3; i++) _traco(c.mu, 10),
          ]),
        ),
        Expanded(
          flex: 3,
          child: Container(
            color: c.surf,
            padding: const EdgeInsets.all(6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: c.acc, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                _traco(c.tx, 28),
              ]),
              _traco(c.mu, 36),
              Container(
                height: 14,
                decoration: BoxDecoration(
                    color: c.chip,
                    border: BorderDirectional(
                        start: BorderSide(color: c.acc, width: 2))),
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: Align(
                    alignment: AlignmentDirectional.topStart,
                    child: _traco(c.tx, 24)),
              ),
            ]),
          ),
        ),
        Expanded(
          flex: 2,
          child: Container(
            color: c.surf,
            padding: const EdgeInsets.all(6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _traco(c.mu, 30),
              _traco(c.mu, 22),
              const Spacer(),
              Container(
                  width: 18,
                  height: 8,
                  decoration: BoxDecoration(
                      color: c.tx, borderRadius: BorderRadius.circular(2))),
            ]),
          ),
        ),
      ]),
    );
  }
}
