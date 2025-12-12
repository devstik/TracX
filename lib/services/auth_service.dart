import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // Para debugPrint

class AuthService {
  // --- Credenciais Offline (Novas Constantes) ---
  static const String _adminUsername =
      'admin'; // Usuário fixo para login offline (Privado)
  static const String _adminPassword =
  
      'admin'; // Senha fixa para login offline (Privado)

  // CORREÇÃO: Tornada pública para ser acessível na LoginScreen
  static const String offlineAdminToken =
      'OFFLINE_ADMIN_TOKEN_VALIDO'; // Token "falso" para modo offline (PÚBLICO)

  // --- Chaves e Validade ---
  static const String _tokenKey = 'token'; // Chave usada para salvar o token
  static const String _expiryKey =
      'tokenExpiry'; // Chave para salvar a data de expiração
  static const int _defaultTokenValiditySeconds = 3600; // 60 minutos (usado apenas para login offline)
  static const String _wmsAuthUrl =
      'https://visions.topmanager.com.br/auth/api/usuarios/entrar?identificadorDaAplicacao=LogTech_WMS&chaveDaAplicacaoExterna=uvkmv%2BQHum%2FXhF8grWeW4nKmzKFRk4UwJk74x7FnZbGC6ECvl4nbxUf3h7L%2BCGk25qSA8QOJoovrJtUJlXlsWQ%3D%3D&enderecoDeRetorno=http://qualquer';
  static const String _wmsEmail = 'suporte.wms';
  static const String _wmsPassword = '123456';
  static const String _wmsUsuarioId = '21578';

  // ✅ NOVO MÉTODO (FALTANDO ANTERIORMENTE)
  // --- NOVO: Função para checar se está em modo Offline ---
  static Future<bool> isOfflineModeActive() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(_tokenKey);
    // Verifica se o token salvo é o token falso usado para o modo offline
    return savedToken == offlineAdminToken;
  }

  // --- NOVO: Função para forçar a expiração local do token ---
  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_expiryKey);
    debugPrint('[AUTH] Token local e data de expiração LIMPOS.');
  }

  // --- FUNÇÃO DE LOGIN OFFLINE (NOVA) ---
  /// Tenta logar o usuário usando as credenciais fixas de admin.
  /// Se for bem-sucedido, salva um token não expirável localmente.
  static Future<bool> loginAdminOffline(
    String username,
    String password,
  ) async {
    // 1. Verifica as credenciais fixas (usando os campos privados)
    if (username.toLowerCase() == _adminUsername &&
        password == _adminPassword) {
      final prefs = await SharedPreferences.getInstance();

      // 2. Salva o token offline (usando o campo público) e a data de expiração muito distante
      await prefs.setString(_tokenKey, offlineAdminToken);

      // Define uma data de expiração muito distante (ex: 10 anos) para evitar expiração offline
      final expiryTime = DateTime.now()
          .add(const Duration(days: 3650))
          .toIso8601String();

      await prefs.setString(_expiryKey, expiryTime);

      debugPrint(
        '[AUTH] Login Admin Offline bem-sucedido. Token: $offlineAdminToken',
      );
      return true;
    }

    debugPrint('[AUTH] Falha no Login Admin Offline. Credenciais inválidas.');
    return false;
  }

  // --- Funções de Extração/Decodificação ---
  static String extrairToken(String respostaDaApi) {
    // Tenta extrair o token de uma string do tipo 'token="VALOR_DO_TOKEN"' (Regex original)
    RegExp regex = RegExp(r'(?<==)[\w\.-]+(?=")');
    Match? match = regex.firstMatch(respostaDaApi);

    if (match != null) {
      return match.group(0)!;
    } else {
      // Alternativamente, tenta decodificar JSON se a API retornar um objeto
      try {
        final decodedJson = jsonDecode(respostaDaApi);
        // Assumindo que o campo retornado é 'Token' ou 'token' (em JSON)
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

  // --- Lógica de Verificação de Expiração (AJUSTADA) ---
  // --- Função Principal de Obtenção de Token ---
  static Future<String?> obterTokenAplicacao() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(_tokenKey);

    if (savedToken == offlineAdminToken) {
      debugPrint('[AUTH] Token offline detectado. Retornando modo offline.');
      return savedToken;
    }

    final token = await _solicitarNovoToken();
    if (token != null) {
      debugPrint('[AUTH] Token Força obtido: $token');
    }
    return token;
  }

  static Future<String?> obterTokenLogtech() async {
    final token = await _solicitarNovoTokenWms();
    if (token != null) {
      debugPrint('[AUTH WMS] Token recém-obtido: $token');
    }
    return token;
  }

  // --- Função de Solicitação de Token (API) ---
  static Future<String?> _solicitarNovoToken() async {
    const String apiUrl =
        'https://visions.topmanager.com.br/auth/api/usuarios/entrar?identificadorDaAplicacao=ForcaDeVendas&chaveDaAplicacaoExterna=2awwG8Tqp12sJtzQcyYIzVrYfQNmMg0crxWq8ohNQMlQU4cU5lvO1Y%2FGNN0hbkAD0JNPPQz3489u8paqUO3jOg%3D%3D&enderecoDeRetorno=http://qualquer';
    debugPrint('[AUTH] Solicitando token no endpoint: $apiUrl');

    final Map<String, String> requestBody = {
      "email": "Stik.ForcaDeVendas",
      "senha": "123456",
      "usuarioID": "15980",
    };

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final String newToken = extrairToken(response.body);
        return newToken;
      } else {
        debugPrint(
          'ERRO: Falha ao gerar novo token. Status: ${response.statusCode}',
        );
        debugPrint(response.body);
        return null;
      }
    } catch (e) {
      debugPrint('ERRO DE REDE: Exceção ao tentar obter novo token: $e');
      return null;
    }
  }

  static Future<String?> _solicitarNovoTokenWms() async {
    try {
      debugPrint('[AUTH WMS] Solicitando token no endpoint: $_wmsAuthUrl');
      final response = await http.post(
        Uri.parse(_wmsAuthUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "email": _wmsEmail,
          "senha": _wmsPassword,
          "usuarioID": _wmsUsuarioId,
        }),
      );

      if (response.statusCode == 200) {
        final String newToken = extrairToken(response.body);
        return newToken;
      } else {
        debugPrint(
          '[AUTH WMS] Falha ao gerar novo token. Status: ${response.statusCode}',
        );
        debugPrint(response.body);
        return null;
      }
    } catch (e) {
      debugPrint('[AUTH WMS] ERRO DE REDE: Exceção ao tentar obter novo token: $e');
      return null;
    }
  }
}
