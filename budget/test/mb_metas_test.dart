import 'package:budget/struct/mbSync/metas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hoje = DateTime(2026, 11, 12);
  final saldos = {'a': 1000.0, 'b': 500.0, 'c': 99.0};

  MbMetaResumo resumo(MbMetaDados m) =>
      mbResumoMetas(metas: [m], saldoPorAplicacao: saldos, hoje: hoje).single;

  test('meta com alvo soma só as aplicações dela', () {
    final r = resumo(const MbMetaDados(
        pk: 'm', nome: 'Viagem', alvo: 3000, aplicacaoPks: ['a', 'b']));
    expect(r.saldo, 1500);
    expect(r.progresso, 0.5);
    expect(r.falta, 1500);
    expect(r.diasRestantes, isNull);
    expect(r.texto, contains('Viagem'));
    expect(r.texto, contains('50%'));
    expect(r.texto, contains('faltam'));
    expect(r.texto, isNot(contains('prazo')));
  });

  test('sem valor definido não tem percentual nem falta', () {
    final r = resumo(const MbMetaDados(
        pk: 'm', nome: 'Reserva de emergência', alvo: 0, aplicacaoPks: ['c']));
    expect(r.saldo, 99);
    expect(r.alvo, isNull);
    expect(r.progresso, isNull);
    expect(r.falta, isNull);
    expect(r.texto, contains('defina o valor da meta'));
  });

  test('meta atingida limita o progresso em 100%', () {
    final r = resumo(const MbMetaDados(
        pk: 'm', nome: 'Carro', alvo: 800, aplicacaoPks: ['a']));
    expect(r.progresso, 1);
    expect(r.falta, 0);
    expect(r.texto, contains('meta atingida'));
  });

  test('prazo futuro, hoje e vencido', () {
    MbMetaResumo comPrazo(DateTime p) => resumo(MbMetaDados(
        pk: 'm', nome: 'X', alvo: 5000, prazo: p, aplicacaoPks: const ['a']));
    expect(comPrazo(DateTime(2026, 11, 22)).diasRestantes, 10);
    expect(comPrazo(DateTime(2026, 11, 12)).texto, contains('prazo é hoje'));
    final vencido = comPrazo(DateTime(2026, 11, 1));
    expect(vencido.diasRestantes, -11);
    expect(vencido.texto, contains('prazo venceu'));
  });

  test('aplicação desconhecida conta zero e meta sem aplicação fica em zero', () {
    expect(resumo(const MbMetaDados(pk: 'm', nome: 'X', alvo: 100, aplicacaoPks: ['z'])).saldo, 0);
    expect(resumo(const MbMetaDados(pk: 'm', nome: 'X', alvo: 100)).saldo, 0);
  });

  test('série do Worker: ordena, ignora lixo e aceita resposta antiga', () {
    expect(mbSerieDeJson(null), isEmpty);
    expect(mbSerieDeJson('x'), isEmpty);
    final s = mbSerieDeJson([
      {
        'mes': '2026-10',
        'itens': [
          {'id': 'a', 'nome': 'CDB', 'banco': 'inter', 'saldo': 100},
          {'id': 'b', 'nome': 'LCI', 'banco': null, 'saldo': 50.5},
          {'id': 'c', 'nome': 'ruim', 'saldo': 'x'},
          {'nome': 'sem id', 'saldo': 1},
        ]
      },
      {'mes': '2026-09', 'itens': [{'id': 'a', 'nome': 'CDB', 'saldo': 80}]},
      {'mes': 5},
      {'mes': '2026-1x', 'itens': []},
    ]);
    expect(s.map((m) => m.mes), ['2026-09', '2026-10']);
    expect(s[1].total, 150.5);
    final v = mbSerieComVariacao(s);
    expect(v[0].variacao, isNull);
    expect(v[1].variacao, 70.5);
  });
}
