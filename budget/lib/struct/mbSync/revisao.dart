import 'dart:convert';

import 'package:budget/struct/mbSync/armazem.dart';
import 'package:budget/struct/mbSync/orcamentos.dart';
import 'package:budget/struct/mbSync/emprestimos.dart';
import 'package:budget/struct/mbSync/mapeamento.dart';
import 'package:budget/struct/mbSync/registro.dart';
import 'package:budget/struct/meuBancoMapping.dart';
import 'package:flutter/foundation.dart';

// Fila "Para revisar": o que precisa de uma decisão do usuário no ciclo atual.
//
// Decisões e memória por destinatário ficam na tabela `revisoes` do `registros` (sincronizada entre aparelhos):
//   id `tx:<transação>`  { tipo: "decisao", tx_id, resposta, categoria_id?, valor, data, descricao }
//   id `dest:<nome>`     { tipo: "destinatario", destinatario, categoria_id }
// Empréstimos e devoluções (emprestimos.dart) e reembolsos (`reembolso_de` = id do gasto reembolsado) saem das decisões
// com resposta "emprestimo" | "devolucao" | "reembolso". A regra de tipo é a mesma de apps/worker/src/revisao.js (tipoDeRevisao).

const String mbCategoriaAClassificar = "A classificar";

const List<String> mbRespostasRevisao = [
  'categoria',
  'emprestimo',
  'investimento',
  'ajuda',
  'devolucao',
  'reembolso',
  'renda',
];

class MbTipoRevisao {
  final String tipo; // pix_enviado | envio_santander | pix_recebido
  final String? destinatario;
  const MbTipoRevisao(this.tipo, [this.destinatario]);
}

String mbNormalizarRevisao(String s) {
  const de = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const para = 'AAAAAEEEEIIIIOOOOOUUUUC';
  final b = StringBuffer();
  for (final c in s.toUpperCase().split('')) {
    final i = de.indexOf(c);
    b.write(i >= 0 ? para[i] : c);
  }
  return b.toString().replaceAll(RegExp(r'[^A-Z ]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

final RegExp _pixEnviado = RegExp(r'^PIX (ENVIAD[OA]|ENVIO)\b ?');
final RegExp _pixRecebido = RegExp(r'^PIX (RECEBID[OA]|RECEBIMENTO)\b ?');
final RegExp _santander = RegExp(r'\bSANTANDER\b');
const int _maxDestinatario = 60;

/// Que pergunta a transação gera (ou null). `valor` no sinal do Cashew; só vale para conta (cartão não pergunta).
MbTipoRevisao? mbTipoDeRevisao(
    {required String descricao, required double valor, String? categoria}) {
  final d = mbNormalizarRevisao(descricao);
  if (valor < 0) {
    // Dinheiro do Inter para o Santander: a categoria "transferência entre minhas contas" não impede a pergunta.
    if (_santander.hasMatch(d)) {
      return mbNaoEhGasto(null, descricao) ? null : const MbTipoRevisao('envio_santander');
    }
    if (mbNaoEhGasto(categoria, descricao)) return null;
    final m = _pixEnviado.firstMatch(d);
    if (m == null) return null;
    final fim = (m.end + _maxDestinatario) > d.length ? d.length : m.end + _maxDestinatario;
    final nome = d.substring(m.end, fim).trim();
    return MbTipoRevisao('pix_enviado', nome.isEmpty ? null : nome);
  }
  if (valor > 0 && !mbNaoEhGasto(categoria, descricao) && _pixRecebido.hasMatch(d)) {
    return const MbTipoRevisao('pix_recebido');
  }
  return null;
}

/// Decisões por transação e memória por destinatário, lidas dos registros (ignora os malformados e os apagados).
class MbRevisoes {
  final Map<String, Map<String, dynamic>> decisoes;
  final Map<String, String> destinos;
  const MbRevisoes([this.decisoes = const {}, this.destinos = const {}]);

  factory MbRevisoes.deRegistros(Iterable<Registro> regs) {
    final decisoes = <String, Map<String, dynamic>>{};
    final destinos = <String, String>{};
    for (final r in regs) {
      final d = r.dados;
      if (r.tabela != 'revisoes' || r.deletedAt != null || d == null) continue;
      if (d['tipo'] == 'decisao' && d['tx_id'] is String && d['resposta'] is String) {
        decisoes[d['tx_id'] as String] = d;
      } else if (d['tipo'] == 'destinatario' &&
          d['destinatario'] is String &&
          d['categoria_id'] is String) {
        destinos[d['destinatario'] as String] = d['categoria_id'] as String;
      }
    }
    return MbRevisoes(decisoes, destinos);
  }

  /// Resposta do usuário; no Pix enviado, a memória do destinatário conta como "categoria".
  String? resposta(String txId, MbTipoRevisao tipo) =>
      decisoes[txId]?['resposta'] as String? ??
      (tipo.tipo == 'pix_enviado' && tipo.destinatario != null && destinos.containsKey(tipo.destinatario)
          ? 'categoria'
          : null);

  /// Categoria escolhida para este Pix: a da decisão ou, sem ela, a lembrada para o destinatário.
  String? categoriaId(String txId, MbTipoRevisao tipo) =>
      decisoes[txId]?['categoria_id'] as String? ??
      (tipo.destinatario == null ? null : destinos[tipo.destinatario]);
}

class MbCandidatoSalario {
  final String txId, data, descricao;
  final double valor;
  const MbCandidatoSalario(this.txId, this.data, this.descricao, this.valor);
}

/// Item da fila vindo de `ciclo.revisar` (Worker). `salario_nao_detectado` traz `dias` e `candidatos`.
class MbItemRevisao {
  final String id, tipo;
  final String? txId, data, descricao, destinatario;
  final double valor;
  final int dias;
  final List<MbCandidatoSalario> candidatos;
  const MbItemRevisao(this.id, this.tipo,
      {this.txId,
      this.data,
      this.descricao,
      this.destinatario,
      this.valor = 0,
      this.dias = 0,
      this.candidatos = const []});

  bool get ehSalario => tipo == 'salario_nao_detectado';

  /// Respostas oferecidas para este tipo de item (Pix enviado escolhe a categoria, não aparece aqui).
  List<String> get respostas => switch (tipo) {
        'envio_santander' => const ['emprestimo', 'investimento', 'ajuda'],
        'pix_recebido' => const ['devolucao', 'reembolso', 'renda'],
        _ => const [],
      };

  static MbItemRevisao? tentar(Object? j) {
    if (j is! Map || j['id'] is! String || j['tipo'] is! String) return null;
    final tipo = j['tipo'] as String;
    if (tipo == 'salario_nao_detectado') {
      return MbItemRevisao(j['id'] as String, tipo,
          dias: (j['dias'] as num?)?.toInt() ?? 0, candidatos: [
        for (final c in (j['candidatos'] as List? ?? const []))
          if (c is Map && c['tx_id'] is String && c['valor'] is num)
            MbCandidatoSalario(c['tx_id'] as String, '${c['data']}', '${c['descricao'] ?? ''}',
                (c['valor'] as num).toDouble())
      ]);
    }
    if (j['tx_id'] is! String || j['valor'] is! num) return null;
    return MbItemRevisao(j['id'] as String, tipo,
        txId: j['tx_id'] as String,
        data: j['data'] is String ? j['data'] as String : null,
        descricao: '${j['descricao'] ?? ''}',
        destinatario: j['destinatario'] as String?,
        valor: (j['valor'] as num).toDouble());
  }
}

/// Itens do `ciclo` guardado no último pull (funciona offline). Worker antigo não manda `revisar`: lista vazia.
List<MbItemRevisao> mbItensRevisar(Object? ciclo) => [
      if (ciclo is Map && ciclo['revisar'] is List)
        for (final j in ciclo['revisar'] as List)
          if (MbItemRevisao.tentar(j) case final item?) item
    ];

/// A fila como o usuário a vê: o que já foi respondido neste aparelho (ou no outro, já puxado) some
/// sem esperar a próxima sincronização.
List<MbItemRevisao> mbFilaVisivel(List<MbItemRevisao> itens, MbRevisoes revisoes) => [
      for (final i in itens)
        if (i.ehSalario ||
            (!revisoes.decisoes.containsKey(i.txId) &&
                !(i.tipo == 'pix_enviado' &&
                    i.destinatario != null &&
                    revisoes.destinos.containsKey(i.destinatario))))
          i
    ];

/// Fila que a Início mostra, lida do que está no aparelho.
final ValueNotifier<List<MbItemRevisao>> meuBancoRevisar = ValueNotifier(const []);

Future<void> mbAtualizarRevisar() async {
  try {
    await mbCriarTabelas();
    await mbCarregarCicloCache();
    final texto = await mbLerEstado('ciclo');
    Object? ciclo;
    try {
      ciclo = texto == null ? null : jsonDecode(texto);
    } catch (_) {}
    final espelho = await mbLerEspelho(tabela: 'revisoes');
    final revisoes = MbRevisoes.deRegistros([for (final e in espelho.values) e.registro]);
    meuBancoRevisar.value = mbFilaVisivel(mbItensRevisar(ciclo), revisoes);
    meuBancoEmprestimos.value = mbCalcularEmprestimos(revisoes.decisoes.values);
  } catch (e) {
    if (kDebugMode) debugPrint('Meu Banco: falha ao ler a fila Para revisar: $e');
  }
}

/// Registros a gravar ao responder: a decisão da transação e, no Pix enviado com categoria, a memória do destinatário.
List<Registro> mbRegistrosDeResposta(MbItemRevisao item, String resposta,
    {String? categoriaPk, String? reembolsoDe, required String agora}) {
  final descricao = item.descricao ?? '';
  return [
    Registro(
        'revisoes',
        'tx:${item.txId}',
        {
          'tipo': 'decisao',
          'tx_id': item.txId,
          'resposta': resposta,
          'valor': item.valor,
          'data': item.data,
          'descricao': descricao.length > 200 ? descricao.substring(0, 200) : descricao,
          if (categoriaPk != null) 'categoria_id': idDoPk(categoriaPk),
          if (item.destinatario != null) 'destinatario': item.destinatario,
          // Reembolso: id (sem prefixo "mb:") do gasto que o usuário confirmou como reembolsado.
          if (resposta == 'reembolso' && reembolsoDe != null) 'reembolso_de': reembolsoDe,
        },
        agora,
        null),
    if (resposta == 'categoria' && categoriaPk != null && item.destinatario != null)
      Registro(
          'revisoes',
          'dest:${item.destinatario}',
          {
            'tipo': 'destinatario',
            'destinatario': item.destinatario,
            'categoria_id': idDoPk(categoriaPk),
          },
          agora,
          null),
  ];
}
