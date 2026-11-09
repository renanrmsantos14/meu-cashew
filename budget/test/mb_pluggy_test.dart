import 'package:budget/struct/mbSync/pluggy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = '0b3e2f4a-1c2d-4e5f-8a9b-0c1d2e3f4a5b';
  test('aceita os três formatos', () {
    expect(mbItemIdDoSucesso({'item': {'id': id}}), id);
    expect(mbItemIdDoSucesso({'itemId': id}), id);
    expect(mbItemIdDoSucesso({'data': {'item': {'id': id}}}), id);
  });
  test('recusa inválido e null', () {
    expect(mbItemIdDoSucesso({'item': {'id': 'abc'}}), isNull);
    expect(mbItemIdDoSucesso({'itemId': 123}), isNull);
    expect(mbItemIdDoSucesso('texto'), isNull);
    expect(mbItemIdDoSucesso(null), isNull);
  });
  test('cai para o próximo formato quando o primeiro é inválido', () {
    expect(mbItemIdDoSucesso({'item': {'id': 'x'}, 'itemId': id}), id);
  });
}
