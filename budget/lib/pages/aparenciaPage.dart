import 'package:budget/colors.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/temas.dart';
import 'package:budget/widgets/editorial/movimento.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/util/checkWidgetLaunch.dart';
import 'package:flutter/material.dart';

class AparenciaPage extends StatefulWidget {
  const AparenciaPage({super.key});

  @override
  State<AparenciaPage> createState() => _AparenciaPageState();
}

class _AparenciaPageState extends State<AparenciaPage> {
  // Grava sem redesenhar e redesenha uma vez ao gravar "accentColor", que
  // alimenta widgets herdados do Cashew (widget da tela inicial, gráficos).
  Future<void> _salvar(String chave, String valor) async {
    await updateSettings(chave, valor, updateGlobalState: false);
    await updateSettings("accentColor", toHexString(acentoEmUso()),
        updateGlobalState: true, forceGlobalStateUpdate: true);
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
              Text("Modo", style: EdTexto.h2(context)),
              const SizedBox(height: 4),
              Text("Troca na hora e fica salvo.",
                  style: EdTexto.rotulo(context)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 24),
          child: GradeTemas(
            selecionado: idTemaSalvo(),
            aoEscolher: (id) => _salvar("temaPronto", id),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 12),
          child: Text("Cor de destaque", style: EdTexto.h2(context)),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 24),
          child: SeletorAcento(
            selecionado: acentoSalvo().id,
            aoEscolher: (id) => _salvar("acento", id),
          ),
        ),
      ],
    );
  }
}

class SeletorAcento extends StatelessWidget {
  const SeletorAcento(
      {super.key, required this.selecionado, required this.aoEscolher});
  final String selecionado;
  final ValueChanged<String> aoEscolher;

  @override
  Widget build(BuildContext context) {
    final c = cores(context);
    final brilho = Theme.of(context).brightness;
    return LayoutBuilder(builder: (context, box) {
      final largura = (box.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in acentos)
          SizedBox(
            width: largura,
            child: Semantics(
              button: true,
              selected: a.id == selecionado,
              label: a.nome,
              excludeSemantics: true,
              onTap: () => aoEscolher(a.id),
              child: ToqueEscala(
                onTap: () => aoEscolher(a.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: curvaEditorial,
                  height: 44,
                  padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 14, 0),
                  decoration: BoxDecoration(
                    color: c.surf,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: a.id == selecionado ? c.tx : c.line,
                        width: a.id == selecionado ? 1.5 : 1),
                  ),
                  child: Row(children: [
                    Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                            color: a.doBrilho(brilho), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(a.nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: EdTexto.h2(context).copyWith(color: c.tx)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

class GradeTemas extends StatelessWidget {
  const GradeTemas(
      {super.key, required this.selecionado, required this.aoEscolher});
  final String selecionado;
  final ValueChanged<String> aoEscolher;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const colunas = 3;
      const espaco = 12.0;
      final largura = (box.maxWidth - espaco * (colunas - 1)) / colunas;
      return Wrap(
        spacing: espaco,
        runSpacing: espaco,
        children: [
          for (final t in [temaSistema, ...temasProntos])
            SizedBox(
              width: largura,
              child: _CartaoTema(
                  tema: t,
                  selecionado: t.id == selecionado,
                  aoTocar: () => aoEscolher(t.id)),
            ),
        ],
      );
    });
  }
}

class _CartaoTema extends StatelessWidget {
  const _CartaoTema(
      {required this.tema, required this.selecionado, required this.aoTocar});
  final TemaPronto tema;
  final bool selecionado;
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
      child: ToqueEscala(
        onTap: aoTocar,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selecionado ? c.tx : c.line, width: selecionado ? 2 : 1),
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
                      color: c.tx)),
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
    // A miniatura mostra a cor de destaque escolhida, não a padrão do modo.
    final acento = acentoSalvo();
    EditorialCores comAcento(EditorialCores c, Brightness b) =>
        c.copyWith(acc: acento.doBrilho(b));
    if (tema.id != 'sistema') {
      return _Desenho(comAcento(tema.cores, tema.brilho));
    }
    // Cada metade mostra um desenho completo (largura dobrada) cortado ao meio.
    Widget metade(EditorialCores c, AlignmentGeometry lado) => Expanded(
        child: ClipRect(
            child: LayoutBuilder(
                builder: (_, box) => OverflowBox(
                    alignment: lado,
                    minWidth: box.maxWidth * 2,
                    maxWidth: box.maxWidth * 2,
                    child: _Desenho(c)))));
    return SizedBox(
      height: 76,
      child: Row(children: [
        metade(comAcento(EditorialCores.claro, Brightness.light),
            AlignmentDirectional.centerStart),
        metade(comAcento(EditorialCores.escuro, Brightness.dark),
            AlignmentDirectional.centerEnd),
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration:
                        BoxDecoration(color: c.acc, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Flexible(child: _traco(c.tx, 28)),
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
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
