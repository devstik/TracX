import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/linha_etiqueta_livre.dart';

class ZebraBluetoothDevice {
  const ZebraBluetoothDevice({
    required this.port,
    required this.name,
    this.bonded = false,
  });

  final String port;
  final String name;
  final bool bonded;

  String get label {
    final base = name.trim().isEmpty ? port : '$name ($port)';
    return bonded ? '$base - Pareado' : base;
  }
}

class ZebraNetworkStatus {
  const ZebraNetworkStatus({
    required this.servidorOnline,
    required this.impressoraRespondeu,
    required this.usbConectado,
    required this.tempoMs,
    this.metodo,
    this.statusRaw,
    this.erro,
  });

  final bool servidorOnline;
  final bool impressoraRespondeu;
  final bool? usbConectado;
  final int? tempoMs;
  final String? metodo;
  final String? statusRaw;
  final String? erro;
}

class _SnmpPrinterStatus {
  const _SnmpPrinterStatus({
    required this.usbConectado,
    required this.descricao,
  });

  final bool? usbConectado;
  final String descricao;
}

class _SnmpValue {
  const _SnmpValue(this.type, this.value);

  final int type;
  final List<int> value;

  int? get integer {
    if (type != 0x02 || value.isEmpty) return null;
    var result = 0;
    for (final byte in value) {
      result = (result << 8) | byte;
    }
    return result;
  }
}

class ZebraPrinterService {
  static const MethodChannel _bluetoothChannel = MethodChannel(
    'com.example.tracx/bluetooth_printer',
  );
  static const String defaultIp = '168.190.30.181';
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
  static const int _imatecWidth = 800; // 100 mm em 203 dpi.
  static const int _imatecHeight = 560; // 70 mm em 203 dpi.
  static const int _opWidth = 422;
  static const int _opHeight = 116;
  static const List<int> _opColumnLefts = [11, 152, 293];
  static const int _opColumnWidth = 118;
  // Posicoes das 3 etiquetas de operador no mesmo avanco do rolo.
  static const int _livreTipoBSize = 400;

  Future<void> imprimirTesteConexao({
    String ip = defaultIp,
    int port = defaultPort,
    String? bluetoothPort,
  }) async {
    final destino = _destinoLabel(ip, port, bluetoothPort);
    final agora = DateTime.now();
    final dataHora =
        '${agora.day.toString().padLeft(2, '0')}/'
        '${agora.month.toString().padLeft(2, '0')}/'
        '${agora.year} '
        '${agora.hour.toString().padLeft(2, '0')}:'
        '${agora.minute.toString().padLeft(2, '0')}';
    final zpl = _zplTesteConexao(destino: destino, dataHora: dataHora);

    debugPrint(
      '[ZEBRA] Teste de conexao | destino=$destino | bytes=${utf8.encode(zpl).length}',
    );
    await _sendPayload(zpl, ip, port, bluetoothPort: bluetoothPort);
  }

  Future<ZebraNetworkStatus> consultarStatusRede({
    String ip = defaultIp,
    int port = defaultPort,
  }) async {
    Socket? socket;
    final sw = Stopwatch()..start();
    try {
      socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 2),
      );

      socket.add(utf8.encode('~HS\r\n'));
      await socket.flush();

      final chunk = await socket.first.timeout(
        const Duration(milliseconds: 900),
        onTimeout: () => Uint8List(0),
      );

      final resposta = ascii.decode(chunk, allowInvalid: true).trim();
      if (resposta.isNotEmpty) {
        sw.stop();
        return ZebraNetworkStatus(
          servidorOnline: true,
          impressoraRespondeu: true,
          usbConectado: true,
          tempoMs: sw.elapsedMilliseconds,
          metodo: 'ZPL',
          statusRaw: 'Resposta direta da impressora recebida',
        );
      }

      final snmpStatus = await _consultarStatusSnmp(ip);
      sw.stop();
      if (snmpStatus != null) {
        return ZebraNetworkStatus(
          servidorOnline: true,
          impressoraRespondeu: snmpStatus.usbConectado == true,
          usbConectado: snmpStatus.usbConectado,
          tempoMs: sw.elapsedMilliseconds,
          metodo: 'SNMP',
          statusRaw: snmpStatus.descricao,
          erro: snmpStatus.usbConectado == false ? snmpStatus.descricao : null,
        );
      }

      return ZebraNetworkStatus(
        servidorOnline: true,
        impressoraRespondeu: false,
        usbConectado: null,
        tempoMs: sw.elapsedMilliseconds,
        metodo: 'TCP',
        statusRaw: 'Print server online; status USB indisponivel',
        erro:
            'O print server respondeu, mas nao informou o status USB por ZPL ou SNMP.',
      );
    } on SocketException catch (e) {
      sw.stop();
      return ZebraNetworkStatus(
        servidorOnline: false,
        impressoraRespondeu: false,
        usbConectado: null,
        tempoMs: null,
        metodo: 'TCP',
        erro: e.message,
      );
    } catch (e) {
      sw.stop();
      return ZebraNetworkStatus(
        servidorOnline: false,
        impressoraRespondeu: false,
        usbConectado: null,
        tempoMs: null,
        metodo: 'TCP',
        erro: e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      await socket?.close();
    }
  }

  Future<_SnmpPrinterStatus?> _consultarStatusSnmp(String ip) async {
    const hrPrinterStatusOid = '1.3.6.1.2.1.25.3.5.1.1.1';
    const hrPrinterDetectedErrorStateOid = '1.3.6.1.2.1.25.3.5.1.2.1';
    const prtGeneralPrinterStatusOid = '1.3.6.1.2.1.43.5.1.1.1.1';

    final detectedError = await _snmpGet(ip, hrPrinterDetectedErrorStateOid);
    if (detectedError != null && detectedError.type == 0x04) {
      final bytes = detectedError.value;
      if (bytes.isNotEmpty && (bytes.first & 0x02) != 0) {
        return const _SnmpPrinterStatus(
          usbConectado: false,
          descricao: 'SNMP informou impressora offline/desconectada.',
        );
      }
    }

    final hrStatus = await _snmpGet(ip, hrPrinterStatusOid);
    final hr = hrStatus?.integer;
    if (hr != null) {
      if (hr == 3 || hr == 4 || hr == 5) {
        return _SnmpPrinterStatus(
          usbConectado: true,
          descricao: 'SNMP hrPrinterStatus=$hr',
        );
      }
      if (hr == 1 || hr == 2) {
        return _SnmpPrinterStatus(
          usbConectado: null,
          descricao: 'SNMP hrPrinterStatus=$hr',
        );
      }
    }

    final prtStatus = await _snmpGet(ip, prtGeneralPrinterStatusOid);
    final prt = prtStatus?.integer;
    if (prt != null) {
      if (prt == 3 || prt == 4 || prt == 5) {
        return _SnmpPrinterStatus(
          usbConectado: true,
          descricao: 'SNMP prtGeneralPrinterStatus=$prt',
        );
      }
      return _SnmpPrinterStatus(
        usbConectado: null,
        descricao: 'SNMP prtGeneralPrinterStatus=$prt',
      );
    }

    return null;
  }

  Future<_SnmpValue?> _snmpGet(String ip, String oid) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? timer;
    try {
      final oidBytes = _snmpOidBytes(oid);
      final packet = _snmpGetPacket(oidBytes);
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final completer = Completer<Datagram?>();

      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        completer.complete(socket?.receive());
      });
      timer = Timer(const Duration(milliseconds: 900), () {
        if (!completer.isCompleted) completer.complete(null);
      });

      socket.send(packet, InternetAddress(ip), 161);
      final datagram = await completer.future;
      if (datagram == null) return null;
      return _snmpValueFromResponse(datagram.data, oidBytes);
    } catch (_) {
      return null;
    } finally {
      timer?.cancel();
      await subscription?.cancel();
      socket?.close();
    }
  }

  List<int> _snmpGetPacket(List<int> oidBytes) {
    final varBind = _berSequence([
      ..._berTlv(0x06, oidBytes),
      ..._berTlv(0x05, const []),
    ]);
    final varBindList = _berSequence([...varBind]);
    final pdu = _berTlv(0xA0, [
      ..._berInteger(1),
      ..._berInteger(0),
      ..._berInteger(0),
      ...varBindList,
    ]);
    return _berSequence([
      ..._berInteger(0),
      ..._berTlv(0x04, ascii.encode('public')),
      ...pdu,
    ]);
  }

  _SnmpValue? _snmpValueFromResponse(List<int> data, List<int> oidBytes) {
    final oidStart = _indexOfBytes(data, oidBytes);
    if (oidStart < 0) return null;
    var offset = oidStart + oidBytes.length;
    if (offset >= data.length) return null;
    final type = data[offset++];
    final lengthInfo = _readBerLength(data, offset);
    if (lengthInfo == null) return null;
    offset = lengthInfo.nextOffset;
    final end = offset + lengthInfo.length;
    if (end > data.length) return null;
    return _SnmpValue(type, data.sublist(offset, end));
  }

  List<int> _snmpOidBytes(String oid) {
    final parts = oid.split('.').map(int.parse).toList();
    final bytes = <int>[parts[0] * 40 + parts[1]];
    for (final part in parts.skip(2)) {
      final stack = <int>[part & 0x7F];
      var value = part >> 7;
      while (value > 0) {
        stack.insert(0, 0x80 | (value & 0x7F));
        value >>= 7;
      }
      bytes.addAll(stack);
    }
    return bytes;
  }

  List<int> _berInteger(int value) => _berTlv(0x02, [value]);

  List<int> _berSequence(List<int> content) => _berTlv(0x30, content);

  List<int> _berTlv(int type, List<int> content) => [
    type,
    ..._berLength(content.length),
    ...content,
  ];

  List<int> _berLength(int length) {
    if (length < 0x80) return [length];
    final bytes = <int>[];
    var value = length;
    while (value > 0) {
      bytes.insert(0, value & 0xFF);
      value >>= 8;
    }
    return [0x80 | bytes.length, ...bytes];
  }

  ({int length, int nextOffset})? _readBerLength(List<int> data, int offset) {
    if (offset >= data.length) return null;
    final first = data[offset++];
    if ((first & 0x80) == 0) {
      return (length: first, nextOffset: offset);
    }
    final count = first & 0x7F;
    if (count == 0 || offset + count > data.length) return null;
    var length = 0;
    for (var i = 0; i < count; i++) {
      length = (length << 8) | data[offset++];
    }
    return (length: length, nextOffset: offset);
  }

  int _indexOfBytes(List<int> data, List<int> pattern) {
    if (pattern.isEmpty || pattern.length > data.length) return -1;
    for (var i = 0; i <= data.length - pattern.length; i++) {
      var found = true;
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          found = false;
          break;
        }
      }
      if (found) return i;
    }
    return -1;
  }

  Future<void> imprimirEtiquetaPalete({
    required String palete,
    String ip = defaultIp,
    int port = defaultPort,
    String? bluetoothPort,
  }) async {
    final endereco = palete.trim().toUpperCase();
    if (endereco.isEmpty) {
      throw Exception('Informe o endereço do palete.');
    }

    final zpl = await _zplPalete(endereco);
    debugPrint(
      '[ZEBRA] Imprimir palete | destino=$ip:$port | bytes=${utf8.encode(zpl).length}',
    );

    await _sendPayload(zpl, ip, port, bluetoothPort: bluetoothPort);
  }

  Future<void> imprimirEtiquetaOperador({
    required int operador,
    int quantidade = 1,
    int fonte = 72,
    String ip = defaultIp,
    int port = defaultPort,
    String? bluetoothPort,
  }) async {
    if (operador <= 0) throw Exception('Informe o número do operador.');
    final zpl = await _zplOperador(
      operador,
      _qtdePositiva(quantidade),
      fonte.clamp(24, 100),
    );
    debugPrint(
      '[ZEBRA] Imprimir operador | destino=$ip:$port | bytes=${utf8.encode(zpl).length}',
    );
    await _sendPayload(zpl, ip, port, bluetoothPort: bluetoothPort);
  }

  Future<void> imprimirEtiquetaCaixa({
    required Map<String, dynamic> dados,
    String ip = defaultIp,
    int port = defaultPort,
    String? bluetoothPort,
  }) async {
    if (dados.isEmpty) {
      throw Exception('Consulte a etiqueta caixa antes de imprimir.');
    }

    final zpl = await _zplCaixa(dados, bluetooth: _isBluetooth(bluetoothPort));
    debugPrint(
      '[ZEBRA] Imprimir caixa | destino=${_destinoLabel(ip, port, bluetoothPort)} | bytes=${utf8.encode(zpl).length}',
    );
    await _sendPayload(zpl, ip, port, bluetoothPort: bluetoothPort);
  }

  // Etiqueta de carretel: usa EPL2 (linguagem Eltron), não ZPL — é o mesmo
  // comando já validado em produção (script VBA/TopManager legado), só com
  // os valores interpolados. Diferente da Caixa, não rasteriza bitmap: a
  // própria impressora Zebra interpreta os comandos de texto/barcode EPL2.
  Future<void> imprimirEtiquetaCarretel({
    required Map<String, dynamic> dados,
    String ip = defaultIp,
    int port = defaultPort,
    String? bluetoothPort,
  }) async {
    if (dados.isEmpty) {
      throw Exception('Consulte a etiqueta carretel antes de imprimir.');
    }

    final epl = _eplCarretel(dados);
    debugPrint(
      '[ZEBRA] Imprimir carretel | destino=$ip:$port | bytes=${utf8.encode(epl).length}',
    );
    await _sendPayload(epl, ip, port, bluetoothPort: bluetoothPort);
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
    String? bluetoothPort,
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
      _qtdePositiva(qtde),
    );
    debugPrint(
      '[ZEBRA] Imprimir livre | destino=$ip:$port | bytes=${utf8.encode(zpl).length}',
    );
    await _sendPayload(zpl, ip, port, bluetoothPort: bluetoothPort);
  }

  // Equivalente à função GetText do VBA original: escapa \ e " e envolve
  // o texto em aspas, no formato que o comando EPL2 espera.
  Future<void> imprimirEtiquetaLivreTipoB({
    required String linha1,
    required String linha2,
    required String codigo,
    required String numero,
    int fonteBase = 36,
    int? fonteLinha1,
    int? fonteLinha2,
    int? fonteCodigo,
    int? fonteNumero,
    int qtde = 1,
    String ip = defaultIp,
    int port = defaultPort,
    String? bluetoothPort,
  }) async {
    final linha1Limpa = linha1.trim().toUpperCase();
    final linha2Limpa = linha2.trim().toUpperCase();
    final codigoLimpo = codigo.trim();
    final numeroLimpo = numero.trim();
    if (linha1Limpa.isEmpty ||
        linha2Limpa.isEmpty ||
        codigoLimpo.isEmpty ||
        numeroLimpo.isEmpty) {
      throw Exception('Preencha todos os campos do Tipo B.');
    }

    final zpl = await _zplLivreTipoB(
      linha1: linha1Limpa,
      linha2: linha2Limpa,
      codigo: codigoLimpo,
      numero: numeroLimpo,
      fonteLinha1: (fonteLinha1 ?? fonteBase).clamp(18, 72),
      fonteLinha2: (fonteLinha2 ?? fonteBase).clamp(18, 72),
      fonteCodigo: (fonteCodigo ?? 32).clamp(16, 64),
      fonteNumero: (fonteNumero ?? 72).clamp(32, 112),
      qtde: _qtdePositiva(qtde),
    );
    debugPrint(
      '[ZEBRA] Imprimir livre Tipo B | destino=$ip:$port | bytes=${utf8.encode(zpl).length}',
    );
    await _sendPayload(zpl, ip, port, bluetoothPort: bluetoothPort);
  }

  Future<void> imprimirEtiquetaLivreFio({
    required String titulo,
    required String cor,
    required String pesoLiquido,
    required String lote,
    required String codigoBarras,
    int qtde = 1,
    String ip = defaultIp,
    int port = defaultPort,
    String? bluetoothPort,
  }) async {
    final tituloLimpo = titulo.trim();
    final corLimpa = cor.trim().toUpperCase();
    final pesoLimpo = pesoLiquido.trim();
    final loteLimpo = lote.trim().toUpperCase();
    final codigoLimpo = codigoBarras.replaceAll(RegExp(r'\D'), '');
    if (tituloLimpo.isEmpty ||
        corLimpa.isEmpty ||
        pesoLimpo.isEmpty ||
        loteLimpo.isEmpty ||
        codigoLimpo.length != 13) {
      throw Exception('Dados da etiqueta de fio incompletos.');
    }

    final zpl = await _zplLivreFio(
      titulo: tituloLimpo,
      cor: corLimpa,
      pesoLiquido: pesoLimpo,
      lote: loteLimpo,
      codigoBarras: codigoLimpo,
      qtde: _qtdePositiva(qtde),
    );
    debugPrint(
      '[ZEBRA] Imprimir livre Fios | destino=$ip:$port | bytes=${utf8.encode(zpl).length}',
    );
    await _sendPayload(zpl, ip, port, bluetoothPort: bluetoothPort);
  }

  Future<void> imprimirEtiquetaLivreImatec({
    required String nome,
    required int numero,
    required String qrData,
    int qtde = 1,
    String ip = defaultIp,
    int port = defaultPort,
    String? bluetoothPort,
  }) async {
    final nomeLimpo = nome.trim();
    final qrLimpo = qrData.trim();
    if (nomeLimpo.isEmpty || numero < 1 || numero > 15 || qrLimpo.isEmpty) {
      throw Exception('Dados da etiqueta Imatec incompletos.');
    }

    final zpl = await _zplLivreImatec(
      nome: nomeLimpo,
      numero: numero,
      qrData: qrLimpo,
      qtde: _qtdePositiva(qtde),
    );
    debugPrint(
      '[ZEBRA] Imprimir livre Imatec | destino=$ip:$port | bytes=${utf8.encode(zpl).length}',
    );
    await _sendPayload(zpl, ip, port, bluetoothPort: bluetoothPort);
  }

  String _eplText(String value) {
    final escaped = _eplSafeText(
      value,
    ).replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    return '"$escaped"';
  }

  String _eplSafeText(String value) {
    const replacements = {
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'ä': 'a',
      'Á': 'A',
      'À': 'A',
      'Ã': 'A',
      'Â': 'A',
      'Ä': 'A',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'É': 'E',
      'È': 'E',
      'Ê': 'E',
      'Ë': 'E',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'Í': 'I',
      'Ì': 'I',
      'Î': 'I',
      'Ï': 'I',
      'ó': 'o',
      'ò': 'o',
      'õ': 'o',
      'ô': 'o',
      'ö': 'o',
      'Ó': 'O',
      'Ò': 'O',
      'Õ': 'O',
      'Ô': 'O',
      'Ö': 'O',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'Ú': 'U',
      'Ù': 'U',
      'Û': 'U',
      'Ü': 'U',
      'ç': 'c',
      'Ç': 'C',
      'ñ': 'n',
      'Ñ': 'N',
    };

    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(replacements[char] ?? char);
    }
    return buffer.toString();
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
    final dataCodificada = _value(dados, const [
      'DataCodificada',
      'data_codificada',
    ]);
    final ean13 = _value(dados, const ['Ean13', 'ean13']);
    final qtde = _qtdePositiva(
      _toInt(_value(dados, const ['QtdeImp', 'qtde_imp']), 1),
    );

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
      'Q200,010',
      'q100',
      'rN',
      'S6',
      'D10',
      'ZT',
      'JF',
      'OD',
      'R179,0',
      'f100',
      'N',
      'A625,269,2,4,1,1,N,${_eplText(nmObj)}',
      'A625,241,2,1,2,2,N,${_eplText(descricao)}',
      'A625,208,2,1,2,2,N,${_eplText(metros)}',
      'A625,42,2,1,1,1,N,${_eplText('Oper:')}${_eplText(operador)}',
      'A625,100,2,1,2,2,N,${_eplText(lote)}',
      'A625,68,2,1,2,2,N,${_eplText(dataCodificada)}',
      'B391,165,2,E30,3,6,109,B,${_eplText(ean13)}',
      'P$qtde',
    ];
    return '${linhas.join('\n')}\n';
  }

  Future<List<ZebraBluetoothDevice>> listarDispositivosBluetooth() async {
    if (Platform.isAndroid) {
      await _ensureAndroidBluetoothPermission();
      final result = await _bluetoothChannel.invokeMethod<List<dynamic>>(
        'listDevices',
      );
      return (result ?? const [])
          .whereType<Map>()
          .map((item) {
            final address = item['address']?.toString().trim() ?? '';
            final name = item['name']?.toString().trim() ?? '';
            final bonded = item['bonded'] == true;
            return ZebraBluetoothDevice(
              port: address,
              name: name,
              bonded: bonded,
            );
          })
          .where((item) => item.port.isNotEmpty)
          .toList()
        ..sort((a, b) {
          if (a.bonded != b.bonded) return a.bonded ? -1 : 1;
          return a.label.compareTo(b.label);
        });
    }

    if (!Platform.isWindows) return const [];

    try {
      final result = await Process.run('powershell', const [
        '-NoProfile',
        '-Command',
        r'''
$rows = @()
Get-CimInstance Win32_PnPEntity |
  Where-Object { $_.Name -match '\(COM\d+\)' } |
  ForEach-Object {
    if ($_.Name -match '(COM\d+)') {
      $rows += [pscustomobject]@{ DeviceID = $Matches[1]; Name = $_.Name }
    }
  }
try {
  $serial = Get-ItemProperty 'HKLM:\HARDWARE\DEVICEMAP\SERIALCOMM'
  foreach ($prop in $serial.PSObject.Properties) {
    if ($prop.Name -notlike 'PS*' -and $prop.Value -match '^COM\d+$') {
      if (-not ($rows | Where-Object { $_.DeviceID -eq $prop.Value })) {
        $rows += [pscustomobject]@{
          DeviceID = $prop.Value
          Name = "$($prop.Value) - Porta serial/Bluetooth"
        }
      }
    }
  }
} catch {}
$rows | Sort-Object DeviceID -Unique | ConvertTo-Json -Compress
''',
      ]);

      if (result.exitCode != 0) return const [];

      final raw = result.stdout.toString().trim();
      if (raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      final rows = decoded is List ? decoded : [decoded];

      return rows
          .whereType<Map>()
          .map((item) {
            final port = item['DeviceID']?.toString().trim() ?? '';
            final name = item['Name']?.toString().trim() ?? '';
            return ZebraBluetoothDevice(port: port, name: name);
          })
          .where((item) => item.port.toUpperCase().startsWith('COM'))
          .toList()
        ..sort((a, b) => a.port.compareTo(b.port));
    } catch (e) {
      debugPrint('[ZEBRA-BT] Erro ao listar portas seriais: $e');
      return const [];
    }
  }

  Future<void> _sendPayload(
    String zpl,
    String ip,
    int port, {
    String? bluetoothPort,
  }) async {
    final btPort = bluetoothPort?.trim();
    if (btPort != null && btPort.isNotEmpty) {
      await _sendBluetoothSerial(zpl, btPort);
      return;
    }
    await _sendZpl(zpl, ip, port);
  }

  bool _isBluetooth(String? bluetoothPort) {
    return bluetoothPort != null && bluetoothPort.trim().isNotEmpty;
  }

  String _destinoLabel(String ip, int port, String? bluetoothPort) {
    final btPort = bluetoothPort?.trim();
    if (btPort != null && btPort.isNotEmpty) {
      return 'Bluetooth $btPort';
    }
    return '$ip:$port';
  }

  Future<void> _sendBluetoothSerial(String zpl, String port) async {
    if (Platform.isAndroid) {
      await _ensureAndroidBluetoothPermission();
      final payloadBytes = ascii.encode(zpl).length;
      debugPrint(
        '[ZEBRA-BT] Imprimir via Android Bluetooth | destino=${port.trim()} | bytes=$payloadBytes',
      );
      await _bluetoothChannel.invokeMethod<void>('print', {
        'address': port.trim(),
        'payload': zpl,
      });
      return;
    }

    if (!Platform.isWindows) {
      throw Exception(
        'Impressao Bluetooth direta disponivel somente no Windows nesta versao.',
      );
    }

    final normalizedPort = port.trim().toUpperCase();
    final devicePath = '\\\\.\\$normalizedPort';
    final payload = utf8.encode(zpl);
    final totalWatch = Stopwatch()..start();

    try {
      await Process.run('cmd', [
        '/c',
        'mode $normalizedPort: BAUD=9600 PARITY=N DATA=8 STOP=1',
      ]);

      final sink = File(devicePath).openWrite();
      sink.add(payload);
      await sink.flush();
      await sink.close();
      totalWatch.stop();
      debugPrint(
        '[ZEBRA-BT] Envio OK | porta=$normalizedPort | bytes=${payload.length} | total=${totalWatch.elapsedMilliseconds}ms',
      );
    } catch (e) {
      debugPrint('[ZEBRA-BT] Erro ao enviar para $normalizedPort: $e');
      throw Exception(
        'Falha ao imprimir via Bluetooth em $normalizedPort. Verifique se a impressora esta pareada e se a porta COM esta livre. $e',
      );
    }
  }

  Future<void> _ensureAndroidBluetoothPermission() async {
    if (!Platform.isAndroid) return;

    final permissions = <Permission>[
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ];

    for (final permission in permissions) {
      final status = await permission.request();
      if (status.isDenied ||
          status.isPermanentlyDenied ||
          status.isRestricted) {
        throw Exception(
          'Permissao de Bluetooth negada. Libere Bluetooth/Localizacao para listar e imprimir.',
        );
      }
    }
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
  ^PON
  ^FWN
  ^LS0
  ^LT0
  ^PW$_paleteWidth
  ^LL$_paleteHeight
  ^LH0,0
  ^FO0,0^GFA,${graphic.totalBytes},${graphic.totalBytes},${graphic.bytesPerRow},${graphic.hexData}^FS
  ^XZ
  ''';
  }

  Future<String> _zplCaixa(
    Map<String, dynamic> dados, {
    bool bluetooth = false,
  }) async {
    if (bluetooth) {
      return _zplCaixaBluetooth(dados);
    }

    final graphic = await _caixaGraphic(dados);
    final qtde = _qtdePositiva(
      _toInt(_value(dados, const ['QtdeImp', 'qtde_imp']), 1),
    );
    return '''
  ^XA
  ^CI28
  ^PON
  ^FWN
  ^LS0
  ^LT0
  ^PW$_caixaWidth
  ^LL$_caixaHeight
  ^LH0,0
  ^FO10,0^GFA,${graphic.totalBytes},${graphic.totalBytes},${graphic.bytesPerRow},${graphic.hexData}^FS
  ^PQ$qtde,0,1,Y
  ^XZ
  ''';
  }

  String _zplTesteConexao({required String destino, required String dataHora}) {
    return '''
  ^XA
  ^CI28
  ^PON
  ^FWN
  ^PW400
  ^LL190
  ^LH0,0
  ^FO20,18^A0N,34,34^FDTRACX CONECTADO^FS
  ^FO20,62^A0N,22,22^FDImpressora pronta para uso^FS
  ^FO20,96^GB360,1,1^FS
  ^FO20,114^A0N,20,20^FDDestino: ${_zplSafe(destino)}^FS
  ^FO20,142^A0N,20,20^FD$dataHora^FS
  ^PQ1,0,1,Y
  ^XZ
  ''';
  }

  String _zplCaixaBluetooth(Map<String, dynamic> dados) {
    final lines = _caixaLines(dados);
    final qrData = _value(dados, const ['QrCode', 'qr_code']);
    final qtde = _qtdePositiva(
      _toInt(_value(dados, const ['QtdeImp', 'qtde_imp']), 1),
    );
    final qr = qrData.isEmpty
        ? ''
        : '^FO392,214^BQN,2,4^FDLA,${_zplSafe(qrData)}^FS';

    return '''
  ^XA
  ^CI28
  ^PON
  ^FWN
  ^LS0
  ^LT0
  ^PW$_caixaWidth
  ^LL$_caixaHeight
  ^LH0,0
  ^FO18,118^FB590,1,0,L,0^A0N,52,52^FD${_zplSafe(lines[0])}^FS
  ^FO18,170^FB590,1,0,L,0^A0N,40,40^FD${_zplSafe(lines[1])}^FS
  ^FO18,218^FB360,1,0,L,0^A0N,24,24^FD${_zplSafe(lines[2])}^FS
  ^FO18,248^FB360,1,0,L,0^A0N,22,22^FD${_zplSafe(lines[3])}^FS
  ^FO18,276^FB360,1,0,L,0^A0N,22,22^FD${_zplSafe(lines[4])}^FS
  ^FO18,304^FB360,1,0,L,0^A0N,20,20^FD${_zplSafe(lines[5])}^FS
  ^FO18,332^FB360,2,0,L,0^A0N,18,18^FD${_zplSafe(lines[6])}^FS
  $qr
  ^PQ$qtde,0,1,Y
  ^XZ
  ''';
  }

  Future<String> _zplOperador(int operador, int qtde, int fonte) async {
    final safeOperador = operador.toString();
    final campos = StringBuffer();
    final top = math.max(0, ((_opHeight - fonte) / 2).round() - 4);
    for (final left in _opColumnLefts) {
      campos.writeln(
        '^FO$left,$top^FB$_opColumnWidth,1,0,C,0'
        '^A0N,$fonte,$fonte^FD$safeOperador^FS',
      );
    }
    return '''
  ^XA
  ^CI28
  ^PON
  ^FWN
  ^LS0
  ^LT0
  ^PW$_opWidth
  ^LL$_opHeight
  ^LH0,0
  ^FO0,0^GB$_opWidth,$_opHeight,0^FS
  ${campos.toString().trimRight()}
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
  ^PON
  ^FWN
  ^LS0
  ^LT0
  ^PW$widthDots
  ^LL$heightDots
  ^LH0,0
  ^FO0,0^GFA,${graphic.totalBytes},${graphic.totalBytes},${graphic.bytesPerRow},${graphic.hexData}^FS
  ^PQ$qtde,0,1,Y
  ^XZ
  ''';
  }

  Future<String> _zplLivreTipoB({
    required String linha1,
    required String linha2,
    required String codigo,
    required String numero,
    required int fonteLinha1,
    required int fonteLinha2,
    required int fonteCodigo,
    required int fonteNumero,
    required int qtde,
  }) async {
    final graphic = await _livreTipoBGraphic(
      linha1: linha1,
      linha2: linha2,
      codigo: codigo,
      numero: numero,
      fonteLinha1: fonteLinha1,
      fonteLinha2: fonteLinha2,
      fonteCodigo: fonteCodigo,
      fonteNumero: fonteNumero,
    );
    return '''
  ^XA
  ^CI28
  ^PON
  ^FWN
  ^LS0
  ^LT0
  ^PW$_livreTipoBSize
  ^LL$_livreTipoBSize
  ^LH0,0
  ^FO0,0^GFA,${graphic.totalBytes},${graphic.totalBytes},${graphic.bytesPerRow},${graphic.hexData}^FS
  ^PQ$qtde,0,1,Y
  ^XZ
  ''';
  }

  Future<String> _zplLivreFio({
    required String titulo,
    required String cor,
    required String pesoLiquido,
    required String lote,
    required String codigoBarras,
    required int qtde,
  }) async {
    final graphic = await _livreFioGraphic(
      titulo: titulo,
      cor: cor,
      pesoLiquido: pesoLiquido,
      lote: lote,
      codigoBarras: codigoBarras,
    );
    return '''
  ^XA
  ^CI28
  ^PON
  ^FWN
  ^LS0
  ^LT0
  ^PW$_caixaWidth
  ^LL$_caixaHeight
  ^LH0,0
  ^FO0,0^GFA,${graphic.totalBytes},${graphic.totalBytes},${graphic.bytesPerRow},${graphic.hexData}^FS
  ^PQ$qtde,0,1,Y
  ^XZ
  ''';
  }

  Future<String> _zplLivreImatec({
    required String nome,
    required int numero,
    required String qrData,
    required int qtde,
  }) async {
    final graphic = await _livreImatecGraphic(
      nome: nome,
      numero: numero,
      qrData: qrData,
    );
    return '''
  ^XA
  ^CI28
  ^PON
  ^FWN
  ^LS0
  ^LT0
  ^PW$_imatecWidth
  ^LL$_imatecHeight
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

    final contentWidth = math.max(1.0, widthDots - 96.0);
    final contentLeft = (widthDots - contentWidth) / 2;
    final lineHeights = linhas.map((linha) => linha.fonte.toDouble()).toList();
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
        y + linha.deslocamentoY,
        contentLeft,
        contentWidth,
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

  Future<_ZplGraphic> _livreTipoBGraphic({
    required String linha1,
    required String linha2,
    required String codigo,
    required String numero,
    required int fonteLinha1,
    required int fonteLinha2,
    required int fonteCodigo,
    required int fonteNumero,
  }) async {
    const widthDots = _imatecWidth;
    const heightDots = _imatecHeight;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, widthDots.toDouble(), heightDots.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, widthDots.toDouble(), heightDots.toDouble()),
      Paint()..color = Colors.white,
    );
    final fonteLabelCod = math.max(
      18.0,
      math.min(64.0, fonteCodigo.toDouble() + 2.0),
    );

    _drawTipoBText(
      canvas,
      linha1,
      const Rect.fromLTWH(28, 24, 230, 58),
      fontSize: fonteLinha1.toDouble(),
      fontWeight: FontWeight.w900,
    );
    _drawTipoBText(
      canvas,
      linha2,
      const Rect.fromLTWH(28, 82, 210, 58),
      fontSize: fonteLinha2.toDouble(),
      fontWeight: FontWeight.w900,
    );
    _drawTipoBText(
      canvas,
      'COD:',
      const Rect.fromLTWH(28, 138, 88, 54),
      fontSize: fonteLabelCod,
      fontWeight: FontWeight.w900,
    );
    _drawTipoBText(
      canvas,
      codigo,
      const Rect.fromLTWH(110, 140, 92, 52),
      fontSize: fonteCodigo.toDouble(),
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.italic,
      textAlign: TextAlign.center,
    );
    _drawTipoBText(
      canvas,
      numero,
      const Rect.fromLTWH(242, 70, 128, 116),
      fontSize: fonteNumero.toDouble(),
      fontWeight: FontWeight.w500,
      textAlign: TextAlign.center,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(widthDots, heightDots);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (bytes == null) {
      throw Exception('Falha ao gerar imagem da etiqueta Tipo B.');
    }
    return _rgbaToZplGraphic(
      bytes.buffer.asUint8List(),
      width: widthDots,
      height: heightDots,
    );
  }

  Future<_ZplGraphic> _livreFioGraphic({
    required String titulo,
    required String cor,
    required String pesoLiquido,
    required String lote,
    required String codigoBarras,
  }) async {
    const widthDots = _caixaWidth;
    const heightDots = _caixaHeight;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, widthDots.toDouble(), heightDots.toDouble()),
    );
    final white = Paint()..color = Colors.white;
    final black = Paint()..color = Colors.black;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, widthDots.toDouble(), heightDots.toDouble()),
      white,
    );

    const textLeft = 58.0;
    const textWidth = 330.0;
    const textTop = 128.0;
    const textGap = 38.0;

    _drawFioText(
      canvas,
      titulo,
      const Rect.fromLTWH(textLeft, textTop, textWidth, 32),
      fontSize: 24,
      fontWeight: FontWeight.w600,
    );
    _drawFioText(
      canvas,
      'Cor: $cor',
      const Rect.fromLTWH(textLeft, textTop + textGap, textWidth, 30),
      fontSize: 23,
      fontWeight: FontWeight.w600,
    );
    _drawFioText(
      canvas,
      'Peso Liquido: $pesoLiquido',
      const Rect.fromLTWH(textLeft, textTop + (textGap * 2), textWidth, 30),
      fontSize: 23,
      fontWeight: FontWeight.w600,
    );
    _drawFioText(
      canvas,
      'Lote: $lote',
      const Rect.fromLTWH(textLeft, textTop + (textGap * 3), textWidth, 30),
      fontSize: 23,
      fontWeight: FontWeight.w600,
    );

    final barcode = Barcode.ean13();
    const barcodeWidth = 218.0;
    const barcodeHeight = 70.0;
    const barcodeLeft = 352.0;
    const barcodeTop = 252.0;
    for (final element in barcode.make(
      codigoBarras,
      width: barcodeWidth,
      height: barcodeHeight,
      drawText: false,
    )) {
      if (element is BarcodeBar && element.black) {
        canvas.drawRect(
          Rect.fromLTWH(
            barcodeLeft + element.left,
            barcodeTop + element.top,
            math.max(2.0, element.width),
            element.height,
          ),
          black,
        );
      }
    }

    _drawFioText(
      canvas,
      _formatarEan13(codigoBarras),
      const Rect.fromLTWH(barcodeLeft - 18, 324, barcodeWidth + 36, 28),
      fontSize: 18,
      fontWeight: FontWeight.w500,
      textAlign: TextAlign.center,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(widthDots, heightDots);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (bytes == null) {
      throw Exception('Falha ao gerar imagem da etiqueta de fio.');
    }
    return _rgbaToZplGraphic(
      bytes.buffer.asUint8List(),
      width: widthDots,
      height: heightDots,
    );
  }

  void _drawLinhaLivre(
    Canvas canvas,
    String text,
    double y,
    double contentLeft,
    double contentWidth,
    double fontSize,
    bool negrito,
    AlinhamentoLinhaLivre alinhamento,
  ) {
    if (text.trim().isEmpty) return;
    const margin = 12.0;
    final maxWidth = math.max(1.0, contentWidth - (margin * 2));
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
        dx = contentLeft + ((contentWidth - tp.width) / 2);
        break;
      case AlinhamentoLinhaLivre.direita:
        dx = contentLeft + contentWidth - margin - tp.width;
        break;
      case AlinhamentoLinhaLivre.esquerda:
        dx = contentLeft + margin;
        break;
    }
    tp.paint(canvas, Offset(dx, y));
  }

  void _drawTipoBText(
    Canvas canvas,
    String text,
    Rect area, {
    required double fontSize,
    required FontWeight fontWeight,
    FontStyle fontStyle = FontStyle.normal,
    TextAlign textAlign = TextAlign.left,
  }) {
    if (text.trim().isEmpty) return;
    var fs = fontSize;
    TextPainter tp;
    while (true) {
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.black,
            fontSize: fs,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            height: 1,
            letterSpacing: 0,
          ),
        ),
        textAlign: textAlign,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: area.width);
      if ((tp.width <= area.width && tp.height <= area.height) || fs <= 10) {
        break;
      }
      fs -= 2;
    }

    var dx = area.left;
    if (textAlign == TextAlign.center) {
      dx = area.left + ((area.width - tp.width) / 2);
    } else if (textAlign == TextAlign.right) {
      dx = area.right - tp.width;
    }
    final dy = area.top + ((area.height - tp.height) / 2);
    tp.paint(canvas, Offset(dx, dy));
  }

  void _drawFioText(
    Canvas canvas,
    String text,
    Rect area, {
    required double fontSize,
    required FontWeight fontWeight,
    TextAlign textAlign = TextAlign.left,
  }) {
    if (text.trim().isEmpty) return;
    var fs = fontSize;
    TextPainter tp;
    while (true) {
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.black,
            fontSize: fs,
            fontWeight: fontWeight,
            height: 1,
            letterSpacing: 0,
          ),
        ),
        textAlign: textAlign,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: area.width);
      if ((tp.width <= area.width && tp.height <= area.height) || fs <= 10) {
        break;
      }
      fs -= 1;
    }

    var dx = area.left;
    if (textAlign == TextAlign.center) {
      dx = area.left + ((area.width - tp.width) / 2);
    } else if (textAlign == TextAlign.right) {
      dx = area.right - tp.width;
    }
    final dy = area.top + ((area.height - tp.height) / 2);
    tp.paint(canvas, Offset(dx, dy));
  }

  String _formatarEan13(String codigo) {
    final digits = codigo.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 13) return codigo;
    return '${digits.substring(0, 1)} ${digits.substring(1, 7)} ${digits.substring(7)}';
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

  Future<_ZplGraphic> _livreImatecGraphic({
    required String nome,
    required int numero,
    required String qrData,
  }) async {
    const widthDots = _imatecWidth;
    const heightDots = _imatecHeight;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, widthDots.toDouble(), heightDots.toDouble()),
    );
    final white = Paint()..color = Colors.white;
    final black = Paint()..color = Colors.black;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, widthDots.toDouble(), heightDots.toDouble()),
      white,
    );
    const qrSize = 390.0;
    const gap = 18.0;
    const labelHeight = 58.0;
    const contentHeight = qrSize + gap + labelHeight;
    const top = (heightDots - contentHeight) / 2;
    const qrRect = Rect.fromLTWH((widthDots - qrSize) / 2, top, qrSize, qrSize);
    final barcode = Barcode.qrCode();
    for (final element in barcode.make(
      qrData,
      width: qrRect.width,
      height: qrRect.height,
      drawText: false,
    )) {
      if (element is BarcodeBar && element.black) {
        canvas.drawRect(
          Rect.fromLTWH(
            qrRect.left + element.left,
            qrRect.top + element.top,
            element.width,
            element.height,
          ),
          black,
        );
      }
    }

    _drawTipoBText(
      canvas,
      nome.toUpperCase(),
      const Rect.fromLTWH(60, top + qrSize + gap, widthDots - 120, labelHeight),
      fontSize: 48,
      fontWeight: FontWeight.w900,
      textAlign: TextAlign.center,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(widthDots, heightDots);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (bytes == null) {
      throw Exception('Falha ao gerar imagem da etiqueta Imatec.');
    }
    return _rgbaToZplGraphic(
      bytes.buffer.asUint8List(),
      width: widthDots,
      height: heightDots,
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
      )
      ..layout(maxWidth: mw)
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
            final d = _value(dados, const [
              'DataFabricacao',
              'data_fabricacao',
            ]);
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

  String _zplSafe(String value) {
    return value
        .replaceAll('^', ' ')
        .replaceAll('~', ' ')
        .replaceAll('\\', '/')
        .trim();
  }

  int _toInt(String value, int fallback) {
    return int.tryParse(value.trim()) ?? fallback;
  }

  int _qtdePositiva(int value) => value < 1 ? 1 : value;

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
