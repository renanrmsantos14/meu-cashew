import 'package:budget/struct/meuBancoSync.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
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

  @override
  void initState() {
    super.initState();
    _carregar();
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
    await meuBancoSalvarConfig(token: _token.text, url: _url.text);
    _token.clear();
    await _carregar();
    await sincronizarMeuBanco();
  }

  String _formatar(DateTime d) {
    String dois(int n) => n.toString().padLeft(2, "0");
    return "${dois(d.day)}/${dois(d.month)}/${d.year} ${dois(d.hour)}:${dois(d.minute)}";
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
                  ? "Última sincronização: ainda não nesta sessão"
                  : "Última sincronização: " + _formatar(ultima),
              fontSize: 14,
              maxLines: 3,
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
      ],
    );
  }
}
