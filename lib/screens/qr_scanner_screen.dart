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
    const double scanAreaSize = 160;

    return Stack(
      children: [
        ColorFiltered(
          colorFilter: const ColorFilter.mode(Colors.black45, BlendMode.srcOut),
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

  // Configurações para Zebra TC26
  final double _scanDelay = 120;

  void _onCodeDetected(Code result) {
    final text = result.text?.trim();
    if (text == null || text.isEmpty) return;

    if (_lastScannedCode == text) {
      _sameCodeCount++;
      if (_sameCodeCount >= 2) {
        if (mounted) Navigator.of(context).pop(text);
      }
    } else {
      _lastScannedCode = text;
      _sameCodeCount = 1;
    }
  }

  void _onControllerCreated(CameraController? controller, Exception? error) {
    if (error != null) {
      debugPrint('Erro ao criar câmera: $error');
      return;
    }

    if (controller != null && controller.value.isInitialized) {
      _cameraController = controller;
      _configureCamera();
    }
  }

  Future<void> _configureCamera() async {
    final cam = _cameraController;
    if (cam == null || !cam.value.isInitialized) return;

    try {
      // Uso de FocusMode.auto por compatibilidade com a maioria das versões do plugin.
      // Se a sua versão suportar foco contínuo, substitua por FocusMode.continuous (após atualizar o package).
      await cam.setFocusMode(FocusMode.auto);
    } catch (e) {
      debugPrint('Aviso: não foi possível setar focusMode: $e');
    }

    try {
      await cam.setExposureMode(ExposureMode.auto);
    } catch (e) {
      debugPrint('Aviso: não foi possível setar exposureMode: $e');
    }

    debugPrint('Câmera configurada (modo compatível) para TC26');
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
    // Se você iniciou um CameraController manualmente em outro ponto, lembre de chamar dispose nele.
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
          ),
        ],
      ),
      body: Stack(
        children: [
          ReaderWidget(
            onScan: _onCodeDetected,
            onScanFailure: (c) => debugPrint("Falhou: $c"),

            // === CONFIGS PARA TC26 ===
            tryHarder: false, // evita travamentos em dispositivos Zebra
            tryInverted: true,
            scanDelay: Duration(milliseconds: _scanDelay.toInt()),
            resolution: ResolutionPreset.medium,
            codeFormat: Format.any,
            showFlashlight: false,
            showGallery: false,
            showToggleCamera: false,
            onControllerCreated: _onControllerCreated,
          ),

          const IgnorePointer(child: ScannerOverlay()),

          if (_sameCodeCount > 0 && _sameCodeCount < 2)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Validando... ($_sameCodeCount/2)',
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
