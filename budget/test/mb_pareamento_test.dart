import 'package:budget/struct/mbSync/pareamento.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
