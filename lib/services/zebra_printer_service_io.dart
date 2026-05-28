import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ZebraPrinterService {
  static const String defaultIp = '168.190.30.157';
  static const int defaultPort = 9100;
  static const int _paleteWidth = 800;
  static const int _paleteHeight = 560;
  static const Rect _paleteQrRect = Rect.fromLTWH(190, 30, 420, 420);
  static const double _paleteTextTop = 455;
  static const int _caixaWidth = 640;
  static const int _caixaHeight = 400;
  static const double _caixaPrintTop = 120;
  static const Rect _caixaQrRect = Rect.fromLTWH(448, 217, 135, 135);
  static const int _opWidth = 422;
  static const int _opHeight = 116;
  static const double _opQrSide = 63;
  // Posições dos 3 QR codes (baseadas nos parâmetros do layout original)
  static const List<Offset> _opQrOffsets = [
    Offset(34, 26),
    Offset(168, 26),
    Offset(325, 21),
  ];

  Future<void> imprimirEtiquetaPalete({
    required String palete,
    String ip = defaultIp,
    int port = defaultPort,
  }) async {
    final endereco = palete.trim().toUpperCase();
    if (endereco.isEmpty) {
      throw Exception('Informe o endereço do palete.');
    }

    final zpl = await _zplPalete(endereco);
    debugPrint(
      '[ZEBRA] Clique imprimir | palete=$endereco | destino=$ip:$port',
    );
    debugPrint('[ZEBRA] ZPL enviado:\n$zpl');

    await _sendZpl(zpl, ip, port);
  }

  Future<void> imprimirEtiquetaOperador({
    required int operador,
    int quantidade = 1,
    String ip = defaultIp,
    int port = defaultPort,
  }) async {
    if (operador <= 0) throw Exception('Informe o número do operador.');
    final zpl = await _zplOperador(operador, quantidade.clamp(1, 99));
    await _sendZpl(zpl, ip, port);
  }

  Future<void> imprimirEtiquetaCaixa({
    required Map<String, dynamic> dados,
    String ip = defaultIp,
    int port = defaultPort,
  }) async {
    if (dados.isEmpty) {
      throw Exception('Consulte a etiqueta caixa antes de imprimir.');
    }

    final zpl = await _zplCaixa(dados);
    debugPrint('[ZEBRA] Clique imprimir etiqueta caixa | destino=$ip:$port');
    debugPrint('[ZEBRA] ZPL caixa enviado:\n$zpl');
    await _sendZpl(zpl, ip, port);
  }

  Future<void> _sendZpl(String zpl, String ip, int port) async {
    Socket? socket;
    try {
      debugPrint('[ZEBRA] Conectando em $ip:$port...');
      socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 5),
      );
      debugPrint(
        '[ZEBRA] Conectado. Enviando ${utf8.encode(zpl).length} bytes...',
      );
      socket.add(utf8.encode(zpl));
      await socket.flush();
      debugPrint('[ZEBRA] Flush concluído.');
    } on SocketException catch (e) {
      debugPrint('[ZEBRA] Erro SocketException: $e');
      throw Exception('Falha ao conectar na Zebra $ip:$port. $e');
    } catch (e) {
      debugPrint('[ZEBRA] Erro inesperado: $e');
      throw Exception('Falha ao imprimir na Zebra. $e');
    } finally {
      await socket?.close();
      debugPrint('[ZEBRA] Socket fechado.');
    }
  }

  Future<String> _zplPalete(String palete) async {
    final safe = palete.replaceAll('^', '').replaceAll('~', '');
    final graphic = await _paleteGraphic(safe);
    return '''
^XA
^CI28
^PW$_paleteWidth
^LL$_paleteHeight
^LH0,0
^FO0,0^GFA,${graphic.totalBytes},${graphic.totalBytes},${graphic.bytesPerRow},${graphic.hexData}^FS
^XZ
''';
  }

  Future<String> _zplCaixa(Map<String, dynamic> dados) async {
    final graphic = await _caixaGraphic(dados);
    final qtde = _toInt(_value(dados, const ['QtdeImp', 'qtde_imp']), 1)
        .clamp(1, 999);
    return '''
^XA
^CI28
^PW$_caixaWidth
^LL$_caixaHeight
^LH0,0
^FO0,0^GFA,${graphic.totalBytes},${graphic.totalBytes},${graphic.bytesPerRow},${graphic.hexData}^FS
^PQ$qtde,0,1,Y
^XZ
''';
  }

  Future<String> _zplOperador(int operador, int qtde) async {
    final graphic = await _operadorGraphic(operador);
    return '''
^XA
^CI28
^PW$_opWidth
^LL$_opHeight
^LH0,0
^FO0,0^GFA,${graphic.totalBytes},${graphic.totalBytes},${graphic.bytesPerRow},${graphic.hexData}^FS
^PQ$qtde,0,1,Y
^XZ
''';
  }

  Future<_ZplGraphic> _operadorGraphic(int operador) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, _opWidth.toDouble(), _opHeight.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _opWidth.toDouble(), _opHeight.toDouble()),
      Paint()..color = Colors.white,
    );

    final qrData = '{"operador":$operador}';
    final barcode = Barcode.qrCode();
    final black = Paint()..color = Colors.black;

    for (final offset in _opQrOffsets) {
      for (final element in barcode.make(
        qrData,
        width: _opQrSide,
        height: _opQrSide,
        drawText: false,
      )) {
        if (element is BarcodeBar && element.black) {
          canvas.drawRect(
            Rect.fromLTWH(
              offset.dx + element.left,
              offset.dy + element.top,
              element.width,
              element.height,
            ),
            black,
          );
        }
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(_opWidth, _opHeight);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (bytes == null) throw Exception('Falha ao gerar imagem da etiqueta operador.');
    return _rgbaToZplGraphic(
      bytes.buffer.asUint8List(),
      width: _opWidth,
      height: _opHeight,
    );
  }

  Future<_ZplGraphic> _paleteGraphic(String palete) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, _paleteWidth.toDouble(), _paleteHeight.toDouble()),
    );
    final white = Paint()..color = Colors.white;
    final black = Paint()..color = Colors.black;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _paleteWidth.toDouble(), _paleteHeight.toDouble()),
      white,
    );

    final barcode = Barcode.qrCode();
    for (final element in barcode.make(
      palete,
      width: _paleteQrRect.width,
      height: _paleteQrRect.height,
      drawText: false,
    )) {
      if (element is BarcodeBar && element.black) {
        canvas.drawRect(
          Rect.fromLTWH(
            _paleteQrRect.left + element.left,
            _paleteQrRect.top + element.top,
            element.width,
            element.height,
          ),
          black,
        );
      }
    }

    final textPainter =
        TextPainter(
          text: TextSpan(
            text: palete,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 58,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(
          minWidth: _paleteWidth.toDouble(),
          maxWidth: _paleteWidth.toDouble(),
        );
    textPainter.paint(canvas, const Offset(0, _paleteTextTop));

    final picture = recorder.endRecording();
    final image = await picture.toImage(_paleteWidth, _paleteHeight);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (bytes == null) {
      throw Exception('Falha ao gerar imagem da etiqueta.');
    }
    return _rgbaToZplGraphic(
      bytes.buffer.asUint8List(),
      width: _paleteWidth,
      height: _paleteHeight,
    );
  }

  Future<_ZplGraphic> _caixaGraphic(Map<String, dynamic> dados) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, _caixaWidth.toDouble(), _caixaHeight.toDouble()),
    );
    final white = Paint()..color = Colors.white;
    final black = Paint()..color = Colors.black;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _caixaWidth.toDouble(), _caixaHeight.toDouble()),
      white,
    );

    final lines = _caixaLines(dados);
    _drawText(
      canvas,
      lines[0],
      const Offset(18, _caixaPrintTop + 0),
      52,
      FontWeight.w900,
      maxWidth: _caixaWidth - 36,
    );
    _drawText(
      canvas,
      lines[1],
      const Offset(18, _caixaPrintTop + 52),
      40,
      FontWeight.w900,
      maxWidth: _caixaWidth - 36,
    );
    _drawText(
      canvas,
      lines[2],
      const Offset(18, _caixaPrintTop + 98),
      24,
      FontWeight.w800,
    );
    _drawText(
      canvas,
      lines[3],
      const Offset(18, _caixaPrintTop + 128),
      22,
      FontWeight.w800,
    );
    _drawText(
      canvas,
      lines[4],
      const Offset(18, _caixaPrintTop + 156),
      22,
      FontWeight.w800,
    );
    _drawText(
      canvas,
      lines[5],
      const Offset(18, _caixaPrintTop + 184),
      20,
      FontWeight.w800,
    );
    _drawText(
      canvas,
      lines[6],
      const Offset(18, _caixaPrintTop + 212),
      18,
      FontWeight.w700,
    );

    final qrData = _value(dados, const ['QrCode', 'qr_code']);
    if (qrData.isNotEmpty) {
      final barcode = Barcode.qrCode();
      for (final element in barcode.make(
        qrData,
        width: _caixaQrRect.width,
        height: _caixaQrRect.height,
        drawText: false,
      )) {
        if (element is BarcodeBar && element.black) {
          canvas.drawRect(
            Rect.fromLTWH(
              _caixaQrRect.left + element.left,
              _caixaQrRect.top + element.top,
              element.width,
              element.height,
            ),
            black,
          );
        }
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(_caixaWidth, _caixaHeight);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (bytes == null) {
      throw Exception('Falha ao gerar imagem da etiqueta caixa.');
    }
    return _rgbaToZplGraphic(
      bytes.buffer.asUint8List(),
      width: _caixaWidth,
      height: _caixaHeight,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    double fontSize,
    FontWeight fontWeight, {
    double? maxWidth,
  }) {
    if (text.trim().isEmpty) return;
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: 0,
        ),
      ),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '',
    )..layout(maxWidth: maxWidth ?? _caixaQrRect.left - offset.dx - 12);
    textPainter.paint(canvas, offset);
  }

  /// Resolve as 7 linhas da etiqueta caixa.
  /// Prioriza os campos pré-computados pela API v2 (Linha230/260/300/LinhaData).
  /// Mantém fallback para campos do endpoint GET legado.
  List<String> _caixaLines(Map<String, dynamic> dados) {
    final linha230 = _value(dados, const ['Linha230']);
    final linha260 = _value(dados, const ['Linha260']);
    final linha300 = _value(dados, const ['Linha300']);
    final linhaData = _value(dados, const ['LinhaData']);

    final metros = linha230.isNotEmpty
        ? linha230
        : _value(dados, const ['Metros', 'metros']);

    final lote = linha260.isNotEmpty
        ? linha260
        : _value(dados, const ['Lote', 'lote']);

    final carretel = linha300.isNotEmpty
        ? linha300
        : () {
            final m = _value(dados, const ['Metragem', 'metragem']);
            return m.isEmpty ? '' : 'Carretel: $m';
          }();

    final dataFab = linhaData.isNotEmpty
        ? linhaData
        : () {
            final d =
                _value(dados, const ['DataFabricacao', 'data_fabricacao']);
            return d.isEmpty ? '' : 'Fabricação: $d';
          }();

    return [
      _value(dados, const ['NmObj1', 'nm_obj1']),
      _value(dados, const ['NmObj2', 'nm_obj2']),
      metros,
      lote,
      carretel,
      dataFab,
      _value(dados, const ['Descricao', 'descricao']),
    ].map((line) => line.trim()).toList();
  }

  String _value(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }

  int _toInt(String value, int fallback) {
    return int.tryParse(value.trim()) ?? fallback;
  }

  _ZplGraphic _rgbaToZplGraphic(
    Uint8List rgba, {
    required int width,
    required int height,
  }) {
    final bytesPerRow = (width + 7) ~/ 8;
    final totalBytes = bytesPerRow * height;
    final output = Uint8List(totalBytes);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixelOffset = ((y * width) + x) * 4;
        final r = rgba[pixelOffset];
        final g = rgba[pixelOffset + 1];
        final b = rgba[pixelOffset + 2];
        final alpha = rgba[pixelOffset + 3];
        final luminance = (0.299 * r) + (0.587 * g) + (0.114 * b);
        final isBlack = alpha > 127 && luminance < 180;
        if (isBlack) {
          final byteIndex = (y * bytesPerRow) + (x ~/ 8);
          output[byteIndex] |= 0x80 >> (x % 8);
        }
      }
    }

    final hex = StringBuffer();
    for (final byte in output) {
      hex.write(byte.toRadixString(16).padLeft(2, '0').toUpperCase());
    }

    return _ZplGraphic(
      bytesPerRow: bytesPerRow,
      totalBytes: totalBytes,
      hexData: hex.toString(),
    );
  }
}

class _ZplGraphic {
  const _ZplGraphic({
    required this.bytesPerRow,
    required this.totalBytes,
    required this.hexData,
  });

  final int bytesPerRow;
  final int totalBytes;
  final String hexData;
}
