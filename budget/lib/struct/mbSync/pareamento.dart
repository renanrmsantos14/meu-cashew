import 'package:budget/struct/mbSync/armazem.dart';
import 'package:budget/struct/meuBancoSync.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/meuBancoMapping.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show BuildContext, Icons;

class MbPareamento {
  final String base;
  final String token;
  const MbPareamento(this.base, this.token);
}

final RegExp _tokenValido = RegExp(r'^mb_[A-Za-z0-9_-]{43}$');

// https sem caminho; http só em depuração e só para o Worker local (localhost / emulador).
bool mbOrigemPermitida(String u, {required bool debug}) {
  final uri = Uri.tryParse(u);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return false;
  if (uri.path.isNotEmpty && uri.path != '/') return false;
  if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) return false;
  if (uri.scheme == 'https') return true;
  return debug &&
      uri.scheme == 'http' &&
      (uri.host == 'localhost' || uri.host == '10.0.2.2');
}

MbPareamento? mbLerLinkPareamento(Uri uri) {
  if (uri.scheme != 'meubanco' || uri.host != 'parear') return null;
  final u = uri.queryParameters['u'];
  final t = uri.queryParameters['t'];
  if (u == null || t == null || !_tokenValido.hasMatch(t)) return null;
  if (!mbOrigemPermitida(u, debug: kDebugMode)) return null;
  return MbPareamento(u.replaceAll(RegExp(r'/+$'), ''), t);
}

// Conta nova: apaga o espelho, a fila, o estado e o que foi importado da conta anterior.
// O que nasceu no Cashew fica e é reenviado como novo, porque o espelho está vazio.
Future<void> mbTrocarConta() async {
  await mbCriarTabelas();
  await database.transaction(() async {
    await database.customStatement('DELETE FROM mb_registros');
    await database.customStatement('DELETE FROM mb_aplicado');
    await database.customStatement('DELETE FROM mb_estado');
    await database.customStatement(
        'DELETE FROM transactions WHERE transaction_pk LIKE ?', ['$mbPrefixo%']);
    // Categorias importadas sem uso local saem; as que ainda têm lançamento do Cashew ficam.
    await database.customStatement(
        "DELETE FROM associated_titles WHERE category_fk LIKE 'mb:cat:%'");
    await database.customStatement('''
      DELETE FROM categories WHERE category_pk LIKE 'mb:cat:%'
        AND category_pk NOT IN (SELECT category_fk FROM transactions)
        AND category_pk NOT IN (SELECT sub_category_fk FROM transactions WHERE sub_category_fk IS NOT NULL)
        AND category_pk NOT IN (SELECT category_fk FROM category_budget_limits)
        AND category_pk NOT IN (SELECT main_category_pk FROM categories WHERE main_category_pk IS NOT NULL)''');
  });
}

Future<bool> _contaDiferente(MbPareamento p) async =>
    await meuBancoLerUrl() != p.base;

// Grava o pareamento. Só chamar depois da confirmação do usuário.
Future<void> mbParear(MbPareamento p) async {
  try {
    if (await _contaDiferente(p)) await mbTrocarConta();
    await meuBancoSalvarConfig(token: p.token, url: p.base);
    await mbCriarTabelas();
    await mbRemoverEstado('cursor');
  } catch (e) {
    if (kDebugMode) debugPrint("Meu Banco: falha ao parear: $e");
    openSnackbar(SnackbarMessage(title: "Não foi possível salvar o pareamento."));
    return;
  }
  openSnackbar(SnackbarMessage(title: "Pareado com ${Uri.parse(p.base).host}"));
  if (!await sincronizarMeuBanco() && meuBancoUltimoErro.value != null) {
    openSnackbar(SnackbarMessage(title: meuBancoUltimoErro.value!));
  }
}

// Nunca grava um pareamento sem o usuário ver o host. Retorna true se confirmou e pareou.
Future<bool> mbConfirmarEParear(BuildContext? context, MbPareamento p) async {
  final ctx = context ?? navigatorKey.currentContext;
  final host = Uri.parse(p.base).host;
  final jaPareado = (await meuBancoLerToken())?.isNotEmpty == true;
  final trocaConta = await _contaDiferente(p);
  final avisos = [
    "Só continue se o endereço for o do seu painel do Meu Banco.",
    if (jaPareado)
      "O pareamento atual será substituído.",
    if (trocaConta)
      "Os dados importados da conta anterior serão removidos deste aparelho. O que você criou no Cashew continua.",
  ];
  final confirmou = await openPopup<bool>(
    ctx,
    title: "Parear com $host?",
    description: avisos.join("\n\n"),
    icon: Icons.link_rounded,
    onSubmitLabel: "Parear",
    onSubmit: () => popRoute(ctx, true),
    onCancelLabel: "Cancelar",
    onCancel: () => popRoute(ctx, false),
  );
  if (confirmou != true) return false;
  await mbParear(p);
  return true;
}
