import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/datawedge_service.dart';

const Color _focusColor = Colors.lightGreenAccent;
const Color _bgColor = Color(0xFF050A14);

class _QrScannerCornersPainter extends CustomPainter {
  const _QrScannerCornersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _focusColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;
    final corner = size.width / 5;

    canvas.drawLine(Offset.zero, Offset(corner, 0), paint);
    canvas.drawLine(Offset.zero, Offset(0, corner), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - corner, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, corner), paint);
    canvas.drawLine(Offset(0, size.height), Offset(corner, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - corner), paint);
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - corner, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - corner),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  late final MobileScannerController _controller;
  bool _scanned = false;
  bool _torchOn = false;
  String? _lastInvalid;
  DateTime? _lastInvalidAt;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    DataWedgeService.scanData.value = null;
    DataWedgeService.init();
    DataWedgeService.scanData.addListener(_onDataWedgeScan);
  }

  @override
  void dispose() {
    DataWedgeService.scanData.removeListener(_onDataWedgeScan);
    _controller.dispose();
    super.dispose();
  }

  void _onDataWedgeScan() {
    final scanned = DataWedgeService.scanData.value;
    if (scanned == null || scanned.trim().isEmpty) return;
    _acceptScan(scanned);
  }

  void _onCameraDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final codes = capture.barcodes
        .map((barcode) => _extractBarcodeText(barcode))
        .where((value) => value.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    if (codes.isEmpty) return;
    _acceptScan(codes.first);
  }

  String _extractBarcodeText(Barcode barcode) {
    final raw = (barcode.rawValue ?? '').trim();
    if (raw.isNotEmpty) return raw;
    final display = (barcode.displayValue ?? '').trim();
    if (display.isNotEmpty) return display;

    final bytes = barcode.rawBytes;
    if (bytes == null || bytes.isEmpty) return '';
    try {
      return String.fromCharCodes(bytes).trim();
    } catch (_) {
      return '';
    }
  }

  void _acceptScan(String value) {
    if (_scanned) return;
    final normalized = _normalizeScan(value);
    if (!_looksLikeUsefulQr(normalized)) {
      _showInvalidOnce(normalized);
      return;
    }

    _scanned = true;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(normalized);
  }

  String _normalizeScan(String value) {
    var text = value
        .replaceAll('\uFEFF', '')
        .replaceAll('\u0000', '')
        .replaceAll('\r', '')
        .trim();

    final firstBrace = text.indexOf('{');
    final lastBrace = text.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      text = text.substring(firstBrace, lastBrace + 1);
    }
    return text.trim();
  }

  bool _looksLikeUsefulQr(String text) {
    if (text.isEmpty) return false;
    if (text.startsWith('{') && text.endsWith('}')) return true;
    return text.length >= 4;
  }

  void _showInvalidOnce(String value) {
    final now = DateTime.now();
    if (_lastInvalid == value &&
        _lastInvalidAt != null &&
        now.difference(_lastInvalidAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastInvalid = value;
    _lastInvalidAt = now;
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Leitura incompleta. Aproxime, estabilize e tente novamente.'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFFB45309),
      ),
    );
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (!mounted) return;
    setState(() => _torchOn = !_torchOn);
  }

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final scannerSize = shortestSide < 380 ? shortestSide * 0.78 : 320.0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'Leitor de QR Code',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: _bgColor,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onCameraDetect,
          ),
          Center(
            child: Container(
              width: scannerSize,
              height: scannerSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: CustomPaint(
                size: Size(scannerSize, scannerSize),
                painter: const _QrScannerCornersPainter(),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white24),
                ),
                child: IconButton(
                  onPressed: _toggleTorch,
                  icon: Icon(
                    _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: _torchOn ? _focusColor : Colors.white,
                  ),
                  tooltip: 'Lanterna',
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text(
                  'Centralize o QR inteiro no quadro. Para QR grande, afaste um pouco ate ficar nitido.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
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
