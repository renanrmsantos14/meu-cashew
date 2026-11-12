import 'package:budget/colors.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart' show brl, diaMes;
import 'package:budget/struct/mbSync/revisao.dart';
import 'package:budget/struct/meuBancoMapping.dart';
import 'package:budget/struct/meuBancoSync.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/functions.dart' show popRoute;
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/util/keepAliveClientMixin.dart';
import 'package:flutter/material.dart';

const _rotulos = {
  'emprestimo': 'Empréstimo',
  'investimento': 'Investimento',
  'ajuda': 'Ajuda',
  'devolucao': 'Devolução',
  'reembolso': 'Reembolso',
  'renda': 'Renda',
};
const int _itensNoCartao = 3;

/// Categoria de despesa pelo nome: a do Cashew com o mesmo nome ou a própria do Meu Banco.
Future<String> _pkDaCategoria(String nome) async {
  final todas = await database.select(database.categories).get();
  for (final c in todas) {
    if (!c.income && c.name.toLowerCase() == nome.toLowerCase()) return c.categoryPk;
  }
  return mbPkCategoria(nome, false);
}

/// Cartão "Para revisar" da Início: some quando a fila está vazia; cada item tem os botões das opções.
class HomePageParaRevisar extends StatefulWidget {
  const HomePageParaRevisar({super.key});

  @override
  State<HomePageParaRevisar> createState() => _HomePageParaRevisarState();
}

class _HomePageParaRevisarState extends State<HomePageParaRevisar> {
  @override
  void initState() {
    super.initState();
    mbAtualizarRevisar();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<MbItemRevisao>>(
      valueListenable: meuBancoRevisar,
      builder: (context, itens, _) {
        if (itens.isEmpty) return const SizedBox.shrink();
        final cor = Theme.of(context).colorScheme;
        return KeepAliveClientMixin(
          child: Container(
            margin: const EdgeInsetsDirectional.only(start: 13, end: 13, bottom: 13),
            padding: const EdgeInsetsDirectional.all(15),
            decoration: BoxDecoration(
              color: getColor(context, "lightDarkAccentHeavyLight"),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: TextFont(
                        text: 'Para revisar',
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                        color: cor.primary,
                        borderRadius: BorderRadius.circular(20)),
                    child: TextFont(
                        text: '${itens.length}',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        textColor: cor.onPrimary),
                  ),
                ]),
                for (final i in itens.take(_itensNoCartao)) ...[
                  const SizedBox(height: 14),
                  ItemParaRevisar(item: i),
                ],
                if (itens.length > _itensNoCartao) ...[
                  const SizedBox(height: 12),
                  Button(
                    label: 'Ver todos (${itens.length})',
                    onTap: () => openBottomSheet(
                        context,
                        PopupFramework(
                            title: 'Para revisar',
                            child: ValueListenableBuilder<List<MbItemRevisao>>(
                              valueListenable: meuBancoRevisar,
                              builder: (context, todos, _) => Column(children: [
                                for (final i in todos) ...[
                                  ItemParaRevisar(item: i),
                                  const SizedBox(height: 14),
                                ]
                              ]),
                            ))),
                    expandedLayout: true,
                    color: cor.secondaryContainer,
                    textColor: cor.onSecondaryContainer,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class ItemParaRevisar extends StatefulWidget {
  const ItemParaRevisar({super.key, required this.item});
  final MbItemRevisao item;

  @override
  State<ItemParaRevisar> createState() => _ItemParaRevisarState();
}

class _ItemParaRevisarState extends State<ItemParaRevisar> {
  bool _enviando = false;

  Future<void> _responder(String resposta, {String? categoriaPk}) async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      await mbResponderRevisao(widget.item, resposta, categoriaPk: categoriaPk);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _escolherCategoria() async {
    final nomes = [...mbCategoriasProprias, mbCategoriaOutros];
    final nome = await openBottomSheet(
      context,
      PopupFramework(
        title: 'Categoria',
        subtitle: widget.item.destinatario,
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final n in nomes)
            Button(
              label: n,
              fontSize: 14,
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 14, vertical: 10),
              onTap: () => popRoute(context, n),
            ),
        ]),
      ),
    );
    if (nome is String) {
      await _responder('categoria', categoriaPk: await _pkDaCategoria(nome));
    }
  }

  Future<void> _marcarSalario(String txId) async {
    if (_enviando) return;
    setState(() => _enviando = true);
    final erro = await mbMarcarSalario(txId);
    if (erro != null) openSnackbar(SnackbarMessage(title: erro));
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    final cor = Theme.of(context).colorScheme;
    final data = DateTime.tryParse(i.data ?? '');
    final titulo = i.ehSalario
        ? 'Salário não detectado'
        : switch (i.tipo) {
            'pix_enviado' => 'Pix enviado${i.destinatario == null ? '' : ' a ${i.destinatario}'}',
            'envio_santander' => 'Enviado ao Santander',
            _ => 'Pix recebido',
          };
    final detalhe = i.ehSalario
        ? 'Há ${i.dias} dias sem salário no Inter. Qual entrada é o salário?'
        : '${brl(i.valor)}${data == null ? '' : ' · ${diaMes(data)}'}';
    return Opacity(
      opacity: _enviando ? 0.5 : 1,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextFont(text: titulo, fontSize: 15, fontWeight: FontWeight.bold),
        TextFont(
            text: detalhe,
            fontSize: 13,
            textColor: getColor(context, "textLight")),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (i.tipo == 'pix_enviado')
            _botao('Escolher categoria', cor, _escolherCategoria),
          for (final r in i.respostas)
            _botao(_rotulos[r]!, cor, () => _responder(r)),
          for (final c in i.candidatos)
            _botao('${brl(c.valor)} · ${diaMes(DateTime.tryParse(c.data) ?? DateTime.now())}',
                cor, () => _marcarSalario(c.txId)),
        ]),
      ]),
    );
  }

  Widget _botao(String rotulo, ColorScheme cor, VoidCallback onTap) => Button(
        label: rotulo,
        fontSize: 14,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 10),
        color: cor.secondaryContainer,
        textColor: cor.onSecondaryContainer,
        onTap: _enviando ? () {} : onTap,
      );
}
