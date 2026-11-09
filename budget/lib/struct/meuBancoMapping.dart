// Mapeamento puro (sem Flutter/Drift) da resposta do Meu Banco para dados do Cashew.
// Espelha public/regras.js do painel do Meu Banco (CATEGORIAS, traduzir, naoEhGasto, valorGasto).

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

class MbConta {
  final String walletPk;
  final String nome;
  final String? moeda;
  final bool cartao;
  const MbConta(this.walletPk, this.nome, this.cartao, {this.moeda});
}

class MbTransacao {
  final String pk;
  final String nome;
  // Sinal do Cashew: despesa negativa, receita positiva.
  final double valor;
  final bool receita;
  final String nota;
  final DateTime data;
  final String carteiraPk;
  final String categoriaNome;
  final String categoriaPk;
  final bool pendente;
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
  // futuras e fora-de-gasto que não foram importadas
  final int ignoradas;
  const MbResultado(
      this.agora, this.contas, this.transacoes, this.pendentesPks, this.ignoradas);
}

String mbPkTransacao(String id) => mbPrefixo + id;
String mbPkConta(String contaId) => mbPrefixo + contaId;
String mbPkCategoria(String nome, bool receita) =>
    mbPrefixo + "cat:" + (receita ? "r:" : "d:") + nome;

DateTime _parseData(String? s) {
  final p = RegExp(r"^(\d{4})-(\d{2})-(\d{2})").firstMatch(s ?? "");
  if (p == null) throw FormatException("data inválida: $s");
  // meio-dia local evita virar o dia por fuso
  return DateTime(
      int.parse(p.group(1)!), int.parse(p.group(2)!), int.parse(p.group(3)!), 12);
}

MbResultado mbMapearResposta(Map<String, dynamic> json) {
  final contas = <MbConta>[];
  final cartoes = <String, bool>{};
  for (final c in (json["contas"] as List? ?? const [])) {
    final id = c["id"].toString();
    final cartao = c["tipo"] == "CREDIT";
    cartoes[id] = cartao;
    contas.add(MbConta(mbPkConta(id), (c["nome"] ?? id).toString(), cartao,
        moeda: "brl"));
  }
  final transacoes = <MbTransacao>[];
  int ignoradas = 0;
  for (final t in (json["transacoes"] as List? ?? const [])) {
    if (t["futura"] == true) {
      ignoradas++;
      continue;
    }
    final categoria = t["categoria"] as String?;
    final descricao = (t["descricao"] ?? t["estabelecimento"] ?? "").toString();
    if (mbNaoEhGasto(categoria, descricao)) {
      ignoradas++;
      continue;
    }
    final bruto = (t["valor"] as num).toDouble();
    final cartao = cartoes[t["conta_id"]] ?? false;
    // Cartão: compra positiva vira despesa (negativa), estorno vira receita. Conta: o sinal já é o do Cashew.
    final valor = cartao ? -bruto : bruto;
    if (valor == 0) {
      ignoradas++;
      continue;
    }
    final receita = valor > 0;
    final nomeCategoria = mbTraduzirCategoria(categoria);
    final pendente = t["status"] == "PENDING";
    final nome = descricao.trim().isEmpty ? "Sem descrição" : descricao.trim();
    transacoes.add(MbTransacao(
      pk: mbPkTransacao(t["id"].toString()),
      nome: nome,
      valor: valor,
      receita: receita,
      nota: pendente ? "Pendente" : "",
      data: _parseData(t["data"] as String?),
      carteiraPk: mbPkConta(t["conta_id"].toString()),
      categoriaNome: nomeCategoria,
      categoriaPk: mbPkCategoria(nomeCategoria, receita),
      pendente: pendente,
    ));
  }
  final pendentes = <String>{
    for (final id in (json["ids_pendentes"] as List? ?? const []))
      mbPkTransacao(id.toString())
  };
  return MbResultado(
      (json["agora"] ?? "").toString(), contas, transacoes, pendentes, ignoradas);
}
