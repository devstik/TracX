import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/checkin_tambores.dart';

class CheckinTamboresService {
  static const String _baseUrl = 'http://168.190.90.2:5000';
  static const String _path = '/consulta/wms/checkin-tambores';
  static const Duration _timeout = Duration(seconds: 12);
  static const Uuid _uuid = Uuid();

  Future<List<CheckinTambores>> listarHistorico({int limite = 100}) async {
    final response = await http
        .get(Uri.parse('$_baseUrl$_path?limite=$limite'))
        .timeout(_timeout);
    final decoded = _decodeResponse(response);

    if (decoded is! List) {
      throw Exception('Resposta invalida ao consultar check-ins.');
    }

    return decoded
        .whereType<Map>()
        .map((item) => CheckinTambores.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<CheckinTambores?> buscarAberto() async {
    final response = await http
        .get(Uri.parse('$_baseUrl$_path/aberto'))
        .timeout(_timeout);
    final decoded = _decodeResponse(response);

    if (decoded == null) return null;
    if (decoded is! Map) {
      throw Exception('Resposta invalida ao consultar check-in aberto.');
    }

    return CheckinTambores.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<List<CheckinTamboresItem>> listarItens(String idCheckin) async {
    final id = int.tryParse(idCheckin);
    if (id == null || id <= 0) {
      throw Exception('ID do check-in invalido.');
    }

    final response = await http
        .get(Uri.parse('$_baseUrl$_path/$id/itens'))
        .timeout(_timeout);
    final decoded = _decodeResponse(response);

    final rawItens = decoded is List
        ? decoded
        : decoded is Map && decoded['itens'] is List
        ? decoded['itens'] as List
        : null;

    if (rawItens == null) {
      throw Exception('Resposta invalida ao consultar tambores bipados.');
    }

    return rawItens
        .whereType<Map>()
        .map(
          (item) =>
              CheckinTamboresItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<CheckinTambores> registrarInicial({
    required int quantidadeTambores,
    required double volumeTotal,
    List<Map<String, dynamic>> itens = const [],
  }) async {
    final idempotencyKey = _uuid.v4();
    final response = await http
        .post(
          Uri.parse('$_baseUrl$_path/inicial'),
          headers: {
            'Content-Type': 'application/json',
            'Idempotency-Key': idempotencyKey,
          },
          body: jsonEncode({
            'idempotency_key': idempotencyKey,
            'quantidade_tambores': quantidadeTambores,
            'volume_total': volumeTotal,
            if (itens.isNotEmpty) 'itens': itens,
          }),
        )
        .timeout(_timeout);
    final decoded = _decodeResponse(response);

    if (decoded is! Map) {
      throw Exception('Resposta invalida ao registrar check-in inicial.');
    }

    return CheckinTambores.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<CheckinTambores> adicionarItem(
    String idCheckin,
    Map<String, dynamic> item,
  ) async {
    final id = int.tryParse(idCheckin);
    if (id == null || id <= 0) {
      throw Exception('ID do check-in invalido.');
    }

    final response = await http
        .post(
          Uri.parse('$_baseUrl$_path/$id/itens'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(item),
        )
        .timeout(_timeout);
    final decoded = _decodeResponse(response);

    if (decoded is! Map) {
      throw Exception('Resposta invalida ao registrar tambor bipado.');
    }

    final map = Map<String, dynamic>.from(decoded);
    final checkin = map['checkin'];
    if (checkin is Map) {
      return CheckinTambores.fromJson(Map<String, dynamic>.from(checkin));
    }

    throw Exception('Resposta sem dados do check-in atualizado.');
  }

  Future<CheckinTambores> removerItem({
    required String idCheckin,
    required String idItem,
  }) async {
    final checkinId = int.tryParse(idCheckin);
    final itemId = int.tryParse(idItem);
    if (checkinId == null || checkinId <= 0 || itemId == null || itemId <= 0) {
      throw Exception('ID do check-in ou do item invalido.');
    }

    final response = await http
        .delete(Uri.parse('$_baseUrl$_path/$checkinId/itens/$itemId'))
        .timeout(_timeout);
    final decoded = _decodeResponse(response);

    if (decoded is! Map) {
      throw Exception('Resposta invalida ao remover tambor bipado.');
    }

    final map = Map<String, dynamic>.from(decoded);
    final checkin = map['checkin'];
    if (checkin is Map) {
      return CheckinTambores.fromJson(Map<String, dynamic>.from(checkin));
    }

    throw Exception('Resposta sem dados do check-in atualizado.');
  }

  Future<CheckinTambores> registrarFinal(CheckinTambores registro) async {
    final id = int.tryParse(registro.id);
    if (id == null || id <= 0) {
      throw Exception('ID do check-in invalido.');
    }

    final response = await http
        .put(Uri.parse('$_baseUrl$_path/$id/final'))
        .timeout(_timeout);
    final decoded = _decodeResponse(response);

    if (decoded is! Map) {
      throw Exception('Resposta invalida ao registrar check-in final.');
    }

    return CheckinTambores.fromJson(Map<String, dynamic>.from(decoded));
  }

  dynamic _decodeResponse(http.Response response) {
    dynamic body;
    if (response.body.trim().isNotEmpty) {
      body = jsonDecode(response.body);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    if (body is Map && body['error'] != null) {
      final error = body['error'].toString();
      if (error.contains('42S02')) {
        throw Exception(
          'Tabela checkin_tambores nao encontrada no banco usado pela API.',
        );
      }
      throw Exception(error);
    }

    throw Exception('Erro ${response.statusCode} ao comunicar com a API.');
  }
}
