import 'dart:convert';
import 'dart:ffi';

import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/armazem.dart';
import 'package:budget/struct/mbSync/categoriaEfetiva.dart';
import 'package:budget/struct/mbSync/cliente.dart';
import 'package:budget/struct/mbSync/emprestimos.dart';
import 'package:budget/struct/mbSync/notificacoes.dart';
import 'package:budget/struct/mbSync/reembolso.dart';
import 'package:budget/struct/mbSync/registro.dart';
import 'package:budget/struct/mbSync/revisao.dart';
import 'package:budget/struct/meuBancoMapping.dart';
import 'package:budget/struct/meuBancoSync.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';

const _ctx0 = MbContextoCategoria({}, [], {}, {});

Map<String, dynamic> _tx(String id, String desc, double valor,
        {String data = '2026-11-10', String? categoria}) =>
    {
      'id': id, 'account_id': 'cc', 'date': data, 'description': desc,
      'amount': valor, 'status': 'POSTED', 'category': categoria, 'scheduled': 0,
    };

Map<String, dynamic> _json(List<Map<String, dynamic>> txs,
        {String? inicio = '2026-11-05'}) =>
    {
      'agora': '2026-11-12T10:00:00.000Z',
      'contas': [{'id': 'cc', 'type': 'BANK', 'name': 'Conta Inter'}],
      'transacoes': txs,
      'ciclo': {if (inicio != null) 'inicio': inicio},
    };

Registro _decisao(String tx, String resposta, {String? categoriaId, String? dest}) =>
    Registro('revisoes', 'tx:$tx', {
      'tipo': 'decisao', 'tx_id': tx, 'resposta': resposta,
      if (categoriaId != null) 'categoria_id': categoriaId,
      if (dest != null) 'destinatario': dest,
    }, '2026-11-11T00:00:00.000Z', null);

Registro _decisaoReembolso(String tx, String gasto) =>
    Registro('revisoes', 'tx:$tx', {
      'tipo': 'decisao', 'tx_id': tx, 'resposta': 'reembolso', 'reembolso_de': gasto,
    }, '2026-11-11T00:00:00.000Z', null);

Registro _destino(String nome, String categoriaId) =>
    Registro('revisoes', 'dest:$nome',
        {'tipo': 'destinatario', 'destinatario': nome, 'categoria_id': categoriaId},
        '2026-11-11T00:00:00.000Z', null);

MbResultado _mapear(List<Map<String, dynamic>> txs,
        {List<Registro> regs = const [], String? inicio = '2026-11-05'}) =>
    mbMapearPull(_json(txs, inicio: inicio), _ctx0,
        revisoes: MbRevisoes.deRegistros(regs),
        pkCategoria: (id, nome, receita) => id ?? mbPkCategoria(nome, receita));

MbTransacao _t(MbResultado r, String id) =>
    r.transacoes.firstWhere((t) => t.pk == 'mb:$id');

void main() {
  group('tipo de item', () {
    test('Pix enviado, envio ao Santander e Pix recebido', () {
      final p = mbTipoDeRevisao(descricao: 'Pix enviado: João Silva', valor: -50)!;
      expect([p.tipo, p.destinatario], ['pix_enviado', 'JOAO SILVA']);
      expect(
          mbTipoDeRevisao(
                  descricao: 'PIX ENVIADO SANTANDER BRASIL',
                  valor: -500,
                  categoria: 'Same person transfer')!
              .tipo,
          'envio_santander');
      expect(mbTipoDeRevisao(descricao: 'Pix recebido: Maria', valor: 80)!.tipo, 'pix_recebido');
    });

    test('compras comuns, aplicações e agendadas não geram pergunta', () {
      expect(mbTipoDeRevisao(descricao: 'MERCADO', valor: -50), isNull);
      expect(mbTipoDeRevisao(descricao: 'Aplicação Santander CDB', valor: -50), isNull);
      expect(mbTipoDeRevisao(descricao: 'Pix enviado: Ana', valor: -50, categoria: 'Investment'), isNull);
    });
  });

  group('não conta até responder', () {
    test('Pix enviado sem resposta é gasto "A classificar"', () {
      final r = _mapear([_tx('p1', 'Pix enviado: Joao', -50)]);
      final t = _t(r, 'p1');
      expect(t.valor, -50);
      expect(t.categoriaNome, mbCategoriaAClassificar);
      expect(r.categoriasProprias.keys, contains(mbCategoriaAClassificar));
    });

    test('envio ao Santander sem resposta fica fora do gasto', () {
      final r = _mapear([_tx('e1', 'PIX ENVIADO SANTANDER', -800)]);
      expect(r.transacoes, isEmpty);
      expect(r.naoGastoPks, contains('mb:e1'));
    });

    test('Ajuda vira gasto em Família, mesmo com categoria de transferência', () {
      final r = _mapear([_tx('e1', 'PIX ENVIADO SANTANDER', -800, categoria: 'Same person transfer')],
          regs: [_decisao('e1', 'ajuda')]);
      final t = _t(r, 'e1');
      expect([t.valor, t.categoriaNome], [-800, mbCategoriaAjuda]);
    });

    test('Empréstimo e Investimento não são gasto', () {
      for (final resposta in ['emprestimo', 'investimento']) {
        final r = _mapear([_tx('e1', 'PIX ENVIADO SANTANDER', -800)], regs: [_decisao('e1', resposta)]);
        expect(r.transacoes, isEmpty, reason: resposta);
        expect(r.naoGastoPks, contains('mb:e1'));
      }
    });
  });

  group('memória por destinatário', () {
    test('a resposta da transação define a categoria', () {
      final r = _mapear([_tx('p1', 'Pix enviado: Joao Silva', -50)],
          regs: [_decisao('p1', 'categoria', categoriaId: 'cashew:lazer')]);
      expect(_t(r, 'p1').categoriaPk, 'cashew:lazer');
    });

    test('Pix seguinte para a mesma pessoa usa a categoria lembrada; outra pessoa continua a classificar', () {
      final r = _mapear([
        _tx('p2', 'Pix enviado: Joao Silva', -70),
        _tx('p3', 'Pix enviado: Ana', -20),
      ], regs: [_destino('JOAO SILVA', 'cashew:lazer')]);
      expect(_t(r, 'p2').categoriaPk, 'cashew:lazer');
      expect(_t(r, 'p3').categoriaNome, mbCategoriaAClassificar);
    });

    test('a categoria que o usuário escolheu no Cashew (ajuste) vale mais que a da fila', () {
      final ctx = MbContextoCategoria({'p1': {'categoria_id': 'cashew:casa'}}, [], {}, {});
      final r = mbMapearPull(_json([_tx('p1', 'Pix enviado: Joao', -50)]), ctx,
          revisoes: MbRevisoes.deRegistros([_destino('JOAO', 'cashew:lazer')]),
          pkCategoria: (id, nome, receita) => id ?? mbPkCategoria(nome, receita));
      expect(_t(r, 'p1').categoriaPk, 'cashew:casa');
    });
  });

  group('Pix recebido', () {
    test('devolução não é renda nem gasto', () {
      final r = _mapear([_tx('r1', 'Pix recebido: Pai', 300)], regs: [_decisao('r1', 'devolucao')]);
      expect(r.transacoes, isEmpty);
      expect(r.naoGastoPks, contains('mb:r1'));
    });

    test('reembolso abate o gasto como estorno genérico em Outros', () {
      final t = _t(_mapear([_tx('r1', 'Pix recebido: Maria', 60)], regs: [_decisao('r1', 'reembolso')]), 'r1');
      expect([t.valor, t.receita, t.categoriaNome], [60, false, mbCategoriaOutros]);
    });

    test('reembolso com gasto confirmado abate aquele gasto, na categoria dele', () {
      final r = _mapear(
          [_tx('g1', 'RESTAURANTE', -60, data: '2026-11-08', categoria: 'Eating out'), _tx('r1', 'Pix recebido: Maria', 60)],
          regs: [_decisaoReembolso('r1', 'g1')]);
      final t = _t(r, 'r1');
      expect([t.valor, t.receita, t.categoriaNome], [60, false, 'Alimentação fora']);
      expect(_t(r, 'g1').categoriaNome, 'Alimentação fora');
    });

    test('reembolso vinculado a gasto de pulls anteriores usa a categoria dele; sem o gasto, cai em Outros', () {
      final comGasto = mbMapearPull(_json([_tx('r1', 'Pix recebido: Maria', 60)]), _ctx0,
          revisoes: MbRevisoes.deRegistros([_decisaoReembolso('r1', 'g1')]),
          compras: [MbCompra('mb:g1', 'X', 6000, DateTime(2026, 11, 8), '', 'cat-local')],
          pkCategoria: (id, nome, receita) => id ?? mbPkCategoria(nome, receita));
      expect(comGasto.transacoes.single.categoriaPk, 'cat-local');
      final semGasto = _mapear([_tx('r1', 'Pix recebido: Maria', 60)], regs: [_decisaoReembolso('r1', 'sumiu')]);
      expect(semGasto.transacoes.single.categoriaNome, mbCategoriaOutros);
    });

    test('gasto vinculado não é consumido por estorno automático', () {
      final r = _mapear([
        _tx('g1', 'RESTAURANTE', -60, data: '2026-11-06'),
        _tx('g2', 'RESTAURANTE', -60, data: '2026-11-08', categoria: 'Eating out'),
        _tx('r1', 'Pix recebido: Maria', 60, data: '2026-11-09'),
        _tx('e1', 'RESTAURANTE', 60, data: '2026-11-10'),
      ], regs: [_decisaoReembolso('r1', 'g2')]);
      expect(_t(r, 'r1').categoriaNome, 'Alimentação fora');
      expect(_t(r, 'e1').valor, 60);
      expect(_t(r, 'e1').receita, false); // o estorno ficou com g1, que sobrou
    });

    test('empréstimo e devolução não geram transação nem ajuste', () {
      final r = _mapear([_tx('e1', 'PIX ENVIADO SANTANDER', -800), _tx('d1', 'Pix recebido: Pai', 300)],
          regs: [_decisao('e1', 'emprestimo'), _decisao('d1', 'devolucao')]);
      expect(r.transacoes, isEmpty);
      expect(r.naoGastoPks, {'mb:e1', 'mb:d1'});
    });

    test('renda fica como receita e não vira estorno de compra', () {
      final r = _mapear([_tx('g1', 'MERCADO', -100), _tx('r1', 'Pix recebido: Pai', 100)],
          regs: [_decisao('r1', 'renda')]);
      expect(_t(r, 'r1').receita, true);
      expect(_t(r, 'g1').valor, -100);
    });
  });

  test('o que é anterior ao ciclo não é reclassificado; sem ciclo no servidor também não', () {
    final velho = _tx('p0', 'Pix enviado: Antigo', -10, data: '2026-10-01', categoria: 'Groceries');
    expect(_t(_mapear([velho]), 'p0').categoriaNome, 'Mercado');
    expect(_t(_mapear([_tx('p1', 'Pix enviado: Joao', -5, categoria: 'Groceries')], inicio: null), 'p1').categoriaNome, 'Mercado');
    // Uma decisão já dada continua valendo depois que o ciclo vira.
    final r = _mapear([_tx('e0', 'PIX ENVIADO SANTANDER', -80, data: '2026-10-01')], regs: [_decisao('e0', 'ajuda')]);
    expect(_t(r, 'e0').categoriaNome, mbCategoriaAjuda);
  });

  group('fila', () {
    final ciclo = {
      'revisar': [
        {'id': 'salario', 'tipo': 'salario_nao_detectado', 'dias': 36, 'candidatos': [
          {'tx_id': 'x1', 'data': '2026-11-01', 'descricao': 'TED', 'valor': 6000}]},
        {'id': 'tx:r1', 'tipo': 'pix_recebido', 'tx_id': 'r1', 'data': '2026-11-10', 'descricao': 'Pix recebido', 'valor': 90},
        {'id': 'tx:p1', 'tipo': 'pix_enviado', 'tx_id': 'p1', 'data': '2026-11-09', 'descricao': 'Pix enviado', 'valor': 50, 'destinatario': 'JOAO'},
        {'id': 'tx:p2', 'tipo': 'pix_enviado', 'tx_id': 'p2', 'data': '2026-11-08', 'descricao': 'Pix enviado', 'valor': 70, 'destinatario': 'JOAO'},
        {'id': 'lixo'},
      ],
    };

    test('lê os itens do ciclo e ignora os malformados; Worker antigo não manda fila', () {
      final itens = mbItensRevisar(ciclo);
      expect(itens.map((i) => i.tipo), ['salario_nao_detectado', 'pix_recebido', 'pix_enviado', 'pix_enviado']);
      expect(itens.first.candidatos.single.txId, 'x1');
      expect(itens[1].respostas, ['devolucao', 'reembolso', 'renda']);
      expect(mbItensRevisar({'inicio': '2026-11-05'}), isEmpty);
      expect(mbItensRevisar(null), isEmpty);
    });

    test('o respondido some da fila, e a memória do destinatário tira os outros Pix da mesma pessoa', () {
      final itens = mbItensRevisar(ciclo);
      final regs = MbRevisoes.deRegistros([
        _decisao('r1', 'renda'),
        _decisao('p1', 'categoria', categoriaId: 'cashew:lazer'),
        _destino('JOAO', 'cashew:lazer'),
      ]);
      expect(mbFilaVisivel(itens, regs).map((i) => i.id), ['salario']);
      expect(mbFilaVisivel(itens, const MbRevisoes()).length, 4);
    });
  });

  test('definirSalario manda PUT /api/config com salario_id', () async {
    late http.Request req;
    final cliente = MbCliente(
        base: 'https://x.test',
        token: 't',
        cliente: MockClient((r) async {
          req = r;
          return http.Response('{"ok":true}', 200);
        }));
    await cliente.definirSalario('x1');
    expect([req.method, req.url.path], ['PUT', '/api/config']);
    expect(jsonDecode(req.body), {'salario_id': 'x1'});
    expect(req.headers['Authorization'], 'Bearer t');
  });

  group('sincronização (Drift)', () {
    late _ClienteRevisao cliente;

    setUpAll(() {
      open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
    });

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      database = FinanceDatabase(NativeDatabase.memory());
      SharedPreferences.setMockInitialValues({'mbNotifCursor': 'x'});
      cliente = _ClienteRevisao();
      meuBancoSincronizando.value = false;
    });

    tearDown(() => database.close());

    Future<void> sync() async =>
        expect(await sincronizarMeuBanco(clienteParaTeste: cliente), true, reason: meuBancoUltimoErro.value);

    Future<Transaction> tx(String pk) =>
        (database.select(database.transactions)..where((t) => t.transactionPk.equals(pk))).getSingle();

    test('responder grava a decisão, a memória e remapeia a transação sem gerar ajuste', () async {
      cliente.transacoes = [_tx('p1', 'Pix enviado: Joao Silva', -50, data: _hoje())];
      cliente.ciclo = {'inicio': _hoje(), 'revisar': [
        {'id': 'tx:p1', 'tipo': 'pix_enviado', 'tx_id': 'p1', 'data': _hoje(), 'descricao': 'Pix enviado: Joao Silva', 'valor': 50, 'destinatario': 'JOAO SILVA'}]};
      await sync(); // a primeira sincronização é carga completa; as seguintes são incrementais
      expect((await tx('mb:p1')).categoryFk, 'mb:cat:d:$mbCategoriaAClassificar');
      expect(meuBancoRevisar.value.map((i) => i.txId), ['p1']);

      await database.into(database.categories).insert(CategoriesCompanion.insert(
          categoryPk: const Value('lazer'), name: 'Lazer', order: 0, dateTimeModified: Value(DateTime.now())));
      cliente.enviados.clear();
      final item = meuBancoRevisar.value.single;
      await mbResponderRevisao(item, 'categoria', categoriaPk: 'lazer', clienteParaTeste: cliente);

      expect((await tx('mb:p1')).categoryFk, 'lazer');
      expect(meuBancoRevisar.value, isEmpty); // some do cartão
      final enviados = cliente.enviados.where((r) => r.tabela == 'revisoes').toList();
      expect(enviados.map((r) => r.id), containsAll(['tx:p1', 'dest:JOAO SILVA']));
      expect(enviados.firstWhere((r) => r.id == 'tx:p1').dados!['categoria_id'], 'cashew:lazer');
      expect(cliente.enviados.where((r) => r.tabela == 'ajustes'), isEmpty);
      expect((await mbLerAplicado())['mb:p1'], 'lazer');
      expect(cliente.pullsCompletos, greaterThan(1)); // decisão local força o re-pull completo
    });

    test('botão da notificação responde a fila; repetir ou item que saiu da fila não faz nada', () async {
      final item = {'id': 'tx:e1', 'tipo': 'envio_santander', 'tx_id': 'e1', 'data': _hoje(), 'descricao': 'PIX ENVIADO SANTANDER', 'valor': 800};
      cliente.transacoes = [_tx('e1', 'PIX ENVIADO SANTANDER', -800, data: _hoje())];
      cliente.ciclo = {'inicio': _hoje(), 'revisar': [item]};
      await sync();
      cliente.enviados.clear();
      final alerta = {'chave': 'revisar:tx:e1', 'titulo': 'x', 'corpo': 'y', 'item': item};

      expect([for (final a in mbAcoesDoAlerta(alerta)) a.id], ['emprestimo', 'investimento', 'ajuda']);
      final payload = mbPayloadAlerta(alerta);
      expect(payload.startsWith(mbPrefixoPayload), true);

      expect(await mbResponderPelaNotificacao(payload, null, clienteParaTeste: cliente), false); // toque simples
      expect(cliente.enviados, isEmpty);
      expect(await mbResponderPelaNotificacao(payload, 'investimento', clienteParaTeste: cliente), true);
      expect(cliente.enviados.firstWhere((r) => r.id == 'tx:e1').dados!['resposta'], 'investimento');
      expect(meuBancoRevisar.value, isEmpty);

      cliente.enviados.clear();
      expect(await mbResponderPelaNotificacao(payload, 'ajuda', clienteParaTeste: cliente), false); // já respondido
      expect(cliente.enviados, isEmpty);
    });

    test('reembolso na notificação abre o app em vez de responder; Pix enviado e salário não têm botões', () {
      final pix = {'id': 'tx:r1', 'tipo': 'pix_recebido', 'tx_id': 'r1', 'valor': 60};
      final acoes = mbAcoesDoAlerta({'chave': 'revisar:tx:r1', 'item': pix});
      expect([for (final a in acoes) [a.id, a.showsUserInterface]],
          [['devolucao', false], ['reembolso', true], ['renda', false]]);
      expect(mbAcoesDoAlerta({'chave': 'revisar:tx:p1', 'item': {'id': 'tx:p1', 'tipo': 'pix_enviado', 'tx_id': 'p1', 'valor': 5}}), isEmpty);
      expect(mbAcoesDoAlerta({'chave': 'revisar:salario:2026-11'}), isEmpty);
    });

    test('decisão vinda de outro aparelho remapeia no pull incremental seguinte', () async {
      cliente.transacoes = [_tx('e1', 'PIX ENVIADO SANTANDER', -800, data: _hoje())];
      cliente.ciclo = {'inicio': _hoje()};
      await sync();
      expect((await database.select(database.transactions).get()).where((t) => t.transactionPk == 'mb:e1'), isEmpty);

      cliente.servidor.add(Registro('revisoes', 'tx:e1',
          {'tipo': 'decisao', 'tx_id': 'e1', 'resposta': 'ajuda'}, '2099-01-01T00:00:00.000Z', null));
      await sync();
      final t = await tx('mb:e1');
      expect([t.amount, t.categoryFk], [-800, 'mb:cat:d:$mbCategoriaAjuda']);
    });

    test('reembolso com gasto confirmado grava o vínculo, abate o gasto e não gera ajuste', () async {
      cliente.transacoes = [
        _tx('g1', 'RESTAURANTE', -60, data: _hoje(), categoria: 'Eating out'),
        _tx('r1', 'Pix recebido: Maria', 60, data: _hoje()),
      ];
      cliente.ciclo = {'inicio': _hoje(), 'revisar': [
        {'id': 'tx:r1', 'tipo': 'pix_recebido', 'tx_id': 'r1', 'data': _hoje(), 'descricao': 'Pix recebido: Maria', 'valor': 60}]};
      await sync();
      expect((await tx('mb:r1')).categoryFk, isNot('mb:cat:d:Alimentação fora')); // ainda renda
      cliente.enviados.clear();
      await mbResponderRevisao(meuBancoRevisar.value.single, 'reembolso', reembolsoDe: 'g1', clienteParaTeste: cliente);

      final r1 = await tx('mb:r1'), g1 = await tx('mb:g1');
      expect([r1.income, r1.amount, r1.categoryFk], [false, 60, g1.categoryFk]);
      final d = cliente.enviados.lastWhere((r) => r.id == 'tx:r1').dados!;
      expect([d['resposta'], d['reembolso_de']], ['reembolso', 'g1']);
      expect(cliente.enviados.where((r) => r.tabela == 'ajustes'), isEmpty);
      expect((await mbLerAplicado())['mb:r1'], g1.categoryFk);
    });

    test('vínculo vindo de outro aparelho remapeia o reembolso no pull seguinte', () async {
      cliente.transacoes = [
        _tx('g1', 'RESTAURANTE', -60, data: _hoje(), categoria: 'Eating out'),
        _tx('r1', 'Pix recebido: Maria', 60, data: _hoje()),
      ];
      cliente.ciclo = {'inicio': _hoje()};
      await sync();
      cliente.servidor.add(Registro('revisoes', 'tx:r1',
          {'tipo': 'decisao', 'tx_id': 'r1', 'resposta': 'reembolso', 'reembolso_de': 'g1'},
          '2099-01-01T00:00:00.000Z', null));
      await sync();
      expect((await tx('mb:r1')).categoryFk, (await tx('mb:g1')).categoryFk);
    });

    test('reembolso sem escolher gasto continua em Outros', () async {
      cliente.transacoes = [_tx('r1', 'Pix recebido: Maria', 60, data: _hoje())];
      cliente.ciclo = {'inicio': _hoje(), 'revisar': [
        {'id': 'tx:r1', 'tipo': 'pix_recebido', 'tx_id': 'r1', 'data': _hoje(), 'descricao': 'Pix recebido: Maria', 'valor': 60}]};
      await sync();
      await mbResponderRevisao(meuBancoRevisar.value.single, 'reembolso', clienteParaTeste: cliente);
      expect((await tx('mb:r1')).categoryFk, 'mb:cat:d:$mbCategoriaOutros');
      expect(cliente.enviados.lastWhere((r) => r.id == 'tx:r1').dados!.containsKey('reembolso_de'), false);
    });

    test('sugestões do banco: gastos recentes do mesmo valor', () async {
      cliente.transacoes = [
        _tx('g1', 'RESTAURANTE', -60, data: _hoje()),
        _tx('g2', 'PADARIA', -60, data: _hoje()),
        _tx('r1', 'Pix recebido: Maria', 60, data: _hoje()),
      ];
      cliente.ciclo = {'inicio': _hoje()};
      await sync();
      final item = MbItemRevisao('tx:r1', 'pix_recebido', txId: 'r1', data: _hoje(), valor: 60);
      final s = await mbSugestoesDoItem(item);
      expect([for (final x in s) x.gasto.pk].toSet(), {'mb:g1', 'mb:g2'});
    });

    test('empréstimos em aberto: respondidos aparecem e a devolução abate', () async {
      cliente.transacoes = [
        _tx('e1', 'PIX ENVIADO SANTANDER', -800, data: _hoje()),
        _tx('d1', 'Pix recebido: Pai', 300, data: _hoje()),
      ];
      cliente.ciclo = {'inicio': _hoje(), 'revisar': [
        {'id': 'tx:e1', 'tipo': 'envio_santander', 'tx_id': 'e1', 'data': _hoje(), 'descricao': 'PIX ENVIADO SANTANDER', 'valor': 800},
        {'id': 'tx:d1', 'tipo': 'pix_recebido', 'tx_id': 'd1', 'data': _hoje(), 'descricao': 'Pix recebido: Pai', 'valor': 300}]};
      await sync();
      expect(meuBancoEmprestimos.value.abertos, isEmpty);
      await mbResponderRevisao(meuBancoRevisar.value.firstWhere((i) => i.txId == 'e1'), 'emprestimo', clienteParaTeste: cliente);
      expect(meuBancoEmprestimos.value.devido, 800);
      await mbResponderRevisao(meuBancoRevisar.value.single, 'devolucao', clienteParaTeste: cliente);
      expect([meuBancoEmprestimos.value.devido, meuBancoEmprestimos.value.abertos.single.original], [500, 800]);
      expect((await database.select(database.transactions).get()).where((t) => t.transactionPk.startsWith('mb:e1') || t.transactionPk.startsWith('mb:d1')), isEmpty);
      expect(cliente.enviados.where((r) => r.tabela == 'ajustes'), isEmpty);
    });

    test('Empréstimo respondido não conta e o registro fica para o PR 4 ler', () async {
      cliente.transacoes = [_tx('e1', 'PIX ENVIADO SANTANDER', -800, data: _hoje())];
      cliente.ciclo = {'inicio': _hoje(), 'revisar': [
        {'id': 'tx:e1', 'tipo': 'envio_santander', 'tx_id': 'e1', 'data': _hoje(), 'descricao': 'PIX ENVIADO SANTANDER', 'valor': 800}]};
      await sync();
      await mbResponderRevisao(meuBancoRevisar.value.single, 'emprestimo', clienteParaTeste: cliente);
      expect((await database.select(database.transactions).get()).where((t) => t.transactionPk == 'mb:e1'), isEmpty);
      final d = cliente.enviados.lastWhere((r) => r.id == 'tx:e1').dados!;
      expect([d['resposta'], d['valor'], d['data']], ['emprestimo', 800, _hoje()]);
    });
  });
}

String _hoje() => DateTime.now().toIso8601String().substring(0, 10);

class _ClienteRevisao extends MbCliente {
  _ClienteRevisao() : super(base: 'https://teste');
  final List<Registro> servidor = [];
  final List<Registro> enviados = [];
  List<Map<String, dynamic>> transacoes = [];
  Map<String, dynamic> ciclo = {};
  int pullsCompletos = 0;

  @override
  Future<Map<String, dynamic>> puxar(String? desde) async {
    if (desde == null) pullsCompletos++;
    return {
      'agora': DateTime.now().toUtc().toIso8601String(),
      'registros': [for (final r in servidor) r.toJson()],
      'contas': [{'id': 'cc', 'type': 'BANK', 'name': 'Conta Inter'}],
      // Como o Worker: o pull incremental não repete transações antigas.
      'transacoes': desde == null ? transacoes : [],
      'pendentes': [],
      'ciclo': ciclo,
    };
  }

  @override
  Future<({int aceitos, List<({int indice, String motivo})> rejeitados})> enviar(
      List<Registro> lote) async {
    enviados.addAll(lote);
    return (aceitos: lote.length, rejeitados: <({int indice, String motivo})>[]);
  }
}
