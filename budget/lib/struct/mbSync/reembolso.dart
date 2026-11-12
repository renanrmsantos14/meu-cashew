import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/revisao.dart';
import 'package:budget/struct/meuBancoMapping.dart';
import 'package:drift/drift.dart';

// Reembolso na fila "Para revisar": o app sugere os gastos dos últimos 15 dias e o usuário confirma qual foi reembolsado.
// O vínculo vai na decisão (`reembolso_de` = id do gasto, sem o prefixo "mb:") e o mapeamento faz o reembolso abater
// aquele gasto, na categoria dele, como um estorno. Sem vínculo, abate em "Outros" (como antes).

const int mbJanelaReembolsoDias = 15;
// "Próximo": diferença de até 20% do valor do gasto (reembolso parcial ou com gorjeta).
const double mbToleranciaReembolso = 0.2;

enum MbAfinidadeReembolso { igual, proximo, outro }

class MbGastoCandidato {
  final String pk, nome, categoria;
  final DateTime data;
  final int centavos;
  const MbGastoCandidato(this.pk, this.nome, this.categoria, this.data, this.centavos);

  double get valor => centavos / 100;
}

typedef MbSugestaoReembolso = ({MbGastoCandidato gasto, MbAfinidadeReembolso afinidade});

DateTime _soDia(DateTime d) => DateTime(d.year, d.month, d.day);

/// Gastos de até 15 dias antes do reembolso (e não depois dele). Um gasto pode ter mais de um reembolso (conta dividida).
/// Ordem: valor igual, valor próximo, os demais; em cada grupo, do mais recente para o mais antigo.
List<MbSugestaoReembolso> mbSugerirReembolso(Iterable<MbGastoCandidato> gastos,
    {required double valor, required DateTime data}) {
  final alvo = (valor.abs() * 100).round();
  final fim = _soDia(data);
  final inicio = DateTime(fim.year, fim.month, fim.day - mbJanelaReembolsoDias);
  final saida = <MbSugestaoReembolso>[];
  for (final g in gastos) {
    final dia = _soDia(g.data);
    if (dia.isBefore(inicio) || dia.isAfter(fim) || g.centavos == 0) continue;
    final afinidade = g.centavos == alvo
        ? MbAfinidadeReembolso.igual
        : (g.centavos - alvo).abs() <= g.centavos * mbToleranciaReembolso
            ? MbAfinidadeReembolso.proximo
            : MbAfinidadeReembolso.outro;
    saida.add((gasto: g, afinidade: afinidade));
  }
  saida.sort((a, b) {
    final c = a.afinidade.index.compareTo(b.afinidade.index);
    if (c != 0) return c;
    final d = b.gasto.data.compareTo(a.gasto.data);
    return d != 0 ? d : a.gasto.pk.compareTo(b.gasto.pk);
  });
  return saida;
}

/// Sugestões para um item "Pix recebido" da fila, lidas do banco do aparelho.
Future<List<MbSugestaoReembolso>> mbSugestoesDoItem(MbItemRevisao item) async {
  final data = DateTime.tryParse(item.data ?? '');
  if (data == null) return const [];
  final inicio = DateTime(data.year, data.month, data.day - mbJanelaReembolsoDias);
  final fim = DateTime(data.year, data.month, data.day + 1);
  final linhas = await (database.select(database.transactions)
        ..where((t) =>
            t.transactionPk.like('$mbPrefixo%') &
            t.transactionPk.like('${mbPrefixo}inv:%').not() &
            t.income.equals(false) &
            t.amount.isSmallerThanValue(0) &
            t.dateCreated.isBiggerOrEqualValue(inicio) &
            t.dateCreated.isSmallerThanValue(fim)))
      .get();
  final categorias = {
    for (final c in await database.select(database.categories).get()) c.categoryPk: c.name
  };
  return mbSugerirReembolso([
    for (final t in linhas)
      MbGastoCandidato(t.transactionPk, t.name, categorias[t.categoryFk] ?? '', t.dateCreated,
          (t.amount.abs() * 100).round())
  ], valor: item.valor, data: data);
}
