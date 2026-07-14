import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/linha_etiqueta_livre.dart';

class ZebraPrinterService {
  static const String defaultIp = '168.190.30.157';
  static const int defaultPort = 9100;
  static const double _dotsPerMm = 8;
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
  // Posições dos 3 QR codes (baseadas nos parâmetros do layout original)

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
      '[ZEBRA] Imprimir palete | destino=$ip:$port | bytes=${utf8.encode(zpl).length}',
    );

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
    debugPrint(
      '[ZEBRA] Imprimir operador | destino=$ip:$port | bytes=${utf8.encode(zpl).length}',
    );
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
    debugPrint(
      '[ZEBRA] Imprimir caixa | destino=$ip:$port | bytes=${utf8.encode(zpl).length}',
    );
    await _sendZpl(zpl, ip, port);
  }

  // Etiqueta de carretel: usa EPL2 (linguagem Eltron), não ZPL — é o mesmo
  // comando já validado em produção (script VBA/TopManager legado), só com
  // os valores interpolados. Diferente da Caixa, não rasteriza bitmap: a
  // própria impressora Zebra interpreta os comandos de texto/barcode EPL2.
  Future<void> imprimirEtiquetaCarretel({
    required Map<String, dynamic> dados,
    String ip = defaultIp,
    int port = defaultPort,
  }) async {
    if (dados.isEmpty) {
      throw Exception('Consulte a etiqueta carretel antes de imprimir.');
    }

    final epl = _eplCarretel(dados);
    debugPrint(
      '[ZEBRA] Imprimir carretel | destino=$ip:$port | bytes=${utf8.encode(epl).length}',
    );
    await _sendZpl(epl, ip, port);
  }

  // Etiqueta livre: usuário informa largura/altura (mm) e monta linhas de
  // texto (tamanho/alinhamento/negrito). Renderiza em bitmap via Canvas,
  // igual às demais etiquetas, e converte para gráfico ZPL (^GFA).
  Future<void> imprimirEtiquetaLivre({
    required double larguraMm,
    required double alturaMm,
    required List<LinhaEtiquetaLivre> linhas,
    int qtde = 1,
    String ip = defaultIp,
    int port = defaultPort,
  }) async {
    if (larguraMm <= 0 || alturaMm <= 0) {
      throw Exception('Informe a largura e a altura da etiqueta.');
    }
    final linhasValidas = linhas
        .where((linha) => linha.texto.trim().isNotEmpty)
        .toList();
    if (linhasValidas.isEmpty) {
      throw Exception('Adicione pelo menos uma linha com texto.');
    }

    final zpl = await _zplLivre(
      larguraMm,
      alturaMm,
      linhasValidas,
      qtde.clamp(1, 999),
    );
    debugPrint(
      '[ZEBRA] Imprimir livre | destino=$ip:$port | bytes=${utf8.encode(zpl).length}',
    );
    await _sendZpl(zpl, ip, port);
  }

  // Equivalente à função GetText do VBA original: escapa \ e " e envolve
  // o texto em aspas, no formato que o comando EPL2 espera.
  String _eplText(String value) {
    final escaped = value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    return '"$escaped"';
  }

  // Remove um "(" no início e ")" no final (ex.: "(71% POLIESTER...)"),
  // pra ganhar espaço na descrição sem perder informação.
  String _semParentesesEnvolventes(String texto) {
    final t = texto.trim();
    if (t.startsWith('(') && t.endsWith(')')) {
      return t.substring(1, t.length - 1).trim();
    }
    return t;
  }

  String _eplCarretel(Map<String, dynamic> dados) {
    final nmObj = _value(dados, const ['NmObj', 'nm_obj']);
    final descricao = _semParentesesEnvolventes(
      _value(dados, const ['Descricao', 'descricao']),
    );
    final metros = _value(dados, const ['Metragem', 'metragem']);
    final operador = _value(dados, const ['Operador', 'operador']);
    final lote = _value(dados, const ['Lote', 'lote']);
    final dataCodificada = _value(
      dados,
      const ['DataCodificada', 'data_codificada'],
    );
    final ean13 = _value(dados, const ['Ean13', 'ean13']);
    final qtde = _toInt(_value(dados, const ['QtdeImp', 'qtde_imp']), 1)
        .clamp(1, 999);

    // A etiqueta física do Carretel é 80x50mm (igual à Caixa) — 640x400 dots
    // a 8 dots/mm. O script legado (VBA) foi feito para uma etiqueta maior
    // (~104x35mm, q831/Q280). No EPL2 rotation=2 usado aqui, AUMENTAR X move
    // o conteúdo pra ESQUERDA (e diminuir move pra direita/centro) — direção
    // confirmada em teste físico. Fonte da descrição mantida em 2x (sem
    // redução automática); a folga vem só do recuo em X.
    final linhas = <String>[
      'I8,A,001',
      '',
      '',
      'Q400,024',
      'q640',
      'rN',
      'S6',
      'D10',
      'ZT',
      'JF',
      'OD',
      'R179,0',
      'f100',
      'N',
      'A525,269,2,4,1,1,N,${_eplText(nmObj)}',
      'A525,241,2,1,2,2,N,${_eplText(descricao)}',
      'A525,208,2,1,2,2,N,${_eplText(metros)}',
      'A525,42,2,1,1,1,N,${_eplText('Oper:')}${_eplText(operador)}',
      'A525,100,2,1,2,2,N,${_eplText(lote)}',
      'A525,68,2,1,2,2,N,${_eplText(dataCodificada)}',
      'B291,165,2,E30,3,6,109,B,${_eplText(ean13)}',
      'P$qtde',
    ];
    return '${linhas.join('\n')}\n';
  }

  Future<void> _sendZpl(String zpl, String ip, int port) async {
    Socket? socket;
    final totalWatch = Stopwatch()..start();
    try {
      final connectWatch = Stopwatch()..start();
      socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 3),
      );
      connectWatch.stop();
      final payload = utf8.encode(zpl);
      debugPrint(
        '[ZEBRA] Conectado em ${connectWatch.elapsedMilliseconds}ms | destino=$ip:$port | bytes=${payload.length}',
      );
      final flushWatch = Stopwatch()..start();
      socket.add(payload);
      await socket.flush();
      flushWatch.stop();
      totalWatch.stop();
      debugPrint(
        '[ZEBRA] Envio OK | flush=${flushWatch.elapsedMilliseconds}ms | total=${totalWatch.elapsedMilliseconds}ms',
      );
    } on SocketException catch (e) {
      debugPrint('[ZEBRA] Erro SocketException: $e');
      throw Exception('Falha ao conectar na Zebra $ip:$port. $e');
    } catch (e) {
      debugPrint('[ZEBRA] Erro inesperado: $e');
      throw Exception('Falha ao imprimir na Zebra. $e');
    } finally {
      await socket?.close();
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
^FO10,0^GFA,${graphic.totalBytes},${graphic.totalBytes},${graphic.bytesPerRow},${graphic.hexData}^FS
^PQ$qtde,0,1,Y
^XZ
''';
  }

  Future<String> _zplOperador(int operador, int qtde) async {
    final safeOperador = operador.toString();
    return '''
^XA
^CI28
^PW$_opWidth
^LL$_opHeight
^LH0,0
^FO0,0^GB$_opWidth,$_opHeight,0^FS
^FO0,18^FB$_opWidth,1,0,C,0^A0N,72,72^FD$safeOperador^FS
^PQ$qtde,0,1,Y
^XZ
''';
  }

  Future<String> _zplLivre(
    double larguraMm,
    double alturaMm,
    List<LinhaEtiquetaLivre> linhas,
    int qtde,
  ) async {
    final widthDots = (larguraMm * _dotsPerMm).round();
    final heightDots = (alturaMm * _dotsPerMm).round();
    final graphic = await _livreGraphic(widthDots, heightDots, linhas);
    return '''
^XA
^CI28
^PW$widthDots
^LL$heightDots
^LH0,0
^FO0,0^GFA,${graphic.totalBytes},${graphic.totalBytes},${graphic.bytesPerRow},${graphic.hexData}^FS
^PQ$qtde,0,1,Y
^XZ
''';
  }

  Future<_ZplGraphic> _livreGraphic(
    int widthDots,
    int heightDots,
    List<LinhaEtiquetaLivre> linhas,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, widthDots.toDouble(), heightDots.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, widthDots.toDouble(), heightDots.toDouble()),
      Paint()..color = Colors.white,
    );

    final lineHeights = linhas
        .map((linha) => _tamanhoLivreDots(linha.tamanho))
        .toList();
    final totalTextHeight =
        lineHeights.fold<double>(0, (sum, height) => sum + height) +
        ((linhas.length - 1) * 12);
    var y = math.max(8.0, (heightDots - totalTextHeight) / 2);

    for (var i = 0; i < linhas.length; i++) {
      final linha = linhas[i];
      final fontSize = lineHeights[i];
      _drawLinhaLivre(
        canvas,
        linha.texto,
        y,
        widthDots.toDouble(),
        fontSize,
        linha.negrito,
        linha.alinhamento,
      );
      y += fontSize + 12;
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(widthDots, heightDots);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (bytes == null) {
      throw Exception('Falha ao gerar imagem da etiqueta livre.');
    }
    return _rgbaToZplGraphic(
      bytes.buffer.asUint8List(),
      width: widthDots,
      height: heightDots,
    );
  }

  double _tamanhoLivreDots(TamanhoLinhaLivre tamanho) {
    switch (tamanho) {
      case TamanhoLinhaLivre.pequeno:
        return 24;
      case TamanhoLinhaLivre.medio:
        return 36;
      case TamanhoLinhaLivre.grande:
        return 52;
    }
  }

  void _drawLinhaLivre(
    Canvas canvas,
    String text,
    double y,
    double widthDots,
    double fontSize,
    bool negrito,
    AlinhamentoLinhaLivre alinhamento,
  ) {
    if (text.trim().isEmpty) return;
    const margin = 12.0;
    final maxWidth = widthDots - (margin * 2);
    var fs = fontSize;
    TextPainter tp;
    while (true) {
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.black,
            fontSize: fs,
            fontWeight: negrito ? FontWeight.w900 : FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (tp.width <= maxWidth || fs <= 10) break;
      fs -= 2;
    }

    double dx;
    switch (alinhamento) {
      case AlinhamentoLinhaLivre.centro:
        dx = (widthDots - tp.width) / 2;
        break;
      case AlinhamentoLinhaLivre.direita:
        dx = widthDots - margin - tp.width;
        break;
      case AlinhamentoLinhaLivre.esquerda:
        dx = margin;
        break;
    }
    tp.paint(canvas, Offset(dx, y));
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
    final mw = maxWidth ?? _caixaQrRect.left - offset.dx - 12;
    var fs = fontSize;
    while (fs >= 12) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.black,
            fontSize: fs,
            fontWeight: fontWeight,
            letterSpacing: 0,
          ),
        ),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      )..layout();
      if (tp.width <= mw) {
        tp.paint(canvas, offset);
        return;
      }
      fs -= 2;
    }
    TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: fontWeight,
          letterSpacing: 0,
        ),
      ),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '',
    )..layout(maxWidth: mw)
    ..paint(canvas, offset);
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
