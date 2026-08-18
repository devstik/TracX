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

class ZebraPrinterService {
  static const String defaultIp = '168.190.30.181';
  static const int defaultPort = 9100;

  Future<void> imprimirTesteConexao({
    String ip = defaultIp,
    int port = defaultPort,
    String? bluetoothPort,
  }) {
    throw UnsupportedError(
      'Impressao direta Zebra disponivel apenas no app mobile/desktop.',
    );
  }

  Future<ZebraNetworkStatus> consultarStatusRede({
    String ip = defaultIp,
    int port = defaultPort,
  }) {
    throw UnsupportedError(
      'Consulta direta Zebra disponivel apenas no app mobile/desktop.',
    );
  }

  Future<void> imprimirEtiquetaPalete({
    required String palete,
    String ip = defaultIp,
    int port = defaultPort,
    String? bluetoothPort,
  }) {
    throw UnsupportedError(
      'Impressão direta Zebra disponível apenas no app mobile/desktop.',
    );
  }

  Future<void> imprimirEtiquetaOperador({
    required int operador,
    int quantidade = 1,
    int fonte = 72,
    String ip = defaultIp,
    int port = defaultPort,
    String? bluetoothPort,
  }) {
    throw UnsupportedError(
      'Impressão direta Zebra disponível apenas no app mobile/desktop.',
    );
  }

  Future<void> imprimirEtiquetaCaixa({
    required Map<String, dynamic> dados,
    String ip = defaultIp,
    int port = defaultPort,
    String? bluetoothPort,
  }) {
    throw UnsupportedError(
      'Impressão direta Zebra disponível apenas no app mobile/desktop.',
    );
  }

  Future<void> imprimirEtiquetaCarretel({
    required Map<String, dynamic> dados,
    String ip = defaultIp,
    int port = defaultPort,
    String? bluetoothPort,
  }) {
    throw UnsupportedError(
      'Impressão direta Zebra disponível apenas no app mobile/desktop.',
    );
  }

  Future<void> imprimirEtiquetaLivre({
    required double larguraMm,
    required double alturaMm,
    required List<LinhaEtiquetaLivre> linhas,
    int qtde = 1,
    String ip = defaultIp,
    int port = defaultPort,
    String? bluetoothPort,
  }) {
    throw UnsupportedError(
      'Impressão direta Zebra disponível apenas no app mobile/desktop.',
    );
  }
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
  }) {
    throw UnsupportedError(
      'ImpressÃ£o direta Zebra disponÃ­vel apenas no app mobile/desktop.',
    );
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
  }) {
    throw UnsupportedError(
      'Impressao direta Zebra disponivel apenas no app mobile/desktop.',
    );
  }

  Future<void> imprimirEtiquetaLivreImatec({
    required String nome,
    required int numero,
    required String qrData,
    int qtde = 1,
    String ip = defaultIp,
    int port = defaultPort,
    String? bluetoothPort,
  }) {
    throw UnsupportedError(
      'Impressao direta Zebra disponivel apenas no app mobile/desktop.',
    );
  }

  Future<List<ZebraBluetoothDevice>> listarDispositivosBluetooth() async {
    return const [];
  }
}
