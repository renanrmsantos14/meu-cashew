// Mapeamento puro (sem Flutter/Drift) da resposta do Meu Banco para dados do RenanCash.
// Espelha public/regras.js do painel do Meu Banco (CATEGORIAS, traduzir, naoEhGasto, valorGasto).

import 'package:budget/struct/mbSync/categoriaEfetiva.dart';
import 'package:budget/struct/mbSync/revisao.dart';

const String mbPrefixo = "mb:";

const Map<String, String> mbCategorias = {
  "Income": "Receitas",
  "Salary": "Salário",
  "Retirement": "Aposentadoria",
  "Entrepreneurial activities": "Atividade empresarial",
  "Government aid": "Auxílio do governo",
  "Non-recurring income": "Receita eventual",
  "Loans and financing": "Empréstimos e financiamentos",
  "Late payment and overdraft costs": "Juros de atraso e cheque especial",
  "Interests charged": "Juros cobrados",
  "Financing": "Financiamento",
  "Real estate financing": "Financiamento imobiliário",
  "Vehicle financing": "Financiamento de veículo",
  "Student loan": "Crédito estudantil",
  "Loans": "Empréstimos",
  "Investments": "Investimentos",
  "Automatic investment": "Investimento automático",
  "Fixed income": "Renda fixa",
  "Mutual funds": "Fundos de investimento",
  "Variable income": "Renda variável",
  "Margin": "Margem",
  "Proceeds interests and dividends": "Rendimentos e dividendos",
  "Pension": "Previdência",
  "Savings": "Poupança",
  "Same person transfer": "Transferência entre minhas contas",
  "Transfers": "Transferências",
  "Transfer - Bank Slip": "Transferência - boleto",
  "Transfer - Cash": "Transferência - dinheiro",
  "Transfer - Check": "Transferência - cheque",
  "Transfer - DOC": "Transferência - DOC",
  "Transfer - Foreign Exchange": "Transferência - câmbio",
  "Transfer - Internal": "Transferência interna",
  "Transfer - PIX": "Pix",
  "Transfer - TED": "TED",
  "Third party transfers": "Transferência para terceiros",
  "Third party transfer - Bank Slip": "Boleto para terceiros",
  "Third party transfer - Debit Card": "Débito para terceiros",
  "Third party transfer - DOC": "DOC para terceiros",
  "Third party transfer - PIX": "Pix para terceiros",
  "Third party transfer - TED": "TED para terceiros",
  "Credit card payment": "Pagamento de fatura",
  "Legal obligations": "Obrigações legais",
  "Blocked balances": "Saldo bloqueado",
  "Alimony": "Pensão alimentícia",
  "Services": "Serviços",
  "Telecommunications": "Telecomunicações",
  "Internet": "Internet",
  "Mobile": "Celular",
  "TV": "TV",
  "Education": "Educação",
  "Online courses": "Cursos online",
  "University": "Faculdade",
  "School": "Escola",
  "Kindergarten": "Creche",
  "Wellness and fitness": "Bem-estar e academia",
  "Gyms and fitness centers": "Academia",
  "Sports practice": "Esportes",
  "Wellness": "Bem-estar",
  "Tickets": "Ingressos",
  "Stadiums and arenas": "Estádios e arenas",
  "Landmarks and museums": "Museus e atrações",
  "Cinema, theater and concerts": "Cinema, teatro e shows",
  "Shopping": "Compras",
  "Online shopping": "Compras online",
  "Electronics": "Eletrônicos",
  "Pet supplies and vet": "Pet e veterinário",
  "Clothing": "Roupas",
  "Kids and toys": "Infantil e brinquedos",
  "Bookstore": "Livraria",
  "Sports goods": "Artigos esportivos",
  "Office supplies": "Papelaria",
  "Cashback": "Cashback",
  "Digital services": "Serviços digitais",
  "Gaming": "Jogos",
  "Video streaming": "Streaming de vídeo",
  "Music streaming": "Streaming de música",
  "Groceries": "Supermercado",
  "Food and drinks": "Alimentação",
  "Eating out": "Restaurantes",
  "Food delivery": "Delivery",
  "Travel": "Viagem",
  "Airport and airlines": "Aéreo",
  "Accommodation": "Hospedagem",
  "Mileage programs": "Programas de milhas",
  "Bus tickets": "Passagens de ônibus",
  "Donations": "Doações",
  "Gambling": "Apostas",
  "Lottery": "Loteria",
  "Online bet": "Apostas online",
  "Taxes": "Impostos",
  "Income taxes": "Imposto de renda",
  "Taxes on investments": "Impostos sobre investimentos",
  "Tax on financial operations": "IOF",
  "Bank fees": "Tarifas bancárias",
  "Account fees": "Tarifa de conta",
  "Wire transfer fees and ATM fees": "Tarifas de transferência e saque",
  "Credit card fees": "Tarifas do cartão",
  "Housing": "Moradia",
  "Rent": "Aluguel",
  "Utilities": "Contas da casa",
  "Water": "Água",
  "Electricity": "Energia",
  "Gas": "Gás",
  "Houseware": "Casa e utilidades",
  "Urban land and building tax": "IPTU",
  "Healthcare": "Saúde",
  "Dentist": "Dentista",
  "Pharmacy": "Farmácia",
  "Optometry": "Ótica",
  "Hospital clinics and labs": "Hospitais, clínicas e exames",
  "Transportation": "Transporte",
  "Taxi and ride-hailing": "Táxi e aplicativos",
  "Public transportation": "Transporte público",
  "Car rental": "Aluguel de carro",
  "Bicycle": "Bicicleta",
  "Automotive": "Automotivo",
  "Gas stations": "Combustível",
  "Parking": "Estacionamento",
  "Tolls and in vehicle payment": "Pedágio e tag",
  "Vehicle ownership taxes and fees": "IPVA e taxas do veículo",
  "Vehicle maintenance": "Manutenção do veículo",
  "Traffic tickets": "Multas de trânsito",
  "Insurance": "Seguros",
  "Life insurance": "Seguro de vida",
  "Home insurance": "Seguro residencial",
  "Health insurance": "Plano de saúde",
  "Vehicle insurance": "Seguro do veículo",
  "Leisure": "Lazer",
  "Other": "Outros",
};

// Categorias próprias do usuário. As despesas da Pluggy são convertidas para estas (o que não casar vira "Outros").
const List<String> mbCategoriasProprias = [
  "Mercado", "Casa", "Saúde", "Transporte", "Alimentação fora", "Lazer",
  "Compras", "Assinaturas", "Educação", "Tarifas", "Família", "Presentes",
];
const String mbCategoriaOutros = "Outros";
// Ajuda ao pai (envio Inter -> Santander respondido como "Ajuda") é gasto em Família.
const String mbCategoriaAjuda = "Família";
// Cashback abate o gasto em Compras (valor positivo numa categoria de despesa).
const String mbCategoriaCashback = "Compras";

const Map<String, List<String>> _pluggyPorCategoriaPropria = {
  "Mercado": ["Groceries"],
  "Casa": [
    "Housing", "Rent", "Utilities", "Water", "Electricity", "Gas", "Houseware",
    "Urban land and building tax", "Home insurance", "Real estate financing",
    "Telecommunications", "Internet", "Mobile",
  ],
  "Saúde": [
    "Healthcare", "Dentist", "Pharmacy", "Optometry", "Hospital clinics and labs",
    "Health insurance", "Wellness and fitness", "Gyms and fitness centers",
    "Sports practice", "Wellness",
  ],
  "Transporte": [
    "Transportation", "Taxi and ride-hailing", "Public transportation", "Car rental",
    "Bicycle", "Automotive", "Gas stations", "Parking", "Tolls and in vehicle payment",
    "Vehicle ownership taxes and fees", "Vehicle maintenance", "Traffic tickets",
    "Vehicle insurance", "Vehicle financing",
  ],
  "Alimentação fora": ["Food and drinks", "Eating out", "Food delivery"],
  "Lazer": [
    "Leisure", "Tickets", "Stadiums and arenas", "Landmarks and museums",
    "Cinema, theater and concerts", "Gaming", "Travel", "Airport and airlines",
    "Accommodation", "Mileage programs", "Bus tickets", "Gambling", "Lottery", "Online bet",
  ],
  "Compras": [
    "Shopping", "Online shopping", "Electronics", "Pet supplies and vet", "Clothing",
    "Kids and toys", "Sports goods", "Office supplies", "Cashback",
  ],
  "Assinaturas": ["Digital services", "Video streaming", "Music streaming", "TV"],
  "Educação": [
    "Education", "Online courses", "University", "School", "Kindergarten",
    "Bookstore", "Student loan",
  ],
  "Tarifas": [
    "Bank fees", "Account fees", "Wire transfer fees and ATM fees", "Credit card fees",
    "Late payment and overdraft costs", "Interests charged", "Tax on financial operations",
    "Taxes", "Income taxes", "Taxes on investments",
  ],
  "Família": ["Alimony"],
  "Presentes": ["Donations"],
};

final Map<String, String> _categoriaPropriaPorPluggy = {
  for (final e in _pluggyPorCategoriaPropria.entries)
    for (final p in e.value) p: e.key
};

String mbCategoriaPropria(String? pluggy) =>
    _categoriaPropriaPorPluggy[pluggy] ?? mbCategoriaOutros;

String mbTraduzirCategoria(String? c) {
  if (c == null || c.isEmpty) return "Sem categoria";
  return mbCategorias[c] ?? c;
}

// Não é gasto: pagamento de fatura, investimentos/poupança e transferência entre minhas contas.
final RegExp _catFora = RegExp(
    r"credit card payment|same person transfer|investment|fixed income|mutual funds|variable income|savings|pension|margin",
    caseSensitive: false);
final RegExp _descFora = RegExp(
    r"pagamento (de |da )?fatura|pgto\.? ?fatura|pagamento recebido|aplica[cç][aã]o|resgate|\bcdb\b|\blci\b|\blca\b|poupan[cç]a|porquinho|tesouro direto",
    caseSensitive: false);

bool mbNaoEhGasto(String? categoria, String? descricao) =>
    _catFora.hasMatch(categoria ?? "") || _descFora.hasMatch(descricao ?? "");

// Resgate do Santander que chega ao Inter: entrada vinda do Santander é transferência, não renda.
final RegExp _descSantander = RegExp(r"santander", caseSensitive: false);

bool mbEhResgateSantander(String? banco, double valor, String? descricao) =>
    valor > 0 &&
    !_descSantander.hasMatch(banco ?? "") &&
    _descSantander.hasMatch(descricao ?? "");

final RegExp _descCashback = RegExp(r"cashback", caseSensitive: false);

bool mbEhCashback(String? categoria, String? descricao, double valor) =>
    valor > 0 &&
    (categoria == "Cashback" || _descCashback.hasMatch(descricao ?? ""));

// Compara estabelecimentos ignorando caixa, acentos, pontuação e o prefixo "Estorno".
String mbNormalizarEstabelecimento(String s) {
  const de = "áàâãäéèêëíìîïóòôõöúùûüç";
  const para = "aaaaaeeeeiiiiooooouuuuc";
  final b = StringBuffer();
  for (final c in s.toLowerCase().split("")) {
    final i = de.indexOf(c);
    b.write(i >= 0 ? para[i] : c);
  }
  return b
      .toString()
      .replaceAll(RegExp(r"^\s*(estorno|devolucao|reembolso)\b"), "")
      .replaceAll(RegExp(r"[^a-z0-9]+"), " ")
      .trim();
}

const int mbJanelaEstornoDias = 60;

// Conta corrente e cartão do Santander são usados por outra pessoa: não entram no app (só poupança e investimentos de lá contam).
// Mesma regra de contaIgnorada no Worker (apps/worker/src/ciclo.js).
final RegExp _bancoIgnorado = RegExp(r"santander", caseSensitive: false);

bool mbContaIgnorada(Map c) =>
    (c["type"] == "CREDIT" ||
        (c["type"] == "BANK" &&
            (c["subtype"] == null || c["subtype"] == "CHECKING_ACCOUNT"))) &&
    _bancoIgnorado.hasMatch("${c["name"] ?? ""} ${c["bank"] ?? ""}");

const String mbCarteiraInvestimentos = mbPrefixo + "investimentos";

class MbInvestimento {
  final String pk;
  final String nome;
  final double saldo;
  final String? banco;
  const MbInvestimento(this.pk, this.nome, this.saldo, this.banco);
}

class MbConta {
  final String walletPk;
  final String nome;
  final bool cartao;
  const MbConta(this.walletPk, this.nome, this.cartao);
}

// Despesa já importada (ou do mesmo pull) que um estorno pode abater.
class MbCompra {
  final String pk;
  final String estabelecimento;
  final int centavos;
  final DateTime data;
  final String categoriaNome;
  final String categoriaPk;
  const MbCompra(this.pk, this.estabelecimento, this.centavos, this.data,
      this.categoriaNome, this.categoriaPk);
}

class MbTransacao {
  final String pk;
  final String nome;
  // Sinal do RenanCash: despesa negativa, receita positiva.
  final double valor;
  final bool receita;
  final String nota;
  final DateTime data;
  final String carteiraPk;
  final String categoriaNome;
  final String categoriaPk;
  final bool pendente;
  // Estorno e cashback entram como valor positivo numa categoria de despesa, para abater o gasto.
  MbTransacao abatendo(String categoriaNome, String categoriaPk) => MbTransacao(
      pk: pk, nome: nome, valor: valor, receita: false, nota: nota, data: data,
      carteiraPk: carteiraPk, categoriaNome: categoriaNome,
      categoriaPk: categoriaPk, pendente: pendente);

  const MbTransacao({
    required this.pk,
    required this.nome,
    required this.valor,
    required this.receita,
    required this.nota,
    required this.data,
    required this.carteiraPk,
    required this.categoriaNome,
    required this.categoriaPk,
    required this.pendente,
  });
}

class MbResultado {
  final String agora;
  final List<MbConta> contas;
  final List<MbTransacao> transacoes;
  // pks ("mb:" + id) das pendentes atuais
  final Set<String> pendentesPks;
  // futuras, ajustadas para fora e fora-de-gasto que não foram importadas
  final int ignoradas;
  final List<Map<String, dynamic>> contasBrutas;
  final Map<String, dynamic> faturas;
  final Map<String, dynamic>? ciclo;
  final List<dynamic> avisos;
  final Map<String, dynamic> config;
  final String? sincronizadoEm;
  // carteiras ("mb:" + id) de contas ignoradas, a apagar se já existirem
  final Set<String> contasIgnoradasPks;
  // null = servidor antigo, sem investimentos (não mexe na carteira)
  final List<MbInvestimento>? investimentos;
  // transações descartadas pelas regras de "não é gasto" (a apagar se já existirem)
  final Set<String> naoGastoPks;
  // categorias próprias (nome -> pk) que precisam existir
  final Map<String, String> categoriasProprias;
  const MbResultado(
    this.agora,
    this.contas,
    this.transacoes,
    this.pendentesPks,
    this.ignoradas, {
    this.contasBrutas = const [],
    this.faturas = const {},
    this.ciclo,
    this.avisos = const [],
    this.config = const {},
    this.sincronizadoEm,
    this.contasIgnoradasPks = const {},
    this.investimentos,
    this.naoGastoPks = const {},
    this.categoriasProprias = const {},
  });
}

String mbPkTransacao(String id) => mbPrefixo + id;
String mbPkConta(String contaId) => mbPrefixo + contaId;
String mbPkInvestimento(String id) => mbPrefixo + "inv:" + id;
String mbPkCategoria(String nome, bool receita) =>
    mbPrefixo + "cat:" + (receita ? "r:" : "d:") + nome;

DateTime _parseData(String? s) {
  final p = RegExp(r"^(\d{4})-(\d{2})-(\d{2})").firstMatch(s ?? "");
  if (p == null) throw FormatException("data inválida: $s");
  // meio-dia local evita virar o dia por fuso
  return DateTime(
      int.parse(p.group(1)!), int.parse(p.group(2)!), int.parse(p.group(3)!), 12);
}

Map<String, dynamic> _mapa(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

MbResultado mbMapearPull(Map<String, dynamic> json, MbContextoCategoria ctx,
    {required String Function(String? catId, String nomeTraduzido, bool receita)
        pkCategoria,
    List<MbCompra> compras = const [],
    List<MbCompra> abatimentos = const [],
    MbRevisoes revisoes = const MbRevisoes()}) {
  final contas = <MbConta>[];
  final brutas = <Map<String, dynamic>>[];
  final cartoes = <String, bool>{};
  final bancos = <String, String>{};
  final ignoradasPks = <String>{};
  for (final c in (json["contas"] as List? ?? const [])) {
    final id = c["id"].toString();
    if (mbContaIgnorada(c)) {
      ignoradasPks.add(mbPkConta(id));
      continue;
    }
    final cartao = c["type"] == "CREDIT";
    cartoes[id] = cartao;
    bancos[id] = (c["bank"] ?? "").toString();
    brutas.add(_mapa(c));
    contas.add(MbConta(mbPkConta(id), (c["name"] ?? id).toString(), cartao));
  }
  final transacoes = <MbTransacao>[];
  int ignoradas = 0;
  final naoGasto = <String>{};
  // Receitas sem ajuste ou regra do usuário: candidatas a estorno de uma compra.
  final estornos = <String>{};
  // Reembolsos da fila com gasto confirmado: pk do reembolso -> pk do gasto.
  final vinculos = <String, String>{};
  final inicioCiclo = _mapa(json["ciclo"])["inicio"] as String?;
  for (final t in (json["transacoes"] as List? ?? const [])) {
    final id = t["id"].toString();
    if (ignoradasPks.contains(mbPkConta(t["account_id"].toString())) ||
        t["scheduled"] == 1 || t["scheduled"] == true) {
      ignoradas++;
      continue;
    }
    final categoria = t["category"] as String?;
    final descricao = (t["description"] ?? t["merchant"] ?? "").toString();
    final bruto = (t["amount"] as num).toDouble();
    final contaId = t["account_id"].toString();
    final cartao = cartoes[contaId] ?? false;
    // Cartão: compra positiva vira despesa (negativa), estorno vira receita. Conta: o sinal já é o do RenanCash.
    final valor = cartao ? -bruto : bruto;
    // Fila "Para revisar" (só conta): a resposta do usuário decide o que Pix e envios ao Santander são.
    // Só vale no ciclo atual (o histórico não é reclassificado) ou onde o usuário já respondeu.
    final noCiclo = inicioCiclo != null &&
        ((t["date"] ?? "").toString().compareTo(inicioCiclo) >= 0);
    final rev = cartao || !(noCiclo || revisoes.decisoes.containsKey(id))
        ? null
        : mbTipoDeRevisao(descricao: descricao, valor: valor, categoria: categoria);
    final resposta = rev == null ? null : revisoes.resposta(id, rev);
    final envioSantander = rev?.tipo == 'envio_santander';
    // Inter -> Santander só é gasto se for "ajuda"; o ajuste do painel não vale aqui (igual ao Worker).
    final gasto = envioSantander ? null : ctx.ajustes[id]?["gasto"];
    if (gasto == 0) {
      ignoradas++;
      continue;
    }
    final foraPelaResposta = (envioSantander && resposta != 'ajuda') ||
        (rev?.tipo == 'pix_recebido' && resposta == 'devolucao');
    if (foraPelaResposta ||
        (gasto != 1 &&
            !(envioSantander && resposta == 'ajuda') &&
            (mbNaoEhGasto(categoria, descricao) ||
                mbEhResgateSantander(bancos[contaId], valor, descricao)))) {
      naoGasto.add(mbPkTransacao(id));
      ignoradas++;
      continue;
    }
    if (valor == 0) {
      ignoradas++;
      continue;
    }
    final receita = valor > 0;
    final ef = mbCategoriaEfetiva(
        txId: id,
        contaId: contaId,
        descricao: descricao,
        categoriaPluggy: categoria,
        receita: receita,
        ctx: ctx);
    // Sem categoria do usuário (ajuste, regra ou servidor): despesa vai para as categorias próprias.
    var nomeCategoria = ef.fonte == 'banco' && !receita
        ? mbCategoriaPropria(categoria)
        : mbTraduzirCategoria(ef.category ?? categoria);
    var categoriaId = ef.categoriaId;
    // Categoria que o próprio usuário escolheu (ajuste ou regra) vale mais que a da fila.
    if (ef.fonte != 'ajuste' && ef.fonte != 'regra') {
      if (envioSantander) {
        nomeCategoria = mbCategoriaAjuda;
        categoriaId = null;
      } else if (rev?.tipo == 'pix_enviado') {
        // Resposta ou memória do destinatário; sem elas, gasto "A classificar" até o usuário responder.
        nomeCategoria = mbCategoriaAClassificar;
        categoriaId = revisoes.categoriaId(id, rev!);
      }
    }
    final pendente = t["status"] == "PENDING";
    final nome = descricao.trim().isEmpty ? "Sem descrição" : descricao.trim();
    // Reembolso e renda decididos na fila não são estorno automático (reembolso abate abaixo, renda é receita).
    final decidida = resposta == 'reembolso' || resposta == 'renda';
    final automatica =
        receita && ef.fonte != 'ajuste' && ef.fonte != 'regra' && !decidida;
    final cashback = automatica && mbEhCashback(categoria, descricao, valor);
    if (automatica && !cashback) estornos.add(mbPkTransacao(id));
    final tx = MbTransacao(
      pk: mbPkTransacao(id),
      nome: nome,
      valor: valor,
      receita: receita,
      nota: pendente ? "Pendente" : "",
      data: _parseData(t["date"] as String?),
      carteiraPk: mbPkConta(contaId),
      categoriaNome: nomeCategoria,
      categoriaPk: pkCategoria(categoriaId, nomeCategoria, receita),
      pendente: pendente,
    );
    // Reembolso abate o gasto como estorno, não entra como renda: o gasto confirmado pelo usuário (se houver)
    // dá a categoria; sem ele, a categoria é a genérica "Outros".
    if (resposta == 'reembolso') {
      final gasto = revisoes.decisoes[id]?['reembolso_de'];
      if (gasto is String) vinculos[mbPkTransacao(id)] = mbPkTransacao(gasto);
    }
    transacoes.add(cashback
        ? tx.abatendo(mbCategoriaCashback,
            pkCategoria(null, mbCategoriaCashback, false))
        : resposta == 'reembolso'
            ? tx.abatendo(mbCategoriaOutros,
                pkCategoria(null, mbCategoriaOutros, false))
            : tx);
  }
  final reservadas = _abaterReembolsosVinculados(transacoes, vinculos, compras);
  _abaterEstornos(transacoes, estornos, compras, abatimentos, reservadas);
  final pendentes = <String>{
    for (final id in (json["pendentes"] as List? ?? const []))
      mbPkTransacao(id.toString())
  };
  return MbResultado(
    (json["agora"] ?? "").toString(),
    contas,
    transacoes,
    pendentes,
    ignoradas,
    contasBrutas: brutas,
    faturas: _mapa(json["faturas"]),
    ciclo: json["ciclo"] is Map ? _mapa(json["ciclo"]) : null,
    avisos: (json["avisos"] as List?) ?? const [],
    config: _mapa(json["config"]),
    sincronizadoEm: json["sincronizado_em"] as String?,
    contasIgnoradasPks: ignoradasPks,
    naoGastoPks: naoGasto,
    categoriasProprias: {
      for (final n in [
        ...mbCategoriasProprias,
        mbCategoriaOutros,
        mbCategoriaAClassificar
      ])
        n: pkCategoria(null, n, false)
    },
    investimentos: json["investimentos"] is List
        ? [
            for (final i in json["investimentos"] as List)
              if (i is Map && i["id"] != null && i["saldo"] is num)
                MbInvestimento(
                    mbPkInvestimento(i["id"].toString()),
                    (i["nome"] ?? "Investimento").toString().trim(),
                    (i["saldo"] as num).toDouble(),
                    i["banco"]?.toString())
          ]
        : null,
  );
}

// Reembolso com gasto confirmado: fica na categoria desse gasto (do mesmo pull ou de pulls anteriores). Se o gasto
// não existe mais, o reembolso segue em "Outros". Devolve os gastos já usados, que estorno automático não pode abater.
Set<String> _abaterReembolsosVinculados(
    List<MbTransacao> transacoes, Map<String, String> vinculos, List<MbCompra> locais) {
  final reservadas = <String>{};
  if (vinculos.isEmpty) return reservadas;
  final gastos = <String, ({String nome, String pk})>{
    for (final c in locais) c.pk: (nome: c.categoriaNome, pk: c.categoriaPk),
    for (final t in transacoes)
      if (t.valor < 0) t.pk: (nome: t.categoriaNome, pk: t.categoriaPk),
  };
  for (var i = 0; i < transacoes.length; i++) {
    final gasto = gastos[vinculos[transacoes[i].pk]];
    if (gasto == null) continue;
    reservadas.add(vinculos[transacoes[i].pk]!);
    transacoes[i] = transacoes[i].abatendo(gasto.nome, gasto.pk);
  }
  return reservadas;
}

// Estorno (mesmo valor e estabelecimento de uma compra nos 60 dias anteriores) abate o gasto: vira valor
// positivo na categoria da compra, em vez de renda. `locais` são compras de pulls anteriores e
// `abatimentosLocais` os estornos já aplicados em pulls anteriores, que já consumiram a compra deles.
void _abaterEstornos(List<MbTransacao> transacoes, Set<String> estornos,
    List<MbCompra> locais, List<MbCompra> abatimentosLocais, Set<String> reservadas) {
  if (estornos.isEmpty) return;
  final pks = {for (final t in transacoes) t.pk};
  final compras = <int, List<MbCompra>>{};
  void add(MbCompra c) => (compras[c.centavos] ??= []).add(c);
  for (final t in transacoes) {
    if (t.valor < 0) {
      add(MbCompra(t.pk, mbNormalizarEstabelecimento(t.nome),
          (-t.valor * 100).round(), t.data, t.categoriaNome, t.categoriaPk));
    }
  }
  locais.where((c) => !pks.contains(c.pk)).forEach(add);

  final usadas = <String>{};
  MbCompra? alvoDe(DateTime data, String nome, int centavos) {
    MbCompra? alvo;
    for (final c in compras[centavos] ?? const <MbCompra>[]) {
      final dias = data.difference(c.data).inDays;
      if (c.estabelecimento != nome ||
          dias < 0 ||
          dias > mbJanelaEstornoDias ||
          usadas.contains(c.pk)) continue;
      if (alvo == null || c.data.isAfter(alvo.data)) alvo = c;
    }
    return alvo;
  }

  final antigos = abatimentosLocais.where((a) => !pks.contains(a.pk)).toList()
    ..sort((a, b) => a.data.compareTo(b.data));
  for (final a in antigos) {
    final alvo = alvoDe(a.data, a.estabelecimento, a.centavos);
    if (alvo != null) usadas.add(alvo.pk);
  }
  usadas.addAll(reservadas);
  // Em ordem cronológica, para o estorno mais antigo ficar com a compra mais antiga.
  final ordem = [
    for (var i = 0; i < transacoes.length; i++)
      if (estornos.contains(transacoes[i].pk)) i
  ]..sort((a, b) {
      final c = transacoes[a].data.compareTo(transacoes[b].data);
      return c != 0 ? c : a.compareTo(b);
    });
  for (final i in ordem) {
    final t = transacoes[i];
    final alvo = alvoDe(
        t.data, mbNormalizarEstabelecimento(t.nome), (t.valor * 100).round());
    if (alvo == null) continue;
    usadas.add(alvo.pk);
    transacoes[i] = t.abatendo(alvo.categoriaNome, alvo.categoriaPk);
  }
}
