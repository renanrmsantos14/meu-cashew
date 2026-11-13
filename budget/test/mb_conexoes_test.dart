import 'package:budget/pages/meuBancoConexoes.dart';
import 'package:budget/struct/mbSync/conexoes.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/temas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MbConexao _con(String id, String banco, String? status,
        {List<Map<String, dynamic>> contas = const []}) =>
    MbConexao.deJson({
      'id': id,
      'banco': banco,
      'status': status,
      'precisaReconectar': status == 'LOGIN_ERROR' || status == 'WAITING_USER_INPUT',
      'atualizado': '2026-11-12T12:00:00.000Z',
      'contas': contas,
    });

Future<void> _monta(WidgetTester t, Widget filho) async {
  appStateSettings = {
    'materialYou': false,
    'accentSystemColor': false,
    'batterySaver': false,
    'increaseTextContrast': false,
    'appAnimations': 0,
  };
  await t.pumpWidget(MaterialApp(
    theme: temaFlutter(temaPorId('padrao-claro')),
    home: Scaffold(body: SingleChildScrollView(child: filho)),
  ));
  await t.pump();
}

void main() {
  test('MbConexao lê o JSON do servidor e traduz o status', () {
    final c = _con('a', 'Banco Inter', 'LOGIN_ERROR', contas: [
      {'type': 'BANK', 'subtype': 'CHECKING_ACCOUNT', 'name': 'Conta Inter', 'balance': 10.5},
      {'type': 'CREDIT', 'name': 'Cartão Gold', 'balance': 600},
    ]);
    expect(c.sigla, 'BA'); // mesma regra da Início
    expect(c.situacao.situacao, MbSituacao.reconectar);
    expect(c.situacao.rotulo, 'Senha mudou');
    expect(c.contas.first.tipo, 'Conta corrente');
    expect(c.contas.last.cartao, isTrue);
    expect(_con('b', 'Nubank', 'UPDATED').situacao.situacao, MbSituacao.emDia);
    expect(_con('c', 'Itaú', null).situacao.rotulo, 'Aguardando');
    expect(_con('d', 'X', 'UPDATING').situacao.situacao, MbSituacao.atualizando);
    expect(_con('e', 'Nubank', 'UPDATED').sigla, 'NU');
    expect(_con('f', 'X', 'OUTDATED').situacao.rotulo, 'Falha temporária');
  });

  testWidgets('lista conexões com status, contas e ações', (t) async {
    await _monta(
      t,
      ContasConectadas(
        carregar: () async => [
          _con('a', 'Nubank', 'UPDATED', contas: [
            {'type': 'BANK', 'subtype': 'CHECKING_ACCOUNT', 'name': 'Conta Nubank', 'balance': 3102.9},
          ]),
          _con('b', 'Banco Inter', 'LOGIN_ERROR'),
        ],
        remover: (_) async {},
        conectar: (c, {itemId}) async {},
      ),
    );
    expect(find.text('Nubank'), findsOneWidget);
    expect(find.text('Em dia'), findsOneWidget);
    expect(find.text('Senha mudou'), findsOneWidget);
    expect(find.text('Conta Nubank · Conta corrente'), findsOneWidget);
    expect(find.text('R\$ 3.102,90'), findsOneWidget);
    expect(find.text('Reconectar'), findsOneWidget);
    expect(find.text('Atualizar login'), findsOneWidget);
    expect(find.text('Conectar banco'), findsOneWidget);
  });

  testWidgets('reconectar abre o Connect do item certo e conectar abre sem item',
      (t) async {
    final chamadas = <String?>[];
    await _monta(
      t,
      ContasConectadas(
        carregar: () async => [_con('b', 'Banco Inter', 'LOGIN_ERROR')],
        remover: (_) async {},
        conectar: (c, {itemId}) async => chamadas.add(itemId),
      ),
    );
    await t.tap(find.text('Reconectar'));
    await t.pump();
    await t.tap(find.text('Conectar banco'));
    await t.pump();
    expect(chamadas, ['b', null]);
  });

  testWidgets('sem conexões mostra estado vazio; erro mostra mensagem e tentar de novo',
      (t) async {
    await _monta(
        t,
        ContasConectadas(
            carregar: () async => const [],
            remover: (_) async {},
            conectar: (c, {itemId}) async {}));
    expect(find.text('Nenhum banco conectado ainda.'), findsOneWidget);

    var tentativas = 0;
    await _monta(
        t,
        ContasConectadas(
            key: const ValueKey('erro'),
            carregar: () async {
              tentativas++;
              throw 'Sem internet';
            },
            remover: (_) async {},
            conectar: (c, {itemId}) async {}));
    expect(find.text('Sem internet'), findsOneWidget);
    await t.tap(find.text('Tentar de novo'));
    await t.pump();
    expect(tentativas, 2);
  });

  testWidgets('remover pede confirmação; cancelar não remove, confirmar remove', (t) async {
    final removidos = <String>[];
    await _monta(
      t,
      ContasConectadas(
        carregar: () async => [
          if (!removidos.contains('a')) _con('a', 'Nubank', 'UPDATED')
        ],
        remover: (id) async => removidos.add(id),
        conectar: (c, {itemId}) async {},
        avisar: (_) {},
      ),
    );
    await t.tap(find.text('Remover'));
    await t.pumpAndSettle();
    expect(find.text('Remover Nubank?'), findsOneWidget);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(removidos, isEmpty);

    await t.tap(find.text('Remover'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remover').last);
    await t.pumpAndSettle();
    expect(removidos, ['a']);
    expect(find.text('Nubank'), findsNothing);
  });
}
