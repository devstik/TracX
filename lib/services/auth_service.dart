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
  static const int _defaultTokenValiditySeconds = 3600; // 60 minutos

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
  static Future<bool> _isTokenExpirado() async {
    final prefs = await SharedPreferences.getInstance();
    final expiryString = prefs.getString(_expiryKey);
    final savedToken = prefs.getString(_tokenKey);

    // Se o token salvo for o token offline (PÚBLICO), ele NUNCA expira.
    if (savedToken == offlineAdminToken) {
      debugPrint('[AUTH] Token offline detectado. Não expirável.');
      return false;
    }

    if (expiryString == null) {
      debugPrint(
        '[AUTH] Data de expiração ausente. Token é considerado expirado.',
      );
      return true; // Sem data de expiração, precisa renovar.
    }

    try {
      final expiryTime = DateTime.parse(expiryString);
      final isExpired = DateTime.now().isAfter(
        expiryTime.subtract(const Duration(minutes: 5)),
      ); // Tolerância de 5 minutos

      if (isExpired) {
        debugPrint(
          '[AUTH] Token expirou ou está prestes a expirar. Hora: $expiryString',
        );
      } else {
        debugPrint('[AUTH] Token válido até: $expiryString');
      }
      return isExpired;
    } catch (e) {
      debugPrint(
        '[AUTH] Erro ao parsear data de expiração. Gerando novo token. Erro: $e',
      );
      return true;
    }
  }

  // --- Função Principal de Obtenção de Token ---
  static Future<String?> obterTokenAplicacao() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(_tokenKey);

    // Se não há token OU o token existe mas está expirado, solicita um novo.
    if (savedToken == null || savedToken.isEmpty || await _isTokenExpirado()) {
      debugPrint('[AUTH] Token ausente/expirado. Solicitando novo token...');
      return await _solicitarNovoToken();
    }

    debugPrint('[AUTH] Token válido encontrado e retornado.');
    return savedToken;
  }

  // --- Função de Solicitação de Token (API) ---
  static Future<String?> _solicitarNovoToken() async {
    const String apiUrl =
        'https://visions.topmanager.com.br/auth/api/usuarios/entrar?identificadorDaAplicacao=ForcaDeVendas&chaveDaAplicacaoExterna=2awwG8Tqp12sJtzQcyYIzVrYfQNmMg0crxWq8ohNQMlQU4cU5lvO1Y%2FGNN0hbkAD0JNPPQz3489u8paqUO3jOg%3D%3D&enderecoDeRetorno=http://qualquer';

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
        final prefs = await SharedPreferences.getInstance();

        // 1. Salva o novo token
        await prefs.setString(_tokenKey, newToken);

        // 2. Calcula e salva a data de expiração
        final expiryTime = DateTime.now()
            .add(const Duration(seconds: _defaultTokenValiditySeconds))
            .toIso8601String();

        await prefs.setString(_expiryKey, expiryTime);

        debugPrint('[AUTH] Novo token salvo com validade até: $expiryTime');
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
}
