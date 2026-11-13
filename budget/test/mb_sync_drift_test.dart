import 'dart:ffi';

import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/armazem.dart';
import 'package:budget/struct/mbSync/cliente.dart';
import 'package:budget/struct/mbSync/mapeamento.dart';
import 'package:budget/struct/mbSync/metas.dart';
import 'package:budget/struct/mbSync/orcamentos.dart';
import 'package:budget/struct/mbSync/pareamento.dart';
import 'package:budget/struct/mbSync/registro.dart';
import 'package:budget/struct/meuBancoSync.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/open.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClienteFalso extends MbCliente {
  ClienteFalso() : super(base: 'https://teste');
  final List<Registro> servidor = [];
  final List<Registro> enviados = [];
  Map<String, dynamic> extra = {};
  bool semRede = false;

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
      List<Registro> lote) async {
    if (semRede) throw http.ClientException('sem rede');
    enviados.addAll(lote);
    return (aceitos: lote.length, rejeitados: <({int indice, String motivo})>[]);
  }
}

String _futuro() =>
    DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String();

Future<void> _categoria(String pk, String nome, {bool receita = false}) =>
    database.into(database.categories).insert(CategoriesCompanion.insert(
        categoryPk: Value(pk),
        name: nome,
        order: 0,
        income: Value(receita),
        dateTimeModified: Value(DateTime.now())));

// Categorias próprias criadas pelo sync (mb:cat:) também sobem ao servidor; os testes olham só o resto.
Iterable<Registro> _semCatsMb(Iterable<Registro> l) =>
    l.where((r) =>
        !r.id.startsWith('cashew:mb:cat:') &&
        r.id != 'cashew:mb:orc:geral' &&
        r.id != 'cashew:mb:meta:reserva');

Future<List<Transaction>> _txs() => database.select(database.transactions).get();

void main() {
  late ClienteFalso cliente;

  setUpAll(() {
    open.overrideFor(OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'));
  });

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    database = FinanceDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({'mbNotifCursor': 'x'});
    cliente = ClienteFalso();
    meuBancoSincronizando.value = false;
  });

  tearDown(() => database.close());

  Future<void> sync() async {
    final ok = await sincronizarMeuBanco(clienteParaTeste: cliente);
    expect(ok, true, reason: meuBancoUltimoErro.value);
  }

  test('categoria criada no RenanCash vai no push com id cashew:<pk>', () async {
    await _categoria('c1', 'Mercado');
    await sync();
    final r = _semCatsMb(cliente.enviados).singleWhere((r) => r.tabela == 'categorias');
    expect(r.id, 'cashew:c1');
    expect(r.dados!['nome'], 'Mercado');
    expect(r.dados!['tipo'], 'despesa');
  });

  test('categoria remota mais nova é aplicada e não é reenviada', () async {
    await _categoria('c1', 'Mercado');
    cliente.servidor.add(Registro('categorias', 'cashew:c1',
        {'nome': 'Supermercado', 'tipo': 'despesa'}, _futuro(), null));
    await sync();
    expect((await database.getCategoryInstanceOrNull('c1'))!.name, 'Supermercado');
    cliente.enviados.clear();
    await sync();
    expect(_semCatsMb(cliente.enviados).where((r) => r.tabela == 'categorias'), isEmpty);
    expect((await database.getCategoryInstanceOrNull('c1'))!.name, 'Supermercado');
  });

  test('edição offline continua pendente e sai na rodada seguinte', () async {
    await _categoria('c1', 'Mercado');
    await sync();
    cliente.enviados.clear();
    await (database.update(database.categories)
          ..where((c) => c.categoryPk.equals('c1')))
        .write(CategoriesCompanion(
            name: const Value('Feira'),
            dateTimeModified: Value(DateTime.now().add(const Duration(seconds: 5)))));
    cliente.semRede = true;
    await sync();
    expect(_semCatsMb(cliente.enviados), isEmpty);
    expect((await mbLerFila()).pendentes, greaterThan(0));
    cliente.semRede = false;
    await sync();
    expect(_semCatsMb(cliente.enviados).single.dados!['nome'], 'Feira');
    expect((await mbLerFila()).pendentes, 0);
  });

  test('tombstone remoto apaga o orçamento local', () async {
    await database.into(database.budgets).insert(BudgetsCompanion.insert(
        budgetPk: const Value('b1'),
        name: 'Casa',
        amount: 500,
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 1, 31),
        periodLength: 1,
        order: 0,
        dateTimeModified: Value(DateTime.now())));
    await sync();
    expect(cliente.enviados.any((r) => r.tabela == 'orcamentos'), true);
    final t = _futuro();
    cliente.servidor
        .add(Registro('orcamentos', 'cashew:b1', null, t, t));
    await sync();
    expect(
        (await database.select(database.budgets).get())
            .where((b) => b.budgetPk != 'mb:orc:geral'),
        isEmpty);
  });

  Map<String, dynamic> banco() => {
        'contas': [
          {'id': 'a1', 'type': 'BANK', 'name': 'Conta'}
        ],
        'transacoes': [
          {
            'id': 't1',
            'account_id': 'a1',
            'date': '2025-01-10',
            'description': 'Padaria',
            'amount': -10.0,
            'category': 'Bakeries',
            'status': 'POSTED',
          }
        ],
      };

  test('mudar categoria de transação mb: gera ajuste e não gera tombstone',
      () async {
    await _categoria('c1', 'Mercado');
    cliente.extra = banco();
    await sync();
    expect((await _txs()).single.transactionPk, 'mb:t1');
    await (database.update(database.transactions)
          ..where((t) => t.transactionPk.equals('mb:t1')))
        .write(TransactionsCompanion(
            categoryFk: const Value('c1'),
            dateTimeModified: Value(DateTime.now().add(const Duration(seconds: 5)))));
    cliente.enviados.clear();
    await sync();
    final aj = cliente.enviados.singleWhere((r) => r.tabela == 'ajustes');
    expect(aj.id, 't1');
    expect(aj.dados!['categoria_id'], 'cashew:c1');
    expect((await _txs()).single.categoryFk, 'c1');
    cliente.enviados.clear();
    await sync();
    expect(cliente.enviados, isEmpty);
    expect((await mbLerEspelho())['ajustes/t1']!.registro.deletedAt, isNull);
    expect((await _txs()).single.categoryFk, 'c1');
  });

  test('categoria apagada remotamente com transações fica e não ressuscita',
      () async {
    await _categoria('c1', 'Mercado');
    await database.into(database.transactions).insert(
        TransactionsCompanion.insert(
            transactionPk: const Value('t1'),
            name: 'Feira',
            amount: -20,
            note: '',
            categoryFk: 'c1',
            walletFk: const Value('0'),
            dateCreated: Value(DateTime(2025, 1, 10)),
            dateTimeModified: Value(DateTime.now())));
    await sync();
    final t = _futuro();
    cliente.servidor.add(Registro('categorias', 'cashew:c1', null, t, t));
    await sync();
    expect(await database.getCategoryInstanceOrNull('c1'), isNotNull);
    final e = (await mbLerEspelho())['categorias/cashew:c1']!;
    expect(e.registro.deletedAt, isNotNull);
    expect(e.projecao, isNull);
    cliente.enviados.clear();
    await sync();
    expect(cliente.enviados.where((r) => r.tabela == 'categorias'), isEmpty);
  });

  test('orçamento arquivado não gera tombstone', () async {
    await database.into(database.budgets).insert(BudgetsCompanion.insert(
        budgetPk: const Value('b1'),
        name: 'Casa',
        amount: 500,
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 1, 31),
        periodLength: 1,
        order: 0,
        dateTimeModified: Value(DateTime.now())));
    await sync();
    await (database.update(database.budgets)
          ..where((b) => b.budgetPk.equals('b1')))
        .write(BudgetsCompanion(
            archived: const Value(true),
            dateTimeModified: Value(DateTime.now().add(const Duration(seconds: 5)))));
    cliente.enviados.clear();
    await sync();
    expect(_semCatsMb(cliente.enviados).where((r) => r.tabela == 'orcamentos'),
        isEmpty);
    expect((await mbLerEspelho())['orcamentos/cashew:b1']!.registro.deletedAt,
        isNull);
  });

  test('reverter categoria A->B->A emite ajuste com A', () async {
    await _categoria('c1', 'Mercado');
    cliente.extra = banco();
    await sync();
    final a = (await _txs()).single.categoryFk;
    Future<void> muda(String cat, int s) =>
        (database.update(database.transactions)
              ..where((t) => t.transactionPk.equals('mb:t1')))
            .write(TransactionsCompanion(
                categoryFk: Value(cat),
                dateTimeModified:
                    Value(DateTime.now().add(Duration(seconds: s)))));
    await muda('c1', 5);
    await sync();
    cliente.enviados.clear();
    await muda(a, 10);
    await sync();
    final aj = cliente.enviados.singleWhere((r) => r.tabela == 'ajustes');
    expect(aj.dados!['categoria_id'], idDoPk(a));
  });

  test('apagar transação mb: gera gasto 0 e ela não volta no pull', () async {
    cliente.extra = banco();
    await sync();
    await database.delete(database.transactions).go();
    cliente.enviados.clear();
    await sync();
    final aj = cliente.enviados.singleWhere((r) => r.tabela == 'ajustes');
    expect(aj.dados, {'gasto': 0});
    expect(await _txs(), isEmpty);
    await sync();
    expect(await _txs(), isEmpty);
  });

  test('entidades remotas aplicadas não voltam como mudança local', () async {
    final t = DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String();
    cliente.servidor.addAll([
      Registro('categorias', 'c9', {'nome': 'Lazer', 'tipo': 'despesa'}, t, null),
      Registro('regras', 'r1', {'padrao': 'CINE*', 'categoria_id': 'c9'}, t, null),
      Registro('orcamentos', 'o1',
          {'nome': 'Lazer', 'valor': 300, 'categoria_ids': ['c9']}, t, null),
      Registro('metas', 'm1', {'nome': 'Viagem', 'valor_alvo': 1000, 'prazo': '2026-12-31'}, t, null),
      Registro('dividas', 'd1',
          {'tipo': 'emprestimo', 'nome': 'Carro', 'sentido': 'devo', 'valor_total': 900}, t, null),
      Registro('lancamentos', 'l1',
          {'data': '2025-03-05', 'descricao': 'Cinema', 'valor': -40, 'categoria_id': 'c9', 'meta_id': 'm1'},
          t, null),
      Registro('assinaturas', 's1',
          {'nome': 'Netflix', 'valor': 39.9, 'dia': 12, 'padrao': 'NETFLIX*', 'status': 'confirmada', 'categoria_id': 'c9'},
          t, null),
    ]);
    await sync();
    expect((await _txs()).map((x) => x.transactionPk).toSet(), {'l1', 's1'});
    expect((await _txs()).firstWhere((x) => x.transactionPk == 'l1').objectiveFk, 'm1');
    // Meta, dívida e a Reserva de emergência criada no primeiro sync.
    expect(await database.select(database.objectives).get(), hasLength(3));
    cliente.enviados.clear();
    await sync();
    expect(_semCatsMb(cliente.enviados), isEmpty);
  });

  group('metas ligadas a aplicações', () {
    Map<String, dynamic> inv(Map<String, double> saldos) => {
          'investimentos': [
            for (final e in saldos.entries)
              {'id': e.key, 'nome': 'Aplicação ${e.key}', 'saldo': e.value, 'banco': 'Inter'}
          ]
        };

    Future<double> progresso(String metaPk) async => (await database
            .customSelect(
                'SELECT COALESCE(SUM(amount), 0) AS s FROM transactions '
                'WHERE objective_fk = ? AND paid = 1',
                variables: [Variable<String>(metaPk)])
            .getSingle())
        .read<double>('s');

    Iterable<Registro> metasEnviadas() => cliente.enviados.where((r) => r.tabela == 'metas');

    test('Reserva de emergência é criada uma vez, sem valor alvo, e vai ao servidor', () async {
      await sync();
      await sync();
      final metas = await database.select(database.objectives).get();
      expect(metas.map((o) => [o.objectivePk, o.name, o.amount, o.endDate, o.pinned]), [
        ['mb:meta:reserva', 'Reserva de emergência', 0.0, null, true]
      ]);
      expect(metas.single.income, isTrue);
      final enviadas = metasEnviadas().toList();
      expect(enviadas, hasLength(1));
      expect(enviadas.single.id, 'cashew:mb:meta:reserva');
      expect(enviadas.single.dados, {'nome': 'Reserva de emergência', 'valor_alvo': 0.0, 'aplicacao_ids': <String>[]});
    });

    test('Reserva já existente no servidor não é recriada; apagada, não volta', () async {
      cliente.servidor.add(Registro('metas', 'cashew:mb:meta:reserva',
          {'nome': 'Reserva de emergência', 'valor_alvo': 30000, 'aplicacao_ids': ['i1']},
          DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String(), null));
      cliente.extra = inv({'i1': 100});
      await sync();
      final o = (await database.select(database.objectives).get()).single;
      expect([o.name, o.amount], ['Reserva de emergência', 30000.0]);
      expect(metasEnviadas(), isEmpty);

      await (database.delete(database.objectives)).go();
      await sync();
      expect(await database.select(database.objectives).get(), isEmpty);
    });

    test('aplicações da meta somam o progresso e não geram ajuste', () async {
      cliente.servidor.add(Registro('metas', 'cashew:m1',
          {'nome': 'Viagem', 'valor_alvo': 5000, 'aplicacao_ids': ['i1', 'i2']},
          DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String(), null));
      cliente.extra = inv({'i1': 1500.5, 'i2': 200, 'i3': 900});
      await sync();
      expect(await progresso('m1'), 1700.5);
      final porPk = {for (final t in await _txs()) t.transactionPk: t.objectiveFk};
      expect(porPk['mb:inv:i3'], isNull);
      // Meta de poupança (income): o tile do RenanCash mostra o progresso positivo.
      expect((await (database.select(database.objectives)..where((o) => o.objectivePk.equals('m1'))).getSingle()).income, isTrue);
      expect(await mbLerAplicado(), isEmpty);
      expect(cliente.enviados.where((r) => r.tabela == 'ajustes'), isEmpty);

      // Saldo muda no sync seguinte: o progresso acompanha.
      cliente.extra = inv({'i1': 1600, 'i2': 200, 'i3': 900});
      await sync();
      expect(await progresso('m1'), 1800.0);
      expect(cliente.enviados.where((r) => r.tabela == 'ajustes'), isEmpty);
    });

    test('vínculo chega antes da aplicação e vale quando ela aparece', () async {
      cliente.servidor.add(Registro('metas', 'cashew:m1',
          {'nome': 'Casa', 'valor_alvo': 10000, 'aplicacao_ids': ['i9']},
          DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String(), null));
      await sync();
      expect(await progresso('m1'), 0);
      cliente.extra = inv({'i9': 777});
      await sync();
      expect(await progresso('m1'), 777);
    });

    test('cada aplicação fica em uma meta só', () async {
      cliente.extra = inv({'i1': 100, 'i2': 50});
      await sync();
      for (final pk in ['m1', 'm2']) {
        await database.into(database.objectives).insert(ObjectivesCompanion.insert(
            objectivePk: Value(pk), name: pk, amount: 1000, order: 5,
            dateTimeModified: Value(DateTime.now())));
      }
      await mbDefinirAplicacoesDaMeta('m1', ['mb:inv:i1']);
      await mbDefinirAplicacoesDaMeta('m2', ['mb:inv:i1', 'mb:inv:i2']);
      expect(await mbVinculosMetas(), {'mb:inv:i1': 'm2', 'mb:inv:i2': 'm2'});
      expect(await progresso('m1'), 0);
      expect(await progresso('m2'), 150);
      final lista = await mbAplicacoes();
      expect({for (final a in lista) a.id: a.metaPk}, {'i1': 'm2', 'i2': 'm2'});
      await mbDefinirAplicacoesDaMeta('m2', ['mb:inv:i2']);
      expect(await progresso('m2'), 50);
      expect((await _txs()).singleWhere((t) => t.transactionPk == 'mb:inv:i1').objectiveFk, isNull);
    });

    test('vínculo escolhido no app sobe ordenado e não volta como mudança', () async {
      cliente.extra = inv({'i1': 100, 'i2': 50});
      await sync();
      await database.into(database.objectives).insert(ObjectivesCompanion.insert(
          objectivePk: const Value('m1'), name: 'Viagem', amount: 2000, order: 5,
          endDate: Value(DateTime(2027, 1, 31, 12)),
          dateTimeModified: Value(DateTime.now())));
      await mbDefinirAplicacoesDaMeta('m1', ['mb:inv:i2', 'mb:inv:i1']);
      cliente.enviados.clear();
      await sync();
      expect(metasEnviadas().singleWhere((r) => r.id == 'cashew:m1').dados,
          {'nome': 'Viagem', 'valor_alvo': 2000.0, 'prazo': '2027-01-31', 'aplicacao_ids': ['i1', 'i2']});
      cliente.enviados.clear();
      await sync();
      expect(_semCatsMb(cliente.enviados), isEmpty);
    });

    test('meta de app antigo (sem aplicacao_ids, sem valor) não apaga vínculos nem o alvo locais', () async {
      cliente.extra = inv({'i1': 100});
      await sync();
      await database.into(database.objectives).insert(ObjectivesCompanion.insert(
          objectivePk: const Value('m1'), name: 'Viagem', amount: 2000, order: 5,
          dateTimeModified: Value(DateTime.now())));
      await mbDefinirAplicacoesDaMeta('m1', ['mb:inv:i1']);
      cliente.servidor.add(Registro('metas', 'cashew:m1', {'nome': 'Viagem 2'}, _futuro(), null));
      await sync();
      final o = await (database.select(database.objectives)..where((x) => x.objectivePk.equals('m1'))).getSingle();
      expect([o.name, o.amount, o.endDate, o.income], ['Viagem 2', 2000.0, null, isTrue]);
      expect(await mbVinculosMetas(), {'mb:inv:i1': 'm1'});
      expect(await progresso('m1'), 100);
    });

    test('meta apagada no servidor solta as aplicações', () async {
      cliente.extra = inv({'i1': 100});
      cliente.servidor.add(Registro('metas', 'cashew:m1',
          {'nome': 'Viagem', 'valor_alvo': 100, 'aplicacao_ids': ['i1']},
          DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String(), null));
      await sync();
      expect(await progresso('m1'), 100);
      final t = _futuro();
      cliente.servidor
        ..clear()
        ..add(Registro('metas', 'cashew:m1', null, t, t));
      await sync();
      expect(await mbVinculosMetas(), isEmpty);
      expect((await _txs()).singleWhere((x) => x.transactionPk == 'mb:inv:i1').objectiveFk, isNull);
    });

    test('série mensal do Worker é guardada; Worker antigo não apaga a série', () async {
      final serie = [
        {'mes': '2026-11', 'itens': [{'id': 'i1', 'nome': 'CDB', 'banco': 'Inter', 'saldo': 1700.5}]},
        {'mes': '2026-10', 'itens': [{'id': 'i1', 'nome': 'CDB', 'banco': 'Inter', 'saldo': 1500}, {'id': 'i2', 'nome': 'Fundo', 'saldo': 200}]},
      ];
      cliente.extra = {...inv({'i1': 1700.5}), 'investimentos_mensal': serie};
      await sync();
      var lida = await mbLerSerieMensal();
      expect(lida.map((m) => m.mes), ['2026-10', '2026-11']);
      expect(lida.map((m) => m.total), [1700.0, 1700.5]);
      cliente.extra = inv({'i1': 1700.5});
      await sync();
      lida = await mbLerSerieMensal();
      expect(lida, hasLength(2));
      expect(mbSerieDeJson('lixo'), isEmpty);
    });
  });

  test('trocar de conta apaga o espelho e o importado, e reenvia o que é do RenanCash', () async {
    await _categoria('c1', 'Mercado');
    cliente.extra = banco();
    await sync();
    expect((await _txs()).map((t) => t.transactionPk), contains('mb:t1'));
    expect(cliente.enviados.where((r) => r.id == 'cashew:c1'), isNotEmpty);
    expect((await database.select(database.categories).get())
        .where((c) => c.categoryPk.startsWith('mb:cat:')), isNotEmpty);
    expect((await database.select(database.wallets).get())
        .where((w) => w.walletPk.startsWith('mb:')), isNotEmpty);

    await mbTrocarConta();
    expect((await _txs()).where((t) => t.transactionPk.startsWith('mb:')), isEmpty);
    expect(await mbLerEspelho(), isEmpty);
    expect(await mbLerAplicado(), isEmpty);
    expect(await mbLerEstado('cursor'), isNull);
    expect(await database.getCategoryInstanceOrNull('c1'), isNotNull);
    final cats = await database.select(database.categories).get();
    expect(cats.where((c) => c.categoryPk.startsWith('mb:cat:')), isEmpty);
    expect((await database.select(database.wallets).get())
        .where((w) => w.walletPk.startsWith('mb:')), isEmpty);

    cliente.enviados.clear();
    cliente.extra = {};
    await sync();
    expect(cliente.enviados.where((r) => r.id == 'cashew:c1'), isNotEmpty);
    expect((await SharedPreferences.getInstance()).getString('mbNotifCursor'), isNull);
  });

  test('conta corrente Santander importada antes é apagada sem mandar ajuste', () async {
    final st = {'id': 'st', 'type': 'BANK', 'subtype': 'CHECKING_ACCOUNT', 'name': 'Conta', 'bank': 'Santander'};
    final tx = {'id': 'st-1', 'account_id': 'st', 'date': '2025-01-10', 'description': 'Pix', 'amount': -10.0, 'category': 'Transfers', 'status': 'POSTED'};
    // Simula o import antigo: carteira e transação mb: já aplicadas.
    cliente.extra = {
      'contas': [{...st, 'bank': 'Inter'}],
      'transacoes': [tx],
    };
    await sync();
    expect((await _txs()).map((t) => t.transactionPk), ['mb:st-1']);
    cliente.enviados.clear();
    cliente.extra = {'contas': [st], 'transacoes': [tx]};
    await sync();
    expect(await database.getWalletInstanceOrNull('mb:st'), isNull);
    expect(await _txs(), isEmpty);
    expect(cliente.enviados.where((r) => r.tabela == 'ajustes'), isEmpty);
    expect(await mbLerEstado('contas'), '[]');
  });

  test('investimentos viram ajuste de saldo na carteira Investimentos', () async {
    cliente.extra = {
      'investimentos': [
        {'id': 'i1', 'nome': 'CDB ', 'saldo': 1500.5, 'banco': 'Santander'},
        {'id': 'i2', 'nome': 'Fundo', 'saldo': 200.0},
      ]
    };
    await sync();
    expect(await database.getWalletInstanceOrNull('mb:investimentos'), isNotNull);
    final cdb = (await _txs()).singleWhere((t) => t.transactionPk == 'mb:inv:i1');
    expect([cdb.name, cdb.amount, cdb.note, cdb.categoryFk, cdb.income], ['CDB', 1500.5, 'Santander', '0', true]);
    cliente.enviados.clear();
    cliente.extra = {
      'investimentos': [
        {'id': 'i1', 'nome': 'CDB', 'saldo': 1600.0, 'banco': 'Santander'},
      ]
    };
    await sync();
    final txs = await _txs();
    expect(txs.map((t) => t.transactionPk), ['mb:inv:i1']);
    expect(txs.single.amount, 1600.0);
    expect(txs.single.dateCreated, cdb.dateCreated);
    expect(cliente.enviados.where((r) => r.tabela == 'ajustes'), isEmpty);
  });

  test('histórico: primeira carga completa converte as categorias sem mandar ajuste', () async {
    await _categoria('c1', 'Mercado');
    cliente.extra = banco();
    await sync();
    await mbRemoverEstado('conv_categorias_v1');
    // Estado antigo: categoria pela tradução do banco, já aplicada.
    await (database.update(database.transactions)
          ..where((t) => t.transactionPk.equals('mb:t1')))
        .write(const TransactionsCompanion(categoryFk: Value('mb:cat:d:Padaria')));
    await mbGravarAplicado({'mb:t1': 'mb:cat:d:Padaria'}, const []);
    cliente.enviados.clear();
    await sync();
    expect((await _txs()).single.categoryFk, 'mb:cat:d:Outros');
    expect((await mbLerAplicado())['mb:t1'], 'mb:cat:d:Outros');
    expect(cliente.enviados.where((r) => r.tabela == 'ajustes'), isEmpty);
    expect(await mbLerEstado('conv_categorias_v1'), isNotNull);
    cliente.enviados.clear();
    await sync();
    expect(cliente.enviados.where((r) => r.tabela == 'ajustes'), isEmpty);
  });

  test('histórico: categoria escolhida pelo usuário sobrevive à conversão', () async {
    await _categoria('c1', 'Mercado');
    cliente.extra = banco();
    await sync();
    await mbRemoverEstado('conv_categorias_v1');
    await (database.update(database.transactions)
          ..where((t) => t.transactionPk.equals('mb:t1')))
        .write(TransactionsCompanion(
            categoryFk: const Value('c1'),
            dateTimeModified: Value(DateTime.now().add(const Duration(seconds: 5)))));
    await sync();
    expect((await _txs()).single.categoryFk, 'c1');
    expect(cliente.enviados.singleWhere((r) => r.tabela == 'ajustes').dados!['categoria_id'], 'cashew:c1');
  });

  test('histórico: transação que passou a ser transferência sai sem ajuste', () async {
    cliente.extra = {
      'contas': [{'id': 'a1', 'type': 'BANK', 'name': 'Conta', 'bank': 'Inter'}],
      'transacoes': [
        {'id': 'r1', 'account_id': 'a1', 'date': '2025-01-10', 'description': 'Pix SANTANDER', 'amount': 900.0, 'status': 'POSTED'}
      ],
    };
    await mbCriarTabelas();
    await sync();
    expect(await _txs(), isEmpty);
    await database.into(database.transactions).insert(TransactionsCompanion.insert(
        transactionPk: const Value('mb:r1'),
        name: 'Pix SANTANDER',
        amount: 900.0,
        note: '',
        categoryFk: 'mb:cat:r:Transferências',
        walletFk: const Value('mb:a1'),
        dateCreated: Value(DateTime(2025, 1, 10, 12)),
        income: const Value(true),
        paid: const Value(true),
        dateTimeModified: Value(DateTime.utc(2000))));
    await mbGravarAplicado({'mb:r1': 'mb:cat:r:Transferências'}, const []);
    await mbRemoverEstado('conv_categorias_v1');
    cliente.enviados.clear();
    await sync();
    expect(await _txs(), isEmpty);
    expect(await mbLerAplicado(), isEmpty);
    expect(cliente.enviados.where((r) => r.tabela == 'ajustes'), isEmpty);
  });

  group('orçamentos', () {
    Future<void> orcamento(String pk) =>
        database.into(database.budgets).insert(BudgetsCompanion.insert(
            budgetPk: Value(pk),
            name: pk,
            amount: 500,
            startDate: DateTime(2025, 1, 1),
            endDate: DateTime(2025, 1, 31),
            periodLength: 1,
            order: 5,
            budgetTransactionFilters: const Value(
                [BudgetTransactionFilters.defaultBudgetTransactionFilters]),
            dateTimeModified: Value(DateTime.now())));

    Future<void> depois(String pk, Set<String>? escolha) =>
        mbDefinirOrcamentosDaTransacao(pk, escolha,
            agora: DateTime.now().add(const Duration(seconds: 5)));

    test('o Geral é criado na sincronização com valor 0 e sobe ao servidor', () async {
      await sync();
      final g = await database.getBudgetInstance(mbOrcamentoGeralPk);
      expect(g.name, 'Geral');
      expect(g.amount, 0);
      await sync();
      final env = cliente.enviados.singleWhere((r) => r.id == 'cashew:mb:orc:geral');
      expect(env.tabela, 'orcamentos');
      expect(env.dados!['valor'], 0);
      expect(env.dados!['periodo'], 'ciclo');
    });

    test('escolha em transação mb: sai em ajustes uma vez e não repete', () async {
      cliente.extra = banco();
      await sync();
      await orcamento('b1');
      await depois('mb:t1', {'b1', mbOrcamentoGeralPk});
      cliente.enviados.clear();
      await sync();
      final aj = cliente.enviados.singleWhere((r) => r.tabela == 'ajustes');
      expect(aj.id, 't1');
      expect(aj.dados!['orcamento_ids'], ['cashew:b1', 'cashew:mb:orc:geral']);
      expect(aj.dados!.containsKey('gasto'), false);
      cliente.enviados.clear();
      await sync();
      expect(cliente.enviados.where((r) => r.tabela == 'ajustes'), isEmpty);
    });

    test('voltar ao Geral apaga a escolha no servidor', () async {
      cliente.extra = banco();
      await sync();
      await orcamento('b1');
      await depois('mb:t1', {'b1'});
      await sync();
      expect(await mbOrcamentosDaTransacao('mb:t1'), {'b1'});
      await mbDefinirOrcamentosDaTransacao('mb:t1', {mbOrcamentoGeralPk},
          agora: DateTime.now().add(const Duration(seconds: 10)));
      cliente.enviados.clear();
      await sync();
      final aj = cliente.enviados.where((r) => r.tabela == 'ajustes');
      expect(aj.every((r) => r.dados?.containsKey('orcamento_ids') != true), true);
      expect(await mbOrcamentosDaTransacao('mb:t1'), isNull);
      expect((await mbLerEspelho())['ajustes/t1']!.projecao?['orcamento_ids'], isNull);
    });

    test('transação mb: sem escolha não gera ajuste nem gasto 0', () async {
      cliente.extra = banco();
      await sync();
      cliente.enviados.clear();
      await sync();
      await sync();
      expect(cliente.enviados.where((r) => r.tabela == 'ajustes'), isEmpty);
    });

    test('ajuste vindo do servidor grava a escolha e não volta como mudança', () async {
      cliente.extra = banco();
      await sync();
      await orcamento('b1');
      cliente.servidor.add(Registro('ajustes', 't1',
          {'orcamento_ids': ['cashew:b1']}, _futuro(), null));
      cliente.enviados.clear();
      await sync();
      expect(await mbOrcamentosDaTransacao('mb:t1'), {'b1'});
      cliente.enviados.clear();
      await sync();
      expect(cliente.enviados.where((r) => r.tabela == 'ajustes'), isEmpty);
    });

    test('lançamento manual: escolha sobe e a recebida de outro aparelho é aplicada', () async {
      await _categoria('c1', 'Mercado');
      await orcamento('b1');
      await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
              transactionPk: const Value('m1'),
              name: 'Feira',
              amount: -20,
              note: '',
              categoryFk: 'c1',
              walletFk: const Value('0'),
              dateCreated: Value(DateTime(2025, 1, 10)),
              dateTimeModified: Value(DateTime.now())));
      await mbDefinirOrcamentosDaTransacao('m1', {'b1'});
      await sync();
      final l = cliente.enviados.singleWhere((r) => r.tabela == 'lancamentos');
      expect(l.dados!['orcamento_ids'], ['cashew:b1']);
      cliente.servidor.add(Registro(
          'lancamentos',
          'l9',
          {'data': '2025-01-11', 'descricao': 'Cinema', 'valor': -40, 'orcamento_ids': ['cashew:b1']},
          _futuro(),
          null));
      cliente.servidor.add(Registro('lancamentos', 'l8',
          {'data': '2025-01-11', 'descricao': 'Padaria', 'valor': -10}, _futuro(), null));
      await sync();
      expect(await mbOrcamentosDaTransacao('l9'), {'b1'});
      expect(await mbOrcamentosDaTransacao('l8'), isNull);
    });
  });
}
