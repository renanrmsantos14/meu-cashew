import 'dart:async';
import 'dart:convert';
import 'package:budget/database/tables.dart';
import 'package:budget/pages/addWalletPage.dart'
    show initializeBalanceCorrectionCategory;
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/aplicarLocal.dart';
import 'package:budget/struct/mbSync/armazem.dart';
import 'package:budget/struct/mbSync/categoriaEfetiva.dart';
import 'package:budget/struct/mbSync/cliente.dart';
import 'package:budget/struct/mbSync/detectar.dart';
import 'package:budget/struct/mbSync/mapeamento.dart';
import 'package:budget/struct/mbSync/projetarLocal.dart';
import 'package:budget/struct/mbSync/registro.dart';
import 'package:budget/struct/mbSync/revisao.dart';
import 'package:budget/struct/mbSync/widget.dart';
import 'package:budget/struct/meuBancoMapping.dart';
import 'package:budget/struct/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' show DateFormat;

const String meuBancoUrlPadrao =
    "https://meu-banco.renanrmsantos14.workers.dev";
const String _chaveToken = "meu_banco_token";
const String _chaveUrl = "meu_banco_url";
const String _chaveDesde = "meuBancoDesde";
// Marca a conversão do histórico para as categorias próprias: uma única carga completa refaz as categorias.
const String _chaveConversao = "conv_categorias_v1";
// Uma decisão da fila "Para revisar" (daqui ou de outro aparelho) muda como transações antigas são mapeadas:
// o pull incremental não as traz de volta, então a próxima sincronização refaz a carga completa.
const String _chaveRepuxar = "repuxar_revisoes";

const FlutterSecureStorage _storage = FlutterSecureStorage();

// Estado para a tela "Meu Banco". Fica só em memória (não vai para backups).
final ValueNotifier<String?> meuBancoUltimoErro = ValueNotifier(null);
final ValueNotifier<DateTime?> meuBancoUltimaSync = ValueNotifier(null);
final ValueNotifier<bool> meuBancoSincronizando = ValueNotifier(false);
final ValueNotifier<MbFila> meuBancoFila = ValueNotifier(const MbFila(0, []));
// Verdadeiro quando o app está pareado (token guardado) ou na web, que usa o cookie da mesma origem.
final ValueNotifier<bool> meuBancoPareado = ValueNotifier(kIsWeb);

Future<void> meuBancoVerificarPareado() async {
  meuBancoPareado.value = kIsWeb || (await meuBancoLerToken())?.isNotEmpty == true;
}

Future<String?> meuBancoLerToken() async {
  try {
    return await _storage.read(key: _chaveToken);
  } catch (e) {
    if (kDebugMode) debugPrint("Meu Banco: falha ao ler o token do armazenamento seguro: $e");
    return null;
  }
}

Future<String> meuBancoLerUrl() async {
  try {
    final u = await _storage.read(key: _chaveUrl);
    if (u != null && u.trim().isNotEmpty) return u.trim();
  } catch (e) {
    if (kDebugMode) debugPrint("Meu Banco: falha ao ler a URL do armazenamento seguro: $e");
  }
  return meuBancoUrlPadrao;
}

Future<void> meuBancoSalvarConfig({String? token, String? url}) async {
  if (token != null && token.trim().isNotEmpty) {
    await _storage.write(key: _chaveToken, value: token.trim());
  }
  if (url != null) {
    final u = url.trim().replaceAll(RegExp(r"/+$"), "");
    await _storage.write(key: _chaveUrl, value: u.isEmpty ? meuBancoUrlPadrao : u);
  }
}

// Apaga token e cursor. Não apaga transações já importadas.
Future<void> meuBancoDesconectar() async {
  await _storage.delete(key: _chaveToken);
  meuBancoPareado.value = kIsWeb;
  await updateSettings(_chaveDesde, null, updateGlobalState: false);
  await mbCriarTabelas();
  await mbRemoverEstado('cursor');
  meuBancoUltimoErro.value = null;
  meuBancoUltimaSync.value = null;
}

Future<void> meuBancoAtualizarFila() async {
  try {
    await mbCriarTabelas();
    meuBancoFila.value = await mbLerFila();
    await mbAtualizarRevisar();
  } catch (e) {
    if (kDebugMode) debugPrint("Meu Banco: falha ao ler a fila: $e");
  }
}

// O cursor saiu dos settings (que vão para backups) e passou para mb_estado. Transações
// `mb:` já importadas entram em mb_aplicado, para o usuário poder apagar/recategorizar.
Future<void> _migrarCursorAntigo() async {
  final antigo = appStateSettings[_chaveDesde];
  if (antigo == null) return;
  if (antigo is String &&
      antigo.isNotEmpty &&
      await mbLerEstado('cursor') == null) {
    await mbGravarEstado({'cursor': antigo});
    await mbGravarAplicado({
      for (final t in await database.select(database.transactions).get())
        if (t.transactionPk.startsWith(mbPrefixo)) t.transactionPk: t.categoryFk
    }, const []);
  }
  await updateSettings(_chaveDesde, null, updateGlobalState: false);
}

// Falha de rede no envio não impede o pull; a fila continua para a próxima rodada.
Future<void> _enviarFila(MbCliente cliente) async {
  try {
    while (true) {
      final lote = await mbPendentes();
      if (lote.isEmpty) return;
      final r = await cliente.enviar([for (final e in lote) e.registro]);
      await mbMarcarEnviados(
          lote, {for (final x in r.rejeitados) x.indice: x.motivo});
    }
  } on TimeoutException {
    return;
  } on http.ClientException {
    return;
  }
}

// Puxa e grava no espelho o que venceu. `revisoes` diz se chegou decisão da fila "Para revisar".
Future<({Map<String, dynamic> json, bool revisoes})> _puxarEAplicar(
    MbCliente cliente, String? desde) async {
  final json = await cliente.puxar(desde);
  final registros = [
    for (final r in (json['registros'] as List? ?? const []))
      Registro.fromJson((r as Map).cast<String, dynamic>())
  ];
  final espelho = await mbLerEspelho();
  final vencedores = remotosVencedores(espelho, registros);
  await mbAplicarRegistros(vencedores, espelho);
  return (json: json, revisoes: vencedores.any((r) => r.tabela == 'revisoes'));
}

// Retorna true se sincronizou. Nunca lança: guarda a última mensagem em meuBancoUltimoErro.
Future<bool> sincronizarMeuBanco({MbCliente? clienteParaTeste}) async {
  if (meuBancoSincronizando.value) return false;
  meuBancoSincronizando.value = true;
  try {
    final cliente = clienteParaTeste ?? await mbClienteConfigurado();
    if (cliente == null) return false; // não configurado: silencioso
    await mbCriarTabelas();
    await _migrarCursorAntigo();

    final agora = isoMs(DateTime.now());
    var espelho = await mbLerEspelho();
    final existentes = <String>{};
    final atuais = await mbProjetarLocal(espelho, await mbLerAplicado(),
        agora: agora, existentes: existentes);
    final mudancas = detectarMudancasLocais(
        espelho: espelho,
        atuais: atuais,
        agora: agora,
        existentes: existentes);
    // Ajustes não têm exclusão local, mas guardam a projeção para não serem reenviados a cada rodada.
    await mbGravarEspelho([
      for (final m in mudancas)
        Espelho(m.registro, m.projecao ?? atuais[m.registro.chave]?.dados, true,
            null)
    ]);
    await _enviarFila(cliente);

    final convertido = await mbLerEstado(_chaveConversao) != null;
    final desde = convertido ? await mbLerEstado('cursor') : null;
    final repuxar = await mbLerEstado(_chaveRepuxar);
    final puxado = await _puxarEAplicar(cliente, desde);
    var json = puxado.json;
    if (convertido &&
        (puxado.revisoes || repuxar != null)) {
      json = (await _puxarEAplicar(cliente, null)).json;
    }
    espelho = await mbLerEspelho();

    final categorias = await database.select(database.categories).get();
    final locais = {for (final c in categorias) c.categoryPk};
    // Categoria do Cashew com o mesmo nome e tipo é reutilizada em vez de criar outra "mb:cat:".
    final porNome = {
      for (final c in categorias) '${c.income}:${c.name.toLowerCase()}': c.categoryPk
    };
    final ctx = MbContextoCategoria.deRegistros(
        [for (final e in espelho.values) e.registro]);
    final historico = await _comprasLocais();
    final resultado = mbMapearPull(json, ctx,
        revisoes: MbRevisoes.deRegistros([for (final e in espelho.values) e.registro]),
        compras: historico.compras,
        abatimentos: historico.abatimentos,
        pkCategoria: (id, nome, receita) =>
            id != null && locais.contains(pkDoId(id))
                ? pkDoId(id)
                : porNome['$receita:${nome.toLowerCase()}'] ??
                    mbPkCategoria(nome, receita));
    // Uma transação só: 1 commit em vez de N e 1 notificação aos streams (as telas recarregavam a cada insert).
    await database.transaction(() => _aplicar(resultado));

    final estado = <String, String>{
      'contas': jsonEncode([
        for (final c in (json['contas'] as List? ?? const []))
          if (c is Map && !mbContaIgnorada(c)) c
      ]),
      'faturas': jsonEncode(json['faturas'] ?? const {}),
      'ciclo': jsonEncode(json['ciclo']),
      'avisos': jsonEncode(json['avisos'] ?? const []),
      'config': jsonEncode(json['config'] ?? const {}),
      'sincronizado_em': '${json['sincronizado_em'] ?? ''}',
    };
    if (resultado.agora.isNotEmpty) estado['cursor'] = resultado.agora;
    estado[_chaveConversao] = '1';
    await mbGravarEstado(estado);
    // Resposta dada durante esta sincronização regrava a marca com outro valor e fica para a próxima.
    if (repuxar != null && await mbLerEstado(_chaveRepuxar) == repuxar) {
      await mbRemoverEstado(_chaveRepuxar);
    }
    await mbAtualizarWidget();
    meuBancoUltimoErro.value = null;
    meuBancoPareado.value = true;
    meuBancoUltimaSync.value = DateTime.now();
    return true;
  } on MbErroHttp catch (e) {
    meuBancoUltimoErro.value = e.mensagem;
  } on TimeoutException {
    meuBancoUltimoErro.value = "Tempo esgotado ao falar com o Meu Banco.";
  } on http.ClientException catch (e) {
    if (kDebugMode) debugPrint("Meu Banco: ClientException: ${e.message}");
    meuBancoUltimoErro.value = "Sem conexão com o Meu Banco.";
  } catch (e) {
    if (kDebugMode) debugPrint("Meu Banco: falha na sincronização: $e");
    meuBancoUltimoErro.value = "Não foi possível sincronizar agora.";
  } finally {
    meuBancoSincronizando.value = false;
    await meuBancoAtualizarFila();
  }
  return false;
}

// Transações `mb:` entram com dateTimeModified fixo (2000), para não contarem como edição do usuário.
final DateTime _semEdicao = DateTime.utc(2000);

Future<void> _criarCarteiraSeFaltar(String pk, String nome) async {
  if (await database.getWalletInstanceOrNull(pk) != null) return;
  await database.createOrUpdateWallet(TransactionWallet(
    walletPk: pk,
    name: nome,
    dateCreated: DateTime.now(),
    dateTimeModified: null,
    order: (await database.getAllWallets()).length,
    currency: "brl",
    decimals: 2,
    homePageWidgetDisplay: defaultWalletHomePageWidgetDisplay,
  ));
}

Future<void> _aplicar(MbResultado r) async {
  // Carteiras: criadas se faltarem; as existentes não são tocadas (preserva ordem e edições).
  for (final conta in r.contas) {
    await _criarCarteiraSeFaltar(conta.walletPk, conta.nome);
  }
  // Categorias por nome: criadas se faltarem. As próprias existem sempre, mesmo sem transação.
  final categoriasVistas = <String>{};
  Future<void> criarCategoriaSeFaltar(String pk, String nome, bool receita) async {
    if (!categoriasVistas.add(pk)) return;
    if (await database.getCategoryInstanceOrNull(pk) != null) return;
    await database.createOrUpdateCategory(
      TransactionCategory(
        categoryPk: pk,
        name: nome,
        dateCreated: DateTime.now(),
        dateTimeModified: null,
        order: await database.getAmountOfCategories(),
        income: receita,
        iconName: "image.png",
        methodAdded: MethodAdded.csv,
      ),
      updateSharedEntry: false,
      customDateTimeModified: _semEdicao,
    );
  }

  for (final e in r.categoriasProprias.entries) {
    await criarCategoriaSeFaltar(e.value, e.key, false);
  }
  for (final t in r.transacoes) {
    // Estorno e cashback entram como despesa (valor positivo), então a categoria é de despesa.
    await criarCategoriaSeFaltar(t.categoriaPk, t.categoriaNome, t.receita);
  }
  // Upsert idempotente pelo pk "mb:<id>", direto no Drift (createOrUpdateTransaction marcaria a categoria como editada).
  for (final t in r.transacoes) {
    await database.into(database.transactions).insertOnConflictUpdate(
          TransactionsCompanion(
            transactionPk: Value(t.pk),
            name: Value(t.nome),
            amount: Value(t.valor),
            note: Value(t.nota),
            categoryFk: Value(t.categoriaPk),
            walletFk: Value(t.carteiraPk),
            dateCreated: Value(t.data),
            dateTimeModified: Value(_semEdicao),
            originalDateDue: Value(t.data),
            income: Value(t.receita),
            paid: const Value(true),
            skipPaid: const Value(false),
            methodAdded: const Value(MethodAdded.csv),
          ),
        );
  }
  final removidos = <String>[];
  // Importada antes de virar "não é gasto" (transferência): sai do app, sem ajuste para o servidor.
  if (r.naoGastoPks.isNotEmpty) {
    final alvos = r.naoGastoPks.toList();
    final existentes = await (database.select(database.transactions)
          ..where((t) => t.transactionPk.isIn(alvos)))
        .get();
    removidos.addAll(existentes.map((t) => t.transactionPk));
    // Direto no Drift, como nas contas ignoradas: sem "apagados recentemente".
    await (database.delete(database.transactions)
          ..where((t) => t.transactionPk.isIn(alvos)))
        .go();
  }
  // Conta ignorada importada antes desta regra: apaga a carteira e os lançamentos dela.
  // Os pks saem de mb_aplicado; senão a projeção os veria como apagados e mandaria "não é gasto" ao servidor.
  for (final pk in r.contasIgnoradasPks) {
    if (await database.getWalletInstanceOrNull(pk) == null) continue;
    for (final t in await database.getAllTransactionsFromWallet(pk)) {
      if (t.transactionPk.startsWith(mbPrefixo)) removidos.add(t.transactionPk);
    }
    // Direto no Drift: deleteWallet mandaria os lançamentos para "apagados recentemente".
    await (database.delete(database.transactions)
          ..where((t) => t.walletFk.equals(pk)))
        .go();
    await (database.delete(database.wallets)..where((x) => x.walletPk.equals(pk)))
        .go();
    await database.fixOrderWallets();
  }
  if (r.investimentos != null) await _aplicarInvestimentos(r.investimentos!);
  // Pendente importada que saiu de pendentes some (virou lançada com outro id ou foi cancelada).
  for (final conta in r.contas) {
    final daCarteira =
        await database.getAllTransactionsFromWallet(conta.walletPk);
    for (final t in daCarteira) {
      if (t.transactionPk.startsWith(mbPrefixo) &&
          t.note == "Pendente" &&
          !r.pendentesPks.contains(t.transactionPk)) {
        await database.deleteTransaction(t.transactionPk,
            updateSharedEntry: false);
        removidos.add(t.transactionPk);
      }
    }
  }
  await mbGravarAplicado({for (final t in r.transacoes) t.pk: t.categoriaPk},
      removidos);
}

// Despesas `mb:` já no app: um estorno novo pode abater uma compra de um pull anterior (valor negativo),
// e os abatimentos já aplicados (valor positivo) indicam quais compras já foram abatidas.
Future<({List<MbCompra> compras, List<MbCompra> abatimentos})>
    _comprasLocais() async {
  final compras = <MbCompra>[], abatimentos = <MbCompra>[];
  final linhas = await (database.select(database.transactions)
        ..where((t) =>
            t.transactionPk.like('mb:%') & t.income.equals(false)))
      .get();
  for (final t in linhas) {
    final c = MbCompra(t.transactionPk, mbNormalizarEstabelecimento(t.name),
        (t.amount.abs() * 100).round(), t.dateCreated, '', t.categoryFk);
    if (t.amount < 0) {
      compras.add(c);
    } else if (t.amount > 0) {
      abatimentos.add(c);
    }
  }
  return (compras: compras, abatimentos: abatimentos);
}

// Cada investimento vira um ajuste de saldo (categoria "0", fora de gastos e receitas) na carteira "Investimentos",
// com o saldo atual. A data do primeiro import é mantida para não aparecer como lançamento novo a cada sync.
Future<void> _aplicarInvestimentos(List<MbInvestimento> lista) async {
  final existentes = {
    for (final t
        in await database.getAllTransactionsFromWallet(mbCarteiraInvestimentos))
      t.transactionPk: t
  };
  if (lista.isEmpty && existentes.isEmpty) return;
  await _criarCarteiraSeFaltar(mbCarteiraInvestimentos, "Investimentos");
  await initializeBalanceCorrectionCategory();
  for (final i in lista) {
    final antes = existentes[i.pk];
    final nota = i.banco ?? "";
    if (antes != null &&
        antes.amount == i.saldo &&
        antes.name == i.nome &&
        antes.note == nota) continue;
    final data = antes?.dateCreated ?? DateTime.now();
    await database.into(database.transactions).insertOnConflictUpdate(
          TransactionsCompanion(
            transactionPk: Value(i.pk),
            name: Value(i.nome),
            amount: Value(i.saldo),
            note: Value(nota),
            categoryFk: const Value("0"),
            walletFk: const Value(mbCarteiraInvestimentos),
            dateCreated: Value(data),
            dateTimeModified: Value(_semEdicao),
            originalDateDue: Value(data),
            income: Value(i.saldo > 0),
            paid: const Value(true),
            skipPaid: const Value(false),
            methodAdded: const Value(MethodAdded.csv),
          ),
        );
  }
  // Resgatado (saiu da lista): o saldo some.
  final atuais = {for (final i in lista) i.pk};
  final sairam = [
    for (final pk in existentes.keys)
      if (pk.startsWith(mbPrefixo + "inv:") && !atuais.contains(pk)) pk
  ];
  if (sairam.isNotEmpty) {
    await (database.delete(database.transactions)
          ..where((t) => t.transactionPk.isIn(sairam)))
        .go();
  }
}

// Responde um item da fila "Para revisar" (Início, e depois as notificações do PR 7): grava a decisão no espelho
// (a fila some na hora), manda ao servidor e remapeia as transações. `categoriaPk` só para resposta "categoria".
// Offline ou com falha, a decisão fica pendente e vai na próxima sincronização.
Future<void> mbResponderRevisao(MbItemRevisao item, String resposta,
    {String? categoriaPk, String? reembolsoDe, MbCliente? clienteParaTeste}) async {
  if (item.txId == null || !mbRespostasRevisao.contains(resposta)) return;
  if (resposta == 'categoria' && categoriaPk == null) return;
  await mbCriarTabelas();
  await mbGravarEspelho([
    for (final r in mbRegistrosDeResposta(item, resposta,
        categoriaPk: categoriaPk, reembolsoDe: reembolsoDe, agora: isoMs(DateTime.now())))
      Espelho(r, null, true, null)
  ]);
  await mbGravarEstado({_chaveRepuxar: isoMs(DateTime.now())});
  await mbAtualizarRevisar();
  await sincronizarMeuBanco(clienteParaTeste: clienteParaTeste);
}

// "Salário não detectado": marca a entrada escolhida como salário no servidor e sincroniza. Retorna o erro, se houver.
Future<String?> mbMarcarSalario(String txId) async {
  try {
    final cliente = await mbClienteConfigurado();
    if (cliente == null) return "Pareie o app com o Meu Banco primeiro.";
    await cliente.definirSalario(txId);
    await sincronizarMeuBanco();
    return null;
  } on MbErroHttp catch (e) {
    return e.mensagem;
  } on TimeoutException {
    return "O Meu Banco demorou a responder. Tente de novo.";
  } on http.ClientException {
    return "Sem conexão com o Meu Banco.";
  } catch (e) {
    if (kDebugMode) debugPrint("Meu Banco: falha ao marcar o salário: $e");
    return "Não foi possível marcar o salário agora.";
  }
}

// Pede ao Worker para consultar a Pluggy agora e, se deu certo, sincroniza. Retorna a mensagem do snackbar.
Future<String> meuBancoAtualizar() async {
  try {
    final cliente = await mbClienteConfigurado();
    if (cliente == null) return "Pareie o app com o Meu Banco primeiro.";
    final r = await cliente.atualizar();
    if (r['ok'] == true) {
      await sincronizarMeuBanco();
      return "Atualizado";
    }
    return (r['mensagem'] ?? "Não foi possível atualizar agora.").toString();
  } on MbErroLimite catch (e) {
    final quando = e.liberadoEm?.toLocal();
    if (quando == null) return e.mensagem;
    return "Atualizado há pouco. Tente de novo às ${DateFormat.Hm('pt_BR').format(quando)}.";
  } on MbErroHttp catch (e) {
    return e.status == 401 ? "Token inválido ou revogado. Pareie de novo." : e.mensagem;
  } on TimeoutException {
    return "O Meu Banco demorou a responder. Tente de novo.";
  } on http.ClientException {
    return "Sem conexão com o Meu Banco.";
  } catch (e) {
    if (kDebugMode) debugPrint("Meu Banco: falha ao atualizar: $e");
    return "Não foi possível atualizar agora.";
  }
}
