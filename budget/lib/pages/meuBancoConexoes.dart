import 'package:budget/functions.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/mbSync/conexoes.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart';
import 'package:budget/struct/mbSync/pluggy.dart';
import 'package:budget/struct/meuBancoSync.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:flutter/material.dart';

void _avisoPadrao(String mensagem) =>
    openSnackbar(SnackbarMessage(title: mensagem));

/// Bancos conectados ao Meu Banco: status, contas e ações (reconectar, remover, conectar outro).
class ContasConectadas extends StatefulWidget {
  const ContasConectadas({
    super.key,
    this.carregar = mbCarregarConexoes,
    this.remover = mbRemoverConexao,
    this.conectar = mbAbrirConnect,
    this.avisar = _avisoPadrao,
  });

  // Injetáveis para os testes não precisarem do servidor.
  final Future<List<MbConexao>> Function() carregar;
  final Future<void> Function(String itemId) remover;
  final Future<void> Function(BuildContext context, {String? itemId}) conectar;
  final void Function(String mensagem) avisar;

  @override
  State<ContasConectadas> createState() => _ContasConectadasState();
}

class _ContasConectadasState extends State<ContasConectadas> {
  List<MbConexao>? _conexoes;
  String? _erro;
  final Set<String> _removendo = {};
  int _pedido = 0; // só a resposta do pedido mais recente vale

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
    final pedido = ++_pedido;
    try {
      final lista = await widget.carregar();
      if (mounted && pedido == _pedido) {
        setState(() {
          _conexoes = lista;
          _erro = null;
        });
      }
    } catch (e) {
      if (mounted && pedido == _pedido) setState(() => _erro = '$e');
    }
  }

  Future<void> _conectar({String? itemId}) async {
    await widget.conectar(context, itemId: itemId);
    await _carregar();
  }

  Future<void> _remover(MbConexao c) async {
    final confirmou = await openPopup<bool>(
      context,
      title: 'Remover ${c.banco}?',
      description:
          'O Meu Banco para de sincronizar esse banco e as contas dele saem da Início. '
          'As transações já importadas continuam no histórico.',
      onSubmitLabel: 'Remover',
      onCancelLabel: 'Cancelar',
      onSubmit: () => popRoute(context, true),
      onCancel: () => popRoute(context, false),
    );
    if (confirmou != true || !mounted) return;
    setState(() => _removendo.add(c.id));
    _pedido++; // descarta um GET em andamento, que ainda traria a conexão
    try {
      await widget.remover(c.id);
      if (mounted) setState(() => _conexoes?.removeWhere((x) => x.id == c.id));
      widget.avisar('${c.banco} removido');
      sincronizarMeuBanco();
    } catch (e) {
      widget.avisar('$e');
    } finally {
      if (mounted) setState(() => _removendo.remove(c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    final conexoes = _conexoes;
    final List<Widget> filhos;
    if (conexoes == null && _erro == null) {
      filhos = [
        for (var i = 0; i < 2; i++)
          Container(
            height: 112,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: e.surf, borderRadius: BorderRadius.circular(16)),
          ),
      ];
    } else if (conexoes == null) {
      filhos = [
        Text(_erro!, style: EdTexto.corpo(context).copyWith(color: e.mu)),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
              onPressed: _carregar, child: const Text('Tentar de novo')),
        ),
      ];
    } else {
      filhos = [
        if (_erro != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Não foi possível atualizar: $_erro',
                style: EdTexto.rotulo(context).copyWith(color: e.warntx)),
          ),
        if (conexoes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Nenhum banco conectado ainda.',
                style: EdTexto.corpo(context).copyWith(color: e.mu)),
          ),
        for (final c in conexoes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CartaoConexao(
              conexao: c,
              removendo: _removendo.contains(c.id),
              aoReconectar: () => _conectar(itemId: c.id),
              aoRemover: () => _remover(c),
            ),
          ),
      ];
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...filhos,
        OutlinedButton.icon(
          onPressed: () => _conectar(),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Conectar banco'),
        ),
      ],
    );
  }
}

class _CartaoConexao extends StatelessWidget {
  const _CartaoConexao({
    required this.conexao,
    required this.removendo,
    required this.aoReconectar,
    required this.aoRemover,
  });
  final MbConexao conexao;
  final bool removendo;
  final VoidCallback aoReconectar, aoRemover;

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    final c = conexao;
    final s = c.situacao;
    final alerta = s.situacao == MbSituacao.reconectar;
    final corChip = switch (s.situacao) {
      MbSituacao.emDia => e.pos,
      MbSituacao.reconectar => e.warntx,
      MbSituacao.atualizando => e.mu,
    };
    return AnimatedOpacity(
      opacity: removendo ? .4 : 1,
      duration: const Duration(milliseconds: 180),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        decoration: BoxDecoration(
          color: e.surf,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: alerta ? e.warn.withOpacity(.4) : e.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: e.chip, borderRadius: BorderRadius.circular(10)),
                  child: Text(c.sigla,
                      style: TextStyle(
                          fontFamily: 'GeistMono',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: e.tx)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.banco,
                          overflow: TextOverflow.ellipsis,
                          style: EdTexto.corpo(context).copyWith(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      if (c.atualizado != null)
                        Text(
                            'Atualizada ${haQuanto(c.atualizado!, DateTime.now())}',
                            style: EdTexto.rotulo(context)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: alerta ? e.warnbg : e.chip,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(s.rotulo,
                      style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: corChip)),
                ),
              ]),
            ),
            if (c.contas.isNotEmpty) const SizedBox(height: 10),
            for (final conta in c.contas)
              Padding(
                padding:
                    const EdgeInsetsDirectional.only(start: 48, end: 4, top: 4),
                child: Row(children: [
                  Expanded(
                    child: Text('${conta.nome} · ${conta.tipo}',
                        overflow: TextOverflow.ellipsis,
                        style: EdTexto.rotulo(context)),
                  ),
                  if (conta.saldo != null)
                    Text(
                        conta.cartao
                            ? 'Fatura ${brl(conta.saldo!)}'
                            : brl(conta.saldo!),
                        style: EdTexto.corpo(context).copyWith(fontSize: 13)),
                ]),
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (removendo)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else ...[
                  TextButton(
                    onPressed: aoRemover,
                    style: TextButton.styleFrom(foregroundColor: e.warntx),
                    child: const Text('Remover'),
                  ),
                  TextButton(
                    onPressed: aoReconectar,
                    style: alerta
                        ? TextButton.styleFrom(
                            backgroundColor: e.tx, foregroundColor: e.bg)
                        : null,
                    child: Text(alerta ? 'Reconectar' : 'Atualizar login'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
