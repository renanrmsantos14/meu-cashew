import 'dart:convert';

import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/armazem.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:intl/intl.dart' show NumberFormat;

typedef ContaInicio = ({String sigla, String nome, String tipo, double saldo});
typedef CartaoInicio = ({
  String nome,
  String final4,
  int? diasFecha,
  String? vence,
  double fatura,
  double? limite,
  double? pct
});
typedef UltimaInicio = ({
  String nome,
  String categoria,
  String quando,
  double valor,
  bool receita
});
typedef UltimaBruta = ({
  String nome,
  String categoria,
  DateTime data,
  double valor,
  bool receita
});

class ModeloInicio {
  final String ciclo, saudacao, origemDisponivel;
  final double disponivel, consumido;
  final double? limite, percentual;
  final int diasRestantes, indiceHoje;
  final List<double> porDia;
  final List<ContaInicio> contas;
  final List<CartaoInicio> cartoes;
  final List<UltimaInicio> ultimas;
  bool get semDados => contas.isEmpty && cartoes.isEmpty && porDia.isEmpty;

  // Igualdade por conteúdo: permite ignorar recargas que não mudaram nada (sem setState).
  @override
  bool operator ==(Object o) =>
      o is ModeloInicio &&
      ciclo == o.ciclo &&
      saudacao == o.saudacao &&
      origemDisponivel == o.origemDisponivel &&
      disponivel == o.disponivel &&
      consumido == o.consumido &&
      limite == o.limite &&
      percentual == o.percentual &&
      diasRestantes == o.diasRestantes &&
      indiceHoje == o.indiceHoje &&
      listEquals(porDia, o.porDia) &&
      listEquals(contas, o.contas) &&
      listEquals(cartoes, o.cartoes) &&
      listEquals(ultimas, o.ultimas);

  @override
  int get hashCode => Object.hash(ciclo, saudacao, disponivel, consumido,
      diasRestantes, indiceHoje, porDia.length, contas.length, ultimas.length);

  const ModeloInicio({
    required this.ciclo,
    required this.saudacao,
    required this.disponivel,
    required this.origemDisponivel,
    required this.consumido,
    required this.limite,
    required this.percentual,
    required this.diasRestantes,
    required this.porDia,
    required this.indiceHoje,
    required this.contas,
    required this.cartoes,
    required this.ultimas,
  });
}

final _brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
String brl(double v) => _brl.format(v).replaceAll('\u00a0', ' ');

const _meses = [
  'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
  'jul', 'ago', 'set', 'out', 'nov', 'dez'
];
String diaMes(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${_meses[d.month - 1]}';
DateTime _soDia(DateTime d) => DateTime(d.year, d.month, d.day);

String quandoRelativo(DateTime d, DateTime agora) {
  final dif = _soDia(agora).difference(_soDia(d)).inDays;
  if (dif == 0) return 'hoje';
  if (dif == 1) return 'ontem';
  return diaMes(d);
}

String haQuanto(DateTime d, DateTime agora) {
  final min = agora.difference(d).inMinutes;
  if (min < 1) return 'agora há pouco';
  if (min < 60) return 'há $min min';
  if (min < 1440) return 'há ${min ~/ 60} h';
  return 'há ${min ~/ 1440} d';
}

DateTime? _lerData(Object? v) {
  if (v is! String || v.isEmpty) return null;
  var s = v.trim();
  if (!s.contains('T')) s = s.replaceFirst(' ', 'T');
  if (s.length > 10 && !RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(s)) s += 'Z';
  return DateTime.tryParse(s);
}

// Próxima ocorrência do dia do mês de [iso] (hoje conta).
DateTime? _proximoDia(Object? iso, DateTime agora) {
  if (iso is! String || iso.length < 10) return null;
  final dia = int.tryParse(iso.substring(8, 10));
  if (dia == null) return null;
  DateTime cand(int ano, int mes) {
    final ultimo = DateTime(ano, mes + 1, 0).day;
    return DateTime(ano, mes, dia > ultimo ? ultimo : dia);
  }

  final hoje = _soDia(agora);
  var c = cand(hoje.year, hoje.month);
  if (c.isBefore(hoje)) c = cand(hoje.year, hoje.month + 1);
  return c;
}

// "12 nov" do próximo dia de fechamento/vencimento de [iso].
String? mbProximoDiaMes(Object? iso, DateTime agora) {
  final d = _proximoDia(iso, agora);
  return d == null ? null : diaMes(d);
}

double _num(Object? v) => v is num ? v.toDouble() : 0;

String _sigla(String nome) {
  final letras = nome.replaceAll(RegExp(r'[^A-Za-zÀ-ú]'), '');
  return letras.isEmpty
      ? '··'
      : letras.substring(0, letras.length < 2 ? 1 : 2).toUpperCase();
}

String _listaE(List<String> itens) => itens.length <= 1
    ? itens.join()
    : '${itens.sublist(0, itens.length - 1).join(', ')} e ${itens.last}';

ModeloInicio montarModeloInicio({
  required Map<String, dynamic> ciclo,
  required List<Map<String, dynamic>> contas,
  required Map<String, dynamic> faturas,
  required String? sincronizadoEm,
  required List<UltimaBruta> ultimas,
  required String nome,
  required DateTime agora,
}) {
  final ini = DateTime.tryParse('${ciclo['inicio']}');
  final fim = DateTime.tryParse('${ciclo['fim']}');
  final rotuloCiclo = ini != null && fim != null
      ? 'Ciclo ${diaMes(ini)} – ${diaMes(fim)}'
      : 'Ciclo atual';

  final bancarias = [for (final c in contas) if (c['type'] == 'BANK') c];
  final poupancas =
      bancarias.where((c) => c['subtype'] == 'SAVINGS_ACCOUNT').toList();
  final correntes =
      bancarias.where((c) => c['subtype'] != 'SAVINGS_ACCOUNT').toList();
  final saldoDe = (List<Map<String, dynamic>> l) =>
      l.fold<double>(0, (s, c) => s + _num(c['balance']));

  final linhas = <ContaInicio>[
    for (final c in correntes)
      (
        sigla: _sigla('${c['bank'] ?? c['name']}'),
        nome: '${c['bank'] ?? c['name']}',
        tipo: 'Conta corrente',
        saldo: _num(c['balance'])
      ),
    if (poupancas.length == 1)
      (
        sigla: _sigla('${poupancas.first['bank'] ?? poupancas.first['name']}'),
        nome: '${poupancas.first['bank'] ?? poupancas.first['name']}',
        tipo: 'Poupança',
        saldo: _num(poupancas.first['balance'])
      )
    else if (poupancas.length > 1)
      (
        sigla: 'PP',
        nome: 'Poupanças',
        tipo: '${poupancas.length} contas',
        saldo: saldoDe(poupancas)
      ),
  ];

  final bancos = <String>[];
  for (final c in correntes) {
    final b = '${c['bank'] ?? c['name']}';
    if (!bancos.contains(b)) bancos.add(b);
  }
  if (poupancas.isNotEmpty) bancos.add('poupanças');
  final quando = _lerData(sincronizadoEm);
  final origem = [
    if (bancos.isNotEmpty) _listaE(bancos),
    if (quando != null) haQuanto(quando, agora),
  ].join(' · ');

  final cartoes = <CartaoInicio>[];
  for (final c in contas.where((c) => c['type'] == 'CREDIT')) {
    final bruto = '${c['name']}';
    final m = RegExp(r'\s*·(\d{4})$').firstMatch(bruto);
    final fat = faturas['${c['id']}'];
    final aberta = fat is Map ? fat['open_bill'] : null;
    final fatura = aberta is Map && aberta['total_amount'] is num
        ? _num(aberta['total_amount'])
        : _num(c['balance']);
    final limite = _num(c['credit_limit']);
    final fecha = _proximoDia(c['closing_date'], agora);
    final venceData = aberta is Map && _lerData('${aberta['due_date']}') != null
        ? _lerData('${aberta['due_date']}')
        : _proximoDia(c['due_date'], agora);
    cartoes.add((
      nome: m == null ? bruto : bruto.substring(0, m.start),
      final4: m?.group(1) ?? '',
      diasFecha: fecha?.difference(_soDia(agora)).inDays,
      vence: venceData == null ? null : diaMes(venceData),
      fatura: fatura,
      limite: limite > 0 ? limite : null,
      pct: limite > 0 ? fatura / limite * 100 : null,
    ));
  }

  final dias = [
    for (final d in (ciclo['por_dia'] as List? ?? const []))
      d is Map ? _num(d['valor']) : _num(d)
  ];
  final hojeIso = _soDia(agora).toIso8601String().substring(0, 10);
  var indice = [
    for (final d in (ciclo['por_dia'] as List? ?? const []))
      d is Map ? '${d['data']}' : ''
  ].indexOf(hojeIso);
  if (indice < 0) {
    indice = dias.isNotEmpty && fim != null && agora.isAfter(fim.add(const Duration(days: 1)))
        ? dias.length - 1
        : 0;
  }

  return ModeloInicio(
    ciclo: rotuloCiclo,
    saudacao: nome.trim().isEmpty ? 'Olá' : 'Olá, ${nome.trim()}',
    disponivel: saldoDe(bancarias),
    origemDisponivel: origem,
    consumido: _num(ciclo['consumido']),
    limite: ciclo['limite'] is num ? _num(ciclo['limite']) : null,
    percentual: ciclo['percentual'] is num ? _num(ciclo['percentual']) : null,
    diasRestantes: (ciclo['diasRestantes'] as num?)?.toInt() ??
        (fim == null ? 0 : _soDia(fim).difference(_soDia(agora)).inDays),
    porDia: dias,
    indiceHoje: indice,
    contas: linhas,
    cartoes: cartoes,
    ultimas: [
      for (final u in ultimas.take(5))
        (
          nome: u.nome,
          categoria: u.categoria,
          quando: quandoRelativo(u.data, agora),
          valor: u.valor,
          receita: u.receita
        )
    ],
  );
}

Object? _decodificar(String? s) => s == null ? null : jsonDecode(s);

// Linhas mais recentes do Cashew para a seção ÚLTIMAS (ficam em paralelo com o modelo, para abrir no editor).
JoinedSelectStatement<HasResultSet, dynamic> _consultaUltimas() =>
    database.select(database.transactions).join([
    innerJoin(database.categories,
        database.categories.categoryPk.equalsExp(database.transactions.categoryFk))
  ])
    ..where(database.transactions.paid.equals(true))
    ..orderBy([OrderingTerm.desc(database.transactions.dateCreated)])
    ..limit(5);

typedef TransacaoInicio = ({Transaction transaction, TransactionCategory category});

TransacaoInicio _linha(TypedResult r) => (
      category: r.readTable(database.categories),
      transaction: r.readTable(database.transactions)
    );

Future<List<TransacaoInicio>> mbUltimasTransacoes() async =>
    [for (final r in await _consultaUltimas().get()) _linha(r)];

Stream<void> mbMudouUltimas() => _consultaUltimas().watch();

Future<({ModeloInicio modelo, List<({Transaction transaction, TransactionCategory category})> transacoes})>
    mbCarregarModeloInicio(String nome, DateTime agora) async {
  final mapa = <String, Object?>{
    for (final k in ['ciclo', 'contas', 'faturas'])
      k: _decodificar(await mbLerEstado(k))
  };
  final txs = await mbUltimasTransacoes();
  final modelo = montarModeloInicio(
    ciclo: ((mapa['ciclo'] as Map?) ?? const {}).cast<String, dynamic>(),
    contas: [
      for (final c in (mapa['contas'] as List? ?? const []))
        (c as Map).cast<String, dynamic>()
    ],
    faturas: ((mapa['faturas'] as Map?) ?? const {}).cast<String, dynamic>(),
    sincronizadoEm: await mbLerEstado('sincronizado_em'),
    ultimas: [
      for (final t in txs)
        (
          nome: t.transaction.name,
          categoria: t.category.name,
          data: t.transaction.dateCreated,
          valor: t.transaction.amount,
          receita: t.transaction.income
        )
    ],
    nome: nome,
    agora: agora,
  );
  return (modelo: modelo, transacoes: txs);
}

// Junta gatilhos de recarga em rajada (uma sync dispara o listener da sync e vários eventos
// do stream de transações): no máximo uma recarga em andamento e uma repetição pendente.
class RecargaColapsada {
  RecargaColapsada(this._carregar);
  final Future<void> Function() _carregar;
  bool _rodando = false, _repetir = false, _fechada = false;

  Future<void> pedir() async {
    if (_fechada) return;
    if (_rodando) {
      _repetir = true;
      return;
    }
    _rodando = true;
    try {
      do {
        _repetir = false;
        await _carregar();
      } while (_repetir && !_fechada);
    } finally {
      _rodando = false;
    }
  }

  void fechar() => _fechada = true;
}
