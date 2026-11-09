import 'dart:async';
import 'dart:convert';

import 'package:budget/struct/mbSync/registro.dart';
import 'package:budget/struct/meuBancoSync.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MbErroHttp implements Exception {
  final int status;
  final String mensagem;
  MbErroHttp(this.status, this.mensagem);
  @override
  String toString() => mensagem;
}

class MbErroLimite extends MbErroHttp {
  final DateTime? liberadoEm;
  MbErroLimite(String mensagem, this.liberadoEm) : super(429, mensagem);
}

class MbCliente {
  MbCliente({required this.base, this.token, http.Client? cliente})
      : _http = cliente ?? http.Client();

  // Android: https com token. Web: mesma origem, a sessão vai por cookie.
  final String base;
  final String? token;
  final http.Client _http;

  Uri _uri(String caminho, [Map<String, String>? query]) {
    final uri = Uri.parse(base + caminho)
        .replace(queryParameters: query == null || query.isEmpty ? null : query);
    final local = uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '10.0.2.2';
    // O token nunca sai por conexão sem criptografia (http só em depuração, para o Worker local).
    if (uri.scheme != 'https' && !kIsWeb && !(kDebugMode && local)) {
      throw 'O endereço do Meu Banco precisa começar com https://';
    }
    return uri;
  }

  Future<Map<String, dynamic>> _chamar(String metodo, String caminho,
      {Map<String, String>? query, Object? corpo}) async {
    final req = http.Request(metodo, _uri(caminho, query));
    req.headers['Accept'] = 'application/json';
    if (token != null && token!.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }
    if (corpo != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(corpo);
    }
    final resp = await http.Response.fromStream(
        await _http.send(req).timeout(const Duration(seconds: 45)));
    Map<String, dynamic> json = {};
    try {
      final j = jsonDecode(utf8.decode(resp.bodyBytes));
      if (j is Map) json = j.cast<String, dynamic>();
    } catch (_) {}
    if (resp.statusCode >= 200 && resp.statusCode < 300) return json;
    final msg = (json['mensagem'] ?? json['erro'])?.toString();
    switch (resp.statusCode) {
      case 401:
        throw MbErroHttp(401,
            'Token inválido ou revogado. Gere um novo token no Meu Banco.');
      case 429:
        throw MbErroLimite(msg ?? 'Atualizado há pouco. Tente de novo em instantes.',
            DateTime.tryParse('${json['liberado_em']}'));
      case 400:
        throw MbErroHttp(400, 'O servidor recusou o pedido${msg == null ? '' : ': $msg'}.');
      default:
        throw MbErroHttp(
            resp.statusCode, 'O Meu Banco respondeu com erro ${resp.statusCode}.');
    }
  }

  Future<Map<String, dynamic>> puxar(String? desde) => _chamar('GET', '/api/sync',
      query: desde == null || desde.isEmpty ? null : {'desde': desde});

  Future<({int aceitos, List<({int indice, String motivo})> rejeitados})> enviar(
      List<Registro> lote) async {
    final j = await _chamar('POST', '/api/sync',
        corpo: {'registros': lote.map((r) => r.toJson()).toList()});
    return (
      aceitos: (j['aceitos'] as num?)?.toInt() ?? 0,
      rejeitados: [
        for (final x in (j['rejeitados'] as List? ?? const []))
          (
            indice: ((x as Map)['indice'] as num).toInt(),
            motivo: '${x['motivo']}'
          )
      ],
    );
  }

  Future<Map<String, dynamic>> atualizar() =>
      _chamar('POST', '/api/sync/atualizar', corpo: const {});

  Future<String> connectToken({String? itemId}) async =>
      (await _chamar('POST', '/api/pluggy/connect-token',
          corpo: {'itemId': itemId}))['accessToken'] as String;

  Future<void> registrarItem(String itemId) async {
    await _chamar('POST', '/api/pluggy/items', corpo: {'itemId': itemId});
  }

  Future<Map<String, dynamic>> notificacoes(String? desde) =>
      _chamar('GET', '/api/notificacoes',
          query: desde == null || desde.isEmpty ? null : {'desde': desde});
}

Future<MbCliente?> mbClienteConfigurado() async {
  if (kIsWeb) return MbCliente(base: Uri.base.origin);
  final token = await meuBancoLerToken();
  if (token == null || token.isEmpty) return null;
  return MbCliente(base: await meuBancoLerUrl(), token: token);
}
