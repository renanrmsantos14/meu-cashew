import 'dart:convert';
import 'dart:io';

import 'package:budget/struct/mbSync/categoriaEfetiva.dart';
import 'package:budget/struct/mbSync/mapeamento.dart';
import 'package:budget/struct/mbSync/registro.dart';
import 'package:budget/struct/meuBancoMapping.dart';
import 'package:flutter_test/flutter_test.dart';

Registro _reg(String tabela, String id, Map<String, dynamic> d) =>
    Registro(tabela, id, d, '2026-11-01T00:00:00.000Z', null);

MbResultado _pull(Map<String, dynamic> j, Iterable<Registro> regs) =>
    mbMapearPull(j, MbContextoCategoria.deRegistros(regs),
        pkCategoria: (id, nome, receita) =>
            id != null ? pkDoId(id) : mbPkCategoria(nome, receita));

Map<String, dynamic> _json(Map<String, dynamic> tx) => {
      'agora': '2026-11-09T10:00:00.000Z',
      'contas': [
        {'id': 'cc', 'type': 'BANK', 'name': 'Conta'}
      ],
      'transacoes': [
        {
          'id': 't1',
          'account_id': 'cc',
          'date': '2026-11-02',
          'description': 'COMPRA DROGASIL',
          'amount': -20.0,
          'status': 'POSTED',
          'category': 'Pharmacy',
          'scheduled': 0,
          ...tx,
        }
      ],
      'pendentes': [],
      'ciclo': {'inicio': '2026-11-01'},
      'faturas': {'cc': []},
      'avisos': [
        {'item_id': 'i1'}
      ],
      'config': {'salario': '5000'},
      'sincronizado_em': '2026-11-09T09:00:00.000Z',
    };

void main() {
  test('ida e volta: categoria', () {
    final c = CatLocal(
        pk: 'c1', nome: 'Mercado', receita: false, cor: '#fff', icone: 'a.png', paiPk: 'p', ordem: 3);
    final d = projetarCategoria(c);
    expect(d['pai_id'], 'cashew:p');
    expect(projetarCategoria(categoriaDeDados('cashew:c1', d)), d);
  });

  test('ida e volta: orçamento (ids ordenados, sem periodo)', () {
    final d = projetarOrcamento(
        OrcLocal(pk: 'o1', nome: 'Casa', valor: 900.5, categoriaPks: ['b', 'a']));
    expect(d['categoria_ids'], ['cashew:a', 'cashew:b']);
    expect(d.containsKey('periodo'), false);
    expect(projetarOrcamento(orcamentoDeDados('cashew:o1', d)), d);
  });

  test('ida e volta: meta e dívida', () {
    final m = projetarObjetivo(ObjLocal(
        pk: 'm1', nome: 'Viagem', divida: false, valor: 3000, prazo: DateTime(2027, 3, 5, 12)));
    expect(m, {'nome': 'Viagem', 'valor_alvo': 3000.0, 'prazo': '2027-03-05'});
    expect(projetarObjetivo(objetivoDeDados('cashew:m1', m, divida: false)), m);
    final dv = projetarObjetivo(ObjLocal(
        pk: 'd1', nome: 'João', divida: true, receita: true, valor: 200));
    expect(dv['sentido'], 'me_devem');
    expect(dv['tipo'], 'emprestimo');
    expect(projetarObjetivo(objetivoDeDados('d1', dv, divida: true)), dv);
  });

  test('ida e volta: lançamento', () {
    final d = projetarLancamento(LancLocal(
        pk: 'l1',
        nome: '  ',
        nota: ' obs ',
        valor: -12.5,
        categoriaPk: 'c1',
        carteiraNome: 'Carteira',
        data: DateTime(2026, 11, 9, 12),
        metaPk: 'm1'));
    expect(d['descricao'], 'Sem descrição');
    expect(d['nota'], 'obs');
    expect(d['divida_id'], null);
    expect(
        projetarLancamento(
            lancamentoDeDados('cashew:l1', d, categoriaPadrao: 'x')),
        d);
  });

  test('lançamento: texto cortado em 200 caracteres', () {
    final d = projetarLancamento(LancLocal(
        pk: 'l', nome: 'a' * 300, valor: 1, categoriaPk: 'c', carteiraNome: 'w', data: DateTime(2026, 1, 1)));
    expect((d['descricao'] as String).length, 200);
  });

  test('ida e volta: assinatura e ignorada vira null', () {
    final d = projetarAssinatura(
        AssinLocal(pk: 's1', nome: 'Netflix', valor: -39.9, dia: 5, categoriaPk: 'c1'));
    expect(d['valor'], 39.9);
    expect(projetarAssinatura(assinaturaDeDados('cashew:s1', d, categoriaPadrao: 'x')!), d);
    expect(assinaturaDeDados('s1', {...d, 'status': 'ignorada'}, categoriaPadrao: 'x'), null);
  });

  test('ida e volta: regra e preservação de DROGASIL*', () {
    final r = regraDeDados('cashew:r1', {'padrao': '*uber*', 'categoria_id': 'cashew:c1'})!;
    expect((r.titulo, r.exato), ('uber', false));
    final d = projetarRegra(r, null)!;
    expect(d, {'padrao': '*uber*', 'categoria_id': 'cashew:c1'});
    expect(projetarRegra(regraDeDados('r1', d)!, null), d);
    final dro = regraDeDados('r2', {'padrao': 'DROGASIL*', 'categoria_id': 'c'})!;
    expect(projetarRegra(dro, {'padrao': 'DROGASIL*'})!['padrao'], 'DROGASIL*');
    expect(projetarRegra(dro, null)!['padrao'], '*DROGASIL*');
    final ex = RegraLocal(pk: 'r', titulo: 'PIX', categoriaPk: 'c', exato: true);
    expect(projetarRegra(ex, {'padrao': '*PIX*'})!['padrao'], 'PIX');
  });

  test('regra com curinga no meio não vira RegraLocal', () {
    expect(regraDeDados('r', {'padrao': 'DRO*SIL', 'categoria_id': 'c'}), null);
  });

  test('projetarAjuste: os três casos', () {
    final apagada = projetarAjuste(
        txPk: 'mb:t1', categoriaPkAtual: null, categoriaPkAplicada: 'mb:cat:d:X',
        existeLocal: false, nomeCategoria: 'X', editadoEm: null)!;
    expect([apagada.tabela, apagada.id], ['ajustes', 't1']);
    expect(apagada.dados, {'gasto': 0});
    final mudou = projetarAjuste(
        txPk: 'mb:t1', categoriaPkAtual: 'c2', categoriaPkAplicada: 'c1',
        existeLocal: true, nomeCategoria: 'Mercado', editadoEm: '2026-11-09T10:00:00.000Z')!;
    expect(mudou.dados, {'categoria_id': 'cashew:c2', 'category': 'Mercado'});
    expect(mudou.editadoEm, '2026-11-09T10:00:00.000Z');
    expect(
        projetarAjuste(
            txPk: 'mb:t1', categoriaPkAtual: 'c1', categoriaPkAplicada: 'c1',
            existeLocal: true, nomeCategoria: 'X', editadoEm: null),
        null);
  });

  test('dataLocal e dataDeTexto', () {
    expect(dataLocal(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
    expect(dataDeTexto('2026-01-05'), DateTime(2026, 1, 5, 12));
    expect(pkDoId('cashew:abc'), 'abc');
    expect(pkDoId('abc'), 'abc');
  });

  group('categoria efetiva: casos compartilhados com o core', () {
    final casos = jsonDecode(
        File('test/fixtures/categoria-casos.json').readAsStringSync()) as List;
    for (final c in casos) {
      test(c['nome'] as String, () {
        final tx = c['tx'] as Map<String, dynamic>;
        final regs = [
          for (final r in c['registros'] as List)
            Registro(r['tabela'], r['id'], (r['dados'] as Map).cast<String, dynamic>(),
                '2026-11-01T00:00:00.000Z', r['deleted_at'])
        ];
        final r = mbCategoriaEfetiva(
            txId: tx['id'],
            contaId: tx['account_id'],
            descricao: tx['description'],
            categoriaPluggy: tx['category'],
            receita: c['receita'] as bool,
            ctx: MbContextoCategoria.deRegistros(regs));
        expect(r.fonte, c['esperado']['fonte']);
        expect(r.categoriaId, c['esperado']['categoria_id']);
      });
    }
  });

  test('mbPadraoCasa escapa o resto e trata o curinga', () {
    expect(mbPadraoCasa('A.B*', 'A.B qualquer'), true);
    expect(mbPadraoCasa('A.B*', 'AxB'), false);
    expect(mbPadraoCasa('  ', 'x'), false);
  });

  group('mbMapearPull', () {
    test('ajuste gasto 0 pula; gasto 1 importa mesmo fora de gasto', () {
      final fora = {'category': 'Credit card payment', 'description': 'PAGAMENTO FATURA'};
      expect(_pull(_json(fora), []).transacoes, isEmpty);
      expect(_pull(_json(fora), [_reg('ajustes', 't1', {'gasto': 1})]).transacoes.length, 1);
      final r = _pull(_json({}), [_reg('ajustes', 't1', {'gasto': 0})]);
      expect(r.transacoes, isEmpty);
      expect(r.ignoradas, 1);
    });

    test('regra muda a categoria da transação', () {
      final r = _pull(_json({}), [
        _reg('regras', 'r1', {'padrao': 'COMPRA*', 'categoria_id': 'cashew:cx'})
      ]);
      expect(r.transacoes.single.categoriaPk, 'cx');
    });

    test('sem regra, converte a categoria do banco para a própria', () {
      expect(_pull(_json({}), []).transacoes.single.categoriaPk, 'mb:cat:d:Saúde');
    });

    test('repassa ciclo, faturas, avisos, config e sincronizado_em', () {
      final r = _pull(_json({}), []);
      expect(r.ciclo, {'inicio': '2026-11-01'});
      expect(r.faturas.keys, ['cc']);
      expect(r.avisos.length, 1);
      expect(r.config['salario'], '5000');
      expect(r.sincronizadoEm, '2026-11-09T09:00:00.000Z');
      expect(r.contasBrutas.single['id'], 'cc');
    });
  });
}
