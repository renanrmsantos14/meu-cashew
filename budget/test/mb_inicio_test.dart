import 'package:budget/pages/homePage/inicioEditorial.dart';
import 'package:budget/struct/editorial.dart';
import 'package:budget/struct/mbSync/estadoInicio.dart';
import 'package:budget/struct/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _agora = DateTime(2026, 11, 9, 15, 0);

ModeloInicio _montar({List<Map<String, dynamic>>? contas, Map<String, dynamic>? faturas, String nome = 'Renan'}) =>
    montarModeloInicio(
      ciclo: {
        'inicio': '2026-10-26',
        'fim': '2026-11-25',
        'consumido': 1300.0,
        'limite': 5000.0,
        'percentual': 26.0,
        'diasRestantes': 16,
        'por_dia': [
          for (var i = 0; i < 31; i++)
            {'data': DateTime(2026, 10, 26 + i).toIso8601String().substring(0, 10), 'valor': i.toDouble()}
        ],
      },
      contas: contas ??
          [
            {'id': 'a', 'type': 'BANK', 'subtype': 'CHECKING_ACCOUNT', 'name': 'Conta Inter', 'bank': 'Inter', 'balance': 1000.5},
            {'id': 'b', 'type': 'BANK', 'subtype': 'SAVINGS_ACCOUNT', 'name': 'Poup 1', 'bank': 'Inter', 'balance': 500.0},
            {'id': 'c', 'type': 'BANK', 'subtype': 'SAVINGS_ACCOUNT', 'name': 'Poup 2', 'bank': 'Santander', 'balance': 100.0},
            {
              'id': 'd', 'type': 'CREDIT', 'name': 'Cartão Gold ·1950', 'bank': 'Santander', 'balance': 607.65,
              'credit_limit': 600.0, 'closing_date': '2026-10-12', 'due_date': '2026-11-05',
            },
          ],
      faturas: faturas ?? {},
      sincronizadoEm: _agora.subtract(const Duration(minutes: 12)).toUtc().toIso8601String(),
      ultimas: [
        (nome: 'Padaria', categoria: 'Alimentação', data: DateTime(2026, 11, 9), valor: -12.0, receita: false),
        (nome: 'Salário', categoria: 'Renda', data: DateTime(2026, 11, 8), valor: 100.0, receita: true),
      ],
      nome: nome,
      agora: _agora,
    );

void main() {
  test('disponível soma só as contas BANK e agrupa poupanças', () {
    final m = _montar();
    expect(m.disponivel, 1600.5);
    expect(m.contas.map((c) => c.nome), ['Inter', 'Poupanças']);
    expect(m.contas.last.tipo, '2 contas');
    expect(m.contas.last.saldo, 600.0);
    expect(m.origemDisponivel, 'Inter e poupanças · há 12 min');
  });

  test('cartão: dias para fechar, vencimento, final e percentual', () {
    final c = _montar().cartoes.single;
    expect(c.nome, 'Cartão Gold');
    expect(c.final4, '1950');
    expect(c.diasFecha, 3);
    expect(c.vence, '05 dez');
    expect(c.pct, closeTo(101.275, .001));
  });

  test('fatura aberta substitui o saldo', () {
    final c = _montar(faturas: {
      'd': {'open_bill': {'total_amount': 300.0, 'due_date': '2026-12-05'}}
    }).cartoes.single;
    expect(c.fatura, 300.0);
    expect(c.pct, 50.0);
  });

  test('ciclo, saudação, índice de hoje e últimas', () {
    final m = _montar();
    expect(m.ciclo, 'Ciclo 26 out – 25 nov');
    expect(m.saudacao, 'Olá, Renan');
    expect(m.indiceHoje, 14);
    expect(m.ultimas.map((u) => u.quando), ['hoje', 'ontem']);
    expect(_montar(nome: '  ').saudacao, 'Olá');
  });

  test('formatadores', () {
    expect(brl(2417.16), 'R\$ 2.417,16');
    expect(quandoRelativo(DateTime(2026, 11, 9, 1), _agora), 'hoje');
    expect(quandoRelativo(DateTime(2026, 11, 8, 23), _agora), 'ontem');
    expect(quandoRelativo(DateTime(2026, 11, 5), _agora), '05 nov');
    expect(haQuanto(DateTime(2026, 11, 9, 14, 48), _agora), 'há 12 min');
    expect(haQuanto(DateTime(2026, 11, 9, 13), _agora), 'há 2 h');
  });

  testWidgets('InicioEditorial mostra Disponível agora e CONTAS', (t) async {
    appStateSettings = {
      'materialYou': false,
      'accentSystemColor': false,
      'batterySaver': false,
      'increaseTextContrast': false,
      'forceFullDarkBackground': false,
    };
    await t.pumpWidget(MaterialApp(
      theme: temaEditorial(Brightness.light),
      home: Scaffold(body: InicioEditorial.comModelo(_montar())),
    ));
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Disponível agora'), findsOneWidget);
    expect(find.text('CONTAS'), findsOneWidget);
    expect(find.text('Olá, Renan'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('sem dados mostra estado vazio em vez de R\$ 0,00', (t) async {
    appStateSettings = {
      'materialYou': false,
      'accentSystemColor': false,
      'batterySaver': false,
      'increaseTextContrast': false,
      'forceFullDarkBackground': false,
    };
    final vazio = montarModeloInicio(
        ciclo: {}, contas: [], faturas: {}, sincronizadoEm: null, ultimas: [], nome: '', agora: _agora);
    await t.pumpWidget(MaterialApp(
      theme: temaEditorial(Brightness.light),
      home: Scaffold(body: InicioEditorial.comModelo(vazio)),
    ));
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Ainda sem dados. Toque em Atualizar.'), findsOneWidget);
    expect(find.text('Disponível agora'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
