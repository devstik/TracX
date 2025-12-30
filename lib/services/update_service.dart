import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:install_plugin_v3/install_plugin_v3.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tracx/core/config/app_config.dart';

class UpdateService {
  static const String checkUrl = "http://168.190.90.2:5000/update/check";

  /// Verifica se há atualizações disponíveis e exibe o dialog se necessário
  static Future<void> check(
    BuildContext context, {
    bool showMessages = false,
  }) async {
    if (kIsWeb) {
      return;
    }
    // Verifica se é Android antes de prosseguir
    if (!Platform.isAndroid) {
      debugPrint(
        "⚠️ Sistema não é Android - ignorando verificação de atualização",
      );
      if (showMessages && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Atualizações automáticas disponíveis apenas para Android',
            ),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    try {
      // Busca informações da versão local
      final info = await PackageInfo.fromPlatform();
      final localCode = int.parse(info.buildNumber);

      debugPrint("🔍 Verificando atualizações (${AppConfig.appId})...");
      debugPrint("📱 Versão local: ${info.version} (build $localCode)");

      // Adicionamos explicitamente a plataforma na URL para evitar erros de identificação no backend
      final platform = Platform.isAndroid ? 'android' : 'ios';
      final requestUrl = Uri.parse(checkUrl).replace(
        queryParameters: {
          'platform': platform,
          'app': AppConfig.appId, // 👈 AQUI está o isolamento
        },
      );

      debugPrint("🌐 URL do servidor: $requestUrl");

      // Busca informações do servidor com timeout maior
      final res = await http
          .get(requestUrl)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              debugPrint(
                "⏱️  Timeout ao conectar com servidor de atualizações",
              );
              throw Exception("Timeout ao conectar com o servidor");
            },
          );

      debugPrint("📡 Resposta do servidor: ${res.statusCode}");

      if (res.statusCode != 200) {
        debugPrint("❌ Erro ao verificar atualização: ${res.statusCode}");
        if (showMessages && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao verificar atualização: ${res.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      debugPrint("📄 Corpo da resposta: ${res.body}");
      final data = jsonDecode(res.body);

      final int serverCode = data['version_code'] ?? 0;
      final int minVersion = data['min_supported_version'] ?? 0;
      final String apkUrl = data['apk_url'] ?? "";
      final bool force = data['force_update'] ?? false;
      final String versionName = data['version_name'] ?? "";
      final List<String> changelog = data['changelog'] != null
          ? List<String>.from(data['changelog'])
          : [];

      // Se o servidor retornar version_code 0 ou se não houver APK URL (caso do iOS no backend)
      if (serverCode == 0 || apkUrl.isEmpty) {
        debugPrint("ℹ️ Nenhuma atualização disponível para esta plataforma");
        if (showMessages && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('App está atualizado!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      debugPrint("🌐 Versão servidor: $versionName (build $serverCode)");
      debugPrint("⚠️  Versão mínima: $minVersion");
      debugPrint("🔒 Atualização forçada: $force");

      // Verifica se precisa atualizar
      if (localCode < minVersion) {
        debugPrint(
          "🚨 Versão abaixo do mínimo suportado - forçando atualização",
        );
        _showDialog(context, apkUrl, versionName, changelog, force: true);
      } else if (localCode < serverCode) {
        debugPrint("✨ Nova versão disponível");
        _showDialog(context, apkUrl, versionName, changelog, force: force);
      } else {
        debugPrint("✅ App está atualizado");
        if (showMessages && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('App está atualizado!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Erro ao verificar atualização: $e");
      debugPrint("📍 Stack trace: ${StackTrace.current}");

      if (showMessages && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erro: Não foi possível conectar ao servidor'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'Detalhes',
              textColor: Colors.white,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Erro de Conexão'),
                    content: SingleChildScrollView(
                      child: Text(
                        'URL: $checkUrl\n\n'
                        'Erro: $e\n\n'
                        'Verifique:\n'
                        '• Se o servidor está rodando\n'
                        '• Se o IP está correto\n'
                        '• Se há conexão de rede\n'
                        '• Se o firewall não está bloqueando',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      }
    }
  }

  /// Exibe o dialog de atualização
  static void _showDialog(
    BuildContext context,
    String apkUrl,
    String versionName,
    List<String> changelog, {
    bool force = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !force,
      builder: (_) => WillPopScope(
        onWillPop: () async => !force,
        child: AlertDialog(
          title: Text("Atualização do ${AppConfig.appName} disponível"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Nova versão: $versionName",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (changelog.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    "O que mudou:",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...changelog.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("• "),
                          Expanded(child: Text(item)),
                        ],
                      ),
                    ),
                  ),
                ],
                if (force) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.orange),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Esta atualização é obrigatória",
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (!force)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Depois"),
              ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _downloadAndInstall(context, apkUrl);
              },
              child: const Text("Atualizar agora"),
            ),
          ],
        ),
      ),
    );
  }

  /// Faz o download e instala o APK com indicador de progresso
  static Future<void> _downloadAndInstall(
    BuildContext context,
    String url,
  ) async {
    final progressNotifier = ValueNotifier<double>(0.0);
    final downloadingNotifier = ValueNotifier<bool>(true);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            content: ValueListenableBuilder<bool>(
              valueListenable: downloadingNotifier,
              builder: (context, isDownloading, child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDownloading) ...[
                      ValueListenableBuilder<double>(
                        valueListenable: progressNotifier,
                        builder: (context, progress, child) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                value: progress > 0 ? progress : null,
                                strokeWidth: 3,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                progress > 0
                                    ? "Baixando atualização... ${(progress * 100).toStringAsFixed(0)}%"
                                    : "Preparando download...",
                                textAlign: TextAlign.center,
                              ),
                              if (progress > 0) ...[
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.grey[300],
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ] else ...[
                      const Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Download concluído!\nInstalando...",
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final path = "${dir.path}/${AppConfig.appId}_update.apk";

      debugPrint("📥 Iniciando download...");
      await Dio().download(
        url,
        path,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            progressNotifier.value = progress;
          }
        },
      );

      debugPrint("✅ Download concluído");
      downloadingNotifier.value = false;
      await Future.delayed(const Duration(milliseconds: 800));

      if (context.mounted) {
        Navigator.pop(context);
      }

      debugPrint("📦 Instalando APK...");
      await InstallPlugin.installApk(path);
    } catch (e) {
      debugPrint("❌ Erro no download/instalação: $e");
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro ao baixar atualização: $e"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      progressNotifier.dispose();
      downloadingNotifier.dispose();
    }
  }
}
