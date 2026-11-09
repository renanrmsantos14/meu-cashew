import 'package:budget/pages/meuBancoConectar.dart';
import 'package:budget/struct/mbSync/cliente.dart';
import 'package:budget/struct/meuBancoSync.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

final RegExp _itemValido = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);

dynamic _no(dynamic m, String k) => m is Map ? m[k] : null;

String? mbItemIdDoSucesso(dynamic data) {
  for (final c in [
    _no(_no(data, 'item'), 'id'),
    _no(data, 'itemId'),
    _no(_no(_no(data, 'data'), 'item'), 'id'),
  ]) {
    if (c is String && _itemValido.hasMatch(c)) return c;
  }
  return null;
}

void _aviso(String msg) => openSnackbar(SnackbarMessage(title: msg));

Future<void> mbAbrirConnect(BuildContext context, {String? itemId}) async {
  if (kIsWeb) {
    _aviso('Conecte bancos pelo app no celular');
    return;
  }
  final MbCliente? cliente = await mbClienteConfigurado();
  if (cliente == null) {
    _aviso('Pareie o app com o Meu Banco antes de conectar um banco.');
    return;
  }
  final String token;
  try {
    token = await cliente.connectToken(itemId: itemId);
  } catch (e) {
    _aviso(_curto(e));
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => MeuBancoConectarPage(
      connectToken: token,
      itemId: itemId,
      onSuccess: (data) async {
        if (kDebugMode) {
          debugPrint('Pluggy onSuccess: ${data.runtimeType} '
              '${data is Map ? data.keys.toList() : ''}');
        }
        final id = mbItemIdDoSucesso(data) ?? itemId;
        if (id == null) {
          _aviso(
              'Conectado, mas o app não recebeu o código da conexão. Ela entra na próxima sincronização pelo webhook.');
          return;
        }
        try {
          await cliente.registrarItem(id);
        } catch (e) {
          _aviso(_curto(e));
          return;
        }
        _aviso('Banco conectado. Sincronizando…');
        Future.delayed(const Duration(seconds: 20), sincronizarMeuBanco);
      },
      onError: (e) => _aviso(_curto(e)),
    ),
  ));
}

String _curto(Object e) {
  final s = e.toString();
  return s.length > 200 ? s.substring(0, 200) : s;
}
