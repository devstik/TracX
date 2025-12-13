import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // Para debugPrint

class AuthService {
  // --- Credenciais Offline ---
  static const String _adminUsername =
      'admin'; // Usuário fixo para login offline
  static const String _adminPassword = 'admin'; // Senha fixa para login offline
  static const String offlineAdminToken =
      'OFFLINE_ADMIN_TOKEN_VALIDO'; // Token "falso" para modo offline

  // --- Chaves e Validade ---
  static const String _tokenKeyAplicacao = 'tokenAplicacao';
  static const String _expiryKeyAplicacao = 'tokenAplicacaoExpiry';
  static const String _tokenKeyWms = 'tokenWms';
  static const String _expiryKeyWms = 'tokenWmsExpiry';
  static const int _defaultTokenValiditySeconds = 3600; // 60 minutos

  // --- Constantes WMS/LogTech ---
  static const String _wmsAuthUrl =
      'https://visions.topmanager.com.br/auth/api/usuarios/entrar?identificadorDaAplicacao=LogTech_WMS&chaveDaAplicacaoExterna=uvkmv%2BQHum%2FXhF8grWeW4nKmzKFRk4UwJk74x7FnZbGC6ECvl4nbxUf3h7L%2BCGk25qSA8QOJoovrJtUJlXlsWQ%3D%3D&enderecoDeRetorno=http://qualquer';
  static const String _wmsEmail = 'suporte.wms';
  static const String _wmsPassword = '123456';
  static const String _wmsUsuarioId = '21578';

  // --- Constantes Força de Vendas (Adicionadas para clareza) ---
  static const String _forcaDeVendasAuthUrl =
      'https://visions.topmanager.com.br/auth/api/usuarios/entrar?identificadorDaAplicacao=ForcaDeVendas&chaveDaAplicacaoExterna=2awwG8Tqp12sJtzQcyYIzVrYfQNmMg0crxWq8ohNQMlQU4cU5lvO1Y%2FGNN0hbkAD0JNPPQz3489u8paqUO3jOg%3D%3D&enderecoDeRetorno=http://qualquer';
  static const String _forcaDeVendasEmail = 'Stik.ForcaDeVendas';
  static const String _forcaDeVendasPassword = '123456';
  static const String _forcaDeVendasUsuarioId = '15980';

  // --- Gerenciamento de Token Local ---

  /// Salva o token e define a data de expiração local (padrão 1 hora).
  static Future<void> _salvarToken(
    String token, {
    required String tokenKey,
    required String expiryKey,
    int validitySeconds = _defaultTokenValiditySeconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(tokenKey, token);

    final expiryTime = DateTime.now()
        .add(Duration(seconds: validitySeconds))
        .toIso8601String();

    await prefs.setString(expiryKey, expiryTime);
    debugPrint(
      '[AUTH] Token salvo localmente com validade de $validitySeconds segundos.',
    );
  }

  /// Verifica se a data de expiração salva está no passado.
  static bool _isTokenExpired(String? expiryString) {
    if (expiryString == null) return true;
    try {
      final expiryDate = DateTime.parse(expiryString);

      // O token offline tem uma expiração muito distante (3650 dias),
      // então é considerado sempre válido
      if (expiryDate.year >= 2030) return false;

      // Adiciona uma pequena tolerância (ex: 5 minutos) antes da expiração real,
      // para garantir que um novo token seja obtido antes de falhar. (Lógica do V1)
      final toleranceTime = expiryDate.subtract(const Duration(minutes: 5));

      return DateTime.now().isAfter(toleranceTime);
    } catch (e) {
      debugPrint('[AUTH] Erro ao analisar data de expiração: $e');
      return true; // Assume expirado em caso de erro de parse
    }
  }

  // --- Funções Auxiliares de Gerenciamento ---

  static Future<bool> isOfflineModeActive() async {
    final prefs = await SharedPreferences.getInstance();
    final tokens = [
      prefs.getString(_tokenKeyAplicacao),
      prefs.getString(_tokenKeyWms),
    ];
    return tokens.any((token) => token == offlineAdminToken);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKeyAplicacao);
    await prefs.remove(_expiryKeyAplicacao);
    await prefs.remove(_tokenKeyWms);
    await prefs.remove(_expiryKeyWms);
    debugPrint('[AUTH] Token local e data de expiração LIMPOS.');
  }

  static Future<bool> loginAdminOffline(
    String username,
    String password,
  ) async {
    if (username.toLowerCase() == _adminUsername &&
        password == _adminPassword) {
      // Define uma expiração de 10 anos
      await _salvarToken(
        offlineAdminToken,
        tokenKey: _tokenKeyAplicacao,
        expiryKey: _expiryKeyAplicacao,
        validitySeconds: 3650 * 24 * 3600,
      );
      await _salvarToken(
        offlineAdminToken,
        tokenKey: _tokenKeyWms,
        expiryKey: _expiryKeyWms,
        validitySeconds: 3650 * 24 * 3600,
      );
      debugPrint(
        '[AUTH] Login Admin Offline bem-sucedido. Token: $offlineAdminToken',
      );
      return true;
    }
    debugPrint('[AUTH] Falha no Login Admin Offline. Credenciais inválidas.');
    return false;
  }

  static String extrairToken(String respostaDaApi) {
    RegExp regex = RegExp(r'(?<==)[\w\.-]+(?=")');
    Match? match = regex.firstMatch(respostaDaApi);

    if (match != null) {
      return match.group(0)!;
    } else {
      try {
        final decodedJson = jsonDecode(respostaDaApi);
        if (decodedJson is Map) {
          if (decodedJson.containsKey('Token')) {
            return decodedJson['Token'] as String;
          }
          if (decodedJson.containsKey('token')) {
            return decodedJson['token'] as String;
          }
        }
      } catch (_) {
        // Ignora erro de parse
      }
      throw Exception(
        'Token não encontrado na resposta da API. Corpo: $respostaDaApi',
      );
    }
  }

  // --- Função Base de Obtenção de Token (Unificada) ---

  /// Lógica centralizada para obter e gerenciar o ciclo de vida do token.
  static Future<String?> _obterTokenBase(
    Future<String?> Function() tokenRequester, {
    required String tokenKey,
    required String expiryKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(tokenKey);
    final expiryString = prefs.getString(expiryKey);

    if (savedToken == offlineAdminToken) {
      debugPrint('[AUTH] Token offline detectado. Retornando modo offline.');
      return savedToken;
    }

    // Se houver um token salvo E ele NÃO estiver expirado, retorna.
    if (savedToken != null &&
        savedToken.isNotEmpty &&
        !_isTokenExpired(expiryString)) {
      debugPrint('[AUTH] Token salvo válido. Retornando...');
      return savedToken;
    }

    // Se não houver token ou se estiver expirado, solicita um novo.
    debugPrint('[AUTH] Token ausente/expirado. Solicitando novo token...');
    final token = await tokenRequester();

    if (token != null) {
      // Salva o novo token com a validade padrão (1h)
      await _salvarToken(
        token,
        tokenKey: tokenKey,
        expiryKey: expiryKey,
      );
    }
    return token;
  }

  // --- Funções Públicas de Acesso ao Token ---

  /// Obtém ou renova o token para a API Força de Vendas.
  static Future<String?> obterTokenAplicacao() async {
    return _obterTokenBase(
      _solicitarNovoTokenForcaDeVendas,
      tokenKey: _tokenKeyAplicacao,
      expiryKey: _expiryKeyAplicacao,
    );
  }

  /// Obtém ou renova o token para a API Logtech (WMS).
  static Future<String?> obterTokenLogtech() async {
    return _obterTokenBase(
      _solicitarNovoTokenWms,
      tokenKey: _tokenKeyWms,
      expiryKey: _expiryKeyWms,
    );
  }

  // --- Funções de Solicitação de Token (Requisição Pura) ---

  /// Solicita novo token para Força de Vendas (NÃO salva, apenas retorna).
  static Future<String?> _solicitarNovoTokenForcaDeVendas() async {
    final Map<String, String> requestBody = {
      "email": _forcaDeVendasEmail,
      "senha": _forcaDeVendasPassword,
      "usuarioID": _forcaDeVendasUsuarioId,
    };

    try {
      final response = await http.post(
        Uri.parse(_forcaDeVendasAuthUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        return extrairToken(response.body);
      } else {
        debugPrint(
          'ERRO: Falha ao gerar novo token Força de Vendas. Status: ${response.statusCode}',
        );
        debugPrint(response.body);
        return null;
      }
    } catch (e) {
      debugPrint('ERRO DE REDE: Exceção ao tentar obter novo token: $e');
      return null;
    }
  }

  /// Solicita novo token para WMS/Logtech (NÃO salva, apenas retorna).
  static Future<String?> _solicitarNovoTokenWms() async {
    final Map<String, String> requestBody = {
      "email": _wmsEmail,
      "senha": _wmsPassword,
      "usuarioID": _wmsUsuarioId,
    };

    try {
      final response = await http.post(
        Uri.parse(_wmsAuthUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        return extrairToken(response.body);
      } else {
        debugPrint(
          '[AUTH WMS] Falha ao gerar novo token. Status: ${response.statusCode}',
        );
        debugPrint(response.body);
        return null;
      }
    } catch (e) {
      debugPrint(
        '[AUTH WMS] ERRO DE REDE: Exceção ao tentar obter novo token: $e',
      );
      return null;
    }
  }
}
