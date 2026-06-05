import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class EtiquetasService {
  static const String baseUrl = "http://168.190.90.2:5000";
  static const String zebraZd220Ip = "168.190.30.157";
  static const String zebraZd220Name = "ZebraZd220";

  static Future<List<Map<String, dynamic>>> buscarImpressoras() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/consulta/wms/impressoras"),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final data = decoded["data"];
          if (data is List) return List<Map<String, dynamic>>.from(data);
        }
      }
    } catch (_) {}
    return [];
  }

  static Future<List<Map<String, dynamic>>> buscarOperadores() async {
    final response = await http.get(
      Uri.parse("$baseUrl/consultar/usuarios"),
      headers: {"Content-Type": "application/json"},
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) return List<Map<String, dynamic>>.from(decoded);
      if (decoded is Map<String, dynamic>) {
        final data = decoded["data"] ?? decoded["usuarios"];
        if (data is List) return List<Map<String, dynamic>>.from(data);
      }
    }

    throw "Erro ${response.statusCode} ao buscar operadores.";
  }

  static Future<List<Map<String, dynamic>>> listarObjetosPorGrupo(
    int grupoId,
  ) async {
    final response = await http.get(
      Uri.parse("$baseUrl/consulta/wms/etiqueta_produto/$grupoId"),
    );

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else if (response.statusCode == 404) {
      throw "Nenhum produto encontrado.";
    }
    throw "Erro ao buscar dados: ${response.statusCode}";
  }

  static Future<Map<String, dynamic>> buscarEtiquetaCaixa(
    int cdObj, {
    String metros = '',
    String nrOrdem = '',
  }) async {
    if (cdObj <= 0) {
      throw "Informe o código do artigo.";
    }

    final queryParameters = <String, String>{"cd_obj": cdObj.toString()};
    if (metros.trim().isNotEmpty) {
      queryParameters["metros"] = metros.trim();
    }
    if (nrOrdem.trim().isNotEmpty) {
      queryParameters["nr_ordem"] = nrOrdem.trim();
    }

    final response = await http.get(
      Uri.parse(
        "$baseUrl/consulta/wms/etiqueta-caixa",
      ).replace(queryParameters: queryParameters),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final data = decoded["data"];
        if (data is Map<String, dynamic>) return data;
        return decoded;
      }
    }

    String message = "Erro ${response.statusCode} ao buscar etiqueta caixa.";
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        message =
            (decoded["error"] ??
                    decoded["message"] ??
                    decoded["details"] ??
                    message)
                .toString();
      }
    } catch (_) {
      if (response.body.trim().isNotEmpty) message = response.body.trim();
    }
    throw message;
  }

  /// Busca apenas metadados do artigo (sem metros/ordem) — usado na etapa de consulta.
  static Future<Map<String, dynamic>> buscarArtigoInfo(int cdObj) async {
    if (cdObj <= 0) throw "Informe o código do artigo.";

    final response = await http.get(
      Uri.parse("$baseUrl/consulta/wms/artigo-info")
          .replace(queryParameters: {"cd_obj": cdObj.toString()}),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final data = decoded["data"];
        if (data is Map<String, dynamic>) return data;
        return decoded;
      }
    }

    String message = "Erro ${response.statusCode} ao buscar artigo.";
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        message = (decoded["error"] ?? decoded["message"] ?? message).toString();
      }
    } catch (_) {
      if (response.body.trim().isNotEmpty) message = response.body.trim();
    }
    throw message;
  }

  /// Endpoint v2 — aplica todas as regras do VBA:
  /// validações por CdObj, PRETO, setor 10180, ENFRALDADO/ENFESTADO,
  /// auto-resolve de Detalhe, QR no formato VBA e linhas de layout pré-computadas.
  static Future<Map<String, dynamic>> buscarEtiquetaCaixaV2({
    required int cdObj,
    required String metros,
    required String nrOrdem,
    int detalhe = 0,
    String lote = '',
    int operador = 0,
    bool pedidoEspecial = false,
    int qtdeImp = 1,
    bool loteInline = false,
  }) async {
    if (cdObj <= 0) throw "Informe o código do artigo.";
    if (metros.trim().isEmpty) throw "Informe os metros.";

    final body = {
      "cd_obj": cdObj,
      "metros": metros.trim(),
      "nr_ordem": nrOrdem.trim(),
      "detalhe": detalhe,
      "lote": lote.trim(),
      "operador": operador,
      "pedido_especial": pedidoEspecial,
      "qtde_imp": qtdeImp,
      "lote_inline": loteInline,
    };

    debugPrint('[ETIQUETA-V2] POST /etiqueta-caixa-v2 body=${jsonEncode(body)}');

    final response = await http.post(
      Uri.parse("$baseUrl/consulta/wms/etiqueta-caixa-v2"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(body),
    );

    debugPrint('[ETIQUETA-V2] status=${response.statusCode} body=${response.body}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final data = decoded["data"];
        if (data is Map<String, dynamic>) return data;
        return decoded;
      }
    }

    String message =
        "Erro ${response.statusCode} ao buscar etiqueta caixa.";
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        message =
            (decoded["error"] ??
                    decoded["message"] ??
                    decoded["details"] ??
                    message)
                .toString();
      }
    } catch (_) {
      if (response.body.trim().isNotEmpty) message = response.body.trim();
    }
    throw message;
  }

  static Future<List<Map<String, dynamic>>> buscarArtigosPorNome(
      String q) async {
    if (q.trim().length < 2) return [];
    final response = await http.get(
      Uri.parse("$baseUrl/consulta/wms/artigos-busca")
          .replace(queryParameters: {"q": q.trim()}),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final data = decoded["data"];
        if (data is List) return List<Map<String, dynamic>>.from(data);
      }
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> listarTodosArtigos() async {
    final response = await http.get(
      Uri.parse("$baseUrl/consulta/allArtigos"),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic> ? decoded["data"] : decoded;
      if (data is List) {
        return data.whereType<Map>().map((item) {
          final registro = Map<String, dynamic>.from(item);
          final cdObj =
              registro['CdObj'] ??
              registro['cdObj'] ??
              registro['cd_obj'] ??
              registro['ObjetoID'] ??
              registro['objetoID'] ??
              registro['Codigo'] ??
              registro['codigo'] ??
              '';
          final nmObj =
              registro['NmObj'] ??
              registro['nmObj'] ??
              registro['nm_obj'] ??
              registro['Artigo'] ??
              registro['artigo'] ??
              registro['Objeto'] ??
              registro['objeto'] ??
              '';
          return {
            ...registro,
            'CdObj': cdObj,
            'NmObj': nmObj,
          };
        }).toList();
      }
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> buscarArtigoLotes(
      int cdObj) async {
    if (cdObj <= 0) throw "Informe o código do artigo.";
    final response = await http.get(
      Uri.parse("$baseUrl/consulta/wms/artigo-lotes")
          .replace(queryParameters: {"cd_obj": cdObj.toString()}),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final data = decoded["data"];
        if (data is List) return List<Map<String, dynamic>>.from(data);
      }
    }
    String message = "Erro ${response.statusCode} ao buscar lotes.";
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        message = (decoded["error"] ?? decoded["message"] ?? message).toString();
      }
    } catch (_) {}
    throw message;
  }

  static String gerarPreviewUrl(Map<String, dynamic> obj) {
    final cd = obj['CdObj'];
    final lot = obj['Detalhe'] ?? '0';
    return "$baseUrl/consulta/wms/gerar_etiqueta?cd=$cd&lot=$lot";
  }

  static Future<void> imprimir(Map<String, dynamic> obj) async {
    final response = await http.post(
      Uri.parse("$baseUrl/consulta/wms/imprimir_etiqueta_api"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "CdObj": obj['CdObj'],
        "NmObj": obj['NmObj'],
        "Detalhe": obj['Detalhe'] ?? '0',
        "Ean13": obj['Ean13'] ?? '',
        "Metragem": obj['Metragem'] ?? '',
      }),
    );

    if (response.statusCode != 200) throw "Erro na impressão";
  }

  static Future<void> imprimirEtiquetaPalete({
    required String endereco,
    String printerIp = zebraZd220Ip,
    String printerName = zebraZd220Name,
  }) async {
    final palete = endereco.trim().toUpperCase();
    if (palete.isEmpty) {
      throw "Informe o endereço do palete.";
    }

    final uri = etiquetaPaleteUri(
      endereco: palete,
      printerIp: printerIp,
      printerName: printerName,
      imprimir: true,
    );
    debugPrint(
      '[ETIQUETA] Enviando impressão | palete=$palete | endpoint=$uri',
    );
    final response = await http.get(uri);
    debugPrint(
      '[ETIQUETA] Resposta impressão | status=${response.statusCode} | body=${response.body}',
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = "Erro ${response.statusCode} na impressão";
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          message =
              (decoded["error"] ??
                      decoded["message"] ??
                      decoded["details"] ??
                      message)
                  .toString();
        }
      } catch (_) {
        if (response.body.trim().isNotEmpty) {
          message = response.body.trim();
        }
      }
      throw message;
    }
  }

  static Uri etiquetaPaleteUri({
    required String endereco,
    String printerIp = zebraZd220Ip,
    String printerName = zebraZd220Name,
    bool imprimir = false,
  }) {
    final palete = endereco.trim().toUpperCase();
    return Uri.parse("$baseUrl/consulta/wms/imprimir_etiqueta").replace(
      queryParameters: {
        "endereco": palete,
        "palete": palete,
        "printer_ip": printerIp,
        "printer_name": printerName,
        "modelo": printerName,
        if (imprimir) "imprimir": "1",
      },
    );
  }
}
