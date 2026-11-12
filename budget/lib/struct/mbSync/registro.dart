import 'dart:convert';

const List<String> mbTabelas = [
  'categorias',
  'regras',
  'orcamentos',
  'metas',
  'dividas',
  'assinaturas',
  'ajustes',
  'lancamentos',
  'revisoes'
];
const String mbNuncaEditado = '2000-01-01T00:00:00.000Z';

String isoMs(DateTime d) =>
    DateTime.fromMillisecondsSinceEpoch(d.millisecondsSinceEpoch, isUtc: true)
        .toIso8601String();
String normalizarIso(String s) => isoMs(DateTime.parse(s));

Object? _ordenar(Object? v) => v is Map
    ? Map.fromEntries(
        (v.keys.map((k) => k.toString()).toList()..sort())
            .map((k) => MapEntry(k, _ordenar(v[k]))))
    : v is List
        ? v.map(_ordenar).toList()
        : v;
String jsonCanonico(Object? v) => jsonEncode(_ordenar(v));

class Registro {
  final String tabela, id;
  final Map<String, dynamic>? dados;
  final String updatedAt;
  final String? deletedAt;
  const Registro(this.tabela, this.id, this.dados, this.updatedAt, this.deletedAt);

  String get chave => '$tabela/$id';

  factory Registro.fromJson(Map<String, dynamic> j) => Registro(
        j['tabela'] as String,
        j['id'] as String,
        (j['dados'] as Map?)?.cast<String, dynamic>(),
        normalizarIso(j['updated_at'] as String),
        j['deleted_at'] == null ? null : normalizarIso(j['deleted_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'tabela': tabela,
        'id': id,
        'dados': deletedAt != null ? null : dados,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };
}

bool vence(Registro novo, String? atualUpdatedAt) =>
    atualUpdatedAt == null || novo.updatedAt.compareTo(atualUpdatedAt) > 0;

class Espelho {
  final Registro registro;
  final Map<String, dynamic>? projecao;
  final bool pendente;
  final String? motivo;
  const Espelho(this.registro, this.projecao, this.pendente, this.motivo);
}

List<Registro> remotosVencedores(
        Map<String, Espelho> espelho, Iterable<Registro> remotos) =>
    remotos.where((r) => vence(r, espelho[r.chave]?.registro.updatedAt)).toList();
