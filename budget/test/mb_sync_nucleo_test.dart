import 'package:budget/struct/mbSync/detectar.dart';
import 'package:budget/struct/mbSync/registro.dart';
import 'package:flutter_test/flutter_test.dart';

const _agora = '2026-11-09T12:00:00.000Z';

Espelho _esp(String tabela, String id, Map<String, dynamic>? dados,
        String updatedAt,
        {String? deletedAt, Map<String, dynamic>? projecao, bool pendente = false}) =>
    Espelho(Registro(tabela, id, dados, updatedAt, deletedAt), projecao,
        pendente, null);

void main() {
  test('isoMs trunca microssegundos para milissegundos', () {
    expect(isoMs(DateTime.utc(2026, 1, 2, 3, 4, 5, 123, 456)),
        '2026-01-02T03:04:05.123Z');
  });

  test('jsonCanonico independe da ordem das chaves', () {
    expect(jsonCanonico({'b': 1, 'a': {'d': 1, 'c': 2}}),
        jsonCanonico({'a': {'c': 2, 'd': 1}, 'b': 1}));
  });

  test('vence: maior vence, igual não, null vence', () {
    final r = Registro('metas', '1', {}, '2026-01-02T00:00:00.000Z', null);
    expect(vence(r, '2026-01-01T00:00:00.000Z'), isTrue);
    expect(vence(r, '2026-01-02T00:00:00.000Z'), isFalse);
    expect(vence(r, null), isTrue);
  });

  test('objeto novo vai com editadoEm ou mbNuncaEditado', () {
    final a = detectarMudancasLocais(
        espelho: {},
        atuais: {
          'metas/1': Projetado('metas', '1', {'nome': 'x'}, '2026-05-01T00:00:00.000Z')
        },
        agora: _agora);
    expect(a.single.registro.updatedAt, '2026-05-01T00:00:00.000Z');
    final b = detectarMudancasLocais(
        espelho: {},
        atuais: {'metas/1': Projetado('metas', '1', {'nome': 'x'}, null)},
        agora: _agora);
    expect(b.single.registro.updatedAt, mbNuncaEditado);
  });

  test('projeção igual ao espelho não gera nada', () {
    final e = _esp('metas', '1', {'nome': 'x'}, '2026-05-01T00:00:00.000Z',
        projecao: {'nome': 'x'});
    expect(
        detectarMudancasLocais(
            espelho: {'metas/1': e},
            atuais: {'metas/1': Projetado('metas', '1', {'nome': 'x'}, null)},
            agora: _agora),
        isEmpty);
  });

  test('mescla preserva chave extra e remove campo null', () {
    final e = _esp('metas', '1', {'nome': 'x', 'pluggy': 'p', 'obs': 'o'},
        '2026-05-01T00:00:00.000Z',
        projecao: {'nome': 'x', 'obs': 'o'});
    final m = detectarMudancasLocais(
        espelho: {'metas/1': e},
        atuais: {
          'metas/1': Projetado('metas', '1', {'nome': 'y', 'obs': null},
              '2026-06-01T00:00:00.000Z')
        },
        agora: _agora);
    expect(m.single.registro.dados, {'nome': 'y', 'pluggy': 'p'});
    expect(m.single.registro.updatedAt, '2026-06-01T00:00:00.000Z');
  });

  test('editadoEm mais antigo que o espelho vira agora', () {
    final e = _esp('metas', '1', {'nome': 'x'}, '2026-05-01T00:00:00.000Z',
        projecao: {'nome': 'x'});
    final m = detectarMudancasLocais(
        espelho: {'metas/1': e},
        atuais: {
          'metas/1': Projetado('metas', '1', {'nome': 'y'}, '2026-04-01T00:00:00.000Z')
        },
        agora: _agora);
    expect(m.single.registro.updatedAt, _agora);
  });

  test('espelho com projeção sem objeto local vira tombstone', () {
    final e = _esp('metas', '1', {'nome': 'x'}, '2026-05-01T00:00:00.000Z',
        projecao: {'nome': 'x'});
    final m = detectarMudancasLocais(
        espelho: {'metas/1': e}, atuais: {}, agora: _agora);
    expect(m.single.registro.dados, isNull);
    expect(m.single.registro.deletedAt, _agora);
  });

  test('ajustes nunca vira tombstone; mudança volta com projecao null', () {
    final e = _esp('ajustes', 'a', {'v': 1}, '2026-05-01T00:00:00.000Z',
        projecao: {'v': 1});
    expect(
        detectarMudancasLocais(
            espelho: {'ajustes/a': e}, atuais: {}, agora: _agora),
        isEmpty);
    final m = detectarMudancasLocais(
        espelho: {'ajustes/a': e},
        atuais: {'ajustes/a': Projetado('ajustes', 'a', {'v': 2}, null)},
        agora: _agora);
    expect(m.single.projecao, isNull);
  });

  test('espelho apagado: editado antes ignora, depois reenvia', () {
    final e = _esp('metas', '1', null, '2026-05-01T00:00:00.000Z',
        deletedAt: '2026-05-01T00:00:00.000Z');
    final antes = detectarMudancasLocais(
        espelho: {'metas/1': e},
        atuais: {
          'metas/1': Projetado('metas', '1', {'nome': 'x'}, '2026-04-01T00:00:00.000Z')
        },
        agora: _agora);
    expect(antes, isEmpty);
    final depois = detectarMudancasLocais(
        espelho: {'metas/1': e},
        atuais: {
          'metas/1': Projetado('metas', '1', {'nome': 'x'}, '2026-06-01T00:00:00.000Z')
        },
        agora: _agora);
    expect(depois.single.registro.deletedAt, isNull);
    expect(depois.single.registro.dados, {'nome': 'x'});
  });

  test('orçamento novo recebe periodo mensal', () {
    expect(completarNovo('orcamentos', {'nome': 'o'})['periodo'], 'mensal');
  });

  test('assinatura nova recebe padrao NOME*', () {
    expect(completarNovo('assinaturas', {'nome': 'Netflix'})['padrao'],
        'NETFLIX*');
  });

  test('remotosVencedores: remoto mais velho perde para pendente local', () {
    final e = _esp('metas', '1', {'nome': 'x'}, '2026-06-01T00:00:00.000Z',
        pendente: true);
    final r = remotosVencedores({
      'metas/1': e
    }, [
      Registro('metas', '1', {'nome': 'r'}, '2026-05-01T00:00:00.000Z', null),
      Registro('metas', '2', {'nome': 'n'}, '2026-05-01T00:00:00.000Z', null),
    ]);
    expect(r.map((x) => x.id), ['2']);
  });
}
