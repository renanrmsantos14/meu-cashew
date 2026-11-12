import 'dart:convert';

import 'package:budget/colors.dart';
import 'package:budget/struct/mbSync/armazem.dart';
import 'package:budget/struct/mbSync/pluggy.dart';
import 'package:budget/struct/meuBancoSync.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Avisos de conexão do último pull (`avisos` do estado): item com login pendente ou com erro.
Future<List<Map<String, dynamic>>> mbLerAvisos() async {
  try {
    final bruto = await mbLerEstado('avisos');
    if (bruto != null) {
      return [
        for (final a in jsonDecode(bruto) as List)
          if (a is Map) Map<String, dynamic>.from(a)
      ];
    }
  } catch (_) {}
  return [];
}

Future<void> mbReconectarAviso(BuildContext context, Map<String, dynamic> aviso) async {
  final itemId = aviso['item_id'];
  if (itemId is String && itemId.isNotEmpty) {
    await mbAbrirConnect(context, itemId: itemId);
    return;
  }
  final url = Uri.tryParse('${aviso['reconnect_url'] ?? ''}');
  if (url != null && url.scheme == 'https') {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}

/// Faixa fixa no topo da Início quando um banco desconectou; some quando a conexão volta.
class HomePageConexaoCaida extends StatefulWidget {
  // `carregar` existe para os testes não precisarem do banco.
  final Future<List<Map<String, dynamic>>> Function() carregar;
  const HomePageConexaoCaida({super.key, this.carregar = mbLerAvisos});

  @override
  State<HomePageConexaoCaida> createState() => _HomePageConexaoCaidaState();
}

class _HomePageConexaoCaidaState extends State<HomePageConexaoCaida> {
  List<Map<String, dynamic>> _avisos = [];

  @override
  void initState() {
    super.initState();
    meuBancoUltimaSync.addListener(_carregar);
    _carregar();
  }

  @override
  void dispose() {
    meuBancoUltimaSync.removeListener(_carregar);
    super.dispose();
  }

  Future<void> _carregar() async {
    final avisos = await widget.carregar();
    if (mounted) setState(() => _avisos = avisos);
  }

  @override
  Widget build(BuildContext context) {
    if (_avisos.isEmpty) return const SizedBox.shrink();
    final cor = Theme.of(context).colorScheme;
    return Column(children: [
      for (final aviso in _avisos)
        Container(
          margin: const EdgeInsetsDirectional.only(start: 13, end: 13, bottom: 13),
          padding: const EdgeInsetsDirectional.all(15),
          decoration: BoxDecoration(
            color: getColor(context, "lightDarkAccentHeavyLight"),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: cor.error.withOpacity(0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.link_off_rounded, color: cor.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFont(
                        text: "${aviso['banco'] ?? 'Conexão'} desconectou",
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 6),
              TextFont(
                  text: "As compras novas não chegam até reconectar.",
                  fontSize: 14,
                  maxLines: 3),
              const SizedBox(height: 10),
              Button(
                label: "Reconectar",
                expandedLayout: true,
                onTap: () => mbReconectarAviso(context, aviso),
              ),
            ],
          ),
        ),
    ]);
  }
}
