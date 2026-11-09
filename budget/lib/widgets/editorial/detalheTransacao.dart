import 'dart:convert';

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/mbSync/armazem.dart';
import 'package:budget/struct/mbSync/categoriaEfetiva.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart';
import 'package:budget/struct/mbSync/mapeamento.dart';
import 'package:budget/struct/meuBancoMapping.dart';
import 'package:budget/widgets/editorial/layoutDesktop.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/globalSnackbar.dart' show SnackbarMessage;
import 'package:budget/widgets/openPopup.dart' show RoutesToPopAfterDelete;
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

typedef HistoricoDetalhe = ({String quando, double valor});

class RegraDetalhe {
  final String padrao, categoria;
  final int aplicadaA;
  const RegraDetalhe(this.padrao, this.categoria, this.aplicadaA);
}

class DetalheModelo {
  final String pk, nome, conta, categoria;
  final DateTime data;
  final double valor;
  final bool receita;
  final String? fatura, pluggy, descricaoRegra;
  final RegraDetalhe? regra;
  final List<HistoricoDetalhe> historico;
  final double media;
  final int noCiclo;
  final Transaction? transacao;

  const DetalheModelo({
    required this.pk,
    required this.nome,
    required this.conta,
    required this.categoria,
    required this.data,
    required this.valor,
    required this.receita,
    this.fatura,
    this.pluggy,
    this.regra,
    this.descricaoRegra,
    this.historico = const [],
    this.media = 0,
    this.noCiclo = 0,
    this.transacao,
  });
}

String mbNormalizarDescricao(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-zà-ú ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _dataHora(DateTime d) =>
    '${diaMes(d)} ${d.year} · '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Future<DetalheModelo?> mbCarregarDetalhe(String pk) async {
  final t = await (database.select(database.transactions)
        ..where((x) => x.transactionPk.equals(pk)))
      .getSingleOrNull();
  if (t == null) return null;
  final carteira = await database.getWalletInstanceOrNull(t.walletFk);
  final categoria = await database.getCategoryInstanceOrNull(t.categoryFk);
  final agora = DateTime.now();
  final ehMb = pk.startsWith(mbPrefixo);

  final contasJson = await mbLerEstado('contas');
  final contaId = t.walletFk.startsWith(mbPrefixo)
      ? t.walletFk.substring(mbPrefixo.length)
      : null;
  String? fatura;
  if (contaId != null && contasJson != null) {
    for (final c in jsonDecode(contasJson) as List) {
      if (c is Map && '${c['id']}' == contaId && c['type'] == 'CREDIT') {
        final f = mbProximoDiaMes(c['closing_date'], agora);
        if (f != null) fatura = 'Fecha $f';
      }
    }
  }

  RegraDetalhe? regra;
  if (ehMb && contaId != null) {
    final espelho = await mbLerEspelho();
    final ctx =
        MbContextoCategoria.deRegistros(espelho.values.map((e) => e.registro));
    final ef = mbCategoriaEfetiva(
        txId: pk.substring(mbPrefixo.length),
        contaId: contaId,
        descricao: t.name,
        categoriaPluggy: null,
        receita: t.income,
        ctx: ctx);
    if (ef.fonte == 'regra') {
      bool casa(MbRegraCtx r, String nome) =>
          (r.contaId == null || r.contaId == contaId) &&
          mbPadraoCasa(r.padrao, nome);
      final r = mbOrdenarRegras(ctx.regras).firstWhere((r) => casa(r, t.name));
      final nomes = await (database.selectOnly(database.transactions)
            ..addColumns([database.transactions.name])
            ..where(database.transactions.transactionPk.like('$mbPrefixo%')))
          .map((l) => l.read(database.transactions.name) ?? '')
          .get();
      final cat = ef.categoriaId == null
          ? null
          : await database.getCategoryInstanceOrNull(pkDoId(ef.categoriaId!));
      regra = RegraDetalhe(r.padrao, cat?.name ?? categoria?.name ?? '',
          nomes.where((n) => casa(r, n)).length);
    }
  }

  final chave = mbNormalizarDescricao(t.name);
  final iguais = chave.isEmpty
      ? <Transaction>[]
      : (await (database.select(database.transactions)
                ..where((x) => x.name.like('%${chave.split(' ').first}%'))
                ..orderBy([(x) => OrderingTerm.desc(x.dateCreated)]))
              .get())
          .where((x) => mbNormalizarDescricao(x.name) == chave)
          .toList();
  final cicloJson = await mbLerEstado('ciclo');
  final ciclo = cicloJson == null ? null : jsonDecode(cicloJson) as Map?;
  final ini = DateTime.tryParse('${ciclo?['inicio']}') ??
      DateTime(agora.year, agora.month);
  final fim = DateTime.tryParse('${ciclo?['fim']}') ??
      DateTime(agora.year, agora.month + 1, 0);
  final noCiclo = iguais
      .where((x) =>
          !x.dateCreated.isBefore(ini) &&
          x.dateCreated.isBefore(fim.add(const Duration(days: 1))))
      .length;

  return DetalheModelo(
    pk: pk,
    nome: t.name,
    conta: carteira?.name ?? '',
    categoria: categoria?.name ?? '',
    data: t.dateCreated,
    valor: t.amount,
    receita: t.income,
    fatura: fatura,
    regra: regra,
    descricaoRegra: chave.isEmpty ? null : chave.toUpperCase(),
    historico: [
      for (final x in iguais.where((x) => x.transactionPk != pk).take(3))
        (quando: diaMes(x.dateCreated), valor: x.amount)
    ],
    media: iguais.isEmpty
        ? 0
        : iguais.fold<double>(0, (s, x) => s + x.amount.abs()) / iguais.length,
    noCiclo: noCiclo,
    transacao: t,
  );
}

Future<void> mbMudarCategoriaDe(BuildContext context, Transaction t) async {
  final atual = await database.getCategoryInstanceOrNull(t.categoryFk);
  if (!context.mounted) return;
  final r = await selectCategorySequence(
    context,
    selectedCategory: atual,
    setSelectedCategory: (_) {},
    selectedSubCategory: null,
    setSelectedSubCategory: (_) {},
    selectedIncomeInitial: t.income,
    allowReorder: false,
  );
  final nova = r.sub ?? r.main;
  if (nova == null || nova.categoryPk == t.categoryFk) return;
  await database.createOrUpdateTransaction(t.copyWith(
      categoryFk: nova.categoryPk,
      subCategoryFk: const Value(null),
      dateTimeModified: Value(DateTime.now())));
}

Future<void> mbCriarRegra(Transaction t, String titulo) async {
  await database.createOrUpdateAssociatedTitle(
    insert: true,
    TransactionAssociatedTitle(
      associatedTitlePk: '-1',
      categoryFk: t.categoryFk,
      isExactMatch: false,
      title: titulo,
      dateCreated: DateTime.now(),
      dateTimeModified: null,
      order: await database.getAmountOfAssociatedTitles(),
    ),
  );
}

// Registrada pelo detalhe aberto: é o que a tecla C aciona.
VoidCallback? mbAcaoMudarCategoria;

class ChipCategoria extends StatelessWidget {
  const ChipCategoria(this.texto,
      {super.key, this.receita = false, this.alerta = false});
  final String texto;
  final bool receita, alerta;

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    final fundo = alerta
        ? e.warnbg
        : receita
            ? e.pos.withOpacity(.12)
            : e.chip;
    final cor = alerta
        ? e.warntx
        : receita
            ? e.pos
            : e.acc;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(6)),
      child: Text(texto.toUpperCase(),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              letterSpacing: .3,
              color: cor)),
    );
  }
}

class DetalheTransacao extends StatefulWidget {
  const DetalheTransacao(
      {super.key,
      required this.pk,
      required this.carregar,
      this.aoMudarCategoria});
  final String pk;
  final Future<DetalheModelo?> Function(String pk) carregar;
  final Future<void> Function(DetalheModelo)? aoMudarCategoria;

  @override
  State<DetalheTransacao> createState() => _DetalheTransacaoState();
}

class _DetalheTransacaoState extends State<DetalheTransacao> {
  DetalheModelo? _m;
  bool _regraCriada = false;

  @override
  void initState() {
    super.initState();
    mbAcaoMudarCategoria = _mudarCategoria;
    _carregar();
  }

  @override
  void dispose() {
    if (mbAcaoMudarCategoria == _mudarCategoria) mbAcaoMudarCategoria = null;
    super.dispose();
  }

  Future<void> _carregar() async {
    final m = await widget.carregar(widget.pk);
    if (!mounted) return;
    if (m == null) {
      mbTransacaoSelecionada.value = null;
      return;
    }
    setState(() => _m = m);
  }

  Future<void> _mudarCategoria() async {
    final m = _m;
    if (m == null) return;
    if (widget.aoMudarCategoria != null) {
      await widget.aoMudarCategoria!(m);
    } else if (m.transacao != null) {
      await mbMudarCategoriaDe(context, m.transacao!);
    }
    if (mounted) _carregar();
  }

  Future<void> _criarRegra(DetalheModelo m) async {
    await mbCriarRegra(m.transacao!, m.descricaoRegra!);
    if (!mounted) return;
    setState(() => _regraCriada = true);
    openSnackbar(SnackbarMessage(title: 'Regra criada'));
  }

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    final m = _m;
    if (m == null) return const SizedBox.shrink();
    final sinal = m.receita ? '+' : '−';
    final linhas = <(String, Widget)>[
      ('Conta', Text(m.conta, style: EdTexto.corpo(context))),
      ('Categoria', ChipCategoria(m.categoria, receita: m.receita)),
      if (m.pluggy != null)
        ('Pluggy', Text(m.pluggy!, style: EdTexto.corpo(context))),
      if (m.fatura != null)
        ('Fatura', Text(m.fatura!, style: EdTexto.corpo(context))),
    ];
    return ColoredBox(
      color: e.surf,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text('Transação',
                              style: EdTexto.rotulo(context))),
                      Semantics(
                        button: true,
                        label: 'Fechar detalhe',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => mbTransacaoSelecionada.value = null,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: e.line)),
                                child: Icon(Icons.close, size: 16, color: e.tx),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(m.nome, style: EdTexto.h1(context)),
                  const SizedBox(height: 6),
                  Text(_dataHora(m.data), style: EdTexto.rotulo(context)),
                  const SizedBox(height: 16),
                  Text('$sinal${brl(m.valor.abs())}',
                      style: EdTexto.numeroGrande(context).copyWith(
                          fontSize: 44,
                          letterSpacing: -.045 * 44,
                          color: m.receita ? e.pos : e.tx)),
                  const SizedBox(height: 20),
                  Divider(height: 1, thickness: 1, color: e.line),
                  for (final l in linhas)
                    SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          SizedBox(
                              width: 96,
                              child:
                                  Text(l.$1, style: EdTexto.rotulo(context))),
                          Expanded(
                              child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: l.$2)),
                        ],
                      ),
                    ),
                  Divider(height: 1, thickness: 1, color: e.line),
                  const SizedBox(height: 16),
                  _blocoRegra(context, m),
                  const SizedBox(height: 24),
                  Text('HISTÓRICO AQUI', style: EdTexto.h2(context)),
                  const SizedBox(height: 8),
                  for (final h in m.historico)
                    SizedBox(
                      height: 36,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(h.quando, style: EdTexto.rotulo(context)),
                          Text(brl(h.valor.abs()),
                              style: EdTexto.corpo(context)),
                        ],
                      ),
                    ),
                  if (m.historico.isEmpty)
                    Text('Primeira compra com esta descrição.',
                        style: EdTexto.rotulo(context)),
                  const SizedBox(height: 8),
                  Text(
                      'Média ${brl(m.media)} por compra · ${m.noCiclo} no ciclo',
                      style: EdTexto.rotulo(context)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              decoration:
                  BoxDecoration(border: Border(top: BorderSide(color: e.line))),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: e.tx,
                            foregroundColor: e.bg,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8))),
                        onPressed: _mudarCategoria,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Mudar categoria'),
                            const SizedBox(width: 8),
                            Text('C',
                                style: EdTexto.mono(context)
                                    .copyWith(color: e.bg.withOpacity(.7))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (m.transacao != null) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: e.tx,
                            side: BorderSide(color: e.line),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8))),
                        onPressed: () => pushRoute(
                            context,
                            AddTransactionPage(
                                transaction: m.transacao,
                                routesToPopAfterDelete:
                                    RoutesToPopAfterDelete.None)),
                        child: const Text('Editar'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blocoRegra(BuildContext context, DetalheModelo m) {
    final e = cores(context);
    final r = m.regra;
    Widget conteudo;
    if (r != null) {
      conteudo = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${r.padrao} → ${r.categoria}',
              style:
                  EdTexto.corpo(context).copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(
              'Aplicada a ${r.aplicadaA} ${r.aplicadaA == 1 ? 'transação' : 'transações'}',
              style: EdTexto.rotulo(context)),
        ],
      );
    } else if (_regraCriada) {
      conteudo = Text('Regra criada. Vale a partir da próxima atualização.',
          style: EdTexto.rotulo(context));
    } else if (m.transacao != null && m.descricaoRegra != null) {
      conteudo = Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: 44,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
                foregroundColor: e.tx,
                side: BorderSide(color: e.line),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: () => _criarRegra(m),
            child: Text('Criar regra ${m.descricaoRegra}* → ${m.categoria}',
                overflow: TextOverflow.ellipsis),
          ),
        ),
      );
    } else {
      conteudo = Text('Sem regra automática.', style: EdTexto.rotulo(context));
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: e.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: e.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Regra automática', style: EdTexto.rotulo(context)),
          const SizedBox(height: 8),
          conteudo,
        ],
      ),
    );
  }
}
