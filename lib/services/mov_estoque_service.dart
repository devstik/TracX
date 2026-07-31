import 'dart:convert';

import 'package:http/http.dart' as http;

class MovEstoqueItem {
  const MovEstoqueItem({
    required this.artigo,
    required this.codigo,
    required this.mae,
    required this.nivel,
    required this.qtEntrada,
    required this.ordem1,
    required this.ordem2,
    required this.ordem3,
  });

  final String artigo;
  final String codigo;
  final String mae;
  final int nivel;
  final double qtEntrada;
  final String ordem1;
  final String ordem2;
  final String ordem3;

  factory MovEstoqueItem.fromJson(Map<dynamic, dynamic> json) {
    return MovEstoqueItem(
      artigo: _text(json['Artigo']),
      codigo: _text(json['Codigo']),
      mae: _text(json['Mae']),
      nivel: _int(json['Nivel']),
      qtEntrada: _double(json['QtEntrada']),
      ordem1: _text(json['Ordem1']),
      ordem2: _text(json['Ordem2']),
      ordem3: _text(json['Ordem3']),
    );
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _double(dynamic value) {
    if (value is num) return value.toDouble();
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return 0;
    var normalized = raw.replaceAll(RegExp(r'\s+'), '');
    if (normalized.contains(',') && normalized.contains('.')) {
      normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
    } else if (normalized.contains(',')) {
      normalized = normalized.replaceAll(',', '.');
    }
    return double.tryParse(normalized) ?? 0;
  }
}

class MovEstoqueService {
  static const String baseUrl = 'http://168.190.90.2:5000';

  static Future<List<MovEstoqueItem>> consultar({
    int cdUne = 0,
    String? dataInicial,
    String? dataFinal,
    int cdArtigo = 0,
  }) async {
    final params = <String, String>{};
    if (cdUne > 0) params['cdUne'] = cdUne.toString();
    if ((dataInicial ?? '').trim().isNotEmpty) {
      params['dataInicial'] = dataInicial!.trim();
    }
    if ((dataFinal ?? '').trim().isNotEmpty) {
      params['dataFinal'] = dataFinal!.trim();
    }
    if (cdArtigo > 0) params['cdArtigo'] = cdArtigo.toString();

    final uri = Uri.parse(
      '$baseUrl/consultar/movimentacao-estoque',
    ).replace(queryParameters: params);

    final response = await http.get(uri).timeout(const Duration(seconds: 25));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map(MovEstoqueItem.fromJson)
            .toList();
      }
      if (decoded is Map<String, dynamic>) {
        final data = decoded['data'] ?? decoded['resultados'];
        if (data is List) {
          return data
              .whereType<Map>()
              .map(MovEstoqueItem.fromJson)
              .toList();
        }
      }
      return const [];
    }

    var message = 'Erro ${response.statusCode} ao consultar movimentação.';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        message =
            (decoded['error'] ?? decoded['erro'] ?? decoded['message'] ?? message)
                .toString();
      }
    } catch (_) {
      if (response.body.trim().isNotEmpty) message = response.body.trim();
    }
    throw Exception(message);
  }
}
