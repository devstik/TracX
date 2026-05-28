import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'estoque_db.dart';

class PadraoCaixaService {
  PadraoCaixaService({EstoqueDbHelper? dbHelper})
    : _dbHelper = dbHelper ?? EstoqueDbHelper();

  final EstoqueDbHelper _dbHelper;

  static const String _nodeUrlPrefKey = 'sync_node_base_url';
  static const String _defaultNodeUrl = 'https://api.stiktech.com.br';
  static const String _lastDailySyncKey = 'padrao_caixa_last_daily_sync';

  // Credenciais da NodeAPI para endpoint protegido /api/artigos.
  static const String _nodeAuthUser = 'anderson';
  static const String _nodeAuthPassword = '142046';
  static const String _nodeTokenKeyPrefix = 'node_api_token_';
  static const String _nodeTokenExpiryKeyPrefix = 'node_api_token_exp_';

  Future<Map<String, dynamic>?> buscarPadraoPorArtigo(
    String artigo, {
    String? artigoMae,
    ValueChanged<String>? onApiDebug,
  }) async {
    final artigoNormalizado = artigo.trim();
    final artigoMaeNormalizado = (artigoMae ?? '').trim();
    if (artigoNormalizado.isEmpty && artigoMaeNormalizado.isEmpty) return null;

    final consultas = <String>[
      if (artigoMaeNormalizado.isNotEmpty) artigoMaeNormalizado,
      if (artigoNormalizado.isNotEmpty &&
          artigoNormalizado.toLowerCase() != artigoMaeNormalizado.toLowerCase())
        artigoNormalizado,
    ];

    final listaCompleta = await _buscarPadroesCaixaNodeApi(
      onApiDebug: onApiDebug,
    );
    if (listaCompleta == null || listaCompleta.isEmpty) return null;

    for (final consulta in consultas) {
      final match = _selecionarMelhorMatch(listaCompleta, consulta);
      if (match != null) {
        await _dbHelper.salvarPadraoCaixa(match);
        return match;
      }
    }

    return null;
  }

  Future<String?> buscarArtigoMaePorSku(
    int codSku, {
    int? cdLot,
    ValueChanged<String>? onApiDebug,
  }) async {
    if (codSku <= 0) return null;

    final baseUrls = await _resolverNodeBaseUrlsArtigos();
    for (final base in baseUrls) {
      final token = await _obterNodeApiToken(base, onApiDebug: onApiDebug);
      if (token == null || token.isEmpty) continue;

      final uri = Uri.parse('$base/api/artigos?CdObj=$codSku');
      final nomeMae = await _consultarArtigos(
        uri,
        codSku: codSku,
        cdLot: cdLot,
        bearerToken: token,
        onApiDebug: onApiDebug,
      );
      if (nomeMae != null && nomeMae.isNotEmpty) return nomeMae;

      final tokenRefresh = await _obterNodeApiToken(
        base,
        onApiDebug: onApiDebug,
        forceRefresh: true,
      );
      if (tokenRefresh == null ||
          tokenRefresh.isEmpty ||
          tokenRefresh == token) {
        continue;
      }

      final nomeMaeRetry = await _consultarArtigos(
        uri,
        codSku: codSku,
        cdLot: cdLot,
        bearerToken: tokenRefresh,
        onApiDebug: onApiDebug,
      );
      if (nomeMaeRetry != null && nomeMaeRetry.isNotEmpty) return nomeMaeRetry;
    }

    return null;
  }

  Future<void> sincronizarPadroesDoDia() async {
    final hoje = DateTime.now().toIso8601String().split('T').first;
    final prefs = await SharedPreferences.getInstance();
    final ultimoSync = prefs.getString(_lastDailySyncKey) ?? '';
    if (ultimoSync == hoje) return;

    final remotos = await _buscarPadroesCaixaNodeApi();
    if (remotos == null || remotos.isEmpty) return;

    await _dbHelper.salvarPadroesCaixa(remotos);
    await prefs.setString(_lastDailySyncKey, hoje);
  }

  static const String _padraoCaixaUrl =
      'https://api.stiktech.com.br/consulta/wms/padrao_caixa';
  static List<Map<String, dynamic>>? _padroesCaixaCache;
  static DateTime? _padroesCaixaCacheAt;
  static const Duration _padroesCaixaCacheTtl = Duration(minutes: 30);

  Future<List<Map<String, dynamic>>?> _buscarPadroesCaixaNodeApi({
    ValueChanged<String>? onApiDebug,
  }) async {
    final cacheAt = _padroesCaixaCacheAt;
    final cache = _padroesCaixaCache;
    if (cache != null &&
        cache.isNotEmpty &&
        cacheAt != null &&
        DateTime.now().difference(cacheAt) < _padroesCaixaCacheTtl) {
      return cache;
    }

    final uri = Uri.parse(_padraoCaixaUrl);
    try {
      final response = await http
          .get(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 12));

      onApiDebug?.call(
        _buildApiDebug(
          uri: uri,
          status: response.statusCode,
          body: response.body,
        ),
      );

      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      final result = _extrairListaPadroes(decoded);
      if (result.isNotEmpty) {
        _padroesCaixaCache = result;
        _padroesCaixaCacheAt = DateTime.now();
        return result;
      }
    } catch (e) {
      onApiDebug?.call('NodeAPI padrao de caixa erro ao consultar $uri: $e');
    }

    return null;
  }

  Future<List<String>> _resolverNodeBaseUrlsArtigos() async {
    final prefs = await SharedPreferences.getInstance();
    final configured = prefs.getString(_nodeUrlPrefKey)?.trim();

    final baseUrls = <String>[
      if (configured != null && configured.isNotEmpty) configured,
      _defaultNodeUrl,
    ];

    final seen = <String>{};
    final normalized = <String>[];
    for (final raw in baseUrls) {
      final value = raw.trim().replaceAll(RegExp(r'/$'), '');
      if (value.isEmpty || seen.contains(value)) continue;
      seen.add(value);
      normalized.add(value);
    }
    return normalized;
  }

  Future<String?> _obterNodeApiToken(
    String baseUrl, {
    ValueChanged<String>? onApiDebug,
    bool forceRefresh = false,
  }) async {
    final key = baseUrl.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final tokenKey = '$_nodeTokenKeyPrefix$key';
    final expiryKey = '$_nodeTokenExpiryKeyPrefix$key';
    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final savedToken = prefs.getString(tokenKey) ?? '';
      final savedExp = prefs.getString(expiryKey) ?? '';
      if (savedToken.isNotEmpty && savedExp.isNotEmpty) {
        final exp = DateTime.tryParse(savedExp);
        if (exp != null &&
            exp.isAfter(DateTime.now().add(const Duration(seconds: 20)))) {
          return savedToken;
        }
      }
    }

    try {
      final uri = Uri.parse('$baseUrl/auth/login');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': _nodeAuthUser,
              'password': _nodeAuthPassword,
            }),
          )
          .timeout(const Duration(seconds: 8));

      onApiDebug?.call(
        _buildApiDebug(
          uri: uri,
          status: response.statusCode,
          body: response.body,
        ),
      );

      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final token = (map['accessToken'] ?? map['token'] ?? '')
          .toString()
          .trim();
      if (token.isEmpty) return null;

      final expiresInRaw = (map['expiresIn'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final exp = DateTime.now().add(
        Duration(seconds: _parseExpiresInSeconds(expiresInRaw)),
      );

      await prefs.setString(tokenKey, token);
      await prefs.setString(expiryKey, exp.toIso8601String());
      return token;
    } catch (e) {
      onApiDebug?.call(
        'NodeAPI auth erro ao consultar $baseUrl/auth/login: $e',
      );
      return null;
    }
  }

  int _parseExpiresInSeconds(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return 3600;
    if (text.endsWith('h')) {
      final n = int.tryParse(text.substring(0, text.length - 1)) ?? 1;
      return n * 3600;
    }
    if (text.endsWith('m')) {
      final n = int.tryParse(text.substring(0, text.length - 1)) ?? 60;
      return n * 60;
    }
    if (text.endsWith('s')) {
      return int.tryParse(text.substring(0, text.length - 1)) ?? 3600;
    }
    return int.tryParse(text) ?? 3600;
  }

  Future<String?> _consultarArtigos(
    Uri uri, {
    required int codSku,
    int? cdLot,
    required String bearerToken,
    ValueChanged<String>? onApiDebug,
  }) async {
    try {
      final response = await http
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $bearerToken',
            },
          )
          .timeout(const Duration(seconds: 8));

      onApiDebug?.call(
        _buildApiDebug(
          uri: uri,
          status: response.statusCode,
          body: response.body,
        ),
      );

      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      final rows = _extractRows(decoded);
      for (final row in rows) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        final sku = _toInt(
          map['CdObj'] ??
              map['cdObj'] ??
              map['ObjetoID'] ??
              map['objetoID'] ??
              map['objetoId'] ??
              map['objeto'],
        );
        if (sku != codSku) continue;
        if (cdLot != null && !_rowPossuiCdLot(map, cdLot)) continue;

        final nomeMae =
            (map['NmObjMae'] ??
                    map['nmObjMae'] ??
                    map['objetoMae'] ??
                    map['ObjMae'] ??
                    '')
                .toString()
                .trim();
        if (nomeMae.isNotEmpty) return nomeMae;
      }
    } catch (e) {
      onApiDebug?.call('NodeAPI artigos erro ao consultar $uri: $e');
    }
    return null;
  }

  List<Map<String, dynamic>> _extrairListaPadroes(dynamic decoded) {
    List<dynamic> rows = const [];
    if (decoded is List) {
      rows = decoded;
    } else if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final possible =
          map['rows'] ??
          map['data'] ??
          map['result'] ??
          map['items'] ??
          map['caixas'] ??
          map['lista'] ??
          map['values'];
      if (possible is List) rows = possible;
      if (rows.isEmpty) {
        final single = map['item'] ?? map['caixa'] ?? map['value'];
        if (single is Map) rows = [single];
      }
    }

    if (rows.isEmpty) return const [];

    final normalized = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final mapped = _normalizarPadrao(Map<String, dynamic>.from(row));
      if (mapped == null) continue;
      normalized.add(mapped);
    }

    return normalized;
  }

  Map<String, dynamic>? _selecionarMelhorMatch(
    List<Map<String, dynamic>> lista,
    String artigo,
  ) {
    if (lista.isEmpty) return null;
    final target = artigo.trim().toLowerCase();
    final targetMae = _extrairArtigoMae(target);

    for (final item in lista) {
      final artigoRow = (item['artigo'] ?? '').toString().trim().toLowerCase();
      if (artigoRow == target) return item;
    }

    for (final item in lista) {
      final artigoRow = (item['artigo'] ?? '').toString().trim().toLowerCase();
      final artigoRowMae = _extrairArtigoMae(artigoRow);
      if (artigoRowMae.isNotEmpty && artigoRowMae == targetMae) return item;
    }

    for (final item in lista) {
      final artigoRow = (item['artigo'] ?? '').toString().trim().toLowerCase();
      if (target.contains(artigoRow) || artigoRow.contains(target)) return item;
    }

    return null;
  }

  Map<String, dynamic>? _normalizarPadrao(Map<String, dynamic> raw) {
    dynamic pick(List<String> keys) {
      for (final key in keys) {
        if (raw.containsKey(key)) return raw[key];
      }
      return null;
    }

    final artigo =
        (pick([
                  'artigo',
                  'Artigo',
                  'ARTIGO',
                  'descricao',
                  'Descricao',
                  'DESCRICAO',
                  'Objeto',
                  'objeto',
                  'NmArtigo',
                  'nmArtigo',
                  'nm_artigo',
                ]) ??
                '')
            .toString()
            .trim();
    if (artigo.isEmpty) return null;

    final caixaP = pick([
      'caixa_p',
      'caixaP',
      'CaixaP',
      'CXP',
      'cxp',
      'caixaPequena',
      'caixa_pequena',
    ]);
    final caixaG = pick([
      'caixa_g',
      'caixaG',
      'CaixaG',
      'CXG',
      'cxg',
      'caixaGrande',
      'caixa_grande',
    ]);
    final enfestado = pick(['enfestado', 'Enfestado', 'ENFE', 'enfe']);
    final enfraldado = pick(['enfraldado', 'Enfraldado', 'ENFR', 'enfr']);
    final disco = pick(['disco', 'Disco', 'D', 'd']);

    final temValor =
        _toInt(caixaP) > 0 ||
        _toInt(caixaG) > 0 ||
        _toInt(enfestado) > 0 ||
        _toInt(enfraldado) > 0 ||
        _toInt(disco) > 0;
    if (!temValor) return null;

    return {
      'artigo': artigo,
      'caixa_p': caixaP,
      'caixa_g': caixaG,
      'enfestado': enfestado,
      'enfraldado': enfraldado,
      'disco': disco,
    };
  }

  List<dynamic> _extractRows(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is! Map) return const [];
    final map = Map<String, dynamic>.from(decoded);
    final possible =
        map['rows'] ??
        map['data'] ??
        map['result'] ??
        map['items'] ??
        map['artigos'] ??
        map['lista'] ??
        map['values'];
    if (possible is List) return possible;
    return const [];
  }

  String _extrairArtigoMae(String descricao) {
    final texto = descricao.trim();
    if (texto.isEmpty) return '';
    final regex = RegExp(r'(.+?\bmm)', caseSensitive: false);
    final match = regex.firstMatch(texto);
    if (match != null) {
      return texto.substring(0, match.end).trim();
    }
    return texto;
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = _toDouble(value);
      return parsed?.toInt() ?? 0;
    }
    return 0;
  }

  bool _rowPossuiCdLot(Map<String, dynamic> row, int cdLot) {
    final valor = row['CdLot'] ?? row['cdLot'] ?? row['Lote'] ?? row['lote'];
    if (valor == null) return false;
    if (valor is List) {
      for (final item in valor) {
        if (_toInt(item) == cdLot) return true;
      }
      return false;
    }
    return _toInt(valor) == cdLot;
  }

  double? _toDouble(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    value = value.replaceAll(' ', '');

    final hasDot = value.contains('.');
    final hasComma = value.contains(',');
    if (hasDot && hasComma) {
      if (value.lastIndexOf(',') > value.lastIndexOf('.')) {
        value = value.replaceAll('.', '').replaceAll(',', '.');
      } else {
        value = value.replaceAll(',', '');
      }
    } else if (hasComma) {
      value = value.replaceAll(',', '.');
    }

    return double.tryParse(value);
  }

  String _buildApiDebug({
    required Uri uri,
    required int status,
    required String body,
  }) {
    final compact = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    final preview = compact.length > 700
        ? '${compact.substring(0, 700)}...'
        : compact;
    return 'NodeAPI padrao de caixa\nURI: $uri\nStatus: $status\nJSON: $preview';
  }
}
