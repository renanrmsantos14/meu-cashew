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
    expect(t.categoriaNome, "Mercado");
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

  test("pendente recebe nota e aparece em pendentesPks; sem categoria vira 'Outros'", () {
    final r = _mapear(_json());
    final t = r.transacoes.firstWhere((t) => t.pk == "mb:cc-3");
    expect(t.pendente, true);
    expect(t.nota, "Pendente");
    expect(t.categoriaNome, "Outros");
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

  test("conta corrente Santander e suas transações ficam fora; poupança e cartão não", () {
    final j = _json();
    j["contas"] = [
      ...j["contas"] as List,
      {"id": "st-cc", "type": "BANK", "subtype": "CHECKING_ACCOUNT", "name": "Conta", "bank": "Santander"},
      {"id": "st-pp", "type": "BANK", "subtype": "SAVINGS_ACCOUNT", "name": "Poupança Santander"},
      {"id": "st-cart", "type": "CREDIT", "name": "Cartão Santander"},
    ];
    j["transacoes"] = [
      ...j["transacoes"] as List,
      {"id": "st-1", "account_id": "st-cc", "date": "2026-11-02", "description": "PIX", "amount": -30.0, "status": "POSTED", "category": "Transfers"},
    ];
    final r = _mapear(j);
    expect(r.contasIgnoradasPks, {"mb:st-cc"});
    expect(r.contas.map((c) => c.walletPk), isNot(contains("mb:st-cc")));
    expect(r.contas.map((c) => c.walletPk), containsAll(["mb:st-pp", "mb:st-cart"]));
    expect(r.transacoes.any((t) => t.pk == "mb:st-1"), false);
    expect(r.ignoradas, _mapear(_json()).ignoradas + 1);
  });

  test("investimentos: null em servidor antigo; itens sem saldo descartados", () {
    expect(_mapear(_json()).investimentos, isNull);
    final j = _json();
    j["investimentos"] = [
      {"id": "i1", "nome": " CDB ", "saldo": 10, "banco": "Santander"},
      {"id": "i2", "nome": "Sem saldo", "saldo": null},
    ];
    final inv = _mapear(j).investimentos!;
    expect(inv.map((i) => [i.pk, i.nome, i.saldo, i.banco]), [
      ["mb:inv:i1", "CDB", 10.0, "Santander"]
    ]);
  });

  group("categorias próprias e regras de transferência", () {
    Map<String, dynamic> tx(String id, String desc, num valor,
            {String? cat, String data = "2026-11-10", String conta = "cc"}) =>
        {"id": id, "account_id": conta, "date": data, "description": desc, "amount": valor, "status": "POSTED", "category": cat, "scheduled": 0};

    MbResultado mapa(List<Map<String, dynamic>> txs,
            {List<MbCompra> compras = const [], String banco = "Inter"}) =>
        mbMapearPull({
          "contas": [
            {"id": "cc", "type": "BANK", "name": "Conta", "bank": banco},
            {"id": "cart", "type": "CREDIT", "name": "Cartão", "bank": banco},
          ],
          "transacoes": txs,
        }, _ctx0,
            compras: compras,
            pkCategoria: (_, nome, receita) => mbPkCategoria(nome, receita));

    test("todo nome do mapa aponta para uma categoria própria e o resto vira Outros", () {
      for (final p in mbCategorias.keys) {
        expect([...mbCategoriasProprias, mbCategoriaOutros], contains(mbCategoriaPropria(p)));
      }
      expect(mbCategoriaPropria("Groceries"), "Mercado");
      expect(mbCategoriaPropria("Eating out"), "Alimentação fora");
      expect(mbCategoriaPropria("Video streaming"), "Assinaturas");
      expect(mbCategoriaPropria("Bank fees"), "Tarifas");
      expect(mbCategoriaPropria("Transfer - PIX"), "Outros");
      expect(mbCategoriaPropria(null), "Outros");
    });

    test("as doze categorias próprias e Outros são devolvidas para criação", () {
      final r = mapa([]);
      expect(r.categoriasProprias.keys, [...mbCategoriasProprias, "Outros"]);
      expect(r.categoriasProprias["Mercado"], "mb:cat:d:Mercado");
    });

    test("receita mantém a tradução do banco (não vira categoria de despesa)", () {
      final t = mapa([tx("a", "SALARIO", 5000, cat: "Salary")]).transacoes.single;
      expect(t.categoriaNome, "Salário");
      expect(t.receita, true);
    });

    test("pagamento da fatura, aplicação, resgate, Porquinho e CDB não são gasto nem renda", () {
      final r = mapa([
        tx("f1", "Pagamento de fatura Inter", -900, cat: "Credit card payment"),
        tx("f2", "PAGAMENTO RECEBIDO", -900, conta: "cart"),
        tx("p1", "Aplicação Porquinho", -100),
        tx("p2", "Resgate Porquinho", 100),
        tx("c1", "Aplicação CDB", -500),
        tx("c2", "Resgate CDB", 510, cat: "Fixed income"),
      ]);
      expect(r.transacoes, isEmpty);
      expect(r.naoGastoPks, {"mb:f1", "mb:f2", "mb:p1", "mb:p2", "mb:c1", "mb:c2"});
    });

    test("resgate do Santander para o Inter é transferência; entrada de outro banco continua renda", () {
      final r = mapa([
        tx("s1", "Pix recebido SANTANDER S.A.", 3000),
        tx("s2", "Pix recebido Maria", 80),
      ]);
      expect(r.naoGastoPks, {"mb:s1"});
      expect(r.transacoes.single.pk, "mb:s2");
      expect(r.transacoes.single.receita, true);
    });

    test("ajuste gasto=1 do usuário mantém a transação mesmo sendo transferência", () {
      final ctx = MbContextoCategoria({"s1": {"gasto": 1}}, [], {}, {});
      final r = mbMapearPull({
        "contas": [{"id": "cc", "type": "BANK", "name": "Conta", "bank": "Inter"}],
        "transacoes": [tx("s1", "Resgate Santander", 3000)],
      }, ctx, pkCategoria: (_, n, rc) => mbPkCategoria(n, rc));
      expect(r.transacoes.single.pk, "mb:s1");
      expect(r.naoGastoPks, isEmpty);
    });

    test("cashback abate o gasto: valor positivo em despesa, não é renda", () {
      final r = mapa([
        tx("k1", "Cashback Inter Loop", 12.5, cat: "Cashback"),
        tx("k2", "CASHBACK compra", 3),
      ]);
      for (final t in r.transacoes) {
        expect(t.receita, false);
        expect(t.valor, greaterThan(0));
        expect(t.categoriaNome, "Compras");
        expect(t.categoriaPk, "mb:cat:d:Compras");
      }
    });

    test("estorno no cartão abate a compra de mesmo valor e estabelecimento em até 60 dias", () {
      final r = mapa([
        tx("c", "Netflix", 39.9, conta: "cart", data: "2026-09-20", cat: "Video streaming"),
        tx("e", "Estorno NETFLIX", -39.9, conta: "cart", data: "2026-11-10"),
      ]);
      final e = r.transacoes.firstWhere((t) => t.pk == "mb:e");
      expect(e.receita, false);
      expect(e.valor, 39.9);
      expect(e.categoriaNome, "Assinaturas");
      expect(e.categoriaPk, "mb:cat:d:Assinaturas");
    });

    test("estorno não abate se passou de 60 dias, o valor difere ou o estabelecimento é outro", () {
      final r = mapa([
        tx("c1", "Loja A", 100, conta: "cart", data: "2026-08-01"),
        tx("e1", "Loja A", -100, conta: "cart", data: "2026-11-10"),
        tx("c2", "Loja B", 100, conta: "cart", data: "2026-11-01"),
        tx("e2", "Loja B", -99.99, conta: "cart", data: "2026-11-10"),
        tx("e3", "Loja C", -100, conta: "cart", data: "2026-11-10"),
      ]);
      for (final id in ["e1", "e2", "e3"]) {
        final t = r.transacoes.firstWhere((t) => t.pk == "mb:$id");
        expect(t.receita, true, reason: id);
      }
    });

    test("estorno não pode ser anterior à compra e cada compra é abatida uma vez", () {
      final r = mapa([
        tx("e0", "Loja", -10, conta: "cart", data: "2026-10-01"),
        tx("c", "Loja", 10, conta: "cart", data: "2026-10-05"),
        tx("e1", "Loja", -10, conta: "cart", data: "2026-10-10"),
        tx("e2", "Loja", -10, conta: "cart", data: "2026-10-11"),
      ]);
      bool abate(String id) => !r.transacoes.firstWhere((t) => t.pk == "mb:$id").receita;
      expect([abate("e0"), abate("e1"), abate("e2")], [false, true, false]);
    });

    test("estorno abate compra de um pull anterior (local) e herda a categoria dela", () {
      final r = mapa([
        tx("e", "Estorno - Farmácia X", -45.9, conta: "cart", data: "2026-11-10"),
      ], compras: [
        MbCompra("mb:antiga", mbNormalizarEstabelecimento("Farmácia X"), 4590,
            DateTime(2026, 10, 20, 12), "", "mb:cat:d:Saúde")
      ]);
      final e = r.transacoes.single;
      expect(e.receita, false);
      expect(e.categoriaPk, "mb:cat:d:Saúde");
    });

    test("estorno de pull anterior já consumiu a compra: o próximo não abate a mesma", () {
      final compra = MbCompra("mb:c", mbNormalizarEstabelecimento("Loja"), 1000,
          DateTime(2026, 10, 5, 12), "", "mb:cat:d:Lazer");
      final anterior = MbCompra("mb:e1", mbNormalizarEstabelecimento("Loja"), 1000,
          DateTime(2026, 10, 10, 12), "", "mb:cat:d:Lazer");
      final r = mapa([tx("e2", "Loja", -10, conta: "cart", data: "2026-10-11")],
          compras: [compra]);
      expect(r.transacoes.single.receita, false);
      final r2 = mbMapearPull({
        "contas": [{"id": "cart", "type": "CREDIT", "name": "Cartão", "bank": "Inter"}],
        "transacoes": [tx("e2", "Loja", -10, conta: "cart", data: "2026-10-11")],
      }, _ctx0,
          compras: [compra],
          abatimentos: [anterior],
          pkCategoria: (_, n, rc) => mbPkCategoria(n, rc));
      expect(r2.transacoes.single.receita, true);
    });

    test("estornos iguais são pareados em ordem cronológica, mesmo vindo fora de ordem", () {
      final r = mapa([
        tx("e2", "Loja", -10, conta: "cart", data: "2026-10-12"),
        tx("e1", "Loja", -10, conta: "cart", data: "2026-10-09"),
        tx("c1", "Loja", 10, conta: "cart", data: "2026-10-01", cat: "Gaming"),
        tx("c2", "Loja", 10, conta: "cart", data: "2026-10-08", cat: "Groceries"),
      ]);
      String cat(String id) => r.transacoes.firstWhere((t) => t.pk == "mb:$id").categoriaNome;
      expect([cat("e1"), cat("e2")], ["Mercado", "Lazer"]);
    });

    test("ajuste do usuário no estorno prevalece", () {
      final ctx = MbContextoCategoria({"e": {"category": "Salary"}}, [], {}, {});
      final r = mbMapearPull({
        "contas": [{"id": "cart", "type": "CREDIT", "name": "Cartão", "bank": "Inter"}],
        "transacoes": [
          tx("c", "Loja", 10, conta: "cart", data: "2026-11-01"),
          tx("e", "Loja", -10, conta: "cart", data: "2026-11-05"),
        ],
      }, ctx, pkCategoria: (_, n, rc) => mbPkCategoria(n, rc));
      expect(r.transacoes.firstWhere((t) => t.pk == "mb:e").receita, true);
    });
  });
}
