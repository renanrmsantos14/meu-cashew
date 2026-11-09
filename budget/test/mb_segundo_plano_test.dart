import 'dart:convert';

import 'package:budget/struct/mbSync/cliente.dart';
import 'package:budget/struct/mbSync/segundoPlano.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

MbCliente _cliente(Future<http.Response> Function(http.Request) f) =>
    MbCliente(base: 'https://x.test', token: 't', cliente: MockClient(f));

void main() {
  test('mbIdNotificacao é estável e positivo', () {
    expect(mbIdNotificacao('orcamento:80'), mbIdNotificacao('orcamento:80'));
    expect(mbIdNotificacao('a'), isNot(mbIdNotificacao('b')));
    expect(mbIdNotificacao('qualquer chave longa com acentos ção'),
        inInclusiveRange(0, 0x7fffffff));
    expect(mbIdNotificacao('a'), 0x7fffffff & 0xe40c292c);
  });

  test('mostra as notificações, grava o cursor e atualiza o widget', () async {
    String? desdeEnviado;
    final cliente = _cliente((req) async {
      desdeEnviado = req.url.queryParameters['desde'];
      return http.Response(
          jsonEncode({
            'cursor': '2026-11-09T12:00:00.000Z',
            'notificacoes': [
              {'chave': 'a', 'titulo': 'T1', 'corpo': 'C1', 'criada': 'x'},
              {'chave': 'b', 'titulo': 'T2', 'corpo': 'C2', 'criada': 'y'},
            ],
            'resumo': {'disponivel': 10, 'consumido': 5},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final mostradas = <String>[];
    String? cursor = '2026-11-08T00:00:00.000Z';
    Map<String, dynamic>? widget;
    final n = await mbConferirAlertas(
      cliente: cliente,
      mostrar: (id, t, c) async => mostradas.add('$t|$c'),
      lerCursor: () async => cursor,
      gravarCursor: (c) async => cursor = c,
      salvarWidget: (r) async => widget = r,
    );
    expect(n, 2);
    expect(mostradas, ['T1|C1', 'T2|C2']);
    expect(desdeEnviado, '2026-11-08T00:00:00.000Z');
    expect(cursor, '2026-11-09T12:00:00.000Z');
    expect(widget?['disponivel'], 10);
  });

  test('em erro de rede não mexe no cursor', () async {
    final cliente = _cliente((req) async => throw http.ClientException('off'));
    var gravou = false;
    final n = await mbConferirAlertas(
      cliente: cliente,
      mostrar: (id, t, c) async {},
      lerCursor: () async => 'c0',
      gravarCursor: (c) async => gravou = true,
      salvarWidget: (r) async {},
    );
    expect(n, 0);
    expect(gravou, false);
  });
}
