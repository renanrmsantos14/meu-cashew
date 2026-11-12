import 'package:budget/struct/mbSync/emprestimos.dart';
import 'package:budget/struct/mbSync/reembolso.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _emp(String tx, double valor, String data) =>
    {'tipo': 'decisao', 'tx_id': tx, 'resposta': 'emprestimo', 'valor': valor, 'data': data};
Map<String, dynamic> _dev(String tx, double valor, String data) =>
    {'tipo': 'decisao', 'tx_id': tx, 'resposta': 'devolucao', 'valor': valor, 'data': data};

List<(String, double, double)> _resumo(MbEmprestimos e) =>
    [for (final a in e.abertos) (a.txId, a.original, a.restante)];

void main() {
  group('empréstimos em aberto', () {
    test('cada empréstimo abre um item; sem decisões a lista é vazia', () {
      expect(mbCalcularEmprestimos(const []).abertos, isEmpty);
      final e = mbCalcularEmprestimos([_emp('b', 300, '2026-11-08'), _emp('a', 500, '2026-11-02')]);
      expect(_resumo(e), [('a', 500, 500), ('b', 300, 300)]); // do mais antigo ao mais novo
      expect(e.devido, 800);
    });

    test('devolução parcial abate o mais antigo', () {
      final e = mbCalcularEmprestimos([_emp('a', 500, '2026-11-02'), _emp('b', 300, '2026-11-08'), _dev('d', 200, '2026-11-09')]);
      expect(_resumo(e), [('a', 500, 300), ('b', 300, 300)]);
      expect(e.abertos.first.parcial, true);
      expect(e.devido, 600);
    });

    test('devolução total quita o mais antigo e segue para o próximo (FIFO)', () {
      final e = mbCalcularEmprestimos([_emp('a', 500, '2026-11-02'), _emp('b', 300, '2026-11-08'), _dev('d', 650, '2026-11-09')]);
      expect(_resumo(e), [('b', 300, 150)]);
      expect(e.devido, 150);
    });

    test('devolução maior que o devido quita tudo e o excedente não vira crédito', () {
      final e = mbCalcularEmprestimos([_emp('a', 100, '2026-11-02'), _dev('d', 400, '2026-11-03'), _emp('b', 50, '2026-11-05')]);
      expect(_resumo(e), [('b', 50, 50)]);
    });

    test('devolução anterior ao empréstimo não o abate; no mesmo dia, o empréstimo vem antes', () {
      expect(_resumo(mbCalcularEmprestimos([_dev('d', 100, '2026-11-01'), _emp('a', 100, '2026-11-02')])), [('a', 100, 100)]);
      expect(mbCalcularEmprestimos([_dev('d', 100, '2026-11-02'), _emp('a', 100, '2026-11-02')]).abertos, isEmpty);
    });

    test('a ordem de chegada das decisões não muda o resultado', () {
      final a = [_emp('a', 500, '2026-11-02'), _dev('d', 200, '2026-11-09'), _emp('b', 300, '2026-11-08')];
      expect(_resumo(mbCalcularEmprestimos(a)), _resumo(mbCalcularEmprestimos(a.reversed)));
    });

    test('ignora outras respostas, valores inválidos e decisões sem data', () {
      final e = mbCalcularEmprestimos([
        {'tipo': 'decisao', 'tx_id': 'x', 'resposta': 'ajuda', 'valor': 10, 'data': '2026-11-01'},
        {'tipo': 'decisao', 'tx_id': 'y', 'resposta': 'emprestimo', 'data': '2026-11-01'},
        {'tipo': 'decisao', 'tx_id': 'z', 'resposta': 'emprestimo', 'valor': 10},
        {'tipo': 'decisao', 'tx_id': 'w', 'resposta': 'emprestimo', 'valor': 0, 'data': '2026-11-01'},
        _emp('ok', 12.34, '2026-11-01T10:00:00Z'),
      ]);
      expect(_resumo(e), [('ok', 12.34, 12.34)]);
    });

    test('centavos não acumulam erro de ponto flutuante', () {
      final e = mbCalcularEmprestimos([_emp('a', 0.3, '2026-11-01'), _dev('d', 0.1, '2026-11-02'), _dev('e', 0.2, '2026-11-03')]);
      expect(e.abertos, isEmpty);
    });
  });

  group('sugestão de reembolso', () {
    final hoje = DateTime(2026, 11, 12);
    MbGastoCandidato g(String pk, double v, DateTime d, [String cat = 'Mercado']) =>
        MbGastoCandidato('mb:$pk', pk, cat, DateTime(d.year, d.month, d.day, 12), (v * 100).round());
    List<String> pks(List<MbSugestaoReembolso> l) => [for (final s in l) s.gasto.pk];

    test('janela de 15 dias, sem gasto posterior ao reembolso', () {
      final r = mbSugerirReembolso([
        g('dentro', 60, hoje.subtract(const Duration(days: 15))),
        g('fora', 60, hoje.subtract(const Duration(days: 16))),
        g('depois', 60, hoje.add(const Duration(days: 1))),
        g('hoje', 60, hoje),
      ], valor: 60, data: hoje);
      expect(pks(r), ['mb:hoje', 'mb:dentro']);
    });

    test('igual primeiro, depois próximo (até 20%), depois os demais; mais recentes antes em cada grupo', () {
      final r = mbSugerirReembolso([
        g('longe', 200, DateTime(2026, 11, 11)),
        g('prox-velho', 55, DateTime(2026, 11, 5)),
        g('igual-velho', 60, DateTime(2026, 11, 4)),
        g('prox-novo', 70, DateTime(2026, 11, 10)),
        g('igual-novo', 60, DateTime(2026, 11, 9)),
      ], valor: 60, data: hoje);
      expect(pks(r), ['mb:igual-novo', 'mb:igual-velho', 'mb:prox-novo', 'mb:prox-velho', 'mb:longe']);
      expect(r.map((s) => s.afinidade.name), ['igual', 'igual', 'proximo', 'proximo', 'outro']);
    });
  });
}
