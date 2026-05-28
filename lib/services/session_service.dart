// session_service.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import necessário

/// Chave para SharedPreferences
const String _kLastUsernameKey = 'lastUsername';
const String _kSessionUserIdKey = 'sessionUserId';
const String _kSessionDisplayNameKey = 'sessionDisplayName';

/// Serviço simples de sessão em memória para armazenar o usuário logado
/// e persistir o último username.
class SessionService extends ChangeNotifier {
  String? _userId;
  String? _displayName;

  // Instância de SharedPreferences e flag de inicialização
  late SharedPreferences _prefs;
  bool _isInitialized = false;
  Future<void>? _initFuture;

  SessionService._internal() {
    // Inicializa o SharedPreferences de forma assíncrona
    _initFuture = _initPrefs();
  }

  static final SessionService _instance = SessionService._internal();

  factory SessionService() => _instance;

  // Inicialização assíncrona
  Future<void> _initPrefs() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _ensurePrefs() async {
    if (_isInitialized) return;
    await (_initFuture ??= _initPrefs());
  }

  String? get userId => _userId;
  String? get displayName => _displayName;
  bool get isLoggedIn => _userId != null;
  bool get isAdmin {
    final user = (_userId ?? '').trim().toLowerCase();
    final name = (_displayName ?? '').trim().toLowerCase();
    return user == 'admin' ||
        name == 'admin' ||
        name == 'administrador' ||
        name.startsWith('administrador ');
  }

  String? getUserId() {
    return _userId;
  }

  Future<void> setUser({required String userId, String? displayName}) async {
    _userId = userId.trim();
    _displayName = (displayName ?? userId).trim();
    notifyListeners();

    await _ensurePrefs();
    await _prefs.setString(_kSessionUserIdKey, _userId!);
    await _prefs.setString(_kSessionDisplayNameKey, _displayName!);
  }

  Future<void> clear() async {
    _userId = null;
    _displayName = null;
    notifyListeners();

    await _ensurePrefs();
    await _prefs.remove(_kSessionUserIdKey);
    await _prefs.remove(_kSessionDisplayNameKey);
  }

  Future<bool> restoreUser() async {
    await _ensurePrefs();
    final userId = _prefs.getString(_kSessionUserIdKey)?.trim();
    if (userId == null || userId.isEmpty) return false;

    final displayName = _prefs.getString(_kSessionDisplayNameKey)?.trim();
    _userId = userId;
    _displayName = displayName?.isNotEmpty == true ? displayName : userId;
    notifyListeners();
    return true;
  }

  // Persiste o último username logado
  Future<void> setLastUsername(String username) async {
    // Garante a inicialização antes de usar _prefs
    await _ensurePrefs();
    await _prefs.setString(_kLastUsernameKey, username.trim());
    if (kDebugMode) {
      print('✅ Último username salvo: ${username.trim()}');
    }
  }

  // Recupera o último username salvo
  Future<String?> getLastUsername() async {
    // Garante a inicialização antes de usar _prefs
    await _ensurePrefs();
    return _prefs.getString(_kLastUsernameKey);
  }
}

final SessionService sessionService = SessionService();
