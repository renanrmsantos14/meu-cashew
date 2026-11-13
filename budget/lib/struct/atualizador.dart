import 'dart:convert';
import 'dart:io';

import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

const String atualizadorUrlLatest =
    "https://api.github.com/repos/renanrmsantos14/meu-cashew/releases/latest";
// Único prefixo aceito para baixar o APK (o GitHub redireciona para o CDN; o redirect é seguido pelo http).
const String _prefixoDownload =
    "https://github.com/renanrmsantos14/meu-cashew/releases/download/";
const int _tamanhoMaximoApk = 300 * 1024 * 1024;
const String _chaveOferta = "atualizacaoOfertada";

/// Resultado de procurar atualização. [versao] é a versão da tag (ex. "5.4.3").
class AtualizacaoDisponivel {
  final String versao;
  final int build;
  final String urlApk;
  final int tamanhoApk;
  const AtualizacaoDisponivel(
      {required this.versao,
      required this.build,
      required this.urlApk,
      required this.tamanhoApk});
}

/// Extrai o buildNumber de uma tag `v<versão>+<build>` (ex. v5.4.3+417 -> 417).
/// Retorna null se a tag não tiver o formato esperado.
int? atualizadorBuildDaTag(String tag) {
  final m = RegExp(r'^v?\d+(?:\.\d+)*\+(\d+)$').firstMatch(tag.trim());
  return m == null ? null : int.parse(m.group(1)!);
}

/// Extrai a versão (sem "v" e sem build) de uma tag. Ex.: v5.4.3+417 -> 5.4.3.
String atualizadorVersaoDaTag(String tag) =>
    tag.trim().replaceFirst(RegExp(r'^v'), '').split('+').first;

/// True se a tag tem buildNumber maior que o do app instalado.
bool atualizadorTagEhMaisNova(String tag, int buildAtual) {
  final build = atualizadorBuildDaTag(tag);
  return build != null && build > buildAtual;
}

/// True só para APKs hospedados nas Releases deste repositório, via https.
bool atualizadorUrlConfiavel(String url) {
  final uri = Uri.tryParse(url)?.normalizePath();
  return uri != null && uri.toString().startsWith(_prefixoDownload);
}

/// Consulta a última Release. Retorna null se não há versão mais nova.
/// Lança exceção em falha de rede/formato (quem chama decide se mostra).
Future<AtualizacaoDisponivel?> atualizadorProcurar() async {
  final buildAtual = int.tryParse(packageInfoGlobal?.buildNumber ?? "") ?? 0;
  final resp = await http.get(Uri.parse(atualizadorUrlLatest), headers: {
    "Accept": "application/vnd.github+json"
  }).timeout(const Duration(seconds: 15));
  if (resp.statusCode != 200) {
    throw Exception("GitHub respondeu ${resp.statusCode}");
  }
  final dados = json.decode(resp.body) as Map<String, dynamic>;
  final tag = (dados["tag_name"] ?? "").toString();
  if (!atualizadorTagEhMaisNova(tag, buildAtual)) return null;
  final assets = (dados["assets"] as List? ?? []).cast<Map<String, dynamic>>();
  final apk = assets.firstWhere(
      (a) => (a["name"] ?? "").toString().toLowerCase().endsWith(".apk"),
      orElse: () => {});
  if (apk.isEmpty) throw Exception("Release sem arquivo .apk");
  final url = apk["browser_download_url"].toString();
  final tamanho = (apk["size"] as num).toInt();
  if (!atualizadorUrlConfiavel(url)) {
    throw Exception("Release com endereço de download não confiável");
  }
  if (tamanho <= 0 || tamanho > _tamanhoMaximoApk) {
    throw Exception("Release com tamanho de APK inválido ($tamanho bytes)");
  }
  return AtualizacaoDisponivel(
    versao: atualizadorVersaoDaTag(tag),
    build: atualizadorBuildDaTag(tag)!,
    urlApk: url,
    tamanhoApk: tamanho,
  );
}

String _hoje() => DateTime.now().toIso8601String().substring(0, 10);

/// Verificação automática (ao abrir o app). Silenciosa em falhas; não bloqueia.
/// Após "Depois", não oferece a mesma versão de novo no mesmo dia.
Future<void> atualizadorVerificarAutomatico(BuildContext context) async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    final nova = await atualizadorProcurar();
    if (nova == null) return;
    if (appStateSettings[_chaveOferta] == "${nova.build}|${_hoje()}") return;
    if (!context.mounted) return;
    await atualizadorMostrarDialogo(context, nova);
  } catch (e) {
    debugPrint("Atualizador (silencioso): $e");
  }
}

/// Botão manual. Retorna mensagem para exibir ao usuário.
Future<String> atualizadorVerificarManual(BuildContext context) async {
  if (kIsWeb || !Platform.isAndroid) return "Atualização dentro do app só no Android.";
  try {
    final nova = await atualizadorProcurar();
    if (nova == null) return "Você já está na versão mais recente.";
    if (!context.mounted) return "";
    await atualizadorMostrarDialogo(context, nova);
    return "";
  } catch (e) {
    return "Não foi possível procurar atualização: $e";
  }
}

Future<void> atualizadorMostrarDialogo(
    BuildContext context, AtualizacaoDisponivel nova) async {
  await openPopup(
    context,
    icon: Icons.system_update_rounded,
    title: "Nova versão ${nova.versao}",
    description: "Baixar e instalar agora?",
    onSubmitLabel: "Atualizar",
    onCancelLabel: "Depois",
    onSubmit: () async {
      Navigator.of(context).pop();
      await atualizadorBaixarEInstalar(context, nova);
    },
    onCancel: () async {
      Navigator.of(context).pop();
      await updateSettings(_chaveOferta, "${nova.build}|${_hoje()}",
          updateGlobalState: false);
    },
  );
}

/// Baixa o APK mostrando progresso, confere o tamanho e abre o instalador.
Future<void> atualizadorBaixarEInstalar(
    BuildContext context, AtualizacaoDisponivel nova) async {
  final progresso = ValueNotifier<double?>(0);
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: Text("Baixando ${nova.versao}"),
      content: ValueListenableBuilder<double?>(
        valueListenable: progresso,
        builder: (_, p, __) =>
            Column(mainAxisSize: MainAxisSize.min, children: [
          LinearProgressIndicator(value: p),
          const SizedBox(height: 10),
          Text(p == null ? "" : "${(p * 100).round()}%"),
        ]),
      ),
    ),
  );
  String? erro;
  File? arquivo;
  try {
    if (!atualizadorUrlConfiavel(nova.urlApk)) {
      throw Exception("endereço de download não confiável");
    }
    final dir = await getTemporaryDirectory();
    arquivo = File("${dir.path}/renancash-${nova.versao}.apk");
    if (await arquivo.exists()) await arquivo.delete();
    final client = http.Client();
    try {
      final resp = await client
          .send(http.Request("GET", Uri.parse(nova.urlApk)))
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) throw Exception("HTTP ${resp.statusCode}");
      final total = nova.tamanhoApk;
      int baixado = 0;
      final sink = arquivo.openWrite();
      try {
        await for (final parte in resp.stream) {
          baixado += parte.length;
          if (baixado > total) throw Exception("arquivo maior que o esperado");
          sink.add(parte);
          progresso.value =
              total > 0 ? (baixado / total).clamp(0.0, 1.0) : null;
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
    final tamanho = await arquivo.length();
    if (tamanho != nova.tamanhoApk) {
      await arquivo.delete();
      throw Exception(
          "arquivo incompleto ($tamanho de ${nova.tamanhoApk} bytes)");
    }
  } catch (e) {
    erro = e.toString();
    try {
      if (arquivo != null && await arquivo.exists()) await arquivo.delete();
    } catch (e) {
      debugPrint("Atualizador: não apagou APK parcial: $e");
    }
  }
  navigator.pop();
  if (erro != null || arquivo == null) {
    if (context.mounted) {
      openSnackbar(SnackbarMessage(
          title: "Falha ao baixar a atualização", description: erro));
    }
    return;
  }
  await OpenFilex.open(arquivo.path,
      type: "application/vnd.android.package-archive");
}
