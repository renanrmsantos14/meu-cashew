import 'dart:async';

import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/pages/settingsPage.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart';
import 'package:budget/struct/meuBancoSync.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/editorial/movimento.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/functions.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:flutter/material.dart';

class InicioEditorial extends StatefulWidget {
  const InicioEditorial({super.key}) : _modelo = null;
  const InicioEditorial.comModelo(ModeloInicio modelo, {super.key})
      : _modelo = modelo;
  final ModeloInicio? _modelo;

  @override
  State<InicioEditorial> createState() => _InicioEditorialState();
}

class _InicioEditorialState extends State<InicioEditorial> {
  ModeloInicio? _modelo;
  List<TransacaoInicio> _transacoes = const [];
  bool _atualizando = false;
  StreamSubscription<void>? _assinatura;

  @override
  void initState() {
    super.initState();
    _modelo = widget._modelo;
    if (_modelo == null) {
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

  Future<void> _carregar() async {
    final r = await mbCarregarModeloInicio(
        '${appStateSettings["username"] ?? ""}', DateTime.now());
    if (!mounted) return;
    setState(() {
      _modelo = r.modelo;
      _transacoes = r.transacoes;
    });
  }

  Future<void> _atualizar() async {
    if (_atualizando) return;
    setState(() => _atualizando = true);
    final msg = await meuBancoAtualizar();
    if (mounted) setState(() => _atualizando = false);
    openSnackbar(SnackbarMessage(title: msg));
  }

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    final m = _modelo;
    final secoes = <Widget>[];
    if (m != null) {
      secoes.addAll([
        _Topo(
            modelo: m,
            atualizando: _atualizando,
            onAtualizar: widget._modelo == null ? _atualizar : null,
            onMenu: widget._modelo == null
                ? () => pushRoute(context, MoreActionsPage())
                : null),
        if (m.semDados)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('Ainda sem dados. Toque em Atualizar.',
                style: EdTexto.corpo(context).copyWith(color: e.mu)),
          )
        else ...[
          _Disponivel(modelo: m),
          _GastoCiclo(modelo: m),
        ],
        if (m.contas.isNotEmpty) _Contas(contas: m.contas),
        for (final c in m.cartoes) _Cartao(cartao: c),
        if (m.ultimas.isNotEmpty)
          _Ultimas(
            itens: m.ultimas,
            onTap: widget._modelo == null
                ? (i) {
                    if (i < _transacoes.length) {
                      pushRoute(
                          context,
                          AddTransactionPage(
                              transaction: _transacoes[i].transaction,
                              routesToPopAfterDelete:
                                  RoutesToPopAfterDelete.None));
                    }
                  }
                : null,
          ),
      ]);
    }
    return ColoredBox(
      color: e.bg,
      child: SafeArea(
        bottom: false,
        child: m == null
            ? _Esqueleto(cor: e.line)
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  for (var i = 0; i < secoes.length; i++)
                    EntradaEditorial(
                      indice: i,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (i > 0)
                            Divider(height: 1, thickness: 1, color: e.line),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: i == 0 ? 0 : 18),
                            child: secoes[i],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _BotaoIcone extends StatelessWidget {
  const _BotaoIcone(
      {required this.icone, required this.onTap, required this.rotulo, this.girar = false});
  final IconData icone;
  final VoidCallback? onTap;
  final String rotulo;
  final bool girar;

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    return Semantics(
      button: true,
      label: rotulo,
      child: ToqueEscala(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: e.surf,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: e.line),
              ),
              child: girar && !semMovimento(context)
                  ? _Girando(child: Icon(icone, size: 20, color: e.tx))
                  : Icon(icone, size: 20, color: e.tx),
            ),
          ),
        ),
      ),
    );
  }
}

class _Girando extends StatefulWidget {
  const _Girando({required this.child});
  final Widget child;
  @override
  State<_Girando> createState() => _GirandoState();
}

class _GirandoState extends State<_Girando>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: _c, child: widget.child);
}

class _Topo extends StatelessWidget {
  const _Topo(
      {required this.modelo,
      required this.atualizando,
      required this.onAtualizar,
      required this.onMenu});
  final ModeloInicio modelo;
  final bool atualizando;
  final VoidCallback? onAtualizar, onMenu;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(modelo.ciclo, style: EdTexto.rotulo(context)),
              const SizedBox(height: 6),
              Text(modelo.saudacao, style: EdTexto.h1(context)),
            ],
          ),
        ),
        _BotaoIcone(
            icone: Icons.refresh,
            rotulo: 'Atualizar',
            girar: atualizando,
            onTap: onAtualizar),
        _BotaoIcone(icone: Icons.menu, rotulo: 'Configurações', onTap: onMenu),
      ],
    );
  }
}

class _Disponivel extends StatelessWidget {
  const _Disponivel({required this.modelo});
  final ModeloInicio modelo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Disponível agora', style: EdTexto.rotulo(context)),
        const SizedBox(height: 8),
        ContagemValor(
            valor: modelo.disponivel,
            formatar: brl,
            estilo: EdTexto.numeroGrande(context)),
        if (modelo.origemDisponivel.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(modelo.origemDisponivel, style: EdTexto.rotulo(context)),
        ],
      ],
    );
  }
}

class _GastoCiclo extends StatelessWidget {
  const _GastoCiclo({required this.modelo});
  final ModeloInicio modelo;

  @override
  Widget build(BuildContext context) {
    final m = modelo;
    final limite = m.limite;
    final pct = m.percentual ?? (limite != null ? m.consumido / limite * 100 : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Gasto no ciclo', style: EdTexto.rotulo(context)),
            Text(brl(m.consumido),
                style: EdTexto.corpo(context)
                    .copyWith(fontWeight: FontWeight.w600, fontSize: 15)),
          ],
        ),
        const SizedBox(height: 10),
        if (limite != null && limite > 0) ...[
          MedidorEditorial(
              fracao: m.consumido / limite, alerta: (pct ?? 0) >= 100),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${(pct ?? 0).round()}% do previsto',
                  style: EdTexto.rotulo(context)),
              Text(
                  '${m.diasRestantes} ${m.diasRestantes == 1 ? 'dia restante' : 'dias restantes'}',
                  style: EdTexto.rotulo(context)),
            ],
          ),
        ] else
          Text('Defina o limite no painel', style: EdTexto.rotulo(context)),
        const SizedBox(height: 14),
        BarrasDias(valores: m.porDia, indiceHoje: m.indiceHoje),
      ],
    );
  }
}

class _Contas extends StatelessWidget {
  const _Contas({required this.contas});
  final List<ContaInicio> contas;

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('CONTAS', style: EdTexto.h2(context)),
        const SizedBox(height: 6),
        for (var i = 0; i < contas.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: e.line),
          SizedBox(
            height: 56,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: e.chip, borderRadius: BorderRadius.circular(6)),
                  child: Text(contas[i].sigla,
                      style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: e.acc)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(contas[i].nome,
                          overflow: TextOverflow.ellipsis,
                          style: EdTexto.corpo(context)
                              .copyWith(fontWeight: FontWeight.w500)),
                      Text(contas[i].tipo, style: EdTexto.rotulo(context)),
                    ],
                  ),
                ),
                Text(brl(contas[i].saldo),
                    style: EdTexto.corpo(context)
                        .copyWith(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
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
    final alto = pct != null && pct >= 80;
    final fecha = c.diasFecha == null
        ? null
        : c.diasFecha == 0
            ? 'Fecha hoje'
            : 'Fecha em ${c.diasFecha} ${c.diasFecha == 1 ? 'dia' : 'dias'}';
    final linhaFecha = [
      if (fecha != null) fecha,
      if (c.vence != null) 'vence ${c.vence}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${c.nome.toUpperCase()}${c.final4.isEmpty ? '' : ' ·${c.final4}'}',
                      style: EdTexto.h2(context)),
                  if (linhaFecha.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(linhaFecha, style: EdTexto.rotulo(context)),
                  ],
                ],
              ),
            ),
            if (pct != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: alto ? e.warnbg : e.chip,
                    borderRadius: BorderRadius.circular(8)),
                child: Text('${pct.round()}%',
                    style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: alto ? e.warntx : e.acc)),
              ),
          ],
        ),
        if (c.limite != null) ...[
          const SizedBox(height: 12),
          MedidorEditorial(
              fracao: c.fatura / c.limite!, alerta: (pct ?? 0) >= 100),
        ],
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Fatura ${brl(c.fatura)}', style: EdTexto.rotulo(context)),
            if (c.limite != null)
              Text('Limite ${brl(c.limite!)}', style: EdTexto.rotulo(context)),
          ],
        ),
      ],
    );
  }
}

class _Ultimas extends StatelessWidget {
  const _Ultimas({required this.itens, required this.onTap});
  final List<UltimaInicio> itens;
  final void Function(int)? onTap;

  @override
  Widget build(BuildContext context) {
    final e = cores(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ÚLTIMAS', style: EdTexto.h2(context)),
        const SizedBox(height: 6),
        for (var i = 0; i < itens.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: e.line),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap == null ? null : () => onTap!(i),
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(itens[i].nome,
                            overflow: TextOverflow.ellipsis,
                            style: EdTexto.corpo(context)
                                .copyWith(fontWeight: FontWeight.w500)),
                        Text('${itens[i].categoria} · ${itens[i].quando}',
                            overflow: TextOverflow.ellipsis,
                            style: EdTexto.rotulo(context)),
                      ],
                    ),
                  ),
                  Text(
                      '${itens[i].receita ? '+' : '−'}${brl(itens[i].valor.abs())}',
                      style: EdTexto.corpo(context).copyWith(
                          fontWeight: FontWeight.w500,
                          color: itens[i].receita ? e.pos : e.tx)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Esqueleto extends StatelessWidget {
  const _Esqueleto({required this.cor});
  final Color cor;

  Widget _bloco(double l, double a) => Container(
      width: l,
      height: a,
      margin: const EdgeInsets.only(bottom: 12),
      decoration:
          BoxDecoration(color: cor, borderRadius: BorderRadius.circular(4)));

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bloco(120, 12),
            _bloco(180, 28),
            const SizedBox(height: 24),
            _bloco(100, 12),
            _bloco(260, 50),
            const SizedBox(height: 24),
            _bloco(double.infinity, 40),
            const SizedBox(height: 12),
            for (var i = 0; i < 3; i++) _bloco(double.infinity, 56),
          ],
        ),
      );
}
