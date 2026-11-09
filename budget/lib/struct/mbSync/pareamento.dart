import 'package:budget/struct/mbSync/armazem.dart';
import 'package:budget/struct/meuBancoSync.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:flutter/foundation.dart';

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

// Cursor zerado: o próximo pull é completo (o LWW resolve o que já existe).
Future<void> mbParear(MbPareamento p) async {
  await meuBancoSalvarConfig(token: p.token, url: p.base);
  await mbCriarTabelas();
  await mbRemoverEstado('cursor');
  openSnackbar(SnackbarMessage(title: "Pareado com ${Uri.parse(p.base).host}"));
  await sincronizarMeuBanco();
}
