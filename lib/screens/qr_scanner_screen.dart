import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

// Cor do foco
const Color focusColor = Colors.lightGreenAccent;

// --- Overlay personalizado ---
class ScannerOverlay extends StatelessWidget {
  const ScannerOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    const double scanAreaSize = 300;

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

// --- Tela do Scanner ---
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  void _onCodeDetected(Code result) {
    if (result.text != null && result.text!.isNotEmpty) {
      // EXIBE NO CONSOLE O QUE FOI LIDO
      debugPrint('-----------------------------');
      debugPrint('CONTEÚDO LIDO: ${result.text}');
      debugPrint('-----------------------------');

      if (mounted) {
        // O pop fecha a tela. Se quiser continuar lendo, remova esta linha.
        Navigator.of(context).pop(result.text);
      }
    }
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
      ),
      body: Stack(
        children: [
          // Widget corrigido da biblioteca flutter_zxing
          ReaderWidget(
            onScan: _onCodeDetected,
            onScanFailure: (code) => debugPrint("Erro de leitura: $code"),
            showFlashlight: true,
            showToggleCamera: true,
            showGallery: false,
          ),

          // Overlay visual
          const ScannerOverlay(),
        ],
      ),
    );
  }
}
