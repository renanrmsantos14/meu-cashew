import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/editorial/layoutDesktop.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Transação aberta no painel lateral do computador (transacao == null: nova).
class EdicaoDesktop {
  const EdicaoDesktop(this.transacao);
  final Transaction? transacao;
}

/// null = painel fechado.
final ValueNotifier<EdicaoDesktop?> mbEdicaoDesktop = ValueNotifier(null);

/// Sobe a cada transação salva pelo painel: o detalhe aberto recarrega.
final ValueNotifier<int> mbEdicoesSalvas = ValueNotifier(0);

/// Pergunta ao formulário aberto se pode ser trocado (alterações não salvas pedem confirmação).
Future<bool> Function()? _podeTrocarFormulario;

/// Transferência e correção de saldo têm dois lados: só a página completa atualiza o par.
bool _precisaPaginaCompleta(Transaction? t) =>
    t != null && (t.categoryFk == '0' || t.pairedTransactionFk != null);

/// Nova/editar transação: painel lateral no computador, página inteira no celular.
Future<void> abrirTransacao(BuildContext context,
    {Transaction? transacao}) async {
  if (ehDesktop(context) && !_precisaPaginaCompleta(transacao)) {
    if (_podeTrocarFormulario != null && !await _podeTrocarFormulario!())
      return;
    mbEdicaoDesktop.value = EdicaoDesktop(transacao);
    return;
  }
  pushRoute(
      context,
      AddTransactionPage(
          transaction: transacao,
          routesToPopAfterDelete: RoutesToPopAfterDelete.None));
}

/// "45,90", "1.234,56", "R$ 12" e "12.5" → número; vazio ou inválido → null.
double? mbLerValor(String texto) {
  var t = texto.replaceAll(RegExp(r'[R$\s]'), '');
  if (t.isEmpty) return null;
  if (t.contains(',') || RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(t);
}

String _valorInicial(double v) =>
    v.toStringAsFixed(2).replaceAll('.', ',').replaceAll(RegExp(r',00$'), '');

/// Formulário único do computador: todos os campos à vista, Enter salva, Esc fecha.
class FormularioTransacao extends StatefulWidget {
  const FormularioTransacao(
      {super.key, this.edicao, this.transacao, this.categorias});
  final Transaction? transacao;

  /// Edição que abriu este formulário (só ela pode ser fechada ao salvar).
  final EdicaoDesktop? edicao;

  // Injetável para os testes não precisarem do banco.
  final Future<List<TransactionCategory>> Function()? categorias;

  @override
  State<FormularioTransacao> createState() => _FormularioTransacaoState();
}

class _FormularioTransacaoState extends State<FormularioTransacao> {
  late final Transaction? t = widget.transacao;
  late bool _receita = t?.income ?? false;
  late final _valor = TextEditingController(
      text: t == null ? '' : _valorInicial(t!.amount.abs()));
  late final _titulo = TextEditingController(text: t?.name ?? '');
  late final _notas = TextEditingController(text: t?.note ?? '');
  late String? _categoriaPk = t?.categoryFk;
  late String _carteiraPk =
      t?.walletFk ?? '${appStateSettings["selectedWalletPk"] ?? "0"}';
  late DateTime _data = t?.dateCreated ?? DateTime.now();
  List<TransactionCategory> _categorias = const [];
  String? _erro;
  bool _salvando = false;
  late final String _inicial;

  String _retrato() => [
        _receita,
        _valor.text,
        _titulo.text,
        _notas.text,
        _categoriaPk,
        _carteiraPk,
        _data
      ].join('|');

  bool get _alterado => _retrato() != _inicial;

  @override
  void initState() {
    super.initState();
    _inicial = _retrato();
    _podeTrocarFormulario = _podeSair;
    (widget.categorias ?? () => database.getAllCategories())().then((lista) {
      // Correção de saldo ("0") não é categoria de uso.
      if (mounted) {
        setState(() => _categorias = [
              for (final c in lista)
                if (c.categoryPk != '0') c
            ]);
      }
    });
  }

  Future<bool> _podeSair() async {
    if (!_alterado || _salvando) return !_salvando;
    final descartar = await openPopup<bool>(
      context,
      title: 'Descartar alterações?',
      onSubmitLabel: 'Descartar',
      onCancelLabel: 'Continuar editando',
      onSubmit: () => popRoute(context, true),
      onCancel: () => popRoute(context, false),
    );
    return descartar == true;
  }

  void _fecharSeAinda() {
    if (mbEdicaoDesktop.value == widget.edicao) mbEdicaoDesktop.value = null;
  }

  @override
  void dispose() {
    if (_podeTrocarFormulario == _podeSair) _podeTrocarFormulario = null;
    _valor.dispose();
    _titulo.dispose();
    _notas.dispose();
    super.dispose();
  }

  Future<void> _fechar() async {
    if (await _podeSair()) _fecharSeAinda();
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    final valor = mbLerValor(_valor.text);
    final categoria =
        _categorias.where((c) => c.categoryPk == _categoriaPk).firstOrNull;
    final erro = valor == null || valor <= 0
        ? 'Informe um valor maior que zero.'
        : categoria == null
            ? 'Escolha a categoria.'
            : null;
    if (erro != null) {
      setState(() => _erro = erro);
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    final nome = _titulo.text.trim();
    final quantia = _receita ? valor! : -valor!;
    // Relê a transação: a sincronização pode ter mudado ou apagado desde que o painel abriu.
    final atual = t == null
        ? null
        : await database.tryGetTransactionFromPk(t!.transactionPk);
    if (t != null && atual == null) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = 'Esta transação foi excluída. Feche o painel.';
        });
      }
      return;
    }
    final transacao = atual == null
        ? Transaction(
            transactionPk: '-1',
            name: nome,
            amount: quantia,
            note: _notas.text,
            categoryFk: categoria!.categoryPk,
            walletFk: _carteiraPk,
            dateCreated: _data,
            income: _receita,
            paid: true,
            skipPaid: true,
            periodLength: 1,
            reoccurrence: BudgetReoccurence.monthly,
          )
        : atual.copyWith(
            name: nome,
            amount: quantia,
            note: _notas.text,
            categoryFk: categoria!.categoryPk,
            // Subcategoria só vale para a categoria original.
            subCategoryFk: categoria.categoryPk == atual.categoryFk
                ? Value(atual.subCategoryFk)
                : const Value(null),
            walletFk: _carteiraPk,
            dateCreated: _data,
            income: _receita,
          );
    try {
      if (nome.isNotEmpty) await addAssociatedTitles(nome, categoria);
      await database.createOrUpdateTransaction(transacao,
          insert: atual == null, originalTransaction: atual);
      mbEdicoesSalvas.value++;
      _podeTrocarFormulario = null;
      _fecharSeAinda();
    } catch (e) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = '$e';
        });
      }
    }
  }

  Future<void> _escolherData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() =>
          _data = DateTime(d.year, d.month, d.day, _data.hour, _data.minute));
    }
  }

  Future<void> _maisOpcoes() async {
    if (!await _podeSair()) return;
    _podeTrocarFormulario = null;
    _fecharSeAinda();
    if (!mounted) return;
    pushRoute(
        context,
        AddTransactionPage(
            transaction: t,
            routesToPopAfterDelete: RoutesToPopAfterDelete.None));
  }

  InputDecoration _campo(String rotulo) => InputDecoration(
        labelText: rotulo,
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    final carteiras = Provider.of<AllWallets>(context).list;
    final categorias = _categorias.where((c) => c.income == _receita).toList();
    final agora = DateTime.now();
    final hoje = _data.year == agora.year &&
        _data.month == agora.month &&
        _data.day == agora.day;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _fechar,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _salvar,
      },
      child: FocusScope(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 8),
              child: Row(children: [
                Expanded(
                  child: Text(t == null ? 'Nova transação' : 'Editar transação',
                      style: EdTexto.h1(context).copyWith(fontSize: 20)),
                ),
                IconButton(
                  tooltip: 'Fechar (Esc)',
                  onPressed: _fechar,
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Despesa')),
                      ButtonSegment(value: true, label: Text('Receita')),
                    ],
                    selected: {_receita},
                    onSelectionChanged: (s) => setState(() {
                      _receita = s.first;
                      // A categoria de outro tipo não serve mais.
                      if (!_categorias.any((c) =>
                          c.categoryPk == _categoriaPk &&
                          c.income == _receita)) {
                        _categoriaPk = null;
                      }
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('valor'),
                    controller: _valor,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: EdTexto.numeroGrande(context).copyWith(fontSize: 28),
                    decoration: _campo('Valor').copyWith(
                        prefixText:
                            '${getCurrencyString(Provider.of<AllWallets>(context), currencyKey: Provider.of<AllWallets>(context).indexedByPk[_carteiraPk]?.currency)} '),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _salvar(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('descricao'),
                    controller: _titulo,
                    decoration: _campo('Descrição'),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _salvar(),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, box) => DropdownMenu<String>(
                      key: ValueKey('categoria-$_receita-${categorias.length}'),
                      width: box.maxWidth,
                      label: const Text('Categoria'),
                      initialSelection: _categoriaPk,
                      enableFilter: true,
                      requestFocusOnTap: true,
                      menuHeight: 320,
                      dropdownMenuEntries: [
                        for (final c in categorias)
                          DropdownMenuEntry(value: c.categoryPk, label: c.name),
                      ],
                      onSelected: (pk) => setState(() => _categoriaPk = pk),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, box) => DropdownMenu<String>(
                      key: ValueKey('conta-${carteiras.length}'),
                      width: box.maxWidth,
                      label: const Text('Conta'),
                      initialSelection: _carteiraPk,
                      dropdownMenuEntries: [
                        for (final w in carteiras)
                          DropdownMenuEntry(value: w.walletPk, label: w.name),
                      ],
                      onSelected: (pk) {
                        if (pk != null) setState(() => _carteiraPk = pk);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _escolherData,
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(hoje
                          ? 'Hoje'
                          : '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notas,
                    minLines: 2,
                    maxLines: 5,
                    decoration: _campo('Notas'),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_erro != null) ...[
                    const SizedBox(height: 12),
                    Text(_erro!,
                        style:
                            EdTexto.corpo(context).copyWith(color: e.warntx)),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: _maisOpcoes,
                      child:
                          const Text('Mais opções (recorrência, tipo, metas)…'),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration:
                  BoxDecoration(border: Border(top: BorderSide(color: e.line))),
              child: Row(children: [
                Expanded(
                  child: Text('Enter salva · Esc fecha',
                      overflow: TextOverflow.ellipsis,
                      style: EdTexto.rotulo(context)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                    onPressed: _fechar, child: const Text('Cancelar')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _salvando ? null : _salvar,
                  child: Text(_salvando ? 'Salvando…' : 'Salvar'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
