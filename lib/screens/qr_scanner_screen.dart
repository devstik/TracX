import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:camera/camera.dart';

// Cor do foco
const Color focusColor = Colors.lightGreenAccent;

// --- Overlay personalizado ---
class ScannerOverlay extends StatelessWidget {
  const ScannerOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    const double scanAreaSize = 150;

    return Stack(
      children: [
        ColorFiltered(
          colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.srcOut),
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  height: scanAreaSize,
                  width: scanAreaSize,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        Center(
          child: Container(
            width: scanAreaSize,
            height: scanAreaSize,
            decoration: BoxDecoration(
              border: Border.all(color: focusColor, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(Icons.qr_code_scanner, color: focusColor, size: 40),
            ),
          ),
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: 80),
            child: Text(
              'Aponte a câmera para o QR Code',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                shadows: [
                  Shadow(
                    blurRadius: 3,
                    color: Colors.black,
                    offset: Offset(1, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- Tela do Scanner OTIMIZADA ---
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  CameraController? _cameraController;
  bool _isTorchOn = false;
  String? _lastScannedCode;
  int _sameCodeCount = 0;

  // Configurações otimizadas para leitura de QR codes danificados
  final int _tryHarder = 1; // Ativa o modo "try harder"
  final double _scanDelay = 100; // Reduz o delay entre scans

  void _onCodeDetected(Code result) {
    if (result.text != null && result.text!.isNotEmpty) {
      // Validação por redundância: só aceita se ler o mesmo código 2-3 vezes
      if (_lastScannedCode == result.text) {
        _sameCodeCount++;

        // Após 2 leituras idênticas, considera válido
        if (_sameCodeCount >= 2) {
          debugPrint('-----------------------------');
          debugPrint('CONTEÚDO VALIDADO: ${result.text}');
          debugPrint('Leituras confirmadas: $_sameCodeCount');
          debugPrint('-----------------------------');

          if (mounted) {
            Navigator.of(context).pop(result.text);
          }
        }
      } else {
        // Novo código detectado, reinicia a contagem
        _lastScannedCode = result.text;
        _sameCodeCount = 1;
        debugPrint(
          'Novo código detectado (aguardando confirmação): ${result.text}',
        );
      }
    }
  }

  void _onControllerCreated(CameraController? controller, Exception? error) {
    if (error != null) {
      debugPrint('Erro ao criar câmera: $error');
      return;
    }

    if (controller != null && controller.value.isInitialized) {
      _cameraController = controller;
      _configureCameraForOptimalScanning();
    } else {
      _cameraController = null;
    }
  }

  // Configura a câmera para melhor leitura
  Future<void> _configureCameraForOptimalScanning() async {
    final cam = _cameraController;
    if (cam == null || !cam.value.isInitialized) return;

    try {
      // Ativa o foco contínuo se disponível
      if (cam.value.focusMode == FocusMode.auto) {
        await cam.setFocusMode(FocusMode.auto);
      }

      // Define exposição para melhor contraste
      await cam.setExposureMode(ExposureMode.auto);

      debugPrint('Câmera configurada para leitura otimizada');
    } catch (e) {
      debugPrint('Erro ao configurar câmera: $e');
    }
  }

  Future<void> _toggleTorch() async {
    final cam = _cameraController;
    if (cam == null || !cam.value.isInitialized) return;

    try {
      if (_isTorchOn) {
        await cam.setFlashMode(FlashMode.off);
        setState(() => _isTorchOn = false);
      } else {
        await cam.setFlashMode(FlashMode.torch);
        setState(() => _isTorchOn = true);
      }
    } catch (e) {
      debugPrint('Falha ao alternar lanterna: $e');
    }
  }

  @override
  void dispose() {
    _cameraController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Leitor de QR Code'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
            onPressed: _toggleTorch,
            tooltip: _isTorchOn ? 'Desligar Lanterna' : 'Ligar Lanterna',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          ReaderWidget(
            onScan: _onCodeDetected,
            onScanFailure: (code) => debugPrint("Erro de leitura: $code"),

            // CONFIGURAÇÕES OTIMIZADAS PARA QR CODES DANIFICADOS
            tryHarder: true, // Ativa algoritmos mais robustos
            tryInverted: true, // Tenta ler códigos invertidos
            scanDelay: Duration(
              milliseconds: _scanDelay.toInt(),
            ), // Scan mais frequente
            // Ativa múltiplos formatos para melhor detecção
            codeFormat: Format.any, // Aceita qualquer formato
            // Configurações de resolução otimizadas
            resolution:
                ResolutionPreset.high, // Maior resolução para melhor leitura
            // Desativa botões nativos
            showFlashlight: false,
            showToggleCamera: false,
            showGallery: false,

            onControllerCreated: _onControllerCreated,
          ),

          // Overlay personalizado
          const IgnorePointer(ignoring: true, child: ScannerOverlay()),

          // Indicador de status de leitura
          if (_sameCodeCount > 0 && _sameCodeCount < 2)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Validando leitura... ($_sameCodeCount/2)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
