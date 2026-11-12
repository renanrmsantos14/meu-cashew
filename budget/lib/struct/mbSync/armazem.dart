import 'dart:convert';

import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/registro.dart';
import 'package:drift/drift.dart';

Future<void> mbCriarTabelas() async {
  await database.customStatement(
      'CREATE TABLE IF NOT EXISTS mb_registros ('
      'tabela TEXT NOT NULL, id TEXT NOT NULL, dados TEXT, updated_at TEXT NOT NULL, '
      'deleted_at TEXT, projecao TEXT, pendente INTEGER NOT NULL DEFAULT 0, motivo TEXT, '
      'PRIMARY KEY (tabela, id))');
  await database.customStatement(
      'CREATE TABLE IF NOT EXISTS mb_estado (chave TEXT PRIMARY KEY, valor TEXT NOT NULL)');
  await database.customStatement(
      'CREATE TABLE IF NOT EXISTS mb_aplicado (tx_pk TEXT PRIMARY KEY, categoria_pk TEXT NOT NULL)');
}

Map<String, dynamic>? _json(Object? texto) => texto == null
    ? null
    : (jsonDecode(texto as String) as Map).cast<String, dynamic>();

Espelho _espelho(Map<String, dynamic> l) => Espelho(
      Registro(l['tabela'] as String, l['id'] as String, _json(l['dados']),
          l['updated_at'] as String, l['deleted_at'] as String?),
      _json(l['projecao']),
      (l['pendente'] as int) == 1,
      l['motivo'] as String?,
    );

Future<Map<String, Espelho>> mbLerEspelho({String? tabela}) async {
  final linhas = await database
      .customSelect('SELECT * FROM mb_registros WHERE ?1 IS NULL OR tabela = ?1',
          variables: [Variable<String>(tabela)])
      .get();
  final out = <String, Espelho>{};
  for (final l in linhas) {
    final e = _espelho(l.data);
    out[e.registro.chave] = e;
  }
  return out;
}

Future<void> _gravar(Iterable<Espelho> itens) async {
  for (final e in itens) {
    final r = e.registro;
    await database.customStatement(
        'INSERT OR REPLACE INTO mb_registros (tabela, id, dados, updated_at, deleted_at, projecao, pendente, motivo) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          r.tabela,
          r.id,
          r.deletedAt != null || r.dados == null ? null : jsonCanonico(r.dados),
          r.updatedAt,
          r.deletedAt,
          e.projecao == null ? null : jsonCanonico(e.projecao),
          e.pendente ? 1 : 0,
          e.motivo,
        ]);
  }
}

Future<void> mbGravarEspelho(Iterable<Espelho> itens) =>
    database.transaction(() => _gravar(itens));

Future<List<Espelho>> mbPendentes({int limite = 500}) async {
  final linhas = await database
      .customSelect(
          'SELECT * FROM mb_registros WHERE pendente = 1 ORDER BY updated_at, tabela, id LIMIT ?',
          variables: [Variable.withInt(limite)])
      .get();
  return [for (final l in linhas) _espelho(l.data)];
}

// Os itens do lote deixam de ser pendentes; os rejeitados (índice no lote) guardam o motivo.
Future<void> mbMarcarEnviados(
    List<Espelho> lote, Map<int, String> rejeitados) {
  return database.transaction(() => _gravar([
        for (var i = 0; i < lote.length; i++)
          Espelho(lote[i].registro, lote[i].projecao, false, rejeitados[i])
      ]));
}

Future<String?> mbLerEstado(String chave) async {
  final l = await database.customSelect('SELECT valor FROM mb_estado WHERE chave = ?',
      variables: [Variable.withString(chave)]).getSingleOrNull();
  return l?.read<String>('valor');
}

Future<void> mbGravarEstado(Map<String, String> valores) =>
    database.transaction(() async {
      for (final e in valores.entries) {
        await database.customStatement(
            'INSERT OR REPLACE INTO mb_estado (chave, valor) VALUES (?, ?)',
            [e.key, e.value]);
      }
    });

Future<void> mbRemoverEstado(String chave) =>
    database.customStatement('DELETE FROM mb_estado WHERE chave = ?', [chave]);

Future<Map<String, String>> mbLerAplicado() async {
  final linhas =
      await database.customSelect('SELECT tx_pk, categoria_pk FROM mb_aplicado').get();
  return {
    for (final l in linhas)
      l.read<String>('tx_pk'): l.read<String>('categoria_pk')
  };
}

Future<void> mbGravarAplicado(
        Map<String, String> novos, Iterable<String> removidos) =>
    database.transaction(() async {
      for (final e in novos.entries) {
        await database.customStatement(
            'INSERT OR REPLACE INTO mb_aplicado (tx_pk, categoria_pk) VALUES (?, ?)',
            [e.key, e.value]);
      }
      for (final pk in removidos) {
        await database
            .customStatement('DELETE FROM mb_aplicado WHERE tx_pk = ?', [pk]);
      }
    });

class MbFila {
  final int pendentes;
  final List<String> rejeitados;
  const MbFila(this.pendentes, this.rejeitados);
}

Future<MbFila> mbLerFila() async {
  final n = await database
      .customSelect('SELECT COUNT(*) AS n FROM mb_registros WHERE pendente = 1')
      .getSingle();
  final rej = await database
      .customSelect(
          'SELECT tabela, id, dados, motivo FROM mb_registros WHERE motivo IS NOT NULL ORDER BY updated_at DESC LIMIT 20')
      .get();
  return MbFila(n.read<int>('n'), [
    for (final l in rej)
      () {
        final d = _json(l.data['dados']);
        final nome = d?['nome'] ?? d?['descricao'] ?? d?['padrao'] ?? l.data['id'];
        return '${l.data['tabela']} · $nome: ${l.data['motivo']}';
      }()
  ]);
}
