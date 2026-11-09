import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart';
import 'package:budget/struct/navBarIconsData.dart';
import 'package:budget/widgets/editorial/lateralEditorial.dart';
import 'package:budget/widgets/editorial/layoutDesktop.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef ResultadoBusca = ({
  String pk,
  String nome,
  String quando,
  double valor,
  bool receita
});

const int _limiteBusca = 20;

Future<List<ResultadoBusca>> mbBuscarTransacoes(String q) async {
  final t = database.transactions;
  final linhas = await (database.select(t)
        ..where((x) => database.onlyShowTransactionBasedOnSearchQuery(x, q,
            withCategories: false,
            joinedWithSubcategoriesTable: null,
            joinedWithObjectiveLoans: null))
        ..orderBy([(x) => OrderingTerm.desc(x.dateCreated)])
        ..limit(_limiteBusca))
      .get();
  final agora = DateTime.now();
  return [
    for (final x in linhas)
      (
        pk: x.transactionPk,
        nome: x.name,
        quando: quandoRelativo(x.dateCreated, agora),
        valor: x.amount,
        receita: x.income
      )
  ];
}

bool _buscaAberta = false;

Future<void> abrirBuscaRapida(
    {Future<List<ResultadoBusca>> Function(String q) buscar =
        mbBuscarTransacoes}) async {
  final nav = navigatorKey.currentState;
  if (nav == null || _buscaAberta) return;
  _buscaAberta = true;
  try {
    await nav.push(RawDialogRoute<void>(
      barrierDismissible: true,
      barrierLabel: 'Fechar busca',
      barrierColor: const Color(0x66000000),
      transitionDuration: Duration.zero,
      pageBuilder: (context, _, __) => BuscaRapida(buscar: buscar),
    ));
  } finally {
    _buscaAberta = false;
  }
}

class _Item {
  const _Item(this.rotulo, this.detalhe, this.abrir,
      {this.valor, this.receita = false});
  final String rotulo;
  final String detalhe;
  final VoidCallback abrir;
  final double? valor;
  final bool receita;
}

class BuscaRapida extends StatefulWidget {
  const BuscaRapida({super.key, required this.buscar});
  final Future<List<ResultadoBusca>> Function(String q) buscar;

  @override
  State<BuscaRapida> createState() => _BuscaRapidaState();
}

class _BuscaRapidaState extends State<BuscaRapida> {
  final _campo = TextEditingController();
  final _foco = FocusNode();
  List<ResultadoBusca> _transacoes = const [];
  int _indice = 0;
  int _geracao = 0;

  @override
  void initState() {
    super.initState();
    _campo.addListener(_aoDigitar);
  }

  @override
  void dispose() {
    _campo.dispose();
    _foco.dispose();
    super.dispose();
  }

  Future<void> _aoDigitar() async {
    final q = _campo.text.trim();
    final minha = ++_geracao;
    final r = q.isEmpty ? <ResultadoBusca>[] : await widget.buscar(q);
    if (!mounted || minha != _geracao) return;
    setState(() {
      _transacoes = r;
      _indice = 0;
    });
  }

  List<_Item> get _itens {
    final q = _campo.text.trim().toLowerCase();
    return [
      for (final p in mbItensLateral)
        if (q.isEmpty || p.rotulo.toLowerCase().contains(q))
          _Item(p.rotulo, 'Ir para', () {
            Navigator.of(context).pop();
            mbIrParaPagina(
                navBarIconsData[p.chave]!.navigationIndexedStackIndex);
          }),
      for (final t in _transacoes)
        _Item(t.nome, t.quando, () {
          Navigator.of(context).pop();
          mbTransacaoSelecionada.value = t.pk;
        }, valor: t.valor, receita: t.receita),
    ];
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent ev) {
    if (ev is KeyUpEvent) return KeyEventResult.ignored;
    final n = _itens.length;
    if (ev.logicalKey == LogicalKeyboardKey.arrowDown && n > 0) {
      setState(() => _indice = (_indice + 1) % n);
      return KeyEventResult.handled;
    }
    if (ev.logicalKey == LogicalKeyboardKey.arrowUp && n > 0) {
      setState(() => _indice = (_indice - 1 + n) % n);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _abrirSelecionado() {
    final itens = _itens;
    if (itens.isNotEmpty) itens[_indice.clamp(0, itens.length - 1)].abrir();
  }

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    final itens = _itens;
    final irPara = itens.where((i) => i.detalhe == 'Ir para').toList();
    final trans = itens.where((i) => i.detalhe != 'Ir para').toList();
    Widget grupo(String titulo, List<_Item> lista) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(titulo, style: EdTexto.h2(context)),
            ),
            for (final i in lista)
              _LinhaBusca(item: i, ativa: itens.indexOf(i) == _indice),
          ],
        );
    return Align(
      alignment: const Alignment(0, -.5),
      child: Material(
        color: e.surf,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: e.line)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Focus(
                  onKeyEvent: _tecla,
                  child: TextField(
                    controller: _campo,
                    focusNode: _foco,
                    autofocus: true,
                    style: EdTexto.corpo(context).copyWith(fontSize: 16),
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _abrirSelecionado(),
                    decoration: InputDecoration(
                      hintText: 'Buscar ou ir para…',
                      hintStyle: EdTexto.corpo(context)
                          .copyWith(fontSize: 16, color: e.mu),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
                Divider(height: 1, thickness: 1, color: e.line),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      if (irPara.isNotEmpty) grupo('Ir para', irPara),
                      if (trans.isNotEmpty) grupo('Transações', trans),
                      if (irPara.isEmpty && trans.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Nada encontrado.',
                              style: EdTexto.rotulo(context)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinhaBusca extends StatelessWidget {
  const _LinhaBusca({required this.item, required this.ativa});
  final _Item item;
  final bool ativa;

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: item.abrir,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: ativa ? e.chip : null,
          border: Border(
              left: BorderSide(
                  color: ativa ? e.acc : Colors.transparent, width: 2)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(item.rotulo,
                  overflow: TextOverflow.ellipsis,
                  style: EdTexto.corpo(context)
                      .copyWith(fontWeight: FontWeight.w500)),
            ),
            if (item.valor != null) ...[
              Text('${item.receita ? '+' : '−'}${brl(item.valor!.abs())}',
                  style: EdTexto.corpo(context)
                      .copyWith(color: item.receita ? e.pos : e.tx)),
              const SizedBox(width: 12),
            ],
            if (item.valor != null)
              Text(item.detalhe, style: EdTexto.rotulo(context)),
          ],
        ),
      ),
    );
  }
}
