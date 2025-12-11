import 'package:flutter/material.dart';
import '../services/datawedge_service.dart'; // Ajuste o caminho conforme sua pasta

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
        // Fundo escuro com área transparente
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
        // Bordas de foco
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
        // Texto de instrução
        const Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: 80),
            child: Text(
              'Aponte o scanner para o QR Code',
              textAlign: TextAlign.center,
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

// --- Tela do Scanner usando DataWedge ---
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  bool _scanned = false; // Evita múltiplos pops acidentais

  @override
  void initState() {
    super.initState();
    // Inicializa o listener do DataWedge
    DataWedgeService.init();
    // Adiciona listener para receber códigos escaneados
    DataWedgeService.scanData.addListener(_onScan);
  }

  void _onScan() {
    final scanned = DataWedgeService.scanData.value;
    if (!_scanned && scanned != null && scanned.isNotEmpty) {
      _scanned = true;
      debugPrint("[QrScannerScreen] Código recebido: $scanned");
      Navigator.of(context).pop(scanned);
    }
  }

  @override
  void dispose() {
    DataWedgeService.scanData.removeListener(_onScan);
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
      ),
      body: const Stack(
        children: [
          // Overlay do scanner
          IgnorePointer(child: ScannerOverlay()),
        ],
      ),
    );
  }
}
