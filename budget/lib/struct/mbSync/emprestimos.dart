import 'package:flutter/foundation.dart';

// Empréstimos ao pai, derivados das decisões da fila "Para revisar" (tabela `revisoes`, sincronizada entre aparelhos):
//   resposta "emprestimo" (envio do Inter ao Santander) abre um empréstimo com o valor da transação;
//   resposta "devolucao" (Pix recebido) abate os empréstimos em aberto.
// Não há registro próprio nem transação no RenanCash: os envios classificados como empréstimo nem entram como gasto.
// Reaproveitar os "objetivos de empréstimo" do RenanCash exigiria criar um objetivo e transações vinculadas por empréstimo,
// que contariam em gastos, orçamentos e saldos das carteiras; derivar das decisões não altera nada disso.
//
// Regra de abatimento (FIFO por data): os eventos são processados em ordem cronológica (no mesmo dia o empréstimo vem
// antes da devolução) e cada devolução quita primeiro o empréstimo aberto mais antigo, depois o seguinte. Devolução maior
// que o devido quita tudo e o excedente é descartado (sem crédito para empréstimos futuros). Devolução anterior a
// qualquer empréstimo conhecido não abate nada.

class MbEmprestimo {
  final String txId;
  final String? data; // yyyy-MM-dd
  final int originalCentavos, restanteCentavos;
  const MbEmprestimo(this.txId, this.data, this.originalCentavos, this.restanteCentavos);

  double get original => originalCentavos / 100;
  double get restante => restanteCentavos / 100;
  bool get parcial => restanteCentavos < originalCentavos;
}

class MbEmprestimos {
  final List<MbEmprestimo> abertos; // do mais antigo para o mais novo
  const MbEmprestimos([this.abertos = const []]);

  double get devido => abertos.fold<int>(0, (s, e) => s + e.restanteCentavos) / 100;

  @override
  bool operator ==(Object o) =>
      o is MbEmprestimos &&
      listEquals([for (final e in abertos) '${e.txId}|${e.restanteCentavos}'],
          [for (final e in o.abertos) '${e.txId}|${e.restanteCentavos}']);

  @override
  int get hashCode => Object.hashAll([for (final e in abertos) e.restanteCentavos]);
}

String? _dia(Object? data) {
  final m = RegExp(r'^\d{4}-\d{2}-\d{2}').firstMatch('${data ?? ''}');
  return m?.group(0);
}

MbEmprestimos mbCalcularEmprestimos(Iterable<Map<String, dynamic>> decisoes) {
  final eventos = <({String dia, bool devolucao, String txId, int centavos})>[];
  for (final d in decisoes) {
    final resposta = d['resposta'];
    final valor = d['valor'];
    if ((resposta != 'emprestimo' && resposta != 'devolucao') || valor is! num) continue;
    final centavos = (valor.abs() * 100).round();
    final dia = _dia(d['data']);
    if (centavos == 0 || dia == null) continue;
    eventos.add((dia: dia, devolucao: resposta == 'devolucao', txId: '${d['tx_id']}', centavos: centavos));
  }
  eventos.sort((a, b) {
    final c = a.dia.compareTo(b.dia);
    if (c != 0) return c;
    if (a.devolucao != b.devolucao) return a.devolucao ? 1 : -1;
    return a.txId.compareTo(b.txId);
  });
  final abertos = <MbEmprestimo>[];
  for (final e in eventos) {
    if (!e.devolucao) {
      abertos.add(MbEmprestimo(e.txId, e.dia, e.centavos, e.centavos));
      continue;
    }
    var sobra = e.centavos;
    for (var i = 0; i < abertos.length && sobra > 0; i++) {
      final a = abertos[i];
      final abate = sobra < a.restanteCentavos ? sobra : a.restanteCentavos;
      sobra -= abate;
      abertos[i] = MbEmprestimo(a.txId, a.data, a.originalCentavos, a.restanteCentavos - abate);
    }
    abertos.removeWhere((a) => a.restanteCentavos == 0);
  }
  return MbEmprestimos(abertos);
}

/// Empréstimos em aberto como a Início os mostra, lidos das decisões do aparelho.
final ValueNotifier<MbEmprestimos> meuBancoEmprestimos = ValueNotifier(const MbEmprestimos());
