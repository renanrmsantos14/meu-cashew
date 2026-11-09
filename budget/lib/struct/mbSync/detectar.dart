import 'package:budget/struct/mbSync/registro.dart';

class Projetado {
  final String tabela, id;
  final Map<String, dynamic> dados;
  final String? editadoEm;
  const Projetado(this.tabela, this.id, this.dados, this.editadoEm);
  String get chave => '$tabela/$id';
}

class MudancaLocal {
  final Registro registro;
  final Map<String, dynamic>? projecao;
  const MudancaLocal(this.registro, this.projecao);
}

const Map<String, Map<String, dynamic>> _padroes = {
  'orcamentos': {'periodo': 'mensal', 'categoria_ids': <String>[]},
  'dividas': {'tipo': 'emprestimo'},
  'assinaturas': {'status': 'confirmada'},
};

Map<String, dynamic> completarNovo(String tabela, Map<String, dynamic> d) {
  final r = {...?_padroes[tabela], ...d};
  if (tabela == 'assinaturas' && r['padrao'] == null) {
    r['padrao'] = '${(d['nome'] as String).toUpperCase()}*';
  }
  return r;
}

List<MudancaLocal> detectarMudancasLocais({
  required Map<String, Espelho> espelho,
  required Map<String, Projetado> atuais,
  required String agora,
  Set<String> semExclusaoLocal = const {'ajustes'},
}) {
  final out = <MudancaLocal>[];
  for (final p in atuais.values) {
    final e = espelho[p.chave];
    if (e != null &&
        e.registro.deletedAt == null &&
        e.projecao != null &&
        jsonCanonico(e.projecao) == jsonCanonico(p.dados)) continue;
    if (e != null &&
        e.registro.deletedAt != null &&
        !(p.editadoEm != null &&
            p.editadoEm!.compareTo(e.registro.deletedAt!) > 0)) continue;
    final base = e?.registro.deletedAt == null
        ? (e?.registro.dados ?? const <String, dynamic>{})
        : const <String, dynamic>{};
    final dados = completarNovo(p.tabela, {...base, ...p.dados})
      ..removeWhere((_, v) => v == null);
    var quando = p.editadoEm ?? mbNuncaEditado;
    if (e != null && quando.compareTo(e.registro.updatedAt) <= 0) quando = agora;
    out.add(MudancaLocal(Registro(p.tabela, p.id, dados, quando, null),
        semExclusaoLocal.contains(p.tabela) ? null : p.dados));
  }
  for (final e in espelho.values) {
    final r = e.registro;
    if (e.projecao == null ||
        r.deletedAt != null ||
        semExclusaoLocal.contains(r.tabela) ||
        atuais.containsKey(r.chave)) continue;
    out.add(MudancaLocal(Registro(r.tabela, r.id, null, agora, agora), null));
  }
  return out;
}
