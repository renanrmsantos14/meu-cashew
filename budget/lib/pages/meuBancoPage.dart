import 'package:budget/pages/meuBancoParear.dart';
import 'package:budget/struct/atualizador.dart';
import 'package:budget/struct/mbSync/armazem.dart';
import 'package:budget/struct/mbSync/pluggy.dart';
import 'package:budget/struct/meuBancoSync.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/functions.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

class MeuBancoPage extends StatefulWidget {
  const MeuBancoPage({Key? key}) : super(key: key);

  @override
  State<MeuBancoPage> createState() => _MeuBancoPageState();
}

class _MeuBancoPageState extends State<MeuBancoPage> {
  final TextEditingController _url =
      TextEditingController(text: meuBancoUrlPadrao);
  final TextEditingController _token = TextEditingController();
  bool _temToken = false;
  bool _atualizando = false;
  bool _procurandoAtualizacao = false;
  String? _msgAtualizacao;
  List<Map<String, dynamic>> _avisos = [];

  @override
  void initState() {
    super.initState();
    _carregar();
    _carregarAvisos();
    meuBancoUltimaSync.addListener(_carregarAvisos);
    meuBancoAtualizarFila();
  }

  Future<void> _carregar() async {
    final url = await meuBancoLerUrl();
    final token = await meuBancoLerToken();
    if (!mounted) return;
    setState(() {
      _url.text = url;
      _temToken = token != null && token.isNotEmpty;
    });
  }

  Future<void> _carregarAvisos() async {
    List<Map<String, dynamic>> avisos = [];
    try {
      final bruto = await mbLerEstado('avisos');
      if (bruto != null) {
        avisos = [
          for (final a in jsonDecode(bruto) as List)
            if (a is Map) Map<String, dynamic>.from(a)
        ];
      }
    } catch (_) {}
    if (mounted) setState(() => _avisos = avisos);
  }

  Future<void> _reconectar(Map<String, dynamic> aviso) async {
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

  @override
  void dispose() {
    meuBancoUltimaSync.removeListener(_carregarAvisos);
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _sincronizar() async {
    await meuBancoSalvarConfig(token: _token.text, url: _url.text);
    _token.clear();
    await _carregar();
    await sincronizarMeuBanco();
  }

  Future<void> _atualizarAgora() async {
    setState(() => _atualizando = true);
    final msg = await meuBancoAtualizar();
    if (mounted) setState(() => _atualizando = false);
    openSnackbar(SnackbarMessage(title: msg));
  }

  Future<void> _procurarAtualizacao() async {
    setState(() {
      _procurandoAtualizacao = true;
      _msgAtualizacao = null;
    });
    final msg = await atualizadorVerificarManual(context);
    if (!mounted) return;
    setState(() {
      _procurandoAtualizacao = false;
      _msgAtualizacao = msg.isEmpty ? null : msg;
    });
  }

  String _haQuanto(DateTime d) {
    final min = DateTime.now().difference(d).inMinutes;
    if (min < 1) return "Sincronizado agora há pouco";
    if (min < 60) return "Sincronizado há $min min";
    if (min < 1440) return "Sincronizado há ${min ~/ 60} h";
    return "Sincronizado há ${min ~/ 1440} d";
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      dragDownToDismiss: true,
      title: "Meu Banco",
      listWidgets: [
        Padding(
          padding:
              const EdgeInsetsDirectional.only(bottom: 5, start: 20, end: 20),
          child: TextFont(
            text:
                "Importa as transações do Meu Banco para o Cashew. O token fica guardado de forma segura no aparelho e não entra nos backups.",
            fontSize: 14,
            maxLines: 10,
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 20, vertical: 5),
          child: TextInput(
            labelText: "Endereço do Meu Banco",
            controller: _url,
            padding: EdgeInsetsDirectional.zero,
            keyboardType: TextInputType.url,
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 20, vertical: 5),
          child: TextInput(
            labelText: _temToken ? "Token (já salvo, cole para trocar)" : "Token (cole aqui)",
            controller: _token,
            obscureText: true,
            padding: EdgeInsetsDirectional.zero,
          ),
        ),
        if (!kIsWeb)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 20, vertical: 5),
            child: Button(
              label: "Parear com QR",
              expandedLayout: true,
              onTap: () async {
                await pushRoute(context, const MeuBancoParearPage());
                await _carregar();
              },
            ),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 20, vertical: 5),
          child: Button(
            label: "Conectar banco",
            expandedLayout: true,
            onTap: () => mbAbrirConnect(context),
          ),
        ),
        for (final aviso in _avisos)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 20, vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFont(
                  text: "${aviso['banco'] ?? 'Conexão'}: ${aviso['mensagem'] ?? ''}",
                  fontSize: 14,
                  maxLines: 6,
                ),
                const SizedBox(height: 5),
                Button(
                  label: "Reconectar",
                  expandedLayout: true,
                  onTap: () => _reconectar(aviso),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 20, vertical: 5),
          child: Button(
            label: _atualizando ? "Atualizando..." : "Atualizar agora",
            disabled: _atualizando,
            expandedLayout: true,
            onTap: _atualizarAgora,
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: meuBancoSincronizando,
          builder: (context, sincronizando, _) => Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 20, vertical: 10),
            child: Button(
              label: sincronizando ? "Sincronizando..." : "Sincronizar agora",
              disabled: sincronizando,
              expandedLayout: true,
              onTap: _sincronizar,
            ),
          ),
        ),
        ValueListenableBuilder<DateTime?>(
          valueListenable: meuBancoUltimaSync,
          builder: (context, ultima, _) => Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 20, vertical: 5),
            child: TextFont(
              text: ultima == null
                  ? "Ainda não sincronizado nesta sessão"
                  : _haQuanto(ultima),
              fontSize: 14,
              maxLines: 3,
            ),
          ),
        ),
        ValueListenableBuilder<MbFila>(
          valueListenable: meuBancoFila,
          builder: (context, fila, _) => Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 20, vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (fila.pendentes > 0)
                  TextFont(
                    text: fila.pendentes == 1
                        ? "1 alteração aguardando envio"
                        : "${fila.pendentes} alterações aguardando envio",
                    fontSize: 14,
                    maxLines: 2,
                  ),
                for (final r in fila.rejeitados)
                  TextFont(
                    text: "Rejeitado: $r",
                    fontSize: 13,
                    maxLines: 4,
                    textColor: Theme.of(context).colorScheme.error,
                  ),
              ],
            ),
          ),
        ),
        ValueListenableBuilder<String?>(
          valueListenable: meuBancoUltimoErro,
          builder: (context, erro, _) => erro == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 20, vertical: 5),
                  child: TextFont(
                    text: "Erro: " + erro,
                    fontSize: 14,
                    maxLines: 6,
                    textColor: Theme.of(context).colorScheme.error,
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 20, vertical: 10),
          child: Button(
            label: "Desconectar",
            expandedLayout: true,
            color: Theme.of(context).colorScheme.errorContainer,
            textColor: Theme.of(context).colorScheme.onErrorContainer,
            onTap: () async {
              await meuBancoDesconectar();
              await _carregar();
            },
          ),
        ),
        Padding(
          padding:
              const EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 5),
          child: TextFont(
            text:
                "Desconectar apaga o token e o ponto de sincronização. As transações já importadas continuam no app.",
            fontSize: 12,
            maxLines: 5,
          ),
        ),
        if (!kIsWeb)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 20, vertical: 10),
            child: Button(
              label: _procurandoAtualizacao
                  ? "Procurando..."
                  : "Procurar atualização",
              disabled: _procurandoAtualizacao,
              expandedLayout: true,
              onTap: _procurarAtualizacao,
            ),
          ),
        if (_msgAtualizacao != null)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 20, vertical: 5),
            child: TextFont(
              text: _msgAtualizacao!,
              fontSize: 14,
              maxLines: 6,
            ),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 20, vertical: 5),
          child: TextFont(
            text: "Versão instalada: ${packageInfoGlobal?.version ?? ""}+${packageInfoGlobal?.buildNumber ?? ""}",
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
