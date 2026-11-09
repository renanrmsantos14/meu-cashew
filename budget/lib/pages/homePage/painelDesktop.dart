import 'dart:async';

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart';
import 'package:budget/struct/meuBancoSync.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/pages/budgetPage.dart' show determineBudgetPolarity;
import 'package:budget/widgets/editorial/buscaRapida.dart';
import 'package:budget/widgets/editorial/detalheTransacao.dart';
import 'package:budget/widgets/editorial/layoutDesktop.dart';
import 'package:budget/widgets/editorial/movimento.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/globalSnackbar.dart' show SnackbarMessage;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

typedef OrcamentoPainel = ({String nome, double gasto, double limite});

Future<List<OrcamentoPainel>> mbCarregarOrcamentos(BuildContext context) async {
  final carteiras = Provider.of<AllWallets>(context, listen: false);
  final agora = DateTime.now();
  final saida = <OrcamentoPainel>[];
  for (final b in await database.getAllBudgets()) {
    if (b.archived) continue;
    final periodo = getBudgetDate(b, agora);
    final total = await database
        .watchTotalSpentInTimeRangeFromCategories(
          allWallets: carteiras,
          start: periodo.start,
          end: periodo.end,
          categoryFks: b.categoryFks,
          categoryFksExclude: b.categoryFksExclude,
          budgetTransactionFilters: b.budgetTransactionFilters,
          memberTransactionFilters: b.memberTransactionFilters,
          onlyShowTransactionsBelongingToBudgetPk:
              b.sharedKey != null || b.addedTransactionsOnly == true
                  ? b.budgetPk
                  : null,
          budget: b,
        )
        .first;
    saida.add((
      nome: b.name,
      gasto: absoluteZero((total ?? 0) * determineBudgetPolarity(b)),
      limite: b.amount
    ));
  }
  return saida;
}

Future<void> mbAtualizarComAviso() async =>
    openSnackbar(SnackbarMessage(title: await meuBancoAtualizar()));

class PainelDesktop extends StatefulWidget {
  const PainelDesktop({super.key})
      : _modelo = null,
        _transacoes = const [],
        _orcamentos = const [];
  const PainelDesktop.comDados(ModeloInicio modelo,
      {super.key,
      List<TransacaoInicio> transacoes = const [],
      List<OrcamentoPainel> orcamentos = const []})
      : _modelo = modelo,
        _transacoes = transacoes,
        _orcamentos = orcamentos;

  final ModeloInicio? _modelo;
  final List<TransacaoInicio> _transacoes;
  final List<OrcamentoPainel> _orcamentos;

  @override
  State<PainelDesktop> createState() => _PainelDesktopState();
}

class _PainelDesktopState extends State<PainelDesktop> {
  ModeloInicio? _modelo;
  List<TransacaoInicio> _transacoes = const [];
  List<OrcamentoPainel> _orcamentos = const [];
  bool _atualizando = false;
  StreamSubscription<void>? _assinatura;

  @override
  void initState() {
    super.initState();
    if (widget._modelo != null) {
      _modelo = widget._modelo;
      _transacoes = widget._transacoes;
      _orcamentos = widget._orcamentos;
      _publicarLista();
    } else {
      meuBancoUltimaSync.addListener(_carregar);
      _assinatura = mbMudouUltimas().listen((_) => _carregar());
      _carregar();
    }
  }

  @override
  void dispose() {
    meuBancoUltimaSync.removeListener(_carregar);
    _assinatura?.cancel();
    super.dispose();
  }

  void _publicarLista() {
    mbListaVisivel.value = [for (final t in _transacoes) t.transaction.transactionPk];
  }

  Future<void> _carregar() async {
    final r = await mbCarregarModeloInicio(
        '${appStateSettings["username"] ?? ""}', DateTime.now());
    if (!mounted) return;
    final orc = await mbCarregarOrcamentos(context);
    if (!mounted) return;
    setState(() {
      _modelo = r.modelo;
      _transacoes = r.transacoes;
      _orcamentos = orc;
    });
    _publicarLista();
  }

  Future<void> _atualizar() async {
    if (_atualizando) return;
    setState(() => _atualizando = true);
    await mbAtualizarComAviso();
    if (mounted) setState(() => _atualizando = false);
  }

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    final m = _modelo;
    return ColoredBox(
      color: e.bg,
      child: m == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(36, 28, 36, 40),
              children: [
                _Topo(modelo: m, atualizando: _atualizando, onAtualizar: _atualizar),
                const SizedBox(height: 28),
                if (m.semDados)
                  Text('Ainda sem dados. Use Atualizar.',
                      style: EdTexto.corpo(context).copyWith(color: e.mu))
                else
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _Disponivel(modelo: m)),
                        Container(
                            width: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 32),
                            color: e.line),
                        Expanded(child: _GastoCiclo(modelo: m)),
                      ],
                    ),
                  ),
                const SizedBox(height: 32),
                Divider(height: 1, thickness: 1, color: e.line),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _Tabela(transacoes: _transacoes)),
                    const SizedBox(width: 40),
                    Expanded(flex: 2, child: _Orcamentos(itens: _orcamentos)),
                  ],
                ),
              ],
            ),
    );
  }
}

class _Topo extends StatelessWidget {
  const _Topo(
      {required this.modelo, required this.atualizando, required this.onAtualizar});
  final ModeloInicio modelo;
  final bool atualizando;
  final VoidCallback onAtualizar;

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    final d = modelo.diasRestantes;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '${modelo.ciclo} · $d ${d == 1 ? 'dia restante' : 'dias restantes'}',
                  style: EdTexto.rotulo(context)),
              const SizedBox(height: 6),
              Text(modelo.saudacao, style: EdTexto.h1(context)),
            ],
          ),
        ),
        Semantics(
          button: true,
          label: 'Buscar ou ir para',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => abrirBuscaRapida(),
            child: SizedBox(
              width: 260,
              height: 44,
              child: Center(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                      color: e.surf,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: e.line)),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 16, color: e.mu),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('Buscar ou ir para…',
                              style: EdTexto.corpo(context)
                                  .copyWith(color: e.mu, fontSize: 13))),
                      Text('Ctrl K', style: EdTexto.mono(context)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 44,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
                foregroundColor: e.tx,
                side: BorderSide(color: e.line),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: atualizando ? null : onAtualizar,
            child: Text(atualizando ? 'Atualizando…' : 'Atualizar'),
          ),
        ),
      ],
    );
  }
}

class _Disponivel extends StatelessWidget {
  const _Disponivel({required this.modelo});
  final ModeloInicio modelo;

  @override
  Widget build(BuildContext context) {
    final pontas = modelo.ciclo.replaceFirst('Ciclo ', '').split(' – ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Disponível agora', style: EdTexto.rotulo(context)),
        const SizedBox(height: 8),
        ContagemValor(
            valor: modelo.disponivel,
            formatar: brl,
            estilo: EdTexto.numeroGrande(context, desktop: true)),
        if (modelo.origemDisponivel.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(modelo.origemDisponivel, style: EdTexto.rotulo(context)),
        ],
        const SizedBox(height: 24),
        BarrasDias(
            valores: modelo.porDia, indiceHoje: modelo.indiceHoje, altura: 50),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
                child: Text(pontas.first, style: EdTexto.mono(context))),
            Text('Gasto por dia', style: EdTexto.rotulo(context)),
            Expanded(
                child: Text(pontas.length > 1 ? pontas.last : '',
                    textAlign: TextAlign.end, style: EdTexto.mono(context))),
          ],
        ),
      ],
    );
  }
}

class _GastoCiclo extends StatelessWidget {
  const _GastoCiclo({required this.modelo});
  final ModeloInicio modelo;

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    final m = modelo;
    final limite = m.limite;
    final pct = m.percentual ?? (limite != null && limite > 0 ? m.consumido / limite * 100 : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('GASTO NO CICLO', style: EdTexto.h2(context)),
        const SizedBox(height: 8),
        Text(brl(m.consumido),
            style: EdTexto.numeroGrande(context)
                .copyWith(fontSize: 32, letterSpacing: -.045 * 32)),
        const SizedBox(height: 14),
        if (limite != null && limite > 0) ...[
          MedidorEditorial(
              fracao: m.consumido / limite, alerta: (pct ?? 0) >= 100),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${(pct ?? 0).round()}% do previsto',
                  style: EdTexto.rotulo(context)),
              Text('Previsto ${brl(limite)}', style: EdTexto.rotulo(context)),
            ],
          ),
        ] else
          Text('Defina o limite no painel', style: EdTexto.rotulo(context)),
        for (final c in m.cartoes) ...[
          const SizedBox(height: 20),
          Divider(height: 1, thickness: 1, color: e.line),
          const SizedBox(height: 16),
          _Cartao(cartao: c),
        ],
      ],
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.cartao});
  final CartaoInicio cartao;

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    final c = cartao;
    final pct = c.pct;
    final alto = pct != null && pct >= 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                  '${c.nome.toUpperCase()}${c.final4.isEmpty ? '' : ' ·${c.final4}'}',
                  overflow: TextOverflow.ellipsis,
                  style: EdTexto.h2(context)),
            ),
            if (pct != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: alto ? e.warnbg : e.chip,
                    borderRadius: BorderRadius.circular(6)),
                child: Text('${pct.round()}% DO LIMITE',
                    style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: alto ? e.warntx : e.acc)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Fatura ${brl(c.fatura)}',
            style: EdTexto.corpo(context).copyWith(fontWeight: FontWeight.w500)),
        if (c.limite != null) ...[
          const SizedBox(height: 8),
          MedidorEditorial(fracao: c.fatura / c.limite!, alerta: alto),
          const SizedBox(height: 8),
          Text('Limite ${brl(c.limite!)}', style: EdTexto.rotulo(context)),
        ],
      ],
    );
  }
}

class _Tabela extends StatelessWidget {
  const _Tabela({required this.transacoes});
  final List<TransacaoInicio> transacoes;

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    final agora = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
                child: Text('ÚLTIMAS TRANSAÇÕES', style: EdTexto.h2(context))),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => mbIrParaPagina(1),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Text('Ver todas',
                        style: EdTexto.rotulo(context).copyWith(color: e.acc)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: e.line)),
                      child: Text('T', style: EdTexto.mono(context)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(flex: 5, child: Text('DESCRIÇÃO', style: EdTexto.mono(context))),
            Expanded(flex: 3, child: Text('CATEGORIA', style: EdTexto.mono(context))),
            Expanded(
                flex: 3,
                child: Text('VALOR',
                    textAlign: TextAlign.end, style: EdTexto.mono(context))),
          ],
        ),
        const SizedBox(height: 6),
        Divider(height: 1, thickness: 1, color: e.line),
        if (transacoes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Nenhuma transação ainda.', style: EdTexto.rotulo(context)),
          ),
        for (final t in transacoes)
          ValueListenableBuilder<String?>(
            valueListenable: mbTransacaoSelecionada,
            builder: (context, sel, _) {
              final x = t.transaction;
              final ativa = sel == x.transactionPk;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => mbTransacaoSelecionada.value = x.transactionPk,
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  decoration: BoxDecoration(
                    color: ativa ? e.surf : null,
                    border: Border(
                      left: BorderSide(
                          color: ativa ? e.acc : Colors.transparent, width: 2),
                      bottom: BorderSide(color: e.line),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(x.name,
                                overflow: TextOverflow.ellipsis,
                                style: EdTexto.corpo(context)
                                    .copyWith(fontWeight: FontWeight.w500)),
                            Text(quandoRelativo(x.dateCreated, agora),
                                style: EdTexto.rotulo(context)),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ChipCategoria(t.category.name,
                              receita: x.income,
                              alerta: t.category.name == 'Sem categoria'),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                            '${x.income ? '+' : '−'}${brl(x.amount.abs())}',
                            textAlign: TextAlign.end,
                            style: EdTexto.corpo(context).copyWith(
                                fontWeight: FontWeight.w500,
                                color: x.income ? e.pos : e.tx)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _Orcamentos extends StatelessWidget {
  const _Orcamentos({required this.itens});
  final List<OrcamentoPainel> itens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text('ORÇAMENTOS', style: EdTexto.h2(context))),
        ),
        if (itens.isEmpty)
          Text('Nenhum orçamento.', style: EdTexto.rotulo(context)),
        for (final o in itens)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(o.nome,
                          overflow: TextOverflow.ellipsis,
                          style: EdTexto.corpo(context)
                              .copyWith(fontWeight: FontWeight.w500)),
                    ),
                    Text('${brl(o.gasto)} de ${brl(o.limite)}',
                        style: EdTexto.rotulo(context)),
                  ],
                ),
                const SizedBox(height: 8),
                MedidorEditorial(
                    fracao: o.limite > 0 ? o.gasto / o.limite : 0,
                    alerta: o.limite > 0 && o.gasto >= o.limite),
              ],
            ),
          ),
      ],
    );
  }
}
