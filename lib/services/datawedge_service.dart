import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class DataWedgeService {
  // Canal nativo para comunicação com o DataWedge
  static const MethodChannel _channel = MethodChannel(
    'com.example.tracx/datawedge',
  );

  // Notificador de QR Codes lidos
  static final ValueNotifier<String?> scanData = ValueNotifier(null);

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Inicializa o serviço e configura o profile
  static Future<void> init() async {
    if (!_isAndroid) {
      if (kDebugMode) {
        print('[DataWedgeService] Ignorando init: plataforma não suportada');
      }
      return;
    }

    // Define o listener de métodos recebidos do Android
    _channel.setMethodCallHandler(_handleMethodCall);

    // Configura o profile do DataWedge
    await configureProfile();
  }

  /// Configura/ativa um profile do DataWedge
  static Future<void> configureProfile() async {
    if (!_isAndroid) {
      return;
    }

    try {
      await _channel.invokeMethod('configureProfile', {
        'profileName': 'TracxFlutterProfile',
        'intentAction': 'com.example.tracx.SCAN',
      });
      if (kDebugMode) {
        print('[DataWedgeService] Profile configurado com sucesso');
      }
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('[DataWedgeService] Erro ao configurar profile: ${e.message}');
      }
    } on MissingPluginException catch (e) {
      if (kDebugMode) {
        print('[DataWedgeService] Canal não disponível: ${e.message}');
      }
    }
  }

  /// Recebe métodos do Android
  static Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onScan') {
      final args = call.arguments;
      String? data;
      if (args is Map && args.containsKey('data')) {
        data = args['data'] as String?;
      } else if (args is String) {
        // fallback caso venha string direta
        data = args;
      }

      if (data != null && data.isNotEmpty) {
        if (kDebugMode) {
          print('[DataWedgeService] Código recebido: $data');
        }
        scanData.value = data;
      }
    }
  }
}
