import 'package:budget/colors.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart' show brl;
import 'package:budget/struct/mbSync/metas.dart';
import 'package:budget/widgets/outlinedButtonStacked.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';

/// Escolha das aplicações que compõem uma meta (tela de editar meta). Cada aplicação fica em uma meta só:
/// as que já estão em outra meta aparecem desabilitadas, com o nome dessa meta.
/// Some quando o app não tem aplicações (sem Meu Banco ou sem investimentos).
class MbAplicacoesDaMeta extends StatefulWidget {
  const MbAplicacoesDaMeta(
      {required this.metaPk, required this.selecionadas, required this.onChanged, super.key});

  /// Meta sendo editada (null = meta nova).
  final String? metaPk;
  final Set<String> selecionadas;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<MbAplicacoesDaMeta> createState() => _MbAplicacoesDaMetaState();
}

class _MbAplicacoesDaMetaState extends State<MbAplicacoesDaMeta> {
  List<MbAplicacao>? aplicacoes;
  Map<String, String> nomesDasMetas = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final lista = await mbAplicacoes();
    final metas = await database.select(database.objectives).get();
    if (!mounted) return;
    setState(() {
      aplicacoes = lista;
      nomesDasMetas = {for (final m in metas) m.objectivePk: m.name};
    });
  }

  @override
  Widget build(BuildContext context) {
    final lista = aplicacoes;
    if (lista == null || lista.isEmpty) return const SizedBox.shrink();
    final suave = getColor(context, "textLight");
    final saldo = lista
        .where((a) => widget.selecionadas.contains(a.pk))
        .fold(0.0, (s, a) => s + a.saldo);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 20, end: 20, top: 25),
      child: OutlinedContainer(
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 16, end: 16, top: 8),
                child: TextFont(text: 'Aplicações da meta', fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 16, end: 16, bottom: 4),
                child: TextFont(
                    text: 'O progresso é a soma do saldo atual das aplicações escolhidas.',
                    fontSize: 13,
                    maxLines: 3,
                    textColor: suave),
              ),
              for (final a in lista)
                Builder(builder: (context) {
                  final emOutra = a.metaPk != null && a.metaPk != widget.metaPk;
                  final marcada = widget.selecionadas.contains(a.pk);
                  return CheckboxListTile(
                    key: ValueKey('aplicacao-${a.id}'),
                    value: marcada,
                    enabled: !emOutra,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => widget.onChanged(v == true
                        ? {...widget.selecionadas, a.pk}
                        : ({...widget.selecionadas}..remove(a.pk))),
                    title: TextFont(text: a.nome, fontSize: 15, maxLines: 2),
                    subtitle: TextFont(
                        text: emOutra
                            ? 'Já na meta ${nomesDasMetas[a.metaPk] ?? ''}'.trim()
                            : (a.banco ?? ''),
                        fontSize: 12.5,
                        textColor: suave),
                    secondary: TextFont(text: brl(a.saldo), fontSize: 14, fontWeight: FontWeight.bold),
                  );
                }),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 16, end: 16, top: 6, bottom: 8),
                child: TextFont(
                    text: 'Saldo escolhido: ${brl(saldo)}',
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
