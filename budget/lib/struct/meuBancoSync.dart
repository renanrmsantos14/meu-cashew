import 'dart:async';
import 'dart:convert';
import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/aplicarLocal.dart';
import 'package:budget/struct/mbSync/armazem.dart';
import 'package:budget/struct/mbSync/categoriaEfetiva.dart';
import 'package:budget/struct/mbSync/cliente.dart';
import 'package:budget/struct/mbSync/detectar.dart';
import 'package:budget/struct/mbSync/mapeamento.dart';
import 'package:budget/struct/mbSync/projetarLocal.dart';
import 'package:budget/struct/mbSync/registro.dart';
import 'package:budget/struct/mbSync/widget.dart';
import 'package:budget/struct/meuBancoMapping.dart';
import 'package:budget/struct/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' show DateFormat;

const String meuBancoUrlPadrao =
    "https://meu-banco.renanrmsantos14.workers.dev";
const String _chaveToken = "meu_banco_token";
const String _chaveUrl = "meu_banco_url";
const String _chaveDesde = "meuBancoDesde";

const FlutterSecureStorage _storage = FlutterSecureStorage();

// Estado para a tela "Meu Banco". Fica só em memória (não vai para backups).
final ValueNotifier<String?> meuBancoUltimoErro = ValueNotifier(null);
final ValueNotifier<DateTime?> meuBancoUltimaSync = ValueNotifier(null);
final ValueNotifier<bool> meuBancoSincronizando = ValueNotifier(false);
final ValueNotifier<MbFila> meuBancoFila = ValueNotifier(const MbFila(0, []));

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

    final json = await cliente.puxar(await mbLerEstado('cursor'));
    final registros = [
      for (final r in (json['registros'] as List? ?? const []))
        Registro.fromJson((r as Map).cast<String, dynamic>())
    ];
    espelho = await mbLerEspelho();
    await mbAplicarRegistros(remotosVencedores(espelho, registros), espelho);
    espelho = await mbLerEspelho();

    final locais = {
      for (final c in await database.select(database.categories).get())
        c.categoryPk
    };
    final ctx = MbContextoCategoria.deRegistros(
        [for (final e in espelho.values) e.registro]);
    final resultado = mbMapearPull(json, ctx,
        pkCategoria: (id, nome, receita) =>
            id != null && locais.contains(pkDoId(id))
                ? pkDoId(id)
                : mbPkCategoria(nome, receita));
    await _aplicar(resultado);

    final estado = <String, String>{
      'contas': jsonEncode(json['contas'] ?? const []),
      'faturas': jsonEncode(json['faturas'] ?? const {}),
      'ciclo': jsonEncode(json['ciclo']),
      'avisos': jsonEncode(json['avisos'] ?? const []),
      'config': jsonEncode(json['config'] ?? const {}),
      'sincronizado_em': '${json['sincronizado_em'] ?? ''}',
    };
    if (resultado.agora.isNotEmpty) estado['cursor'] = resultado.agora;
    await mbGravarEstado(estado);
    await mbAtualizarWidget();
    meuBancoUltimoErro.value = null;
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

Future<void> _aplicar(MbResultado r) async {
  // Carteiras: criadas se faltarem; as existentes não são tocadas (preserva ordem e edições).
  for (final conta in r.contas) {
    if (await database.getWalletInstanceOrNull(conta.walletPk) != null) continue;
    await database.createOrUpdateWallet(TransactionWallet(
      walletPk: conta.walletPk,
      name: conta.nome,
      dateCreated: DateTime.now(),
      dateTimeModified: null,
      order: (await database.getAllWallets()).length,
      currency: conta.moeda,
      decimals: 2,
      homePageWidgetDisplay: defaultWalletHomePageWidgetDisplay,
    ));
  }
  // Categorias por nome: criadas se faltarem.
  final categoriasVistas = <String>{};
  for (final t in r.transacoes) {
    if (!categoriasVistas.add(t.categoriaPk)) continue;
    if (await database.getCategoryInstanceOrNull(t.categoriaPk) != null) continue;
    await database.createOrUpdateCategory(
      TransactionCategory(
        categoryPk: t.categoriaPk,
        name: t.categoriaNome,
        dateCreated: DateTime.now(),
        dateTimeModified: null,
        order: await database.getAmountOfCategories(),
        income: t.receita,
        iconName: "image.png",
        methodAdded: MethodAdded.csv,
      ),
      updateSharedEntry: false,
      customDateTimeModified: _semEdicao,
    );
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
