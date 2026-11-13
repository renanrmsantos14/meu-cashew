import 'package:budget/pages/meuBancoConexoes.dart';
import 'package:budget/pages/meuBancoParear.dart';
import 'package:budget/struct/atualizador.dart';
import 'package:budget/struct/mbSync/armazem.dart';
import 'package:budget/struct/mbSync/pareamento.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart';
import 'package:budget/struct/meuBancoSync.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/functions.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _carregar();
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

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _sincronizar() async {
    final url = _url.text.trim().replaceAll(RegExp(r'/+$'), '');
    final segredo = _token.text;
    // Senha, token novo ou endereço diferente é pareamento: mesma validação e confirmação do QR.
    if (segredo.isNotEmpty || url != await meuBancoLerUrl()) {
      if (segredo.trim().isEmpty ||
          !mbOrigemPermitida(url, debug: kDebugMode)) {
        openSnackbar(SnackbarMessage(
            title:
                "Informe um endereço https válido e a senha do painel para parear."));
        return;
      }
      if (mbTokenValido(segredo.trim())) {
        if (!mounted ||
            !await mbConfirmarEParear(
                context, MbPareamento(url, segredo.trim()))) return;
      } else {
        // A senha só sai do aparelho depois que o usuário confirma o endereço.
        if (!mounted || !await mbConfirmarHost(context, url)) return;
        try {
          await mbParear(await mbPedirToken(url, segredo));
        } on String catch (msg) {
          openSnackbar(SnackbarMessage(title: msg));
          return;
        }
      }
      _token.clear();
      await _carregar();
      return;
    }
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

  Widget _secao(String titulo, List<Widget> filhos) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titulo, style: EdTexto.h2(context)),
            const SizedBox(height: 10),
            ...filhos,
          ],
        ),
      );

  Widget _campos() => Column(children: [
        TextInput(
          labelText: "Endereço do Meu Banco",
          controller: _url,
          padding: EdgeInsetsDirectional.zero,
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 10),
        TextInput(
          labelText: _temToken
              ? "Senha do painel ou token (para trocar)"
              : "Senha do painel ou token",
          controller: _token,
          obscureText: true,
          padding: EdgeInsetsDirectional.zero,
        ),
      ]);

  Widget _parearQr() => OutlinedButton.icon(
        onPressed: () async {
          await pushRoute(context, const MeuBancoParearPage());
          await _carregar();
        },
        icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
        label: const Text("Parear com QR"),
      );

  // Pareado: horário da última sincronização, fila e erro, com as duas ações principais.
  Widget _status() {
    final e = cores(context);
    final host = Uri.tryParse(_url.text)?.host ?? _url.text;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: e.surf,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: e.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: meuBancoUltimoErro,
            builder: (context, erro, _) => Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: erro == null ? e.pos : e.warn),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text("Pareado · $host",
                    overflow: TextOverflow.ellipsis,
                    style: EdTexto.corpo(context)
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<DateTime?>(
            valueListenable: meuBancoUltimaSync,
            builder: (context, ultima, _) => Text(
                ultima == null
                    ? "Ainda não sincronizado nesta sessão"
                    : "Sincronizado ${haQuanto(ultima, DateTime.now())}",
                style: EdTexto.rotulo(context)),
          ),
          ValueListenableBuilder<MbFila>(
            valueListenable: meuBancoFila,
            builder: (context, fila, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (fila.pendentes > 0)
                  Text(
                      fila.pendentes == 1
                          ? "1 alteração aguardando envio"
                          : "${fila.pendentes} alterações aguardando envio",
                      style: EdTexto.rotulo(context)),
                for (final r in fila.rejeitados)
                  Text("Rejeitado: $r",
                      style: EdTexto.rotulo(context).copyWith(color: e.warntx)),
              ],
            ),
          ),
          ValueListenableBuilder<String?>(
            valueListenable: meuBancoUltimoErro,
            builder: (context, erro, _) => erro == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(erro,
                        style:
                            EdTexto.rotulo(context).copyWith(color: e.warntx)),
                  ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: meuBancoSincronizando,
                builder: (context, sincronizando, _) => FilledButton(
                  onPressed: sincronizando ? null : sincronizarMeuBanco,
                  child: Text(sincronizando ? "Sincronizando…" : "Sincronizar"),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _atualizando ? null : _atualizarAgora,
                child: Text(_atualizando ? "Atualizando…" : "Atualizar bancos"),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    return PageFramework(
      dragDownToDismiss: true,
      title: "Meu Banco",
      listWidgets: [
        // Web usa a sessão do painel (cookie): está sempre pareado e não tem pareamento a trocar.
        if (_temToken || kIsWeb) ...[
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
            child: _status(),
          ),
          _secao("Contas conectadas", [const ContasConectadas()]),
          if (!kIsWeb)
            _secao("Pareamento", [
              _campos(),
              const SizedBox(height: 10),
              Row(children: [
                if (!kIsWeb) ...[
                  Expanded(child: _parearQr()),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: _sincronizar,
                    child: const Text("Trocar pareamento"),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: e.warntx),
                  onPressed: () async {
                    await meuBancoDesconectar();
                    await _carregar();
                  },
                  child: const Text("Desconectar este aparelho"),
                ),
              ),
              Text(
                  "Desconectar apaga o token e o ponto de sincronização. As transações já importadas continuam no app.",
                  style: EdTexto.rotulo(context)),
            ]),
        ] else
          _secao("Parear com o Meu Banco", [
            Text(
                "Importa contas, cartões e transações do Meu Banco. O acesso fica guardado de forma segura no aparelho e não entra nos backups.",
                style: EdTexto.corpo(context).copyWith(color: e.mu)),
            const SizedBox(height: 14),
            if (!kIsWeb) ...[_parearQr(), const SizedBox(height: 16)],
            _campos(),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _sincronizar,
              child: const Text("Parear"),
            ),
          ]),
        _secao("App", [
          if (!kIsWeb)
            OutlinedButton(
              onPressed: _procurandoAtualizacao ? null : _procurarAtualizacao,
              child: Text(_procurandoAtualizacao
                  ? "Procurando…"
                  : "Procurar atualização"),
            ),
          if (_msgAtualizacao != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_msgAtualizacao!, style: EdTexto.rotulo(context)),
            ),
          const SizedBox(height: 8),
          Text(
              "Versão instalada: ${packageInfoGlobal?.version ?? ""}+${packageInfoGlobal?.buildNumber ?? ""}",
              style: EdTexto.mono(context)),
          const SizedBox(height: 32),
        ]),
      ],
    );
  }
}
