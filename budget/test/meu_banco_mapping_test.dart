import 'package:budget/struct/mbSync/categoriaEfetiva.dart';
import 'package:budget/struct/meuBancoMapping.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json() => {
      "agora": "2026-11-08T23:16:32.807Z",
      "contas": [
        {"id": "conta-cc", "type": "BANK", "name": "Conta Corrente Inter"},
        {"id": "conta-cartao", "type": "CREDIT", "name": "Cartão Inter"},
      ],
      "transacoes": [
        // despesa na conta: valor negativo
        {"id": "cc-1", "account_id": "conta-cc", "date": "2026-11-02", "description": "MERCADO", "amount": -50.25, "type": "DEBIT", "status": "POSTED", "category": "Groceries", "scheduled": 0},
        // receita na conta: valor positivo
        {"id": "cc-2", "account_id": "conta-cc", "date": "2026-11-05", "description": "SALARIO", "amount": 5000.0, "type": "CREDIT", "status": "POSTED", "category": "Salary", "scheduled": 0},
        // compra no cartão: valor positivo vira despesa
        {"id": "cart-59", "account_id": "conta-cartao", "date": "2026-05-15", "description": "DROGASIL", "amount": 68.35, "type": "DEBIT", "status": "POSTED", "category": "Pharmacy", "scheduled": 0},
        // estorno no cartão: valor negativo vira receita
        {"id": "cart-60", "account_id": "conta-cartao", "date": "2026-05-16", "description": "ESTORNO", "amount": -10.0, "type": "CREDIT", "status": "POSTED", "category": "Pharmacy", "scheduled": 0},
        // pendente
        {"id": "cc-3", "account_id": "conta-cc", "date": "2026-11-08", "description": "PADARIA", "amount": -12.0, "type": "DEBIT", "status": "PENDING", "category": null, "scheduled": 0},
        // futura: ignorada
        {"id": "cart-61", "account_id": "conta-cartao", "date": "2026-12-15", "description": "PARCELA 2/3", "amount": 100.0, "type": "DEBIT", "status": "POSTED", "category": "Shopping", "scheduled": 1},
        // pagamento de fatura: não é gasto
        {"id": "cc-4", "account_id": "conta-cc", "date": "2026-11-06", "description": "PAGAMENTO FATURA", "amount": -900.0, "type": "DEBIT", "status": "POSTED", "category": "Credit card payment", "scheduled": 0},
      ],
      "pendentes": ["cc-3"],
    };

const _ctx0 = MbContextoCategoria({}, [], {}, {});

MbResultado _mapear(Map<String, dynamic> j, [MbContextoCategoria ctx = _ctx0]) =>
    mbMapearPull(j, ctx, pkCategoria: (_, nome, receita) => mbPkCategoria(nome, receita));

void main() {
  test("despesa na conta fica negativa", () {
    final t = _mapear(_json()).transacoes.firstWhere((t) => t.pk == "mb:cc-1");
    expect(t.valor, -50.25);
    expect(t.receita, false);
    expect(t.categoriaNome, "Supermercado");
    expect(t.carteiraPk, "mb:conta-cc");
    expect(t.data, DateTime(2026, 11, 2, 12));
  });

  test("receita na conta fica positiva", () {
    final t = _mapear(_json()).transacoes.firstWhere((t) => t.pk == "mb:cc-2");
    expect(t.valor, 5000.0);
    expect(t.receita, true);
    expect(t.categoriaNome, "Salário");
  });

  test("cartão: compra vira despesa e estorno vira receita", () {
    final r = _mapear(_json());
    final compra = r.transacoes.firstWhere((t) => t.pk == "mb:cart-59");
    final estorno = r.transacoes.firstWhere((t) => t.pk == "mb:cart-60");
    expect(compra.valor, -68.35);
    expect(compra.receita, false);
    expect(estorno.valor, 10.0);
    expect(estorno.receita, true);
    expect(r.contas.firstWhere((c) => c.walletPk == "mb:conta-cartao").cartao, true);
  });

  test("pendente recebe nota e aparece em pendentesPks; sem categoria vira 'Sem categoria'", () {
    final r = _mapear(_json());
    final t = r.transacoes.firstWhere((t) => t.pk == "mb:cc-3");
    expect(t.pendente, true);
    expect(t.nota, "Pendente");
    expect(t.categoriaNome, "Sem categoria");
    expect(r.pendentesPks, {"mb:cc-3"});
  });

  test("futura e não-gasto (pagamento de fatura) são ignoradas", () {
    final r = _mapear(_json());
    final pks = r.transacoes.map((t) => t.pk).toSet();
    expect(pks.contains("mb:cart-61"), false);
    expect(pks.contains("mb:cc-4"), false);
    expect(r.ignoradas, 2);
  });

  test("todos os pks usam o prefixo mb:", () {
    final r = _mapear(_json());
    expect(r.transacoes.every((t) => t.pk.startsWith("mb:")), true);
    expect(r.contas.every((c) => c.walletPk.startsWith("mb:")), true);
    expect(r.transacoes.every((t) => t.categoriaPk.startsWith("mb:cat:")), true);
  });

  test("idempotência: mesmo JSON gera os mesmos pks e valores", () {
    final a = _mapear(_json());
    final b = _mapear(_json());
    expect(a.transacoes.map((t) => t.pk).toList(), b.transacoes.map((t) => t.pk).toList());
    expect(a.transacoes.map((t) => t.valor).toList(), b.transacoes.map((t) => t.valor).toList());
    expect(a.transacoes.map((t) => t.categoriaPk).toList(), b.transacoes.map((t) => t.categoriaPk).toList());
    expect(a.agora, b.agora);
  });
}
