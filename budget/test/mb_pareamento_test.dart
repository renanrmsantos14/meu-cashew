import 'package:budget/struct/mbSync/pareamento.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _t = 'mb_${'A' * 43}';

Uri _link({String esquema = 'meubanco', String host = 'parear', String u = 'https://exemplo.test', String? t}) =>
    Uri(scheme: esquema, host: host, queryParameters: {'u': u, 't': t ?? _t});

void main() {
  test('link válido', () {
    final p = mbLerLinkPareamento(_link())!;
    expect(p.base, 'https://exemplo.test');
    expect(p.token, _t);
  });
  test('esquema errado', () => expect(mbLerLinkPareamento(_link(esquema: 'https')), isNull));
  test('host errado', () => expect(mbLerLinkPareamento(_link(host: 'outro')), isNull));
  test('token curto', () => expect(mbLerLinkPareamento(_link(t: 'mb_AAAA')), isNull));
  test('barra final removida', () {
    expect(mbLerLinkPareamento(_link(u: 'https://exemplo.test/'))!.base, 'https://exemplo.test');
  });
  test('origem: http recusado em release, aceito local em debug', () {
    expect(mbOrigemPermitida('http://exemplo.test', debug: false), isFalse);
    expect(mbOrigemPermitida('http://localhost', debug: false), isFalse);
    expect(mbOrigemPermitida('http://localhost', debug: true), isTrue);
    expect(mbOrigemPermitida('http://10.0.2.2', debug: true), isTrue);
    expect(mbOrigemPermitida('http://exemplo.test', debug: true), isFalse);
    expect(mbOrigemPermitida('https://exemplo.test/caminho', debug: false), isFalse);
    expect(mbOrigemPermitida('https://exemplo.test', debug: false), isTrue);
  });

  group('mbPedirToken', () {
    MockClient resp(int status, Object corpo, [void Function(http.Request)? ver]) =>
        MockClient((r) async {
          ver?.call(r);
          return http.Response(jsonEncode(corpo), status);
        });

    test('troca a senha por token', () async {
      final p = await mbPedirToken('https://exemplo.test', 's3nha',
          cliente: resp(201, {'token': _t}, (r) {
        expect(r.url.toString(), 'https://exemplo.test/api/app/parear');
        expect(jsonDecode(r.body), {'senha': 's3nha', 'nome': 'RenanCash'});
      }));
      expect(p.base, 'https://exemplo.test');
      expect(p.token, _t);
    });
    test('senha errada vira mensagem', () {
      expect(mbPedirToken('https://exemplo.test', 'x', cliente: resp(401, {'erro': 'Senha incorreta'})),
          throwsA('Senha incorreta.'));
    });
    test('limite de tentativas repassa a mensagem do servidor', () {
      expect(
          mbPedirToken('https://exemplo.test', 'x',
              cliente: resp(429, {'erro': 'Muitas tentativas. Espere 1 minuto.'})),
          throwsA('Muitas tentativas. Espere 1 minuto.'));
    });
    test('token inválido na resposta', () {
      expect(mbPedirToken('https://exemplo.test', 'x', cliente: resp(201, {'token': 'mb_curto'})),
          throwsA('Resposta inesperada do Meu Banco.'));
    });
    test('falha de rede', () {
      expect(
          mbPedirToken('https://exemplo.test', 'x',
              cliente: MockClient((_) async => throw http.ClientException('off'))),
          throwsA(startsWith('Não foi possível falar')));
    });
  });
}
