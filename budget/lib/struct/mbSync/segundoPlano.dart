import 'dart:ui';

import 'package:budget/struct/mbSync/cliente.dart';
import 'package:budget/struct/mbSync/widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const String mbTarefaAlertas = 'meu-banco-alertas';
const String _chaveCursor = 'mbNotifCursor';
const String _canalId = 'meu_banco_alertas';

// FNV-1a de 31 bits: estável entre execuções (String.hashCode não é).
int mbIdNotificacao(String chave) {
  var h = 0x811c9dc5;
  for (final b in chave.codeUnits) {
    h = ((h ^ (b & 0xff)) * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

Future<int> mbConferirAlertas({
  required MbCliente cliente,
  required Future<void> Function(int id, String titulo, String corpo) mostrar,
  required Future<String?> Function() lerCursor,
  required Future<void> Function(String) gravarCursor,
  required Future<void> Function(Map<String, dynamic> resumo) salvarWidget,
}) async {
  final Map<String, dynamic> r;
  try {
    r = await cliente.notificacoes(await lerCursor());
  } catch (_) {
    return 0;
  }
  final lista = (r['notificacoes'] as List? ?? const []);
  for (final n in lista) {
    final m = (n as Map).cast<String, dynamic>();
    await mostrar(mbIdNotificacao('${m['chave']}'), '${m['titulo'] ?? ''}',
        '${m['corpo'] ?? ''}');
  }
  final cursor = r['cursor'];
  if (cursor is String && cursor.isNotEmpty) await gravarCursor(cursor);
  final resumo = r['resumo'];
  if (resumo is Map) await salvarWidget(resumo.cast<String, dynamic>());
  return lista.length;
}

@pragma('vm:entry-point')
void mbDespachante() {
  Workmanager().executeTask((tarefa, _) async {
    if (tarefa != mbTarefaAlertas) return true;
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      final cliente = await mbClienteConfigurado();
      if (cliente == null) return true;
      final prefs = await SharedPreferences.getInstance();
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      await mbConferirAlertas(
        cliente: cliente,
        mostrar: (id, titulo, corpo) => plugin.show(
            id,
            titulo,
            corpo,
            const NotificationDetails(
                android: AndroidNotificationDetails(
                    _canalId, 'Alertas do Meu Banco',
                    importance: Importance.high, priority: Priority.high))),
        lerCursor: () async => prefs.getString(_chaveCursor),
        gravarCursor: (c) => prefs.setString(_chaveCursor, c),
        salvarWidget: (resumo) => mbAtualizarWidget(resumo: resumo),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Meu Banco: falha nos alertas em segundo plano: $e');
    }
    return true;
  });
}

Future<void> mbRegistrarSegundoPlano() async {
  await Workmanager().initialize(mbDespachante);
  await Workmanager().registerPeriodicTask(mbTarefaAlertas, mbTarefaAlertas,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep);
}
