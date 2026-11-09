import 'package:budget/struct/atualizador.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extrai build e versão da tag', () {
    expect(atualizadorBuildDaTag('v5.4.3+417'), 417);
    expect(atualizadorVersaoDaTag('v5.4.3+417'), '5.4.3');
    expect(atualizadorBuildDaTag('v5.4.3'), isNull);
    expect(atualizadorBuildDaTag('lixo'), isNull);
  });

  test('compara só o buildNumber', () {
    expect(atualizadorTagEhMaisNova('v5.4.3+417', 416), isTrue);
    expect(atualizadorTagEhMaisNova('v5.4.3+417', 417), isFalse);
    expect(atualizadorTagEhMaisNova('v5.4.3+9', 417), isFalse);
    expect(atualizadorTagEhMaisNova('v5.4.3+1000', 999), isTrue);
    expect(atualizadorTagEhMaisNova('invalida', 1), isFalse);
  });
}
