// Medições de desempenho reproduzíveis (imprimem linhas "PERF ..."):
//   PERF=1 TZ=UTC flutter test test/perf_test.dart 2>&1 | rg "PERF"
// Não são asserções de tempo (variam por máquina); só travam contagens estáveis.
// A única comparação de tempo (maior pausa do event loop) só roda com PERF=1.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:budget/database/platform/native.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/cliente.dart';
import 'package:budget/struct/mbSync/registro.dart';
import 'package:budget/struct/meuBancoSync.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';

class ContadorQueries extends QueryInterceptor {
  int selects = 0, escritas = 0;
  int estadoCiclo = 0; // leituras de mb_estado['ciclo'] = recargas completas do Início
  void zerar() => selects = escritas = estadoCiclo = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
      QueryExecutor e, String sql, List<Object?> args) {
    selects++;
    if (sql.contains('mb_estado') && args.isNotEmpty && args.first == 'ciclo') {
      estadoCiclo++;
    }
    return super.runSelect(e, sql, args);
  }

  @override
  Future<int> runInsert(QueryExecutor e, String sql, List<Object?> args) {
    escritas++;
    return super.runInsert(e, sql, args);
  }

  @override
  Future<int> runUpdate(QueryExecutor e, String sql, List<Object?> args) {
    escritas++;
    return super.runUpdate(e, sql, args);
  }

  @override
  Future<int> runDelete(QueryExecutor e, String sql, List<Object?> args) {
    escritas++;
    return super.runDelete(e, sql, args);
  }

  @override
  Future<void> runCustom(QueryExecutor e, String sql, List<Object?> args) {
    escritas++;
    return super.runCustom(e, sql, args);
  }
}

class ClienteFalso extends MbCliente {
  ClienteFalso() : super(base: 'https://teste');
  final List<Registro> servidor = [];
  Map<String, dynamic> extra = {};

  @override
  Future<Map<String, dynamic>> puxar(String? desde) async => {
        'agora': DateTime.now().toUtc().toIso8601String(),
        'registros': [for (final r in servidor) r.toJson()],
        'contas': [],
        'transacoes': [],
        'pendentes': [],
        ...extra,
      };

  @override
  Future<({int aceitos, List<({int indice, String motivo})> rejeitados})> enviar(
          List<Registro> lote) async =>
      (aceitos: lote.length, rejeitados: <({int indice, String motivo})>[]);
}

final _ciclo = {
  'inicio': '2026-10-26',
  'fim': '2026-11-25',
  'consumido': 1300.0,
  'limite': 5000.0,
  'percentual': 26.0,
  'diasRestantes': 16,
  'por_dia': [
    for (var i = 0; i < 31; i++)
      {'data': DateTime(2026, 10, 26 + i).toIso8601String().substring(0, 10), 'valor': i * 3.0}
  ],
};

Map<String, dynamic> _banco(int n, {int offset = 0}) => {
      'contas': [
        {'id': 'a1', 'type': 'BANK', 'name': 'Conta', 'bank': 'Inter', 'balance': 1000.0}
      ],
      'ciclo': _ciclo,
      'sincronizado_em': DateTime.now().toUtc().toIso8601String(),
      'transacoes': [
        for (var i = offset; i < offset + n; i++)
          {
            'id': 't$i',
            'account_id': 'a1',
            'date': '2026-10-${(i % 28 + 1).toString().padLeft(2, '0')}',
            'description': 'Compra $i',
            'amount': -(i % 97 + 1).toDouble(),
            'category': 'Cat${i % 12}',
            'status': 'POSTED',
          }
      ],
    };

List<Registro> _lancamentos(int n, String t) => [
      Registro('categorias', 'c9', {'nome': 'Lazer', 'tipo': 'despesa'}, t, null),
      for (var i = 0; i < n; i++)
        Registro(
            'lancamentos',
            'l$i',
            {
              'data': '2026-10-${(i % 28 + 1).toString().padLeft(2, '0')}',
              'descricao': 'Lanc $i',
              'valor': -(i % 97 + 1),
              'categoria_id': 'c9',
            },
            t,
            null),
    ];

String _futuro() =>
    DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String();

void main() {
  setUpAll(() {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  var bancoAberto = false;
  late ContadorQueries contador;
  late ClienteFalso cliente;

  Future<void> novoBanco() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    contador = ContadorQueries();
    database = FinanceDatabase(NativeDatabase.memory().interceptWith(contador));
    SharedPreferences.setMockInitialValues({'mbNotifCursor': 'x'});
    cliente = ClienteFalso();
    meuBancoSincronizando.value = false;
    bancoAberto = true;
    await database.customSelect('select 1').get(); // cria o schema antes de medir
    contador.zerar();
  }

  Future<void> sync() async {
    final ok = await sincronizarMeuBanco(clienteParaTeste: cliente);
    expect(ok, true, reason: meuBancoUltimoErro.value);
  }

  Future<String> medir(String rotulo, int n) async {
    contador.zerar();
    final sw = Stopwatch()..start();
    await sync();
    sw.stop();
    return 'PERF sync $rotulo N=$n: ${sw.elapsedMilliseconds} ms, '
        '${contador.selects} selects, ${contador.escritas} escritas';
  }

  tearDown(() async {
    if (bancoAberto) await database.close();
    bancoAberto = false;
  });

  for (final n in [500, 2000]) {
    test('sync Pluggy (transacoes) N=$n', () async {
      await novoBanco();
      cliente.extra = _banco(n);
      final linhas = <String>[await medir('pluggy 1a sync', n)];
      linhas.add(await medir('pluggy 2a sync (idempotente)', n));
      linhas.forEach(print);
      expect((await database.select(database.transactions).get()).length, n);
    });

    test('sync registros (lancamentos) N=$n', () async {
      await novoBanco();
      cliente.servidor.addAll(_lancamentos(n, _futuro()));
      final linhas = <String>[await medir('registros 1a sync', n)];
      cliente.servidor.clear();
      linhas.add(await medir('registros 2a sync (sem novidade)', n));
      linhas.forEach(print);
      expect((await database.select(database.transactions).get()).length, n);
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  // Banco em arquivo (commit real em disco, como no aparelho), conexão em isolate.
  test('sync Pluggy em disco N=2000', () async {
    final dir = await Directory.systemTemp.createTemp('perf_sync');
    addTearDown(() => dir.delete(recursive: true));
    TestWidgetsFlutterBinding.ensureInitialized();
    contador = ContadorQueries();
    database = FinanceDatabase(abrirExecutorNativo(File('${dir.path}/db.sqlite'),
            isolateSetup: () => open.overrideFor(
                OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0')))
        .interceptWith(contador));
    bancoAberto = true;
    SharedPreferences.setMockInitialValues({'mbNotifCursor': 'x'});
    cliente = ClienteFalso()..extra = _banco(2000);
    meuBancoSincronizando.value = false;
    await database.customSelect('select 1').get();
    var emissoes = 0;
    final sub = mbMudouUltimas().skip(1).listen((_) => emissoes++);
    await Future.delayed(const Duration(milliseconds: 100));
    final linha = await medir('pluggy em disco 1a sync', 2000);
    await Future.delayed(const Duration(milliseconds: 300));
    await sub.cancel();
    print('$linha, $emissoes emissões do stream das últimas');
  }, timeout: const Timeout(Duration(minutes: 5)));

  // Liga os gatilhos como InicioEditorial/PainelDesktop: cada _carregar() completo faz
  // 4 leituras de mb_estado + o join das últimas e termina em setState.
  test('Início: recargas completas por sync', () async {
    await novoBanco();
    cliente.extra = _banco(50);
    await sync();
    var cargas = 0, gatilhosSync = 0, gatilhosStream = 0;
    final recarga = RecargaColapsada(() async {
      cargas++;
      await mbCarregarModeloInicio('Renan', DateTime.now());
    });
    void aoSync() {
      gatilhosSync++;
      recarga.pedir();
    }

    meuBancoUltimaSync.addListener(aoSync);
    final sub = mbMudouUltimas().listen((_) {
      gatilhosStream++;
      recarga.pedir();
    });
    addTearDown(() {
      meuBancoUltimaSync.removeListener(aoSync);
      recarga.fechar();
      return sub.cancel();
    });
    Future<void> assentar() => Future.delayed(const Duration(milliseconds: 200));
    final linhas = <String>[];
    await assentar(); // initState: a 1ª emissão do stream faz a carga
    linhas.add('PERF Início abertura: $cargas recarga(s) completa(s)');

    Future<void> cenario(String rotulo, Future<void> Function() acao) async {
      cargas = gatilhosSync = gatilhosStream = 0;
      contador.zerar();
      await acao();
      await assentar();
      linhas.add('PERF Início $rotulo: $cargas recargas completas '
          '(gatilhos: sync=$gatilhosSync, stream=$gatilhosStream; ${contador.selects} selects)');
    }

    await cenario('sync com 5 novas', () async {
      cliente.extra = _banco(55);
      await sync();
    });
    await cenario('sync sem novidade', sync);
    linhas.forEach(print);
  });

  // Prova do item 1: leitura na thread de UI. Um ticker de 1 ms mede o maior intervalo
  // entre ticks enquanto uma consulta pesada (CPU puro no SQLite) roda.
  Future<int> maiorPausa(QueryExecutor executor) async {
    final db = FinanceDatabase(executor);
    await db.customSelect('select 1').get();
    var ultimo = Stopwatch()..start();
    var maior = 0;
    final ticker = Timer.periodic(const Duration(milliseconds: 1), (_) {
      final dt = ultimo.elapsedMilliseconds;
      if (dt > maior) maior = dt;
      ultimo = Stopwatch()..start();
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    maior = 0;
    for (var i = 0; i < 3; i++) {
      await db.customSelect(
          'WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM c WHERE x<3000000) '
          'SELECT sum(x) AS s FROM c').get();
    }
    await Future<void>.delayed(const Duration(milliseconds: 5)); // deixa o ticker registrar a pausa
    ticker.cancel();
    await db.close();
    return maior;
  }

  test('SQLite fora da thread de UI: maior pausa do event loop durante leituras', () async {
    final dir = await Directory.systemTemp.createTemp('perf_db');
    addTearDown(() => dir.delete(recursive: true));
    void setupIsolate() => open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
    // Configuração antiga de constructDb: leitura NativeDatabase (isolate principal).
    final antigo = await maiorPausa(MultiExecutor(
        read: NativeDatabase(File('${dir.path}/a.sqlite')),
        write: NativeDatabase.createInBackground(File('${dir.path}/a.sqlite'),
            isolateSetup: setupIsolate)));
    // Configuração nova.
    final novo = await maiorPausa(
        abrirExecutorNativo(File('${dir.path}/b.sqlite'), isolateSetup: setupIsolate));
    print('PERF maior pausa do event loop (3 leituras pesadas): '
        'antes=$antigo ms, depois=$novo ms');
    expect(novo, lessThan(antigo));
    // Asserção de tempo: instável em runner compartilhado, e o release roda `flutter test`.
  }, skip: Platform.environment['PERF'] == null ? 'medição de tempo: rode com PERF=1' : false);
}
