import 'dart:convert';

import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/armazem.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart' show brl, diaMes;
import 'package:budget/struct/mbSync/mapeamento.dart';
import 'package:budget/struct/meuBancoMapping.dart' show mbCarteiraInvestimentos;
import 'package:drift/drift.dart';

// Metas do Meu Banco.
//
// Modelo: a meta é um Objetivo "meta" do Cashew (já sincronizado como `metas`). O que o Cashew não tem é
// "a meta é composta por estas aplicações": isso vive em `mb_meta_aplicacao` (aplicação -> meta). A chave
// primária na aplicação garante "cada aplicação em uma meta só". O vínculo é copiado em
// `transactions.objective_fk` das transações `mb:inv:*` (mbReconciliarVinculos), e o progresso nativo do Cashew
// (soma dos lançamentos pagos da meta) passa a ser a soma dos saldos atuais dessas aplicações.
// A tabela própria (e não só o objective_fk) existe porque o vínculo precisa sobreviver a um aparelho em que a
// transação da aplicação ainda não existe; e mexer só em `objective_fk` não cria ajuste (`mb_aplicado`) nem
// altera `dateTimeModified` das transações.

/// Meta criada uma vez, sem valor alvo. Pk fixo: dois aparelhos que a criem juntos não duplicam (LWW).
const String mbMetaReservaPk = 'mb:meta:reserva';
const String mbMetaReservaNome = 'Reserva de emergência';
const String _prefixoAplicacao = 'mb:inv:';
const String _chaveReservaCriada = 'reserva_criada';

/// Id da aplicação no sync (id Pluggy, sem o prefixo local).
String mbIdAplicacao(String pk) =>
    pk.startsWith(_prefixoAplicacao) ? pk.substring(_prefixoAplicacao.length) : pk;
String mbPkAplicacao(String id) => _prefixoAplicacao + id;

// ---------------------------------------------------------------------------------------------
// Vínculos

/// A tabela nasce com o primeiro uso (app sem Meu Banco pareado também abre a edição de meta).
Future<void> _tabela() => database.customStatement(mbDdlMetaAplicacao);

/// aplicação (pk) -> meta (pk), só de metas que existem.
Future<Map<String, String>> mbVinculosMetas() async {
  await _tabela();
  final linhas = await database
      .customSelect('SELECT v.aplicacao_pk, v.meta_pk FROM mb_meta_aplicacao v '
          'JOIN objectives o ON o.objective_pk = v.meta_pk')
      .get();
  return {
    for (final l in linhas) l.read<String>('aplicacao_pk'): l.read<String>('meta_pk')
  };
}

/// Ids de aplicação (sem prefixo, ordenados) de cada meta: o campo `aplicacao_ids` do sync.
Future<Map<String, List<String>>> mbAplicacoesPorMeta() async {
  final out = <String, List<String>>{};
  for (final e in (await mbVinculosMetas()).entries) {
    (out[e.value] ??= []).add(mbIdAplicacao(e.key));
  }
  for (final l in out.values) {
    l.sort();
  }
  return out;
}

/// Copia o vínculo para `objective_fk` das transações das aplicações (só escreve onde difere) e descarta
/// vínculos de metas que não existem mais.
Future<void> mbReconciliarVinculos() async {
  await database.customUpdate(
      'DELETE FROM mb_meta_aplicacao WHERE meta_pk NOT IN (SELECT objective_pk FROM objectives)',
      updates: {},
      updateKind: UpdateKind.delete);
  const alvo = '(SELECT v.meta_pk FROM mb_meta_aplicacao v '
      'WHERE v.aplicacao_pk = transactions.transaction_pk)';
  const diverge = "transaction_pk LIKE '$_prefixoAplicacao%' AND objective_fk IS NOT $alvo";
  // Sem divergência não escreve: evita recarregar os streams de transações a cada sync.
  if ((await database.customSelect('SELECT 1 FROM transactions WHERE $diverge LIMIT 1').get()).isEmpty) return;
  await database.customUpdate(
      "UPDATE transactions SET objective_fk = $alvo WHERE $diverge",
      updates: {database.transactions},
      updateKind: UpdateKind.update);
}

/// Define as aplicações da meta [metaPk]. Aplicação que estava em outra meta passa para esta (a interface
/// bloqueia isso; vale para sincronização remota conflitante).
Future<void> mbDefinirAplicacoesDaMeta(String metaPk, Iterable<String> aplicacaoPks) =>
    database.transaction(() async {
      await _tabela();
      await database
          .customStatement('DELETE FROM mb_meta_aplicacao WHERE meta_pk = ?', [metaPk]);
      for (final pk in aplicacaoPks) {
        await database.customStatement(
            'INSERT OR REPLACE INTO mb_meta_aplicacao (aplicacao_pk, meta_pk) VALUES (?, ?)',
            [pk, metaPk]);
      }
      // O tile do Cashew só mostra o progresso positivo em meta de poupança (income); saldo de aplicação é positivo.
      if (aplicacaoPks.isNotEmpty) {
        await database.customUpdate(
            'UPDATE objectives SET income = 1 WHERE objective_pk = ? AND income = 0',
            variables: [Variable.withString(metaPk)],
            updates: {database.objectives},
            updateKind: UpdateKind.update);
      }
      await mbReconciliarVinculos();
    });

// ---------------------------------------------------------------------------------------------
// Aplicações atuais

class MbAplicacao {
  final String pk, nome;
  final String? banco, metaPk;
  final double saldo;
  const MbAplicacao(this.pk, this.nome, this.banco, this.saldo, this.metaPk);
  String get id => mbIdAplicacao(pk);
}

/// Aplicações da carteira Investimentos, com a meta a que pertencem (ou null).
Future<List<MbAplicacao>> mbAplicacoes() async {
  final vinculos = await mbVinculosMetas();
  final txs = await (database.select(database.transactions)
        ..where((t) =>
            t.walletFk.equals(mbCarteiraInvestimentos) &
            t.transactionPk.like('$_prefixoAplicacao%'))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .get();
  return [
    for (final t in txs)
      MbAplicacao(t.transactionPk, t.name, t.note.isEmpty ? null : t.note, t.amount,
          vinculos[t.transactionPk])
  ];
}

// ---------------------------------------------------------------------------------------------
// Reserva de emergência

/// Cria a Reserva uma vez: pk fixo + `insertOrIgnore`; nada se o espelho já tem (ou apagou) a meta, ou se ela já
/// foi criada neste aparelho (quem apagar não a vê voltar). Chamar depois do pull.
Future<void> mbGarantirReserva({DateTime? agora}) async {
  if (await mbLerEstado(_chaveReservaCriada) != null) return;
  final id = idDoPk(mbMetaReservaPk);
  final noEspelho = await database
      .customSelect('SELECT 1 FROM mb_registros WHERE tabela = ? AND id = ?',
          variables: [Variable<String>('metas'), Variable<String>(id)])
      .get();
  final existe = noEspelho.isNotEmpty ||
      await (database.select(database.objectives)
            ..where((o) => o.objectivePk.equals(mbMetaReservaPk)))
          .getSingleOrNull() !=
          null;
  if (!existe) {
    await database.into(database.objectives).insert(
        ObjectivesCompanion.insert(
          objectivePk: const Value(mbMetaReservaPk),
          type: const Value(ObjectiveType.goal),
          name: mbMetaReservaNome,
          amount: 0,
          order: await _contarObjetivos(),
          pinned: const Value(true),
          income: const Value(true),
          walletFk: const Value('0'),
          dateTimeModified: Value(agora ?? DateTime.now()),
        ),
        mode: InsertMode.insertOrIgnore);
  }
  await mbGravarEstado({_chaveReservaCriada: '1'});
}

Future<int> _contarObjetivos() async => (await database
        .customSelect('SELECT COUNT(*) AS n FROM objectives')
        .getSingle())
    .read<int>('n');

// ---------------------------------------------------------------------------------------------
// Evolução mensal (série do Worker: `investimentos_mensal`)

class MbRetratoMes {
  final String mes; // aaaa-mm
  final List<MbAplicacaoMes> itens;
  const MbRetratoMes(this.mes, this.itens);
  double get total => itens.fold(0.0, (s, i) => s + i.saldo);
}

class MbAplicacaoMes {
  final String id, nome;
  final String? banco;
  final double saldo;
  const MbAplicacaoMes(this.id, this.nome, this.banco, this.saldo);
}

/// Lê a série do JSON do Worker. Resposta sem o campo (Worker antigo) ou inválida = lista vazia.
List<MbRetratoMes> mbSerieDeJson(Object? json) {
  if (json is! List) return const [];
  final out = <MbRetratoMes>[];
  for (final m in json) {
    if (m is! Map || m['mes'] is! String || m['itens'] is! List) continue;
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(m['mes'] as String)) continue;
    out.add(MbRetratoMes(m['mes'] as String, [
      for (final i in m['itens'] as List)
        if (i is Map && i['id'] is String && i['saldo'] is num)
          MbAplicacaoMes(i['id'] as String, '${i['nome'] ?? ''}',
              i['banco'] is String ? i['banco'] as String : null, (i['saldo'] as num).toDouble())
    ]));
  }
  out.sort((a, b) => a.mes.compareTo(b.mes));
  return out;
}

/// Total de cada mês e a variação sobre o mês anterior (null no primeiro).
List<({MbRetratoMes mes, double? variacao})> mbSerieComVariacao(List<MbRetratoMes> serie) => [
      for (var i = 0; i < serie.length; i++)
        (mes: serie[i], variacao: i == 0 ? null : serie[i].total - serie[i - 1].total)
    ];

Future<List<MbRetratoMes>> mbLerSerieMensal() async {
  final texto = await mbLerEstado(chaveSerieMensal);
  if (texto == null) return const [];
  try {
    return mbSerieDeJson(jsonDecode(texto));
  } catch (_) {
    return const [];
  }
}

const String chaveSerieMensal = 'investimentos_mensal';

// ---------------------------------------------------------------------------------------------
// Resumo (função pura; o resumo semanal do PR 7 usa a mesma)

class MbMetaDados {
  final String pk, nome;
  final double alvo; // 0 = sem valor definido
  final DateTime? prazo;
  final List<String> aplicacaoPks;
  const MbMetaDados(
      {required this.pk,
      required this.nome,
      required this.alvo,
      this.prazo,
      this.aplicacaoPks = const []});
}

class MbMetaResumo {
  final String pk, nome, texto;
  final double saldo;
  final double? alvo; // null = sem valor definido
  final double? progresso; // 0..1 (limitado); null sem alvo
  final double? falta; // 0 se atingiu; null sem alvo
  final DateTime? prazo;
  final int? diasRestantes; // negativo = vencido; null sem prazo
  const MbMetaResumo(this.pk, this.nome, this.texto, this.saldo, this.alvo,
      this.progresso, this.falta, this.prazo, this.diasRestantes);
}

/// Resumo de cada meta: saldo = soma dos saldos das suas aplicações ([saldoPorAplicacao] por pk).
/// [texto] é a linha pronta para o resumo semanal e a Início.
List<MbMetaResumo> mbResumoMetas(
    {required List<MbMetaDados> metas,
    required Map<String, double> saldoPorAplicacao,
    required DateTime hoje}) {
  final dia = DateTime(hoje.year, hoje.month, hoje.day);
  return [
    for (final m in metas)
      () {
        final saldo = m.aplicacaoPks.fold(0.0, (s, pk) => s + (saldoPorAplicacao[pk] ?? 0));
        final temAlvo = m.alvo > 0;
        final falta = temAlvo ? (m.alvo - saldo).clamp(0, double.infinity).toDouble() : null;
        final progresso = temAlvo ? (saldo / m.alvo).clamp(0.0, 1.0).toDouble() : null;
        final dias = m.prazo == null
            ? null
            : DateTime(m.prazo!.year, m.prazo!.month, m.prazo!.day).difference(dia).inDays;
        final partes = <String>[
          if (temAlvo) '${brl(saldo)} de ${brl(m.alvo)} (${(progresso! * 100).floor()}%)' else brl(saldo),
          if (!temAlvo) 'defina o valor da meta',
          if (temAlvo && falta! > 0) 'faltam ${brl(falta)}',
          if (temAlvo && falta == 0) 'meta atingida',
          if (m.prazo != null)
            dias! < 0
                ? 'prazo venceu em ${diaMes(m.prazo!)}'
                : dias == 0
                    ? 'prazo é hoje'
                    : 'prazo ${diaMes(m.prazo!)} ($dias ${dias == 1 ? 'dia' : 'dias'})',
        ];
        return MbMetaResumo(m.pk, m.nome, '${m.nome}: ${partes.join(', ')}', saldo,
            temAlvo ? m.alvo : null, progresso, falta, m.prazo, dias);
      }()
  ];
}

/// Metas do banco (não arquivadas) prontas para [mbResumoMetas].
Future<List<MbMetaResumo>> mbResumoMetasLocais({DateTime? hoje}) async {
  final porMeta = await mbVinculosMetas();
  final aplicacoes = await mbAplicacoes();
  final saldos = {for (final a in aplicacoes) a.pk: a.saldo};
  final aplicPorMeta = <String, List<String>>{};
  for (final e in porMeta.entries) {
    (aplicPorMeta[e.value] ??= []).add(e.key);
  }
  final objetivos = await (database.select(database.objectives)
        ..where((o) => o.type.equalsValue(ObjectiveType.goal) & o.archived.equals(false))
        ..orderBy([(o) => OrderingTerm.asc(o.order)]))
      .get();
  return mbResumoMetas(
      metas: [
        for (final o in objetivos)
          MbMetaDados(
              pk: o.objectivePk,
              nome: o.name,
              alvo: o.amount,
              prazo: o.endDate,
              aplicacaoPks: aplicPorMeta[o.objectivePk] ?? const [])
      ],
      saldoPorAplicacao: saldos,
      hoje: hoje ?? DateTime.now());
}
