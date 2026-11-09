import 'dart:convert';

import 'package:budget/struct/mbSync/armazem.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

const String _providerAndroid = 'MeuBancoWidgetProvider';

String _brl(num v) =>
    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(v);

num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

Future<Map<String, dynamic>> _resumoDoEstado() async {
  Future<dynamic> ler(String chave) async {
    final s = await mbLerEstado(chave);
    return s == null ? null : jsonDecode(s);
  }

  final ciclo = (await ler('ciclo') as Map?)?.cast<String, dynamic>() ?? {};
  final contas = (await ler('contas') as List?) ?? const [];
  return {
    'disponivel': contas
        .whereType<Map>()
        .where((c) => c['type'] == 'BANK')
        .fold<num>(0, (s, c) => s + _n(c['balance'])),
    'consumido': ciclo['consumido'],
    'limite': ciclo['limite'],
    'percentual': ciclo['percentual'],
    'sincronizado_em': await mbLerEstado('sincronizado_em'),
  };
}

Future<void> mbAtualizarWidget({Map<String, dynamic>? resumo}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final r = resumo ?? await _resumoDoEstado();
    final consumido = _n(r['consumido']);
    final limite = r['limite'] == null ? null : _n(r['limite']);
    final pct = (r['percentual'] == null
            ? (limite != null && limite > 0 ? consumido / limite * 100 : 0)
            : _n(r['percentual']))
        .round()
        .clamp(0, 100);
    final sinc = DateTime.tryParse('${r['sincronizado_em'] ?? ''}')?.toLocal();
    await HomeWidget.saveWidgetData<String>(
        'mb_disponivel', _brl(_n(r['disponivel'])));
    await HomeWidget.saveWidgetData<String>(
        'mb_gasto',
        limite == null
            ? _brl(consumido)
            : '${_brl(consumido)} de ${_brl(limite)}');
    await HomeWidget.saveWidgetData<String>('mb_pct', '$pct');
    await HomeWidget.saveWidgetData<String>(
        'mb_alerta', limite != null && consumido >= limite ? '1' : '0');
    await HomeWidget.saveWidgetData<String>(
        'mb_sinc', sinc == null ? '' : 'Sinc. ${DateFormat('HH:mm').format(sinc)}');
    await HomeWidget.updateWidget(androidName: _providerAndroid);
  } catch (e) {
    if (kDebugMode) debugPrint('Meu Banco: falha ao atualizar o widget: $e');
  }
}
