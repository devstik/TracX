import '../models/linha_etiqueta_livre.dart';

class ZebraPrinterService {
  static const String defaultIp = '168.190.30.157';
  static const int defaultPort = 9100;

  Future<void> imprimirEtiquetaPalete({
    required String palete,
    String ip = defaultIp,
    int port = defaultPort,
  }) {
    throw UnsupportedError(
      'Impressão direta Zebra disponível apenas no app mobile/desktop.',
    );
  }

  Future<void> imprimirEtiquetaOperador({
    required int operador,
    int quantidade = 1,
    String ip = defaultIp,
    int port = defaultPort,
  }) {
    throw UnsupportedError(
      'Impressão direta Zebra disponível apenas no app mobile/desktop.',
    );
  }

  Future<void> imprimirEtiquetaCaixa({
    required Map<String, dynamic> dados,
    String ip = defaultIp,
    int port = defaultPort,
  }) {
    throw UnsupportedError(
      'Impressão direta Zebra disponível apenas no app mobile/desktop.',
    );
  }

  Future<void> imprimirEtiquetaCarretel({
    required Map<String, dynamic> dados,
    String ip = defaultIp,
    int port = defaultPort,
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
  }) {
    throw UnsupportedError(
      'Impressão direta Zebra disponível apenas no app mobile/desktop.',
    );
  }
}
