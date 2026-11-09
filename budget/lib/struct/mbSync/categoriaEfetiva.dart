import 'package:budget/struct/mbSync/registro.dart';
import 'package:budget/struct/meuBancoMapping.dart';

String _escapar(String s) => RegExp.escape(s);

bool mbPadraoCasa(String padrao, String texto) {
  final p = padrao.trim();
  if (p.isEmpty) return false;
  return RegExp('^${p.split('*').map(_escapar).join('.*')}\$',
          caseSensitive: false)
      .hasMatch(texto.trim());
}

class MbEfetiva {
  final String fonte;
  final String? categoriaId;
  final String? category;
  const MbEfetiva(this.fonte, this.categoriaId, this.category);
}

class MbRegraCtx {
  final String id, padrao, categoriaId;
  final String? contaId;
  final num prioridade;
  const MbRegraCtx(
      this.id, this.padrao, this.categoriaId, this.contaId, this.prioridade);
}

class MbContextoCategoria {
  final Map<String, Map<String, dynamic>> ajustes;
  final List<MbRegraCtx> regras;
  final Map<String, String> pluggy;
  final Map<String, String> porNome;
  const MbContextoCategoria(this.ajustes, this.regras, this.pluggy, this.porNome);

  factory MbContextoCategoria.deRegistros(Iterable<Registro> regs) {
    final ajustes = <String, Map<String, dynamic>>{};
    final regras = <MbRegraCtx>[];
    final pluggy = <String, String>{};
    final nomes = <String, String>{};
    for (final r in regs) {
      final d = r.dados;
      if (r.deletedAt != null || d == null) continue;
      if (r.tabela == 'ajustes') {
        ajustes[r.id] = d;
      } else if (r.tabela == 'regras') {
        regras.add(MbRegraCtx(r.id, '${d['padrao']}', '${d['categoria_id']}',
            d['conta_id'] as String?, (d['prioridade'] as num?) ?? 0));
      } else if (r.tabela == 'categorias') {
        for (final p in d['pluggy'] is List ? d['pluggy'] as List : const []) {
          pluggy[p as String] = r.id;
        }
        nomes['${d['tipo']}:${'${d['nome']}'.toLowerCase()}'] = r.id;
      }
    }
    return MbContextoCategoria(ajustes, regras, pluggy, nomes);
  }

  String? _porNome(String nome, bool receita) =>
      porNome['${receita ? 'receita' : 'despesa'}:${nome.toLowerCase()}'];
}

List<MbRegraCtx> mbOrdenarRegras(Iterable<MbRegraCtx> regras) =>
    regras.toList()
      ..sort((a, b) {
        final p = b.prioridade.compareTo(a.prioridade);
        if (p != 0) return p;
        final l = b.padrao.length.compareTo(a.padrao.length);
        return l != 0 ? l : a.id.compareTo(b.id);
      });

String? _preenchido(Object? v) => v is String && v.isNotEmpty ? v : null;

MbEfetiva mbCategoriaEfetiva({
  required String txId,
  required String contaId,
  required String? descricao,
  required String? categoriaPluggy,
  required bool receita,
  required MbContextoCategoria ctx,
}) {
  final a = ctx.ajustes[txId];
  final aCat = _preenchido(a?['categoria_id']);
  if (aCat != null) return MbEfetiva('ajuste', aCat, null);
  final aNome = _preenchido(a?['category']);
  if (aNome != null) {
    return MbEfetiva(
        'ajuste',
        ctx.pluggy[aNome] ?? ctx._porNome(mbTraduzirCategoria(aNome), receita),
        aNome);
  }
  for (final r in mbOrdenarRegras(ctx.regras)) {
    if ((r.contaId == null || r.contaId == contaId) &&
        mbPadraoCasa(r.padrao, descricao ?? '')) {
      return MbEfetiva('regra', r.categoriaId, null);
    }
  }
  final m = categoriaPluggy == null ? null : ctx.pluggy[categoriaPluggy];
  if (m != null) return MbEfetiva('pluggy', m, null);
  final n = ctx._porNome(mbTraduzirCategoria(categoriaPluggy), receita);
  return n != null
      ? MbEfetiva('nome', n, null)
      : MbEfetiva('banco', null, categoriaPluggy);
}
