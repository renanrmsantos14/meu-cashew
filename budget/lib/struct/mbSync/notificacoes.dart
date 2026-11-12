import 'dart:convert';
import 'dart:ui';

import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/struct/mbSync/armazem.dart';
import 'package:budget/struct/mbSync/cliente.dart';
import 'package:budget/struct/mbSync/revisao.dart';
import 'package:budget/struct/meuBancoSync.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Notificações do Meu Banco no celular: o Worker manda cada alerta com `chave` e, nos de "Para revisar", o
// `item` da fila. O payload leva os dois, para responder pelos botões sem abrir o app.

const String mbPrefixoPayload = 'mb:';

const Map<String, String> _rotulos = {
  'emprestimo': 'Empréstimo',
  'investimento': 'Investimento',
  'ajuda': 'Ajuda',
  'devolucao': 'Devolução',
  'reembolso': 'Reembolso',
  'renda': 'Renda',
};

String mbPayloadAlerta(Map<String, dynamic> n) =>
    mbPrefixoPayload + jsonEncode({'chave': '${n['chave']}', if (n['item'] != null) 'item': n['item']});

/// Botões da notificação: as respostas do item. Reembolso precisa escolher o gasto, então abre o app.
List<AndroidNotificationAction> mbAcoesDoAlerta(Map<String, dynamic> n) {
  final item = MbItemRevisao.tentar(n['item']);
  if (item == null) return const [];
  return [
    for (final r in item.respostas)
      AndroidNotificationAction(r, _rotulos[r] ?? r,
          showsUserInterface: r == 'reembolso', cancelNotification: r != 'reembolso')
  ];
}

/// Responde a fila pelo botão da notificação. `false` quando não há o que fazer (toque simples, item que já
/// saiu da fila, resposta que pede o app).
Future<bool> mbResponderPelaNotificacao(String? payload, String? acao,
    {MbCliente? clienteParaTeste}) async {
  if (payload == null || !payload.startsWith(mbPrefixoPayload) || acao == null || acao.isEmpty) return false;
  if (acao == 'reembolso') return false;
  final Object? json;
  try {
    json = jsonDecode(payload.substring(mbPrefixoPayload.length));
  } catch (_) {
    return false;
  }
  final item = MbItemRevisao.tentar(json is Map ? json['item'] : null);
  if (item == null || !item.respostas.contains(acao)) return false;
  // O aviso chega antes da próxima sincronização: puxa o que houver (offline segue com o que tem) e só barra
  // se já existe decisão para a transação, vinda deste ou de outro aparelho.
  await sincronizarMeuBanco(clienteParaTeste: clienteParaTeste);
  final espelho = await mbLerEspelho(tabela: 'revisoes');
  final revisoes = MbRevisoes.deRegistros([for (final e in espelho.values) e.registro]);
  if (revisoes.decisoes.containsKey(item.txId)) return false;
  await mbResponderRevisao(item, acao, clienteParaTeste: clienteParaTeste);
  return true;
}

/// Isolate de segundo plano (botão da notificação com o app fechado) nasce sem os globais do `main`.
Future<void> mbPrepararIsolate() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    sharedPreferences;
  } on Error {
    sharedPreferences = await SharedPreferences.getInstance();
  }
  try {
    database;
  } on Error {
    database = await constructDb('db');
  }
}

Future<void> mbTratarRespostaNotificacao(NotificationResponse r) async {
  if (r.payload?.startsWith(mbPrefixoPayload) != true) return;
  try {
    await mbPrepararIsolate();
    await mbResponderPelaNotificacao(r.payload, r.actionId);
  } catch (e) {
    if (kDebugMode) debugPrint('Meu Banco: falha ao responder pela notificação: $e');
  }
}
