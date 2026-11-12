import 'package:budget/struct/mbSync/detectar.dart';

const String prefixoCashew = 'cashew:';
String idDoPk(String pk) => prefixoCashew + pk;
String pkDoId(String id) =>
    id.startsWith(prefixoCashew) ? id.substring(prefixoCashew.length) : id;

String _dois(int n) => n.toString().padLeft(2, '0');
String dataLocal(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_dois(d.month)}-${_dois(d.day)}';
DateTime dataDeTexto(String yyyymmdd) {
  final p = yyyymmdd.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2], 12);
}

String _cortar(String s) => s.length > 200 ? s.substring(0, 200) : s;
String? _pkOuNulo(Object? id) => id == null ? null : pkDoId(id as String);

class CatLocal {
  final String pk, nome;
  final bool receita;
  final String? cor, icone, paiPk;
  final int ordem;
  final DateTime? modificadoEm;
  const CatLocal({
    required this.pk,
    required this.nome,
    required this.receita,
    this.cor,
    this.icone,
    this.paiPk,
    this.ordem = 0,
    this.modificadoEm,
  });
}

class OrcLocal {
  final String pk, nome;
  final double valor;
  final List<String>? categoriaPks;
  final DateTime? modificadoEm;
  const OrcLocal({
    required this.pk,
    required this.nome,
    required this.valor,
    this.categoriaPks,
    this.modificadoEm,
  });
}

class ObjLocal {
  final String pk, nome;
  final bool divida, receita;
  final double valor;
  final DateTime? prazo, modificadoEm;
  const ObjLocal({
    required this.pk,
    required this.nome,
    required this.divida,
    this.receita = false,
    required this.valor,
    this.prazo,
    this.modificadoEm,
  });
}

class LancLocal {
  final String pk, nome, nota, categoriaPk, carteiraNome;
  final double valor;
  final DateTime data;
  final String? metaPk, dividaPk;
  // Escolha de orçamentos (pks); null = padrão (Geral). `limparOrcamentos`: o servidor tem uma escolha antiga a apagar.
  final Set<String>? orcamentoPks;
  final bool limparOrcamentos;
  final DateTime? modificadoEm;
  const LancLocal({
    required this.pk,
    required this.nome,
    this.nota = '',
    required this.valor,
    required this.categoriaPk,
    required this.carteiraNome,
    required this.data,
    this.metaPk,
    this.dividaPk,
    this.orcamentoPks,
    this.limparOrcamentos = false,
    this.modificadoEm,
  });
}

class AssinLocal {
  final String pk, nome, categoriaPk;
  final double valor;
  final int dia;
  final DateTime? modificadoEm;
  const AssinLocal({
    required this.pk,
    required this.nome,
    required this.valor,
    required this.dia,
    required this.categoriaPk,
    this.modificadoEm,
  });
}

class RegraLocal {
  final String pk, titulo, categoriaPk;
  final bool exato;
  final DateTime? modificadoEm;
  const RegraLocal({
    required this.pk,
    required this.titulo,
    required this.categoriaPk,
    required this.exato,
    this.modificadoEm,
  });
}

Map<String, dynamic> projetarCategoria(CatLocal c) => {
      'nome': _cortar(c.nome),
      'tipo': c.receita ? 'receita' : 'despesa',
      'cor': c.cor,
      'icone': c.icone,
      'pai_id': c.paiPk == null ? null : idDoPk(c.paiPk!),
      'ordem': c.ordem,
    };

Map<String, dynamic> projetarOrcamento(OrcLocal o) => {
      'nome': _cortar(o.nome),
      'valor': o.valor,
      'categoria_ids': (o.categoriaPks ?? <String>[]).map(idDoPk).toList()
        ..sort(),
      // Todo orçamento segue o ciclo do salário; sem isso o Worker usaria o mês civil ("mensal").
      'periodo': 'ciclo',
    };

/// Campo `orcamento_ids` (ids com prefixo, ordenados); `null` apaga a escolha antiga do servidor; ausente = nada a dizer.
Map<String, dynamic> _orcamentoIds(Set<String>? pks, bool limpar) => pks != null
    ? {'orcamento_ids': (pks.map(idDoPk).toList()..sort())}
    : limpar
        ? {'orcamento_ids': null}
        : const {};

Map<String, dynamic> projetarObjetivo(ObjLocal o) => o.divida
    ? {
        'tipo': 'emprestimo',
        'nome': _cortar(o.nome),
        'sentido': o.receita ? 'me_devem' : 'devo',
        'valor_total': o.valor,
      }
    : {
        'nome': _cortar(o.nome),
        'valor_alvo': o.valor,
        'prazo': o.prazo == null ? null : dataLocal(o.prazo!),
      };

Map<String, dynamic> projetarLancamento(LancLocal l) {
  final nome = l.nome.trim();
  final nota = l.nota.trim();
  return {
    'data': dataLocal(l.data),
    'descricao': nome.isEmpty ? 'Sem descrição' : _cortar(nome),
    'valor': l.valor,
    'categoria_id': idDoPk(l.categoriaPk),
    'carteira': l.carteiraNome.isEmpty ? null : _cortar(l.carteiraNome),
    'nota': nota.isEmpty ? null : _cortar(nota),
    'meta_id': l.metaPk == null ? null : idDoPk(l.metaPk!),
    'divida_id': l.dividaPk == null ? null : idDoPk(l.dividaPk!),
    ..._orcamentoIds(l.orcamentoPks, l.limparOrcamentos),
  };
}

Map<String, dynamic> projetarAssinatura(AssinLocal a) => {
      'nome': _cortar(a.nome),
      'valor': a.valor.abs(),
      'dia': a.dia,
      'categoria_id': idDoPk(a.categoriaPk),
    };

Map<String, dynamic>? projetarRegra(RegraLocal r, Map<String, dynamic>? base) {
  if (r.titulo.trim().isEmpty || r.titulo.contains('*')) return null;
  final b = base?['padrao'];
  var padrao = r.exato ? r.titulo : '*${r.titulo}*';
  if (b is String &&
      b.replaceAll(RegExp(r'^\*|\*$'), '') == r.titulo &&
      !b.contains('*') == r.exato) {
    padrao = b;
  }
  return {'padrao': _cortar(padrao), 'categoria_id': idDoPk(r.categoriaPk)};
}

CatLocal categoriaDeDados(String id, Map<String, dynamic> d) => CatLocal(
      pk: pkDoId(id),
      nome: d['nome'] as String,
      receita: d['tipo'] == 'receita',
      cor: d['cor'] as String?,
      icone: d['icone'] as String?,
      paiPk: _pkOuNulo(d['pai_id']),
      ordem: (d['ordem'] as num?)?.toInt() ?? 0,
    );

OrcLocal orcamentoDeDados(String id, Map<String, dynamic> d) => OrcLocal(
      pk: pkDoId(id),
      nome: d['nome'] as String,
      valor: (d['valor'] as num).toDouble(),
      categoriaPks: [
        for (final c in (d['categoria_ids'] as List? ?? const [])) pkDoId(c as String)
      ],
    );

ObjLocal objetivoDeDados(String id, Map<String, dynamic> d,
    {required bool divida}) {
  final prazo = d['prazo'] as String?;
  return ObjLocal(
    pk: pkDoId(id),
    nome: d['nome'] as String,
    divida: divida,
    receita: divida && d['sentido'] == 'me_devem',
    valor: ((divida ? d['valor_total'] : d['valor_alvo']) as num).toDouble(),
    prazo: divida || prazo == null ? null : dataDeTexto(prazo),
  );
}

LancLocal lancamentoDeDados(String id, Map<String, dynamic> d,
        {required String categoriaPadrao}) =>
    LancLocal(
      pk: pkDoId(id),
      nome: d['descricao'] as String,
      nota: (d['nota'] as String?) ?? '',
      valor: (d['valor'] as num).toDouble(),
      categoriaPk: _pkOuNulo(d['categoria_id']) ?? categoriaPadrao,
      carteiraNome: (d['carteira'] as String?) ?? '',
      data: dataDeTexto(d['data'] as String),
      metaPk: _pkOuNulo(d['meta_id']),
      dividaPk: _pkOuNulo(d['divida_id']),
      orcamentoPks: orcamentoPksDeDados(d),
    );

/// `orcamento_ids` do registro como pks; `null` (campo ausente) = padrão.
Set<String>? orcamentoPksDeDados(Map<String, dynamic> d) => d['orcamento_ids'] is List
    ? {for (final c in d['orcamento_ids'] as List) pkDoId(c as String)}
    : null;

AssinLocal? assinaturaDeDados(String id, Map<String, dynamic> d,
        {required String categoriaPadrao}) =>
    d['status'] == 'ignorada'
        ? null
        : AssinLocal(
            pk: pkDoId(id),
            nome: d['nome'] as String,
            valor: (d['valor'] as num).toDouble(),
            dia: (d['dia'] as num).toInt(),
            categoriaPk: _pkOuNulo(d['categoria_id']) ?? categoriaPadrao,
          );

final RegExp _padraoSimples = RegExp(r'^\*?[^*]+\*?$');

RegraLocal? regraDeDados(String id, Map<String, dynamic> d) {
  final padrao = d['padrao'] as String?;
  final cat = d['categoria_id'] as String?;
  if (padrao == null || cat == null || !_padraoSimples.hasMatch(padrao)) {
    return null;
  }
  return RegraLocal(
    pk: pkDoId(id),
    titulo: padrao.replaceAll('*', ''),
    categoriaPk: pkDoId(cat),
    exato: !padrao.contains('*'),
  );
}

Projetado? projetarAjuste({
  required String txPk,
  required String? categoriaPkAtual,
  required String? categoriaPkAplicada,
  required bool existeLocal,
  required String nomeCategoria,
  required String? editadoEm,
  bool ajusteDeCategoriaVigente = false,
  Set<String>? orcamentoPks,
  bool limparOrcamentos = false,
}) {
  final id = txPk.startsWith('mb:') ? txPk.substring(3) : txPk;
  Map<String, dynamic>? dados;
  if (categoriaPkAplicada != null) {
    if (!existeLocal) {
      return Projetado('ajustes', id, {'gasto': 0}, editadoEm);
    }
    // Voltar à categoria aplicada com um ajuste ainda vigente precisa sobrescrever o ajuste antigo.
    if (categoriaPkAtual != null &&
        (categoriaPkAtual != categoriaPkAplicada || ajusteDeCategoriaVigente)) {
      dados = {'categoria_id': idDoPk(categoriaPkAtual), 'category': nomeCategoria};
    }
  }
  final orcamentos = existeLocal ? _orcamentoIds(orcamentoPks, limparOrcamentos) : const {};
  if (dados == null && orcamentos.isEmpty) return null;
  return Projetado('ajustes', id, {...?dados, ...orcamentos}, editadoEm);
}
