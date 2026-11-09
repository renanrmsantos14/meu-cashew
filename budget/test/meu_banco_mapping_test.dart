import 'package:budget/struct/meuBancoMapping.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json() => {
      "agora": "2026-11-08T23:16:32.807Z",
      "contas": [
        {"id": "conta-cc", "tipo": "BANK", "nome": "Conta Corrente Inter"},
        {"id": "conta-cartao", "tipo": "CREDIT", "nome": "Cartão Inter"},
      ],
      "transacoes": [
        // despesa na conta: valor negativo
        {"id": "cc-1", "conta_id": "conta-cc", "data": "2026-11-02", "descricao": "MERCADO", "valor": -50.25, "tipo": "DEBIT", "status": "POSTED", "categoria": "Groceries", "futura": false},
        // receita na conta: valor positivo
        {"id": "cc-2", "conta_id": "conta-cc", "data": "2026-11-05", "descricao": "SALARIO", "valor": 5000.0, "tipo": "CREDIT", "status": "POSTED", "categoria": "Salary", "futura": false},
        // compra no cartão: valor positivo vira despesa
        {"id": "cart-59", "conta_id": "conta-cartao", "data": "2026-05-15", "descricao": "DROGASIL", "valor": 68.35, "tipo": "DEBIT", "status": "POSTED", "categoria": "Pharmacy", "futura": false},
        // estorno no cartão: valor negativo vira receita
        {"id": "cart-60", "conta_id": "conta-cartao", "data": "2026-05-16", "descricao": "ESTORNO", "valor": -10.0, "tipo": "CREDIT", "status": "POSTED", "categoria": "Pharmacy", "futura": false},
        // pendente
        {"id": "cc-3", "conta_id": "conta-cc", "data": "2026-11-08", "descricao": "PADARIA", "valor": -12.0, "tipo": "DEBIT", "status": "PENDING", "categoria": null, "futura": false},
        // futura: ignorada
        {"id": "cart-61", "conta_id": "conta-cartao", "data": "2026-12-15", "descricao": "PARCELA 2/3", "valor": 100.0, "tipo": "DEBIT", "status": "POSTED", "categoria": "Shopping", "futura": true},
        // pagamento de fatura: não é gasto
        {"id": "cc-4", "conta_id": "conta-cc", "data": "2026-11-06", "descricao": "PAGAMENTO FATURA", "valor": -900.0, "tipo": "DEBIT", "status": "POSTED", "categoria": "Credit card payment", "futura": false},
      ],
      "ids_pendentes": ["cc-3"],
    };

void main() {
  test("despesa na conta fica negativa", () {
    final t = mbMapearResposta(_json()).transacoes.firstWhere((t) => t.pk == "mb:cc-1");
    expect(t.valor, -50.25);
    expect(t.receita, false);
    expect(t.categoriaNome, "Supermercado");
    expect(t.carteiraPk, "mb:conta-cc");
    expect(t.data, DateTime(2026, 11, 2, 12));
  });

  test("receita na conta fica positiva", () {
    final t = mbMapearResposta(_json()).transacoes.firstWhere((t) => t.pk == "mb:cc-2");
    expect(t.valor, 5000.0);
    expect(t.receita, true);
    expect(t.categoriaNome, "Salário");
  });

  test("cartão: compra vira despesa e estorno vira receita", () {
    final r = mbMapearResposta(_json());
    final compra = r.transacoes.firstWhere((t) => t.pk == "mb:cart-59");
    final estorno = r.transacoes.firstWhere((t) => t.pk == "mb:cart-60");
    expect(compra.valor, -68.35);
    expect(compra.receita, false);
    expect(estorno.valor, 10.0);
    expect(estorno.receita, true);
    expect(r.contas.firstWhere((c) => c.walletPk == "mb:conta-cartao").cartao, true);
  });

  test("pendente recebe nota e aparece em pendentesPks; sem categoria vira 'Sem categoria'", () {
    final r = mbMapearResposta(_json());
    final t = r.transacoes.firstWhere((t) => t.pk == "mb:cc-3");
    expect(t.pendente, true);
    expect(t.nota, "Pendente");
    expect(t.categoriaNome, "Sem categoria");
    expect(r.pendentesPks, {"mb:cc-3"});
  });

  test("futura e não-gasto (pagamento de fatura) são ignoradas", () {
    final r = mbMapearResposta(_json());
    final pks = r.transacoes.map((t) => t.pk).toSet();
    expect(pks.contains("mb:cart-61"), false);
    expect(pks.contains("mb:cc-4"), false);
    expect(r.ignoradas, 2);
  });

  test("todos os pks usam o prefixo mb:", () {
    final r = mbMapearResposta(_json());
    expect(r.transacoes.every((t) => t.pk.startsWith("mb:")), true);
    expect(r.contas.every((c) => c.walletPk.startsWith("mb:")), true);
    expect(r.transacoes.every((t) => t.categoriaPk.startsWith("mb:cat:")), true);
  });

  test("idempotência: mesmo JSON gera os mesmos pks e valores", () {
    final a = mbMapearResposta(_json());
    final b = mbMapearResposta(_json());
    expect(a.transacoes.map((t) => t.pk).toList(), b.transacoes.map((t) => t.pk).toList());
    expect(a.transacoes.map((t) => t.valor).toList(), b.transacoes.map((t) => t.valor).toList());
    expect(a.transacoes.map((t) => t.categoriaPk).toList(), b.transacoes.map((t) => t.categoriaPk).toList());
    expect(a.agora, b.agora);
  });
}
