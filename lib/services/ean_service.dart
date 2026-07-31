import 'dart:convert';

import 'package:http/http.dart' as http;

class EanCadastro {
  const EanCadastro({
    required this.id,
    required this.cdObj,
    required this.nmObj,
    required this.nrCao,
  });

  final int id;
  final int cdObj;
  final String nmObj;
  final String nrCao;

  factory EanCadastro.fromJson(Map<dynamic, dynamic> json) {
    return EanCadastro(
      id: _toInt(json['ID']),
      cdObj: _toInt(json['CdObj']),
      nmObj: _text(json['NmObj']),
      nrCao: _text(json['NrCao']),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';
}

class ProximoEan {
  const ProximoEan({required this.ultimoEan, required this.proximoEan});

  final String ultimoEan;
  final String proximoEan;

  factory ProximoEan.fromJson(Map<dynamic, dynamic> json) {
    return ProximoEan(
      ultimoEan: json['ultimo_ean']?.toString().trim() ?? '',
      proximoEan: json['proximo_ean']?.toString().trim() ?? '',
    );
  }
}

class EanCadastroService {
  static const String baseUrl = 'http://168.190.90.2:5000';
  static const Duration _timeout = Duration(seconds: 25);

  static Future<List<EanCadastro>> listar() async {
    final response = await http.get(Uri.parse('$baseUrl/ean13')).timeout(_timeout);
    return _parseLista(response, fallback: 'Erro ao listar EANs.');
  }

  static Future<List<EanCadastro>> pesquisar(String busca) async {
    final termo = busca.trim();
    if (termo.isEmpty) return listar();

    final uri = Uri.parse(
      '$baseUrl/ean13/pesquisar',
    ).replace(queryParameters: {'busca': termo});
    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode == 404) return const [];
    return _parseLista(response, fallback: 'Erro ao pesquisar EANs.');
  }

  static Future<ProximoEan?> obterProximo() async {
    final response = await http
        .get(Uri.parse('$baseUrl/ean13/proximo'))
        .timeout(_timeout);
    if (response.statusCode == 404) return null;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return ProximoEan.fromJson(decoded);
    }
    throw Exception(_mensagemErro(response, 'Erro ao gerar o próximo EAN.'));
  }

  static Future<EanCadastro> cadastrar({
    required int cdObj,
    required String nmObj,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/ean13'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'cd_obj': cdObj, 'nm_obj': nmObj.trim()}),
        )
        .timeout(_timeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        return EanCadastro(
          id: 0,
          cdObj: cdObj,
          nmObj: decoded['nm_obj']?.toString().trim() ?? nmObj.trim(),
          nrCao: decoded['novo_ean']?.toString().trim() ?? '',
        );
      }
    }
    throw Exception(_mensagemErro(response, 'Erro ao cadastrar EAN-13.'));
  }

  static Future<void> atualizar({
    required String ean,
    required int cdObj,
    required String nmObj,
  }) async {
    final response = await http
        .patch(
          Uri.parse('$baseUrl/ean13/$ean'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'cd_obj': cdObj, 'nm_obj': nmObj.trim()}),
        )
        .timeout(_timeout);

    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw Exception(_mensagemErro(response, 'Erro ao atualizar registro.'));
  }

  static Future<void> excluir(String ean) async {
    final response = await http
        .delete(Uri.parse('$baseUrl/ean13/$ean'))
        .timeout(_timeout);

    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw Exception(_mensagemErro(response, 'Erro ao excluir registro.'));
  }

  static List<EanCadastro> _parseLista(
    http.Response response, {
    required String fallback,
  }) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return decoded.whereType<Map>().map(EanCadastro.fromJson).toList();
      }
      if (decoded is Map) {
        final data = decoded['data'] ?? decoded['resultados'];
        if (data is List) {
          return data.whereType<Map>().map(EanCadastro.fromJson).toList();
        }
      }
      return const [];
    }
    throw Exception(_mensagemErro(response, fallback));
  }

  static String _mensagemErro(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        return (decoded['erro'] ?? decoded['error'] ?? decoded['message'] ?? fallback)
            .toString();
      }
    } catch (_) {
      if (response.body.trim().isNotEmpty) return response.body.trim();
    }
    return fallback;
  }
}
