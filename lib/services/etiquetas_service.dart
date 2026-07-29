import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class EtiquetasService {
  static const String baseUrl = "http://168.190.90.2:5000";
  static const String zebraZd220Ip = "168.190.30.74";
  static const String zebraZd220Name = "ZebraZd220";
  static const Duration _quickTimeout = Duration(seconds: 8);

  static Future<List<Map<String, dynamic>>> buscarOperadores() async {
    final response = await http.get(
      Uri.parse("$baseUrl/consultar/usuarios"),
      headers: {"Content-Type": "application/json"},
    ).timeout(_quickTimeout);

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

  static Future<List<Map<String, dynamic>>> buscarImpressoras() async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/consulta/wms/impressoras"),
      ).timeout(_quickTimeout);
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
    String? li,
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
      if (li != null && li.trim().isNotEmpty) "li": li.trim(),
    };

    final sw = Stopwatch()..start();
    final response = await http.post(
      Uri.parse("$baseUrl/consulta/wms/etiqueta-caixa-v2"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(body),
    ).timeout(_quickTimeout);
    sw.stop();

    debugPrint(
      '[ETIQUETA-V2] status=${response.statusCode} | tempo=${sw.elapsedMilliseconds}ms',
    );

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

  static Future<Map<String, dynamic>> buscarEtiquetaCarretel({
    required int cdObj,
    String lote = '',
    String operador = '',
    int qtdeImp = 1,
  }) async {
    if (cdObj <= 0) throw "Informe o código do artigo.";

    final body = {
      "cd_obj": cdObj,
      "lote": lote.trim(),
      "operador": operador.trim(),
      "qtde_imp": qtdeImp,
    };

    final sw = Stopwatch()..start();
    final response = await http.post(
      Uri.parse("$baseUrl/consulta/wms/etiqueta-carretel"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(body),
    ).timeout(_quickTimeout);
    sw.stop();

    debugPrint(
      '[ETIQUETA-CARRETEL] status=${response.statusCode} | tempo=${sw.elapsedMilliseconds}ms',
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final data = decoded["data"];
        if (data is Map<String, dynamic>) return data;
        return decoded;
      }
    }

    String message = "Erro ${response.statusCode} ao buscar etiqueta carretel.";
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

  static Future<List<Map<String, dynamic>>> buscarOrdensExpedicao({
    String skuName = '',
    String productionFamily = '',
    String plant = '',
  }) async {
    final params = <String, String>{};
    if (skuName.trim().isNotEmpty) params['sku_name'] = skuName.trim();
    if (productionFamily.trim().isNotEmpty) {
      params['production_family'] = productionFamily.trim();
    }
    if (plant.trim().isNotEmpty) params['plant'] = plant.trim();

    final response = await http
        .get(
          Uri.parse(
            "$baseUrl/buffer_expedicao_ordem",
          ).replace(queryParameters: params.isEmpty ? null : params),
          headers: {"Content-Type": "application/json"},
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) return List<Map<String, dynamic>>.from(decoded);
      if (decoded is Map<String, dynamic>) {
        final data = decoded["data"] ?? decoded["ordens"] ?? decoded["items"];
        if (data is List) return List<Map<String, dynamic>>.from(data);
      }
    }

    String message = "Erro ${response.statusCode} ao buscar ordens.";
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        message =
            (decoded["erro"] ??
                    decoded["error"] ??
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

  static Future<List<Map<String, dynamic>>> consultarPlanejamentoTinturaria({
    required String dataInicio,
    required String dataFim,
    String cdUne = '',
    String cdVpd = '',
    String cdCli = '',
    String cdObj = '',
    String nmObj = '',
    String cdObjLin = '',
    bool somenteAtrasados = false,
    bool somentePendentes = true,
  }) async {
    final params = <String, String>{
      'DataInicio': _normalizarDataSql(dataInicio),
      'DataFim': _normalizarDataSql(dataFim),
      'SomenteAtrasados': somenteAtrasados ? '1' : '0',
      'SomentePendentes': somentePendentes ? '1' : '0',
    };

    void addIfNotEmpty(String key, String value) {
      final normalized = value.trim();
      if (normalized.isNotEmpty) params[key] = normalized;
    }

    addIfNotEmpty('CdUne', cdUne);
    addIfNotEmpty('CdVpd', cdVpd);
    addIfNotEmpty('CdCli', cdCli);
    addIfNotEmpty('CdObj', cdObj);
    addIfNotEmpty('NmObj', nmObj);
    addIfNotEmpty('CdObjLin', cdObjLin);

    final response = await http
        .get(
          Uri.parse(
            "$baseUrl/consultar/planejamento-tinturaria",
          ).replace(queryParameters: params),
          headers: {"Content-Type": "application/json"},
        )
        .timeout(const Duration(seconds: 35));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) return List<Map<String, dynamic>>.from(decoded);
      if (decoded is Map<String, dynamic>) {
        final data =
            decoded["data"] ?? decoded["resultados"] ?? decoded["items"];
        if (data is List) return List<Map<String, dynamic>>.from(data);
      }
    }

    String message =
        "Erro ${response.statusCode} ao consultar pedido especial.";
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        message =
            (decoded["erro"] ??
                    decoded["error"] ??
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

  static String _normalizarDataSql(String value) {
    final raw = value.trim();
    if (RegExp(r'^\d{8}$').hasMatch(raw)) return raw;

    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (iso != null) return '${iso.group(1)}${iso.group(2)}${iso.group(3)}';

    final br = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(raw);
    if (br != null) return '${br.group(3)}${br.group(2)}${br.group(1)}';

    return raw;
  }

  static Future<List<Map<String, dynamic>>> buscarArtigoLotes(
      int cdObj) async {
    if (cdObj <= 0) throw "Informe o código do artigo.";
    final response = await http.get(
      Uri.parse("$baseUrl/consulta/wms/artigo-lotes")
          .replace(queryParameters: {"cd_obj": cdObj.toString()}),
    ).timeout(_quickTimeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(_normalizarLote)
            .toList();
      }
      if (decoded is Map<String, dynamic>) {
        final data = decoded["data"] ?? decoded["lotes"] ?? decoded["items"];
        if (data is List) {
          return data
              .whereType<Map<String, dynamic>>()
              .map(_normalizarLote)
              .toList();
        }
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

  static Map<String, dynamic> _normalizarLote(Map<String, dynamic> lote) {
    final cdLot =
        lote["CdLot"] ??
        lote["cdLot"] ??
        lote["cd_lot"] ??
        lote["DetalheId"] ??
        lote["detalhe_id"] ??
        lote["Detalhe"] ??
        lote["detalhe"] ??
        0;
    final nmLot =
        lote["NmLot"] ??
        lote["nmLot"] ??
        lote["nm_lot"] ??
        lote["NmDetalhe"] ??
        lote["nmDetalhe"] ??
        lote["Nome"] ??
        lote["nome"] ??
        lote["Descricao"] ??
        lote["descricao"] ??
        lote["Detalhe"] ??
        lote["detalhe"] ??
        "";
    return {
      ...lote,
      "CdLot": cdLot is int ? cdLot : int.tryParse("$cdLot".trim()) ?? 0,
      "NmLot": "$nmLot".trim(),
    };
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
    final response = await http.get(uri).timeout(_quickTimeout);
    debugPrint(
      '[ETIQUETA] Resposta impressao palete | status=${response.statusCode}',
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
