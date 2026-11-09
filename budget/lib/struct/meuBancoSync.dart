import 'dart:async';
import 'dart:convert';
import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/mbSync/categoriaEfetiva.dart';
import 'package:budget/struct/meuBancoMapping.dart';
import 'package:budget/struct/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

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

Future<String?> meuBancoLerToken() async {
  try {
    return await _storage.read(key: _chaveToken);
  } catch (e) {
    debugPrint("Meu Banco: falha ao ler o token do armazenamento seguro: $e");
    return null;
  }
}

Future<String> meuBancoLerUrl() async {
  try {
    final u = await _storage.read(key: _chaveUrl);
    if (u != null && u.trim().isNotEmpty) return u.trim();
  } catch (e) {
    debugPrint("Meu Banco: falha ao ler a URL do armazenamento seguro: $e");
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
  meuBancoUltimoErro.value = null;
  meuBancoUltimaSync.value = null;
}

// Retorna true se sincronizou. Nunca lança: guarda a última mensagem em meuBancoUltimoErro.
Future<bool> sincronizarMeuBanco() async {
  if (meuBancoSincronizando.value) return false;
  final token = await meuBancoLerToken();
  if (token == null || token.isEmpty) return false; // não configurado: silencioso
  meuBancoSincronizando.value = true;
  try {
    final base = await meuBancoLerUrl();
    final desde = appStateSettings[_chaveDesde];
    final uri = Uri.parse(base + "/api/sync").replace(
        queryParameters: desde is String && desde.isNotEmpty
            ? {"desde": desde}
            : null);
    // O token nunca sai por conexão sem criptografia.
    if (uri.scheme != "https") {
      throw "O endereço do Meu Banco precisa começar com https://";
    }
    final resp = await http.get(uri, headers: {
      "Authorization": "Bearer " + token,
      "Accept": "application/json",
    }).timeout(const Duration(seconds: 45));
    if (resp.statusCode == 401) {
      throw "Token inválido ou revogado. Gere um novo token no Meu Banco.";
    }
    if (resp.statusCode == 400) {
      throw "O servidor recusou o pedido (data inicial inválida).";
    }
    if (resp.statusCode != 200) {
      throw "O Meu Banco respondeu com erro ${resp.statusCode}.";
    }
    final resultado =
        mbMapearPull(
            json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>,
            MbContextoCategoria.deRegistros(const []),
            pkCategoria: (_, nome, receita) => mbPkCategoria(nome, receita));
    await _aplicar(resultado);
    if (resultado.agora.isNotEmpty) {
      await updateSettings(_chaveDesde, resultado.agora,
          updateGlobalState: false);
    }
    meuBancoUltimoErro.value = null;
    meuBancoUltimaSync.value = DateTime.now();
    return true;
  } on TimeoutException {
    meuBancoUltimoErro.value = "Tempo esgotado ao falar com o Meu Banco.";
  } on http.ClientException catch (e) {
    meuBancoUltimoErro.value = "Sem conexão com o Meu Banco: " + e.message;
  } catch (e) {
    meuBancoUltimoErro.value = e.toString();
  } finally {
    meuBancoSincronizando.value = false;
  }
  return false;
}

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
    );
  }
  // Upsert idempotente: o pk "mb:<id>" é preservado (insert false => insertOrReplace pelo pk).
  for (final t in r.transacoes) {
    await database.createOrUpdateTransaction(
      Transaction(
        transactionPk: t.pk,
        name: t.nome,
        amount: t.valor,
        note: t.nota,
        categoryFk: t.categoriaPk,
        walletFk: t.carteiraPk,
        dateCreated: t.data,
        dateTimeModified: null,
        originalDateDue: t.data,
        income: t.receita,
        paid: true,
        skipPaid: false,
        methodAdded: MethodAdded.csv,
      ),
      updateSharedEntry: false,
    );
  }
  // Pendente importada que saiu de ids_pendentes some (virou lançada com outro id ou foi cancelada).
  for (final conta in r.contas) {
    final daCarteira =
        await database.getAllTransactionsFromWallet(conta.walletPk);
    for (final t in daCarteira) {
      if (t.transactionPk.startsWith(mbPrefixo) &&
          t.note == "Pendente" &&
          !r.pendentesPks.contains(t.transactionPk)) {
        await database.deleteTransaction(t.transactionPk,
            updateSharedEntry: false);
      }
    }
  }
}
