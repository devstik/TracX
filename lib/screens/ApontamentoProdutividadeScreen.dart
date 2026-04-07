import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_helper;
import '../services/auth_service.dart' as top_auth;

// =========================================================================
// CONFIGURAÇÃO DE REDE
// =========================================================================
const String _kBaseUrlFlask = "http://168.190.90.2:5000";
const String _kMapaEficienciaEmbEndpoint =
    "/apontamento/mapa-eficiencia-emb";
const String _kFalhaTipoBEndpoint = "/consultar/falha-tipo-b";
const String _kConsultaApiBase =
    "https://mediumpurple-loris-159660.hostingersite.com";

// =========================================================================
// 🎨 PALETA OFICIAL (PADRÃO HOME + SPLASH)
// =========================================================================
const Color _kPrimaryColor = Color(0xFF2563EB);
const Color _kAccentColor = Color(0xFF60A5FA);

const Color _kBgTop = Color(0xFF050A14);
const Color _kBgBottom = Color(0xFF0B1220);

const Color _kSurface = Color(0xFF101B34);
const Color _kSurface2 = Color(0xFF0F172A);

const Color _kTextPrimary = Color(0xFFF9FAFB);
const Color _kTextSecondary = Color(0xFF9CA3AF);

const Color _kBorderSoft = Color(0x33FFFFFF);
const String _kPaleteTipoBFixo = 'PA-L1-R500-D-P1';
const String _kTopmanagerBaseUrl = 'visions.topmanager.com.br';
const String _kEmpresaIdOrdemProducao = '2';
const String _kOrdensFabricacaoPath =
    '/Servidor_2.8.0_api/logtechwms/itemdemapadeproducao/ordensdefabricacao';
const String _kIncluirOrdemFabricacaoPath =
    '/Servidor_2.8.0_api/logtechwms/itemdemapadeproducao/incluirordemdefabricacao';
const String _kErroOrdemFabricacaoGenerico =
    'Não foi possível criar a Ordem de Fabricação.';

class _ResultadoOrdemFabricacao {
  final int? id;
  final String? erro;

  const _ResultadoOrdemFabricacao({this.id, this.erro});
}

// =========================================================================
// SETORES BLOQUEADOS (não aparecem na lista)
// =========================================================================
const List<String> _kSetoresBloqueados = ['TECELAGEM', 'TINTURARIA'];

// Setor que dispensa seleção de máquina
const String _kSetorSemMaquina = 'REVISAO';

// =========================================================================
// MODELOS
// =========================================================================
class Setor {
  final int codigo;
  final String nome;

  Setor({required this.codigo, required this.nome});

  factory Setor.fromJson(Map<String, dynamic> json) {
    return Setor(
      codigo: json['Codigo'] is int
          ? json['Codigo']
          : int.tryParse(json['Codigo'].toString()) ?? 0,
      nome: json['Nome']?.toString() ?? '',
    );
  }
}

class Maquina {
  final int codigo;
  final String nome;

  Maquina({required this.codigo, required this.nome});

  factory Maquina.fromJson(Map<String, dynamic> json) {
    return Maquina(
      codigo: json['Codigo'] is int
          ? json['Codigo']
          : int.tryParse(json['Codigo'].toString()) ?? 0,
      nome: json['Nome']?.toString() ?? '',
    );
  }
}

class UsuarioOperador {
  final int id;
  final String cdUser;
  final String nmUser;

  UsuarioOperador({
    required this.id,
    required this.cdUser,
    required this.nmUser,
  });

  factory UsuarioOperador.fromJson(Map<String, dynamic> json) {
    return UsuarioOperador(
      id: json['Id'] is int ? json['Id'] : int.tryParse('${json['Id']}') ?? 0,
      cdUser: json['CdUser']?.toString() ?? '',
      nmUser: json['NmUser']?.toString() ?? '',
    );
  }
}

class _DefeitoTipoB {
  final String codigo;
  final String nome;

  const _DefeitoTipoB(this.codigo, this.nome);

  factory _DefeitoTipoB.fromJson(Map<String, dynamic> json) {
    return _DefeitoTipoB(
      (json['ID'] ?? json['Id'] ?? json['id'] ?? '').toString().trim(),
      (json['NmFalaTipoB'] ?? json['NmFalhaTipoB'] ?? json['nome'] ?? '')
          .toString()
          .trim(),
    );
  }
}

// =========================================================================
// DATABASE SERVICE (SQLITE)
// =========================================================================
class DatabaseService {
  static Database? _database;
  static const String _dbName = 'stik_produtos.db';
  static const String _tableProdutos = 'produtos';
  static const String _lastSyncKey = 'last_sync_timestamp';

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    String dbPath = path_helper.join(await getDatabasesPath(), _dbName);
    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableProdutos (
            objetoID TEXT,
            detalheID TEXT,
            objeto TEXT,
            detalhe TEXT,
            empresaID TEXT,
            centroDeCustosID TEXT,
            PRIMARY KEY (objetoID, detalheID)
          )
        ''');
      },
    );
  }

  static Future<bool> precisaSincronizar() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_lastSyncKey);
    if (lastSync == null) return true;
    final lastSyncDate = DateTime.parse(lastSync);
    final now = DateTime.now();
    final difference = now.difference(lastSyncDate);
    return difference.inHours >= 24;
  }

  static Future<void> marcarSincronizacao() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
  }

  static Future<void> salvarProdutos(
    List<Map<String, dynamic>> produtos,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (var produto in produtos) {
      batch.insert(_tableProdutos, {
        'objetoID': produto['objetoID']?.toString() ?? '',
        'detalheID': produto['detalheID']?.toString() ?? '',
        'objeto': produto['objeto']?.toString() ?? '',
        'detalhe': produto['detalhe']?.toString() ?? '',
        'empresaID': produto['empresaID']?.toString() ?? '',
        'centroDeCustosID': produto['centroDeCustosID']?.toString() ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<Map<String, dynamic>?> buscarProduto(
    String objetoID,
    String detalheID,
  ) async {
    final db = await database;
    final results = await db.query(
      _tableProdutos,
      where: 'objetoID = ? AND detalheID = ?',
      whereArgs: [objetoID, detalheID],
      limit: 1,
    );
    if (results.isNotEmpty) return results.first;
    return null;
  }

  static Future<List<Map<String, dynamic>>> buscarPorObjetoID(
    String objetoID,
  ) async {
    final db = await database;
    return await db.query(
      _tableProdutos,
      where: 'objetoID = ?',
      whereArgs: [objetoID],
    );
  }

  static Future<List<Map<String, dynamic>>> buscarArtigosPorNome(
    String termo, {
    String? objetoIDRestrito,
  }) async {
    final db = await database;
    final termoBusca = '%${termo.trim().toUpperCase()}%';
    final restrito = (objetoIDRestrito ?? '').trim();
    final restritoNormalizado = _normalizarCodigoConsulta(restrito);

    if (restrito.isNotEmpty) {
      return await db.rawQuery(
        '''
        SELECT objetoID, objeto
        FROM $_tableProdutos
        WHERE (objetoID = ? OR ltrim(objetoID, '0') = ?)
          AND UPPER(objeto) LIKE ?
        GROUP BY objetoID, objeto
        ORDER BY objeto
        LIMIT 60
        ''',
        [restrito, restritoNormalizado, termoBusca],
      );
    }

    return await db.rawQuery(
      '''
      SELECT objetoID, objeto
      FROM $_tableProdutos
      WHERE UPPER(objeto) LIKE ?
      GROUP BY objetoID, objeto
      ORDER BY objeto
      LIMIT 60
      ''',
      [termoBusca],
    );
  }

  static Future<List<Map<String, dynamic>>> buscarLotesPorObjetoID(
    String objetoID, {
    String termo = '',
  }) async {
    final db = await database;
    final objetoNormalizado = _normalizarCodigoConsulta(objetoID);
    final termoBusca = '%${termo.trim().toUpperCase()}%';

    return await db.rawQuery(
      '''
      SELECT detalheID, detalhe
      FROM $_tableProdutos
      WHERE (objetoID = ? OR ltrim(objetoID, '0') = ?)
        AND UPPER(detalhe) LIKE ?
      GROUP BY detalheID, detalhe
      ORDER BY detalhe
      LIMIT 100
      ''',
      [objetoID, objetoNormalizado, termoBusca],
    );
  }

  static Future<void> limparProdutos() async {
    final db = await database;
    await db.delete(_tableProdutos);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncKey);
  }

  static Future<int> contarProdutos() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableProdutos',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static String _normalizarCodigoConsulta(String valor) {
    final texto = valor.trim();
    if (texto.isEmpty) return '';
    final semZeros = texto.replaceFirst(RegExp(r'^0+'), '');
    return semZeros.isEmpty ? '0' : semZeros;
  }

  static Future<bool> sincronizarTodosProdutos() async {
    try {
      await marcarSincronizacao();
      return true;
    } catch (e) {
      debugPrint('[ERRO SYNC] $e');
      return false;
    }
  }

  // ── Setores cache ─────────────────────────────────────────────────────
  static const String _tableSetores = 'setores';
  static const String _tableMaquinas = 'maquinas';
  static const String _lastSyncSetoresKey = 'last_sync_setores_timestamp';

  static Future<void> _garantirTabelasSetoresMaquinas() async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableSetores (
        codigo INTEGER PRIMARY KEY,
        nome TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableMaquinas (
        codigo INTEGER PRIMARY KEY,
        nome TEXT NOT NULL,
        setorId INTEGER NOT NULL
      )
    ''');
  }

  static Future<bool> precisaSincronizarSetores() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_lastSyncSetoresKey);
    if (lastSync == null) return true;
    return DateTime.now().difference(DateTime.parse(lastSync)).inHours >= 24;
  }

  static Future<void> _marcarSincronizacaoSetores() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastSyncSetoresKey,
      DateTime.now().toIso8601String(),
    );
  }

  static Future<void> salvarSetores(List<Setor> setores) async {
    await _garantirTabelasSetoresMaquinas();
    final db = await database;
    final batch = db.batch();
    batch.delete(_tableSetores);
    for (var s in setores) {
      batch.insert(_tableSetores, {
        'codigo': s.codigo,
        'nome': s.nome,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    await _marcarSincronizacaoSetores();
  }

  static Future<List<Setor>> carregarSetoresCache() async {
    await _garantirTabelasSetoresMaquinas();
    final db = await database;
    final rows = await db.query(_tableSetores, orderBy: 'codigo');
    return rows
        .map(
          (r) => Setor(codigo: r['codigo'] as int, nome: r['nome'] as String),
        )
        .toList();
  }

  static Future<bool> temSetoresCache() async {
    await _garantirTabelasSetoresMaquinas();
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableSetores',
    );
    return (Sqflite.firstIntValue(result) ?? 0) > 0;
  }

  // ── Máquinas cache ────────────────────────────────────────────────────
  static Future<void> salvarMaquinas(
    int setorId,
    List<Maquina> maquinas,
  ) async {
    await _garantirTabelasSetoresMaquinas();
    final db = await database;
    final batch = db.batch();
    batch.delete(_tableMaquinas, where: 'setorId = ?', whereArgs: [setorId]);
    for (var m in maquinas) {
      batch.insert(_tableMaquinas, {
        'codigo': m.codigo,
        'nome': m.nome,
        'setorId': setorId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Maquina>> carregarMaquinasCache(int setorId) async {
    await _garantirTabelasSetoresMaquinas();
    final db = await database;
    final rows = await db.query(
      _tableMaquinas,
      where: 'setorId = ?',
      whereArgs: [setorId],
      orderBy: 'nome',
    );
    return rows
        .map(
          (r) => Maquina(codigo: r['codigo'] as int, nome: r['nome'] as String),
        )
        .toList();
  }

  static Future<bool> temMaquinasCache(int setorId) async {
    await _garantirTabelasSetoresMaquinas();
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableMaquinas WHERE setorId = ?',
      [setorId],
    );
    return (Sqflite.firstIntValue(result) ?? 0) > 0;
  }

  static Future<void> limparSetoresMaquinas() async {
    await _garantirTabelasSetoresMaquinas();
    final db = await database;
    await db.delete(_tableSetores);
    await db.delete(_tableMaquinas);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncSetoresKey);
  }
}

// =========================================================================
// AUTH SERVICE
// =========================================================================
class AuthService {
  static const String _tokenKey = 'jwt_token';
  static const String _expiryKey = 'jwt_expiry';
  static const String _loginUrl =
      "https://mediumpurple-loris-159660.hostingersite.com/auth/login";

  static Future<void> limparToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_expiryKey);
  }

  static Future<String?> obterToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final expiry = prefs.getString(_expiryKey);
    if (token != null &&
        expiry != null &&
        DateTime.now().isBefore(DateTime.parse(expiry))) {
      return token;
    }
    return await _login();
  }

  static Future<String?> _login() async {
    try {
      final response = await http.post(
        Uri.parse(_loginUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": "anderson", "password": "142046"}),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final token = json["accessToken"];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, token);
        await prefs.setString(
          _expiryKey,
          DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
        );
        return token;
      } else {
        debugPrint("Erro login: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      debugPrint("Erro login JWT: $e");
    }
    return null;
  }
}

// =========================================================================
// SETOR/MAQUINA SERVICE
// =========================================================================
class SetorMaquinaService {
  static bool _setorBloqueado(String nome) {
    final nomeUpper = nome.toUpperCase().trim();
    return _kSetoresBloqueados.any((b) => nomeUpper.contains(b));
  }

  static Future<List<Setor>> buscarSetores() async {
    final temCache = await DatabaseService.temSetoresCache();
    final precisaSync = await DatabaseService.precisaSincronizarSetores();

    if (temCache && !precisaSync) {
      final todos = await DatabaseService.carregarSetoresCache();
      return todos.where((s) => !_setorBloqueado(s.nome)).toList();
    }

    try {
      final response = await http.get(
        Uri.parse("$_kBaseUrlFlask/consulta/setores"),
        headers: {"Content-Type": "application/json"},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final setores = data.map((e) => Setor.fromJson(e)).toList();
        await DatabaseService.salvarSetores(setores);
        return setores.where((s) => !_setorBloqueado(s.nome)).toList();
      }
    } catch (e) {
      debugPrint("Erro buscarSetores: $e");
    }

    if (temCache) {
      final todos = await DatabaseService.carregarSetoresCache();
      return todos.where((s) => !_setorBloqueado(s.nome)).toList();
    }
    return [];
  }

  static Future<List<Maquina>> buscarMaquinas(int setorId) async {
    final temCache = await DatabaseService.temMaquinasCache(setorId);
    final precisaSync = await DatabaseService.precisaSincronizarSetores();

    if (temCache && !precisaSync) {
      return await DatabaseService.carregarMaquinasCache(setorId);
    }

    try {
      final response = await http.get(
        Uri.parse("$_kBaseUrlFlask/consulta/maquinas?setor=$setorId"),
        headers: {"Content-Type": "application/json"},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final maquinas = data.map((e) => Maquina.fromJson(e)).toList();
        await DatabaseService.salvarMaquinas(setorId, maquinas);
        return maquinas;
      }
    } catch (e) {
      debugPrint("Erro buscarMaquinas: $e");
    }

    if (temCache) return await DatabaseService.carregarMaquinasCache(setorId);
    return [];
  }
}

class UsuarioOperadorService {
  static Future<List<UsuarioOperador>> buscarUsuarios() async {
    try {
      final response = await http.get(
        Uri.parse("$_kBaseUrlFlask/consultar/usuarios"),
        headers: {"Content-Type": "application/json"},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data
            .map((e) => UsuarioOperador.fromJson(Map<String, dynamic>.from(e)))
            .where((u) => u.cdUser.trim().isNotEmpty)
            .toList();
      }
      debugPrint(
        "Erro buscarUsuarios: ${response.statusCode} - ${response.body}",
      );
    } catch (e) {
      debugPrint("Erro buscarUsuarios: $e");
    }
    return [];
  }
}

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _kBgBottom,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _kPrimaryColor,
        brightness: Brightness.dark,
      ),
    ),
    home: const SplashScreen(),
  ),
);

// =========================================================================
// SPLASH SCREEN
// =========================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = 'Inicializando...';
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    setState(() {
      _status = 'Verificando banco de dados...';
      _progress = 0.2;
    });

    await Future.delayed(const Duration(milliseconds: 500));

    final precisaSync = await DatabaseService.precisaSincronizar();
    final totalProdutos = await DatabaseService.contarProdutos();

    if (precisaSync || totalProdutos == 0) {
      setState(() {
        _status = 'Sincronizando produtos...';
        _progress = 0.4;
      });

      final sucesso = await DatabaseService.sincronizarTodosProdutos();

      if (sucesso) {
        final novoTotal = await DatabaseService.contarProdutos();
        setState(() {
          _status = '$novoTotal produtos sincronizados!';
          _progress = 1.0;
        });
      } else {
        setState(() {
          _status = 'Erro na sincronização. Usando cache.';
          _progress = 1.0;
        });
      }
    } else {
      setState(() {
        _status = 'Cache atualizado ($totalProdutos produtos)';
        _progress = 1.0;
      });
    }

    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ProducaoTabsScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_kBgTop, _kSurface2, _kBgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.factory_outlined,
                  size: 100,
                  color: _kTextPrimary,
                ),
                const SizedBox(height: 30),
                const Text(
                  'Apontamentos',
                  style: TextStyle(
                    color: _kTextPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 50),
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    _kAccentColor,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _status,
                  style: const TextStyle(color: _kTextSecondary, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// TABS PRINCIPAL
// =========================================================================
class ProducaoTabsScreen extends StatefulWidget {
  final bool mostrarTipoB;
  final bool mostrarSomenteTipoB;
  final String? artigoEsperadoId;
  final String? artigoEsperadoNome;
  final VoidCallback? onApontamentoConcluido;
  final bool fecharAoConcluir;

  const ProducaoTabsScreen({
    super.key,
    this.mostrarTipoB = true,
    this.mostrarSomenteTipoB = false,
    this.artigoEsperadoId,
    this.artigoEsperadoNome,
    this.onApontamentoConcluido,
    this.fecharAoConcluir = false,
  });
  @override
  State<ProducaoTabsScreen> createState() => _ProducaoTabsScreenState();
}

class _ProducaoTabsScreenState extends State<ProducaoTabsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.mostrarSomenteTipoB ? 1 : (widget.mostrarTipoB ? 2 : 1),
      vsync: this,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sincronizacaoAutomatica();
    });
  }

  Future<void> _sincronizacaoAutomatica() async {
    try {
      final precisaSync = await DatabaseService.precisaSincronizar();
      final totalProdutos = await DatabaseService.contarProdutos();
      if (precisaSync || totalProdutos == 0) {
        final sucesso = await DatabaseService.sincronizarTodosProdutos();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                sucesso
                    ? "Sincronização automática concluída!"
                    : "Erro na sincronização automática",
              ),
              backgroundColor: sucesso ? Colors.green : Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Erro sincronização automática: $e");
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _mostrarMenuOpcoes() async {
    final totalProdutos = await DatabaseService.contarProdutos();
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString('last_sync_timestamp');
    String ultimaSync = 'Nunca';

    if (lastSync != null) {
      final date = DateTime.parse(lastSync);
      ultimaSync =
          '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurface,
        title: const Text(
          'Configurações',
          style: TextStyle(color: _kTextPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Produtos em cache: $totalProdutos',
              style: const TextStyle(color: _kTextSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Última sincronização: $ultimaSync',
              style: const TextStyle(color: _kTextSecondary),
            ),
            const SizedBox(height: 20),
            const Text(
              'Sincronização automática a cada 24h',
              style: TextStyle(fontSize: 12, color: _kTextSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _forcarSincronizacao();
            },
            child: const Text(
              'Sincronizar Agora',
              style: TextStyle(color: _kAccentColor),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx2) => AlertDialog(
                  backgroundColor: _kSurface,
                  title: const Text(
                    'Confirmar',
                    style: TextStyle(color: _kTextPrimary),
                  ),
                  content: const Text(
                    'Deseja limpar todo o cache local?',
                    style: TextStyle(color: _kTextSecondary),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx2, false),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(color: _kTextSecondary),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx2, true),
                      child: const Text(
                        'Limpar',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await DatabaseService.limparProdutos();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Cache limpo com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Limpar Cache',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Fechar',
              style: TextStyle(color: _kTextSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _forcarSincronizacao() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          color: _kSurface,
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: _kAccentColor),
                SizedBox(height: 16),
                Text(
                  'Sincronizando...',
                  style: TextStyle(color: _kTextPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final sucesso = await DatabaseService.sincronizarTodosProdutos();

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sucesso ? 'Sincronização concluída!' : 'Erro na sincronização',
          ),
          backgroundColor: sucesso ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final isMacOs = defaultTargetPlatform == TargetPlatform.macOS;
    int turnoNum = (hour >= 6 && hour < 14)
        ? 8
        : (hour >= 14 && hour < 22)
        ? 9
        : 10;
    String turnoLetra = turnoNum == 8 ? 'A' : (turnoNum == 9 ? 'B' : 'C');

    return TooltipVisibility(
      visible: !isMacOs,
      child: Scaffold(
        backgroundColor: _kBgBottom,
        appBar: AppBar(
          elevation: 0,
          centerTitle: true,
          backgroundColor: _kBgBottom,
          foregroundColor: _kTextPrimary,
          iconTheme: const IconThemeData(color: _kTextPrimary),
          title: const Text(
            'Apontamentos',
            style: TextStyle(color: _kTextPrimary, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings, color: _kTextPrimary),
              onPressed: _mostrarMenuOpcoes,
            ),
          ],
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_kBgTop, _kSurface2, _kBgBottom],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          bottom: widget.mostrarSomenteTipoB
              ? null
              : widget.mostrarTipoB
              ? TabBar(
                  controller: _tabController,
                  labelColor: _kTextPrimary,
                  unselectedLabelColor: _kTextSecondary,
                  indicatorColor: _kAccentColor,
                  tabs: const [
                    Tab(text: 'Tipo A', icon: Icon(Icons.factory_outlined)),
                    Tab(text: 'Tipo B', icon: Icon(Icons.factory_outlined)),
                  ],
                )
              : null,
        ),
        body: widget.mostrarSomenteTipoB
            ? FormularioGeral(
                tipo: 'B',
                turno: turnoNum,
                turnoLetra: turnoLetra,
                artigoEsperadoId: widget.artigoEsperadoId,
                artigoEsperadoNome: widget.artigoEsperadoNome,
                onApontamentoConcluido: widget.onApontamentoConcluido,
                fecharAoConcluir: widget.fecharAoConcluir,
              )
            : widget.mostrarTipoB
            ? TabBarView(
                controller: _tabController,
                children: [
                  FormularioGeral(
                    tipo: 'A',
                    turno: turnoNum,
                    turnoLetra: turnoLetra,
                    artigoEsperadoId: widget.artigoEsperadoId,
                    artigoEsperadoNome: widget.artigoEsperadoNome,
                    onApontamentoConcluido: widget.onApontamentoConcluido,
                    fecharAoConcluir: widget.fecharAoConcluir,
                  ),
                  FormularioGeral(
                    tipo: 'B',
                    turno: turnoNum,
                    turnoLetra: turnoLetra,
                    artigoEsperadoId: widget.artigoEsperadoId,
                    artigoEsperadoNome: widget.artigoEsperadoNome,
                    onApontamentoConcluido: widget.onApontamentoConcluido,
                    fecharAoConcluir: widget.fecharAoConcluir,
                  ),
                ],
              )
            : FormularioGeral(
                tipo: 'A',
                
                turno: turnoNum,
                turnoLetra: turnoLetra,
                artigoEsperadoId: widget.artigoEsperadoId,
                artigoEsperadoNome: widget.artigoEsperadoNome,
                onApontamentoConcluido: widget.onApontamentoConcluido,
                fecharAoConcluir: widget.fecharAoConcluir,
              ),
      ),
    );
  }
}

// =========================================================================
// FORMULÁRIO GERAL
// =========================================================================

/// Etapas do fluxo do Tipo A
enum _EtapaA { identificacao, producao }

class FormularioGeral extends StatefulWidget {
  final String tipo;
  final int turno;
  final String turnoLetra;
  final String? artigoEsperadoId;
  final String? artigoEsperadoNome;
  final VoidCallback? onApontamentoConcluido;
  final bool fecharAoConcluir;

  const FormularioGeral({
    required this.tipo,
    required this.turno,
    required this.turnoLetra,
    this.artigoEsperadoId,
    this.artigoEsperadoNome,
    this.onApontamentoConcluido,
    this.fecharAoConcluir = false,
    super.key,
  });

  @override
  State<FormularioGeral> createState() => _FormularioGeralState();
}

class _FormularioGeralState extends State<FormularioGeral> {
  // ── Etapa atual (só usado em Tipo A) ──────────────────────────────────
  _EtapaA _etapaA = _EtapaA.identificacao;

  // ── Campos de saída (read-only) ───────────────────────────────────────
  final _artigoController = TextEditingController();
  final _detalheController = TextEditingController();
  final _qtdeController = TextEditingController();
  final _qtde2Controller = TextEditingController();
  final _operadorController = TextEditingController();
  final _operador2Controller = TextEditingController();
  final _setorController = TextEditingController();
  final _maquinaController = TextEditingController();
  final _maquina2Controller = TextEditingController();
  final _defeitoController = TextEditingController();
  final _dataController = TextEditingController();
  final _turnoInfoController = TextEditingController();
  final _ordemProducaoController = TextEditingController();
  final _palletController = TextEditingController();
  String? _defeitoSelecionadoCodigo;
  String? _operadorCdUserSelecionado;
  String? _operador2CdUserSelecionado;
  List<_DefeitoTipoB> _defeitosTipoB = [];
  bool _loadingDefeitosTipoB = false;
  List<UsuarioOperador> _usuariosOperadores = [];
  bool _loadingUsuariosOperadores = false;

  // ── Coletor HID – Artigo ──────────────────────────────────────────────
  final _coletorArtigoController = TextEditingController();
  final FocusNode _coletorArtigoFocus = FocusNode();

  // ── Dropdown ──────────────────────────────────────────────────────────
  List<Setor> _setores = [];
  List<Maquina> _maquinas = [];
  Setor? _setorSelecionado;
  Maquina? _maquinaSelecionada;
  Maquina? _maquinaSelecionadaSecundaria;
  bool _loadingSetores = false;
  bool _loadingMaquinas = false;

  // ── Produto selecionado ───────────────────────────────────────────────
  String _cdObjReal = "";
  String _detalheReal = "";
  bool _isLoading = false;
  String _artigoEsperadoId = "";
  String _artigoEsperadoNome = "";
  List<Map<String, dynamic>> _lotesDisponiveis = [];
  bool _buscandoOrdemProducao = false;

  // ── Estado visual do coletor ──────────────────────────────────────────
  bool _coletorArtigoAtivo = false;

  bool get _isRevisao =>
      _setorSelecionado != null &&
      _setorSelecionado!.nome.toUpperCase().trim().contains(_kSetorSemMaquina);

  bool get _maquinasSelecionadasDuplicadas =>
      !_isRevisao &&
      _maquinaSelecionada != null &&
      _maquinaSelecionadaSecundaria != null &&
      _maquinaSelecionada!.codigo == _maquinaSelecionadaSecundaria!.codigo;

  String get _resumoMaquinas {
    if (_isRevisao) return '';
    final maqPrincipal = _maquinaSelecionada?.nome ?? '—';
    final maqSecundaria = _maquinaSelecionadaSecundaria?.nome;
    if (maqSecundaria == null || maqSecundaria.trim().isEmpty) {
      return '  •  Máquina: $maqPrincipal';
    }
    return '  •  Máquinas: $maqPrincipal / $maqSecundaria';
  }

  String _descricaoTurno(String letra) {
    switch (letra.trim().toUpperCase()) {
      case 'A':
        return 'Manhã';
      case 'B':
        return 'Tarde';
      case 'C':
        return 'Noite';
      default:
        return letra;
    }
  }

  // ── Verifica se a Etapa 1 está completa para habilitar "Avançar" ──────
  bool get _etapa1Completa {
    if ((_operadorCdUserSelecionado ?? '').trim().isEmpty) return false;
    if (_setorSelecionado == null) return false;
    if (!_isRevisao && _maquinaSelecionada == null) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    if (widget.tipo == 'A' || widget.tipo == 'B') {
      _carregarSetores();
      _carregarUsuariosOperadores();
    }
    if (widget.tipo == 'B') {
      _carregarDefeitosTipoB();
    }
    _artigoEsperadoId = widget.artigoEsperadoId?.trim() ?? '';
    _artigoEsperadoNome = widget.artigoEsperadoNome?.trim() ?? '';
    _dataController.text = DateFormat('dd/MM/yyyy').format(DateTime.now());
    _turnoInfoController.text = _descricaoTurno(widget.turnoLetra);
    if (widget.tipo == 'B') {
      _palletController.text = _kPaleteTipoBFixo;
    }
  }

  @override
  void dispose() {
    _artigoController.dispose();
    _detalheController.dispose();
    _qtdeController.dispose();
    _qtde2Controller.dispose();
    _operadorController.dispose();
    _operador2Controller.dispose();
    _setorController.dispose();
    _maquinaController.dispose();
    _maquina2Controller.dispose();
    _defeitoController.dispose();
    _dataController.dispose();
    _turnoInfoController.dispose();
    _ordemProducaoController.dispose();
    _palletController.dispose();
    _coletorArtigoController.dispose();
    _coletorArtigoFocus.dispose();
    super.dispose();
  }

  int _compareAlpha(String a, String b) {
    final aNorm = a.trim().toUpperCase();
    final bNorm = b.trim().toUpperCase();
    return aNorm.compareTo(bNorm);
  }

  String _normalizarCodigo(String valor) {
    final trimmed = valor.trim();
    if (trimmed.isEmpty) return '';
    final asInt = int.tryParse(trimmed);
    if (asInt != null) return asInt.toString();
    return trimmed;
  }

  String _labelDefeito(_DefeitoTipoB defeito) =>
      '${defeito.codigo} - ${defeito.nome}';

  List<UsuarioOperador> _ordenarUsuarios(List<UsuarioOperador> usuarios) {
    final ordenados = List<UsuarioOperador>.from(usuarios);
    ordenados.sort((a, b) {
      final nomeCmp = _compareAlpha(a.nmUser, b.nmUser);
      if (nomeCmp != 0) return nomeCmp;
      return _compareAlpha(a.cdUser, b.cdUser);
    });
    return ordenados;
  }

  List<Setor> _ordenarSetores(List<Setor> setores) {
    final ordenados = List<Setor>.from(setores);
    ordenados.sort((a, b) => _compareAlpha(a.nome, b.nome));
    return ordenados;
  }

  List<Maquina> _ordenarMaquinas(List<Maquina> maquinas) {
    final ordenadas = List<Maquina>.from(maquinas);
    ordenadas.sort((a, b) => _compareAlpha(a.nome, b.nome));
    return ordenadas;
  }

  Widget _buildCampoSelecao({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool selecionado,
    required bool habilitado,
    required VoidCallback? onTap,
    String? helperText,
    bool mostrarLimpar = false,
    VoidCallback? onClear,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      enabled: habilitado,
      onTap: onTap,
      style: TextStyle(
        color: habilitado ? _kTextPrimary : _kTextSecondary,
        fontWeight: selecionado ? FontWeight.w600 : FontWeight.w400,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kTextSecondary),
        hintText: hint,
        hintStyle: const TextStyle(color: _kTextSecondary),
        helperText: helperText,
        helperStyle: const TextStyle(color: _kTextSecondary, fontSize: 11),
        prefixIcon: Icon(icon, color: _kAccentColor),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selecionado
                  ? Icons.check_circle
                  : Icons.keyboard_arrow_down_rounded,
              color: selecionado ? Colors.green : _kTextSecondary,
            ),
            if (mostrarLimpar)
              GestureDetector(
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.close, color: _kTextSecondary, size: 18),
                ),
              ),
          ],
        ),
        filled: true,
        fillColor: !habilitado
            ? _kSurface
            : selecionado
            ? Colors.green.withValues(alpha: 0.07)
            : _kSurface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kBorderSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: selecionado
                ? Colors.green.withValues(alpha: 0.5)
                : _kBorderSoft,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kBorderSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kAccentColor, width: 2),
        ),
      ),
    );
  }

  Future<void> _abrirSeletorOperador({bool segundo = false}) async {
    if (_usuariosOperadores.isEmpty) return;

    final String? selecionado = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String filtro = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final listaFiltrada = _usuariosOperadores.where((u) {
              final nome = u.nmUser.toUpperCase();
              final id = u.cdUser.toUpperCase();
              final termo = filtro.trim().toUpperCase();
              if (termo.isEmpty) return true;
              return nome.contains(termo) || id.contains(termo);
            }).toList();

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.78,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Selecionar operador',
                      style: TextStyle(
                        color: _kTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        onChanged: (value) =>
                            setModalState(() => filtro = value),
                        style: const TextStyle(color: _kTextPrimary),
                        decoration: InputDecoration(
                          hintText: 'Buscar por nome ou ID',
                          hintStyle: const TextStyle(color: _kTextSecondary),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: _kTextSecondary,
                          ),
                          filled: true,
                          fillColor: _kSurface2,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _kBorderSoft),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _kBorderSoft),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: _kAccentColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: listaFiltrada.isEmpty
                          ? const Center(
                              child: Text(
                                'Nenhum operador encontrado',
                                style: TextStyle(color: _kTextSecondary),
                              ),
                            )
                          : ListView.separated(
                              itemCount: listaFiltrada.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, color: _kBorderSoft),
                              itemBuilder: (_, i) {
                                final usuario = listaFiltrada[i];
                                return ListTile(
                                  leading: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: _kAccentColor.withValues(
                                        alpha: 0.14,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.person_outline,
                                      color: _kAccentColor,
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(
                                    usuario.nmUser,
                                    style: const TextStyle(
                                      color: _kTextPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'ID ${usuario.cdUser}',
                                    style: const TextStyle(
                                      color: _kTextSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  onTap: () =>
                                      Navigator.of(ctx).pop(usuario.cdUser),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || selecionado == null) return;

    String nome = '';
    for (final usuario in _usuariosOperadores) {
      if (usuario.cdUser == selecionado) {
        nome = usuario.nmUser;
        break;
      }
    }

    setState(() {
      if (segundo) {
        _operador2CdUserSelecionado = selecionado;
        _operador2Controller.text = nome;
      } else {
        _operadorCdUserSelecionado = selecionado;
        _operadorController.text = nome;
      }
    });
  }

  Future<void> _abrirSeletorSetor() async {
    if (_setores.isEmpty) return;

    final Setor? selecionado = await showModalBottomSheet<Setor>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String filtro = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final listaFiltrada = _setores.where((s) {
              final nome = s.nome.toUpperCase();
              final codigo = s.codigo.toString().toUpperCase();
              final termo = filtro.trim().toUpperCase();
              if (termo.isEmpty) return true;
              return nome.contains(termo) || codigo.contains(termo);
            }).toList();

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.78,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Selecionar setor',
                      style: TextStyle(
                        color: _kTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        onChanged: (value) =>
                            setModalState(() => filtro = value),
                        style: const TextStyle(color: _kTextPrimary),
                        decoration: InputDecoration(
                          hintText: 'Buscar por nome ou código',
                          hintStyle: const TextStyle(color: _kTextSecondary),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: _kTextSecondary,
                          ),
                          filled: true,
                          fillColor: _kSurface2,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _kBorderSoft),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _kBorderSoft),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: _kAccentColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: listaFiltrada.isEmpty
                          ? const Center(
                              child: Text(
                                'Nenhum setor encontrado',
                                style: TextStyle(color: _kTextSecondary),
                              ),
                            )
                          : ListView.separated(
                              itemCount: listaFiltrada.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, color: _kBorderSoft),
                              itemBuilder: (_, i) {
                                final setor = listaFiltrada[i];
                                return ListTile(
                                  leading: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: _kAccentColor.withValues(
                                        alpha: 0.14,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.apartment_outlined,
                                      color: _kAccentColor,
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(
                                    setor.nome,
                                    style: const TextStyle(
                                      color: _kTextPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Código ${setor.codigo}',
                                    style: const TextStyle(
                                      color: _kTextSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  onTap: () => Navigator.of(ctx).pop(setor),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || selecionado == null) return;

    setState(() {
      _setorSelecionado = selecionado;
      _setorController.text = selecionado.nome;
      _maquinaSelecionada = null;
      _maquinaSelecionadaSecundaria = null;
      _maquinaController.clear();
      _maquina2Controller.clear();
      _maquinas = [];
    });

    if (widget.tipo == 'A' &&
        !selecionado.nome.toUpperCase().trim().contains(_kSetorSemMaquina)) {
      _carregarMaquinas(selecionado.codigo);
    }
  }

  Future<void> _abrirSeletorMaquina({bool segunda = false}) async {
    if (_setorSelecionado == null) return;

    final Maquina? selecionada = await showModalBottomSheet<Maquina>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String filtro = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final listaFiltrada = _maquinas.where((m) {
              final nome = m.nome.toUpperCase();
              final codigo = m.codigo.toString().toUpperCase();
              final termo = filtro.trim().toUpperCase();
              if (termo.isEmpty) return true;
              return nome.contains(termo) || codigo.contains(termo);
            }).toList();

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.78,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Selecionar máquina',
                      style: TextStyle(
                        color: _kTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        onChanged: (value) =>
                            setModalState(() => filtro = value),
                        style: const TextStyle(color: _kTextPrimary),
                        decoration: InputDecoration(
                          hintText: 'Buscar por nome ou código',
                          hintStyle: const TextStyle(color: _kTextSecondary),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: _kTextSecondary,
                          ),
                          filled: true,
                          fillColor: _kSurface2,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _kBorderSoft),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _kBorderSoft),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: _kAccentColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: listaFiltrada.isEmpty
                          ? const Center(
                              child: Text(
                                'Nenhuma máquina encontrada',
                                style: TextStyle(color: _kTextSecondary),
                              ),
                            )
                          : ListView.separated(
                              itemCount: listaFiltrada.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, color: _kBorderSoft),
                              itemBuilder: (_, i) {
                                final maq = listaFiltrada[i];
                                return ListTile(
                                  leading: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: _kAccentColor.withValues(
                                        alpha: 0.14,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.precision_manufacturing_outlined,
                                      color: _kAccentColor,
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(
                                    maq.nome,
                                    style: const TextStyle(
                                      color: _kTextPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Código ${maq.codigo}',
                                    style: const TextStyle(
                                      color: _kTextSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  onTap: () => Navigator.of(ctx).pop(maq),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || selecionada == null) return;

    if (segunda &&
        _maquinaSelecionada != null &&
        _maquinaSelecionada!.codigo == selecionada.codigo) {
      _showSnack("Máquina 2 deve ser diferente da Máquina 1", Colors.orange);
      return;
    }

    setState(() {
      if (segunda) {
        _maquinaSelecionadaSecundaria = selecionada;
        _maquina2Controller.text = selecionada.nome;
        return;
      }

      _maquinaSelecionada = selecionada;
      _maquinaController.text = selecionada.nome;
      if (_maquinaSelecionadaSecundaria?.codigo == selecionada.codigo) {
        _maquinaSelecionadaSecundaria = null;
        _maquina2Controller.clear();
      }
    });
  }

  // -----------------------------------------------------------------------
  // COLETOR – ATIVAÇÃO
  // -----------------------------------------------------------------------

  void _ativarColetorArtigo() {
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    setState(() => _coletorArtigoAtivo = true);
    _coletorArtigoController.clear();
    _coletorArtigoFocus.requestFocus();
    Future.microtask(
      () => SystemChannels.textInput.invokeMethod('TextInput.hide'),
    );
  }

  void _limparArtigoSelecionado() {
    setState(() {
      _artigoController.clear();
      _detalheController.clear();
      _ordemProducaoController.clear();
      _cdObjReal = "";
      _detalheReal = "";
      _lotesDisponiveis = [];
      _coletorArtigoAtivo = false;
    });
  }

  void _aplicarProdutoSelecionado({
    required String artigoCodigo,
    required String artigoNome,
    required String loteCodigo,
    required String loteNome,
  }) {
    setState(() {
      _artigoController.text = artigoNome;
      _detalheController.text = loteNome;
      _ordemProducaoController.clear();
      _cdObjReal = artigoCodigo;
      _detalheReal = loteCodigo;
      _coletorArtigoAtivo = false;
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _carregarLotesDoArtigo(
    String artigoCodigo, {
    String? loteSelecionadoCodigo,
    String? loteSelecionadoNome,
  }) async {
    final codigo = artigoCodigo.trim();
    if (codigo.isEmpty) {
      if (!mounted) return;
      setState(() => _lotesDisponiveis = []);
      return;
    }

    final lotes = await DatabaseService.buscarLotesPorObjetoID(codigo);
    if (!mounted) return;

    final normalizados = <Map<String, dynamic>>[];
    final chaves = <String>{};

    for (final lote in lotes) {
      final detalheID = (lote['detalheID'] ?? '').toString().trim();
      final detalhe = (lote['detalhe'] ?? '').toString().trim();
      if (detalheID.isEmpty || detalhe.isEmpty) continue;
      if (chaves.add(detalheID)) {
        normalizados.add({'detalheID': detalheID, 'detalhe': detalhe});
      }
    }

    final selecionadoCodigo = (loteSelecionadoCodigo ?? '').trim();
    final selecionadoNome = (loteSelecionadoNome ?? '').trim();
    if (selecionadoCodigo.isNotEmpty &&
        selecionadoNome.isNotEmpty &&
        chaves.add(selecionadoCodigo)) {
      normalizados.insert(0, {
        'detalheID': selecionadoCodigo,
        'detalhe': selecionadoNome,
      });
    }

    setState(() {
      _lotesDisponiveis = normalizados;
    });
  }

  Future<void> _carregarDefeitosTipoB({bool mostrarErro = false}) async {
    if (_loadingDefeitosTipoB) return;
    if (mounted) {
      setState(() => _loadingDefeitosTipoB = true);
    } else {
      _loadingDefeitosTipoB = true;
    }

    try {
      final response = await http.get(
        Uri.parse("$_kBaseUrlFlask$_kFalhaTipoBEndpoint"),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      final data = decoded is List ? decoded : <dynamic>[];
      final defeitos = data
          .whereType<Map<String, dynamic>>()
          .map(_DefeitoTipoB.fromJson)
          .where((item) => item.codigo.isNotEmpty && item.nome.isNotEmpty)
          .toList()
        ..sort((a, b) => _compareAlpha(a.codigo.padLeft(4, '0'), b.codigo.padLeft(4, '0')));

      if (!mounted) return;
      setState(() {
        _defeitosTipoB = defeitos;
      });
    } catch (e) {
      debugPrint('[ERRO_DEFEITO_TIPOB] $e');
      if (mostrarErro && mounted) {
        _showSnack(
          "Erro ao carregar defeitos do Tipo B",
          Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingDefeitosTipoB = false);
      } else {
        _loadingDefeitosTipoB = false;
      }
    }
  }

  Future<void> _abrirSeletorDefeitoTipoB() async {
    if (_defeitosTipoB.isEmpty) {
      await _carregarDefeitosTipoB(mostrarErro: true);
    }
    if (!mounted || _defeitosTipoB.isEmpty) return;

    String busca = '';
    final selecionado = await showModalBottomSheet<_DefeitoTipoB>(
      context: context,
      backgroundColor: _kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            List<_DefeitoTipoB> filtrar() {
              if (busca.trim().isEmpty) return _defeitosTipoB;
              final termo = busca.trim().toUpperCase();
              return _defeitosTipoB.where((defeito) {
                return defeito.codigo.contains(termo) ||
                    defeito.nome.toUpperCase().contains(termo);
              }).toList();
            }

            final itens = filtrar();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(
                            Icons.arrow_back,
                            color: _kTextPrimary,
                          ),
                          tooltip: 'Voltar',
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Text(
                            'Selecionar Defeito',
                            style: TextStyle(
                              color: _kTextPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${itens.length} itens',
                          style: const TextStyle(
                            color: _kTextSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Escolha pelo nome ou pelo codigo para enviar somente o numero do defeito.',
                      style: TextStyle(
                        color: _kTextSecondary.withOpacity(0.9),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      style: const TextStyle(color: _kTextPrimary),
                      decoration: InputDecoration(
                        hintText: 'Buscar por codigo ou nome',
                        hintStyle: const TextStyle(color: _kTextSecondary),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: _kAccentColor,
                        ),
                        filled: true,
                        fillColor: _kBgBottom,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: _kBorderSoft),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: _kAccentColor,
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (value) => setModalState(() => busca = value),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 360,
                      child: itens.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Nenhum defeito encontrado.',
                                style: TextStyle(color: _kTextSecondary),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: itens.length,
                              separatorBuilder: (_, __) => const SizedBox(
                                height: 10,
                              ),
                              itemBuilder: (_, index) {
                                final defeito = itens[index];
                                final ativo =
                                    _defeitoSelecionadoCodigo ==
                                    defeito.codigo;
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => Navigator.pop(ctx, defeito),
                                    child: Ink(
                                      decoration: BoxDecoration(
                                        color: ativo
                                            ? _kAccentColor.withOpacity(0.10)
                                            : _kSurface2,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: ativo
                                              ? _kAccentColor
                                              : _kBorderSoft,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 38,
                                              height: 38,
                                              decoration: BoxDecoration(
                                                color: _kAccentColor.withOpacity(
                                                  0.15,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  defeito.codigo,
                                                  style: const TextStyle(
                                                    color: _kAccentColor,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    defeito.nome,
                                                    style: const TextStyle(
                                                      color: _kTextPrimary,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Codigo ${defeito.codigo}',
                                                    style: const TextStyle(
                                                      color: _kTextSecondary,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Icon(
                                              ativo
                                                  ? Icons.check_circle
                                                  : Icons.chevron_right,
                                              color: ativo
                                                  ? _kAccentColor
                                                  : _kTextSecondary,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || selecionado == null) return;
    setState(() {
      _defeitoSelecionadoCodigo = selecionado.codigo;
      _defeitoController.text = _labelDefeito(selecionado);
    });
  }

  Future<Map<String, dynamic>?> _abrirSeletorArtigoManualTipoB() async {
    final artigoEsperado = _normalizarCodigo(_artigoEsperadoId);
    String busca = '';
    bool carregando = false;
    bool carregado = false;
    List<Map<String, dynamic>> resultados = [];

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: _kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        Future<void> carregarResultados(StateSetter setModalState) async {
          setModalState(() => carregando = true);
          final itens = await DatabaseService.buscarArtigosPorNome(
            busca,
            objetoIDRestrito: artigoEsperado.isEmpty ? null : artigoEsperado,
          );
          if (!ctx.mounted) return;
          setModalState(() {
            resultados = itens;
            carregando = false;
          });
        }

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            if (!carregado) {
              carregado = true;
              Future.microtask(() => carregarResultados(setModalState));
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Selecionar artigo manualmente',
                      style: TextStyle(
                        color: _kTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (artigoEsperado.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Artigo esperado: ${_artigoEsperadoNome.isNotEmpty ? _artigoEsperadoNome : artigoEsperado}',
                        style: const TextStyle(
                          color: _kTextSecondary,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      style: const TextStyle(color: _kTextPrimary),
                      decoration: InputDecoration(
                        hintText: 'Digite o nome do artigo',
                        hintStyle: const TextStyle(color: _kTextSecondary),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: _kAccentColor,
                        ),
                        filled: true,
                        fillColor: _kSurface2,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: _kBorderSoft),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: _kBorderSoft),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: _kAccentColor,
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        setModalState(() => busca = value);
                        carregarResultados(setModalState);
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 360,
                      child: carregando
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(
                                color: _kAccentColor,
                              ),
                            )
                          : resultados.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Nenhum artigo encontrado no catalogo local.',
                                style: TextStyle(color: _kTextSecondary),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: resultados.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(color: _kBorderSoft, height: 1),
                              itemBuilder: (_, index) {
                                final item = resultados[index];
                                final codigo =
                                    (item['objetoID'] ?? '').toString().trim();
                                final nome =
                                    (item['objeto'] ?? '').toString().trim();
                                return ListTile(
                                  title: Text(
                                    nome,
                                    style: const TextStyle(
                                      color: _kTextPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Codigo $codigo',
                                    style: const TextStyle(
                                      color: _kTextSecondary,
                                    ),
                                  ),
                                  onTap: () => Navigator.pop(ctx, item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _abrirSeletorLoteManualTipoB(
    String artigoCodigo,
  ) async {
    String busca = '';
    bool carregando = false;
    bool carregado = false;
    List<Map<String, dynamic>> resultados = [];

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: _kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        Future<void> carregarResultados(StateSetter setModalState) async {
          setModalState(() => carregando = true);
          final itens = await DatabaseService.buscarLotesPorObjetoID(
            artigoCodigo,
            termo: busca,
          );
          if (!ctx.mounted) return;
          setModalState(() {
            resultados = itens;
            carregando = false;
          });
        }

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            if (!carregado) {
              carregado = true;
              Future.microtask(() => carregarResultados(setModalState));
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Selecionar lote',
                      style: TextStyle(
                        color: _kTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      style: const TextStyle(color: _kTextPrimary),
                      decoration: InputDecoration(
                        hintText: 'Digite o nome do lote',
                        hintStyle: const TextStyle(color: _kTextSecondary),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: _kAccentColor,
                        ),
                        filled: true,
                        fillColor: _kSurface2,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: _kBorderSoft),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: _kBorderSoft),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: _kAccentColor,
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        setModalState(() => busca = value);
                        carregarResultados(setModalState);
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 360,
                      child: carregando
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(
                                color: _kAccentColor,
                              ),
                            )
                          : resultados.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Nenhum lote encontrado para este artigo.',
                                style: TextStyle(color: _kTextSecondary),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: resultados.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(color: _kBorderSoft, height: 1),
                              itemBuilder: (_, index) {
                                final item = resultados[index];
                                final codigo =
                                    (item['detalheID'] ?? '').toString().trim();
                                final nome =
                                    (item['detalhe'] ?? '').toString().trim();
                                return ListTile(
                                  title: Text(
                                    nome,
                                    style: const TextStyle(
                                      color: _kTextPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Codigo $codigo',
                                    style: const TextStyle(
                                      color: _kTextSecondary,
                                    ),
                                  ),
                                  onTap: () => Navigator.pop(ctx, item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _abrirFluxoManualArtigoTipoB() async {
    final totalProdutos = await DatabaseService.contarProdutos();
    if (totalProdutos == 0) {
      _showSnack(
        'Catalogo local vazio. Sincronize os produtos para usar o modo manual.',
        Colors.orange,
      );
      return;
    }

    final artigo = await _abrirSeletorArtigoManualTipoB();
    if (!mounted || artigo == null) return;

    final artigoCodigo = (artigo['objetoID'] ?? '').toString().trim();
    final artigoNome = (artigo['objeto'] ?? '').toString().trim();
    if (artigoCodigo.isEmpty || artigoNome.isEmpty) {
      _showSnack('Artigo invalido selecionado.', Colors.orange);
      return;
    }

    final lote = await _abrirSeletorLoteManualTipoB(artigoCodigo);
    if (!mounted || lote == null) return;

    final loteCodigo = (lote['detalheID'] ?? '').toString().trim();
    final loteNome = (lote['detalhe'] ?? '').toString().trim();
    if (loteCodigo.isEmpty || loteNome.isEmpty) {
      _showSnack('Lote invalido selecionado.', Colors.orange);
      return;
    }

    _aplicarProdutoSelecionado(
      artigoCodigo: artigoCodigo,
      artigoNome: artigoNome,
      loteCodigo: loteCodigo,
      loteNome: loteNome,
    );
    await _carregarLotesDoArtigo(
      artigoCodigo,
      loteSelecionadoCodigo: loteCodigo,
      loteSelecionadoNome: loteNome,
    );
    await _buscarOrdemProducaoParaObjeto(artigoCodigo);
    _showSnack('Artigo e lote definidos manualmente.', Colors.green);
  }

  Future<void> _escolherModoLeituraArtigo() async {
    if (_coletorArtigoAtivo) {
      setState(() => _coletorArtigoAtivo = false);
      FocusScope.of(context).unfocus();
    }

    final escolha = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Como deseja ler o artigo?',
                  style: TextStyle(
                    color: _kTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(
                    Icons.qr_code_scanner,
                    color: _kAccentColor,
                  ),
                  title: const Text(
                    'Câmera',
                    style: TextStyle(color: _kTextPrimary),
                  ),
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.barcode_reader,
                    color: _kAccentColor,
                  ),
                  title: const Text(
                    'Coletor',
                    style: TextStyle(color: _kTextPrimary),
                  ),
                  onTap: () => Navigator.pop(ctx, 'coletor'),
                ),
                if (widget.tipo == 'B')
                  ListTile(
                    leading: const Icon(
                      Icons.edit_note,
                      color: _kAccentColor,
                    ),
                    title: const Text(
                      'Manual',
                      style: TextStyle(color: _kTextPrimary),
                    ),
                    subtitle: const Text(
                      'Escolher artigo e lote pelo nome',
                      style: TextStyle(color: _kTextSecondary),
                    ),
                    onTap: () => Navigator.pop(ctx, 'manual'),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || escolha == null) return;

    if (escolha == 'camera') {
      final String? code = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const ScannerPage(modo: 'qr', titulo: 'Ler Artigo'),
        ),
      );
      if (code != null && code.isNotEmpty) {
        _processarBuscaProduto(code);
      }
      return;
    }

    if (escolha == 'coletor') {
      _ativarColetorArtigo();
      return;
    }

    if (escolha == 'manual' && widget.tipo == 'B') {
      await _abrirFluxoManualArtigoTipoB();
    }
  }

  Future<void> _carregarUsuariosOperadores() async {
    if (_loadingUsuariosOperadores) return;
    setState(() => _loadingUsuariosOperadores = true);
    try {
      final usuarios = await UsuarioOperadorService.buscarUsuarios();
      if (!mounted) return;
      setState(() => _usuariosOperadores = _ordenarUsuarios(usuarios));
    } finally {
      if (mounted) setState(() => _loadingUsuariosOperadores = false);
    }
  }

  // -----------------------------------------------------------------------
  // SETOR / MÁQUINA
  // -----------------------------------------------------------------------

  Future<void> _carregarSetores() async {
    setState(() => _loadingSetores = true);
    try {
      final setores = await SetorMaquinaService.buscarSetores();
      setState(() => _setores = _ordenarSetores(setores));
    } catch (e) {
      _showSnack("Erro ao carregar setores", Colors.red);
    } finally {
      setState(() => _loadingSetores = false);
    }
  }

  Future<void> _carregarMaquinas(int setorId) async {
    setState(() {
      _loadingMaquinas = true;
      _maquinas = [];
      _maquinaSelecionada = null;
      _maquinaSelecionadaSecundaria = null;
      _maquinaController.clear();
      _maquina2Controller.clear();
    });
    try {
      final maquinas = await SetorMaquinaService.buscarMaquinas(setorId);
      setState(() => _maquinas = _ordenarMaquinas(maquinas));
    } catch (e) {
      _showSnack("Erro ao carregar máquinas", Colors.red);
    } finally {
      setState(() => _loadingMaquinas = false);
    }
  }

  // -----------------------------------------------------------------------
  // BUSCA DE PRODUTO
  // -----------------------------------------------------------------------

  Future<void> _processarBuscaProduto(String code) async {
    setState(() => _isLoading = true);
    try {
      String buscadoObjID = "";
      String buscadoDetID = "";

      if (code.startsWith('{')) {
        final decoded = jsonDecode(code);
        buscadoObjID = decoded['CdObj']?.toString() ?? "";
        buscadoDetID = decoded['Detalhe']?.toString() ?? "";
      } else {
        buscadoObjID = code;
      }

      if (buscadoObjID.isEmpty) {
        _showSnack("Código inválido", Colors.orange);
        return;
      }

      final esperado = _normalizarCodigo(_artigoEsperadoId);
      final recebido = _normalizarCodigo(buscadoObjID);
      if (esperado.isNotEmpty && recebido != esperado) {
        setState(() => _coletorArtigoAtivo = false);
        _showSnack("Artigo diferente do selecionado", Colors.red);
        return;
      }

      final produto = await DatabaseService.buscarProduto(
        buscadoObjID,
        buscadoDetID,
      );

      if (produto != null) {
        final artigoCodigo = (produto['objetoID'] ?? '').toString();
        final artigoNome = (produto['objeto'] ?? '').toString();
        final loteCodigo = (produto['detalheID'] ?? '').toString();
        final loteNome = (produto['detalhe'] ?? '').toString();
        _aplicarProdutoSelecionado(
          artigoCodigo: artigoCodigo,
          artigoNome: artigoNome,
          loteCodigo: loteCodigo,
          loteNome: loteNome,
        );
        await _carregarLotesDoArtigo(
          artigoCodigo,
          loteSelecionadoCodigo: loteCodigo,
          loteSelecionadoNome: loteNome,
        );
        await _buscarOrdemProducaoParaObjeto(artigoCodigo);
        _showSnack("Produto encontrado!", Colors.green);
      } else {
        await _buscarNaAPI(buscadoObjID, buscadoDetID);
      }
    } catch (e) {
      debugPrint('[ERRO] $e');
      _showSnack("Erro ao buscar produto", Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _buscarNaAPI(String objetoID, String detalheID) async {
    try {
      String? token = await AuthService.obterToken();
      if (token == null) {
        _showSnack("Erro: não foi possível autenticar", Colors.red);
        return;
      }

      final uri = Uri.parse(
        "https://mediumpurple-loris-159660.hostingersite.com/api/artigos?CdObj=$objetoID",
      );

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final List<dynamic> data = json["data"] ?? [];

        if (data.isEmpty) {
          _showSnack("Produto não encontrado", Colors.orange);
          return;
        }

        Map<String, dynamic>? loteEncontrado;
        for (var item in data) {
          final List<dynamic> cdLotList = item["CdLot"] ?? [];
          if (cdLotList.contains(int.parse(detalheID))) {
            loteEncontrado = item;
            break;
          }
        }

        if (loteEncontrado == null) {
          _showSnack(
            "Lote correspondente ao detalhe não encontrado",
            Colors.orange,
          );
          return;
        }

        final String nomeProduto = loteEncontrado["NmObj"]?.toString() ?? "";
        final String nmLot = loteEncontrado["NmLot"]?.toString() ?? "";

        _aplicarProdutoSelecionado(
          artigoCodigo: objetoID,
          artigoNome: nomeProduto,
          loteCodigo: detalheID,
          loteNome: nmLot,
        );
        await _carregarLotesDoArtigo(
          objetoID,
          loteSelecionadoCodigo: detalheID,
          loteSelecionadoNome: nmLot,
        );
        await _buscarOrdemProducaoParaObjeto(objetoID);
        _showSnack("✅ Produto e lote encontrados", Colors.green);
      } else if (response.statusCode == 401) {
        await AuthService.limparToken();
        _showSnack("Token expirado, tente novamente", Colors.orange);
      } else {
        _showSnack("Erro ao consultar artigo", Colors.red);
      }
    } catch (e) {
      debugPrint("[ERRO API] $e");
      _showSnack("Erro ao consultar artigo", Colors.red);
    }
  }

  DateTime? _tentarLerDataBr(String texto) {
    final candidatos = [DateFormat('dd/MM/yyyy'), DateFormat('dd/MM/yy')];
    for (final formato in candidatos) {
      try {
        return formato.parseStrict(texto);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String _obterDataInicialOrdens() {
    final textoData = _dataController.text.trim();
    final referencia = _tentarLerDataBr(textoData) ?? DateTime.now();
    return DateFormat("yyyy-MM-dd'T'00:00:00").format(referencia);
  }

  String _formatarDataIsoMidnight(DateTime data) {
    return DateFormat("yyyy-MM-dd'T'00:00:00").format(data);
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  List<dynamic> _normalizarRespostaOrdens(dynamic decoded) {
    if (decoded == null) return const [];
    if (decoded is List) return decoded;
    if (decoded is Map<String, dynamic>) {
      const possiveisChaves = [
        'data',
        'dados',
        'resultado',
        'result',
        'ordens',
        'items',
        'values',
      ];
      for (final chave in possiveisChaves) {
        final valor = decoded[chave];
        if (valor is List) {
          return valor;
        }
      }
      for (final valor in decoded.values) {
        if (valor is List) return valor;
      }
    }
    return const [];
  }

  int? _extrairIdOrdem(dynamic item) {
    if (item is int) return item;
    if (item is String) return int.tryParse(item.trim());

    if (item is Map<String, dynamic>) {
      const possiveisChaves = [
        'ID',
        'Id',
        'id',
        'OrdemProducaoID',
        'ordemProducaoID',
        'OrdemFabricacaoID',
        'ordemFabricacaoID',
        'OrdemFabricacaoId',
        'ordemFabricacaoId',
        'NrOrdem',
        'nrOrdem',
        'Ordem',
        'ordem',
        'Numero',
        'numero',
        'NumeroOrdem',
        'numeroOrdem',
      ];

      for (final chave in possiveisChaves) {
        final valor = item[chave];
        if (valor == null) continue;
        if (valor is int) return valor;
        if (valor is String) {
          final parsed = int.tryParse(valor.trim());
          if (parsed != null) return parsed;
        }
      }
    }
    return null;
  }

  int? _extrairIdOrdemCriada(dynamic decoded) {
    if (decoded == null) return null;
    if (decoded is int) return decoded;
    if (decoded is String) return int.tryParse(decoded.trim());
    if (decoded is Map<String, dynamic>) {
      const possiveisChaves = [
        'id',
        'Id',
        'ID',
        'ordemProducaoId',
        'ordemProducaoID',
        'ordemFabricacaoId',
        'ordemFabricacaoID',
        'OrdemProducaoID',
        'OrdemFabricacaoID',
      ];
      for (final chave in possiveisChaves) {
        final valor = decoded[chave];
        if (valor is int) return valor;
        if (valor is String) {
          final parsed = int.tryParse(valor.trim());
          if (parsed != null) return parsed;
        }
      }
    }
    return null;
  }

  Future<void> _buscarOrdemProducaoParaObjeto(
    String objetoCodigo, {
    bool isRetry = false,
  }) async {
    final objetoID = int.tryParse(objetoCodigo.trim());
    if (objetoID == null) return;

    final isOffline = await top_auth.AuthService.isOfflineModeActive();
    if (isOffline) {
      if (mounted) {
        _showSnack(
          "Modo offline ativo. Não foi possível consultar a Ordem de Produção.",
          Colors.orange,
        );
      }
      return;
    }

    final token = await top_auth.AuthService.obterTokenLogtech();
    if (token == null) {
      if (mounted) {
        _showSnack(
          "Falha na autenticação ao consultar Ordens de Produção.",
          Colors.red,
        );
      }
      return;
    }

    final queryParams = {
      'empresaID': _kEmpresaIdOrdemProducao,
      'objetoID': objetoID.toString(),
      'dataInicial': _obterDataInicialOrdens(),
    };

    if (mounted) {
      setState(() => _buscandoOrdemProducao = true);
    } else {
      _buscandoOrdemProducao = true;
    }

    try {
      final uri = Uri.https(_kTopmanagerBaseUrl, _kOrdensFabricacaoPath, queryParams);
      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 401 && !isRetry) {
        await top_auth.AuthService.clearToken();
        await _buscarOrdemProducaoParaObjeto(objetoCodigo, isRetry: true);
        return;
      }

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final decoded = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      final ordens = _normalizarRespostaOrdens(decoded);
      final ordemSelecionada = ordens
          .map<int?>((o) => _extrairIdOrdem(o))
          .firstWhere((value) => value != null, orElse: () => null);

      if (!mounted) return;
      setState(() {
        _ordemProducaoController.text =
            ordemSelecionada?.toString() ?? '';
      });
    } catch (e) {
      debugPrint('[ERRO_ORDEM] Falha ao buscar ordens de produção: $e');
      if (mounted) {
        _showSnack(
          "Erro ao consultar Ordens de Produção.",
          Colors.orange,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _buscandoOrdemProducao = false);
      } else {
        _buscandoOrdemProducao = false;
      }
    }
  }

  Future<_ResultadoOrdemFabricacao> _incluirOrdemFabricacao({
    required int objetoProduzidoId,
    required double quantidadePlanejada,
    required String token,
    bool isRetry = false,
  }) async {
    final agora = DateTime.now();
    final payload = {
      'dataAtivacao': _formatarDataIsoMidnight(agora),
      'dataDesativacao': _formatarDataIsoMidnight(agora),
      'empresaId': int.tryParse(_kEmpresaIdOrdemProducao) ?? 0,
      'objetoId': 1532,
      'objetoProduzidoId': objetoProduzidoId,
      'quantidadePlanejada': quantidadePlanejada,
      'quantidadeProduzida': 0,
      'situacaoEvento': 1,
    };

    try {
      final uri = Uri.https(_kTopmanagerBaseUrl, _kIncluirOrdemFabricacaoPath);
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 401 && !isRetry) {
        await top_auth.AuthService.clearToken();
        final novoToken = await top_auth.AuthService.obterTokenLogtech();
        if (novoToken == null) {
          return const _ResultadoOrdemFabricacao(
            erro: 'Falha na autenticação ao criar ordem.',
          );
        }
        return _incluirOrdemFabricacao(
          objetoProduzidoId: objetoProduzidoId,
          quantidadePlanejada: quantidadePlanejada,
          token: novoToken,
          isRetry: true,
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String? erroDetalhado;
        if (response.body.isNotEmpty) {
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map<String, dynamic>) {
              erroDetalhado =
                  decoded['erro']?.toString() ?? decoded['Message']?.toString();
            } else {
              erroDetalhado = response.body;
            }
          } catch (_) {
            erroDetalhado = response.body;
          }
        }
        return _ResultadoOrdemFabricacao(erro: erroDetalhado);
      }

      if (response.body.isEmpty) {
        return const _ResultadoOrdemFabricacao();
      }

      final decoded = jsonDecode(response.body);
      final id = _extrairIdOrdemCriada(decoded);
      return _ResultadoOrdemFabricacao(id: id);
    } catch (e) {
      return _ResultadoOrdemFabricacao(erro: e.toString());
    }
  }

  // -----------------------------------------------------------------------
  // ENVIO
  // -----------------------------------------------------------------------

  Future<http.Response> _postJson(
    String endpoint,
    Map<String, dynamic> payload,
  ) {
    return http.post(
      Uri.parse("$_kBaseUrlFlask$endpoint"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );
  }

  String _formatarDataSqlServer(DateTime data) {
    String doisDigitos(int valor) => valor.toString().padLeft(2, '0');
    return '${data.year}${doisDigitos(data.month)}${doisDigitos(data.day)} '
        '${doisDigitos(data.hour)}:${doisDigitos(data.minute)}:${doisDigitos(data.second)}';
  }

  Map<String, dynamic> _criarPayloadMapaEficiencia(
    Map<String, dynamic> payloadOriginal,
    DateTime dataApontamento,
  ) {
    final codigoLote =
        payloadOriginal["CdLot"] ??
        payloadOriginal["Cdlot"] ??
        payloadOriginal["Detalhe"];

    return {
      "Data": _formatarDataSqlServer(dataApontamento),
      "CdTur":
          payloadOriginal["CdTur"] ?? payloadOriginal["turno"] ?? widget.turno,
      "Setor": payloadOriginal["Setor"],
      "Maq": payloadOriginal["Maq"],
      "Operador": payloadOriginal["Operador"],
      "Artigo": payloadOriginal["Artigo"],
      "Qtde": payloadOriginal["Qtde"],
      "Defeito": payloadOriginal["Defeito"],
      "CdLot": codigoLote,
      "Cdlot": codigoLote,
      "CdMppite": payloadOriginal["CdMppite"],
      "CdVpd": payloadOriginal["CdVpd"],
      "TpMovimento": payloadOriginal["TpMovimento"] ?? 1,
    };
  }

  Future<void> _enviar() async {
    if (_cdObjReal.isEmpty) return _showSnack("Bipe um Artigo", Colors.orange);

    final codigoDefeito =
        (_defeitoSelecionadoCodigo ?? _normalizarCodigo(_defeitoController.text))
            .trim();

    if (widget.tipo == 'B') {
      if (codigoDefeito.isEmpty) {
        return _showSnack("Preencha o campo Defeito", Colors.orange);
      }
      if (_palletController.text.trim().toUpperCase() != _kPaleteTipoBFixo) {
        return _showSnack(
          "Selecione o palete $_kPaleteTipoBFixo",
          Colors.orange,
        );
      }
      if ((_operadorCdUserSelecionado ?? '').trim().isEmpty) {
        return _showSnack("Selecione o Operador", Colors.orange);
      }
    }

    if (widget.tipo == 'A') {
      if (_setorSelecionado == null) {
        return _showSnack("Selecione o Setor", Colors.orange);
      }
      if (!_isRevisao && _maquinaSelecionada == null) {
        return _showSnack("Selecione a Máquina", Colors.orange);
      }
      if (_maquinasSelecionadasDuplicadas) {
        return _showSnack(
          "Máquina 2 deve ser diferente da Máquina 1",
          Colors.orange,
        );
      }
      if ((_operadorCdUserSelecionado ?? '').trim().isEmpty) {
        return _showSnack("Selecione o Operador", Colors.orange);
      }
    }

    if (_qtdeController.text.trim().isEmpty ||
        int.tryParse(_qtdeController.text) == null) {
      return _showSnack("Preencha a quantidade corretamente", Colors.orange);
    }
    if (widget.tipo == 'A') {
      final operador2 = (_operador2CdUserSelecionado ?? '').trim();
      if (operador2.isNotEmpty) {
        if (_qtde2Controller.text.trim().isEmpty ||
            int.tryParse(_qtde2Controller.text) == null) {
          return _showSnack(
            "Preencha a quantidade do Operador 2 corretamente",
            Colors.orange,
          );
        }
      }
    }

    setState(() => _isLoading = true);

    final endpoint = widget.tipo == 'A'
        ? '/apontamento/tipoA'
        : '/apontamento/tipoB';

    final quantidade = int.tryParse(_qtdeController.text) ?? 0;
    final quantidade2 = int.tryParse(_qtde2Controller.text) ?? 0;
    final payloads = <Map<String, dynamic>>[];

    if (widget.tipo == 'B') {
      int? ordemProducaoId = int.tryParse(_ordemProducaoController.text.trim());
      if (ordemProducaoId == null) {
        final token = await top_auth.AuthService.obterTokenLogtech();
        if (token == null) {
          setState(() => _isLoading = false);
          return _showSnack(
            "Falha na autenticação. Não foi possível gerar a Ordem de Produção.",
            Colors.red,
          );
        }

        final resultado = await _incluirOrdemFabricacao(
          objetoProduzidoId: _toInt(_cdObjReal),
          quantidadePlanejada: quantidade.toDouble(),
          token: token,
        );

        if (resultado.id == null) {
          setState(() => _isLoading = false);
          final erro = (resultado.erro ?? '').trim();
          return _showSnack(
            erro.isEmpty
                ? _kErroOrdemFabricacaoGenerico
                : '$_kErroOrdemFabricacaoGenerico $erro',
            Colors.red,
          );
        }

        _ordemProducaoController.text = resultado.id.toString();
      }
    }

    if (widget.tipo == 'A') {
      final base = <String, dynamic>{
        "Setor": _setorSelecionado!.codigo,
        "Qtde": quantidade,
        "Artigo": _cdObjReal,
        "Detalhe": _detalheReal,
        "CdLot": _detalheReal,
        "TpMovimento": 1,
        "turno": widget.turno,
      };

      // Registro do Operador 1
      payloads.add({
        ...base,
        "Maq": _setorSelecionado!.codigo,
        "Operador": _operadorCdUserSelecionado,
      });

      // Se houver Operador 2, cria um segundo registro usando a mesma leitura de QR
      final operador2 = (_operador2CdUserSelecionado ?? '').trim();
      if (operador2.isNotEmpty) {
        payloads.add({
          ...base,
          "Maq": _setorSelecionado!.codigo,
          "Operador": operador2,
          "Qtde": quantidade2,
        });
      }
    } else {
      payloads.add({
        "Setor": _setorSelecionado?.codigo,
        "Maq": _setorSelecionado?.codigo,
        "Operador": _operadorCdUserSelecionado,
        "Artigo": _cdObjReal,
        "Detalhe": _detalheReal,
        "CdLot": _detalheReal,
        "Defeito": codigoDefeito,
        "Qtde": quantidade,
        "TpMovimento": 1,
        "turno": widget.turno,
      });
    }

    try {
      bool houveFalhaMapaEficiencia = false;
      final dataApontamento = DateTime.now();

      for (var i = 0; i < payloads.length; i++) {
        final payloadAtual = payloads[i];
        final resp = await _postJson(endpoint, payloadAtual);

        if (resp.statusCode != 201) {
          _showSnack("Erro ao salvar: ${resp.statusCode}", Colors.red);
          return;
        }

        final mapaResp = await _postJson(
          _kMapaEficienciaEmbEndpoint,
          _criarPayloadMapaEficiencia(payloadAtual, dataApontamento),
        );

        if (mapaResp.statusCode != 201) {
          houveFalhaMapaEficiencia = true;
          debugPrint(
            '[ERRO MAPA EFICIENCIA] '
            'status=${mapaResp.statusCode} body=${mapaResp.body}',
          );
        }
      }

      _showSnack(
        houveFalhaMapaEficiencia
            ? "Apontamento salvo, mas falhou no Mapa de Eficiência"
            : "Salvo com sucesso!",
        houveFalhaMapaEficiencia ? Colors.orange : Colors.green,
      );
      widget.onApontamentoConcluido?.call();
      if (widget.fecharAoConcluir && mounted) {
        Navigator.of(context).pop();
        return;
      }
      _limpar();
    } catch (e) {
      debugPrint('[ERRO ENVIO] $e');
      _showSnack("Erro ao salvar", Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _limpar() {
    _artigoController.clear();
    _detalheController.clear();
    _qtdeController.clear();
    _qtde2Controller.clear();
    _ordemProducaoController.clear();
    _palletController.clear();
    _operadorController.clear();
    _operador2Controller.clear();
    _setorController.clear();
    _maquinaController.clear();
    _maquina2Controller.clear();
    _coletorArtigoController.clear();
    _defeitoController.clear();
    _defeitoSelecionadoCodigo = null;
    _operadorCdUserSelecionado = null;
    _operador2CdUserSelecionado = null;
    _cdObjReal = "";
    _detalheReal = "";
    _lotesDisponiveis = [];

    if (widget.tipo == 'A') {
      setState(() {
        _etapaA = _EtapaA.identificacao;
        _setorSelecionado = null;
        _maquinaSelecionada = null;
        _maquinaSelecionadaSecundaria = null;
        _maquinas = [];
        _coletorArtigoAtivo = false;
        _buscandoOrdemProducao = false;
      });
    } else {
      setState(() {
        _setorSelecionado = null;
        _maquinaSelecionada = null;
        _maquinaSelecionadaSecundaria = null;
        _maquinas = [];
        _coletorArtigoAtivo = false;
        _buscandoOrdemProducao = false;
        _palletController.text = _kPaleteTipoBFixo;
      });
    }
  }

  void _showSnack(String msg, Color cor) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: cor));
  }

  // -----------------------------------------------------------------------
  // AVANÇAR ETAPA (Tipo A)
  // -----------------------------------------------------------------------

  void _avancarParaProducao() {
    if (!_etapa1Completa) {
      String msg = "Preencha todos os campos da Identificação";
      if ((_operadorCdUserSelecionado ?? '').trim().isEmpty) {
        msg = "Selecione o Operador";
      } else if (_setorSelecionado == null) {
        msg = "Selecione o Setor";
      } else if (!_isRevisao && _maquinaSelecionada == null) {
        msg = "Selecione a Máquina";
      }
      _showSnack(msg, Colors.orange);
      return;
    }

    if (_maquinasSelecionadasDuplicadas) {
      _showSnack("Máquina 2 deve ser diferente da Máquina 1", Colors.orange);
      return;
    }

    setState(() => _etapaA = _EtapaA.producao);
    // Foca automaticamente no coletor do artigo
    WidgetsBinding.instance.addPostFrameCallback((_) => _ativarColetorArtigo());
  }

  void _voltarParaIdentificacao() {
    setState(() {
      _etapaA = _EtapaA.identificacao;
      _coletorArtigoAtivo = false;
    });
  }

  // -----------------------------------------------------------------------
  // BUILD PRINCIPAL
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.tipo == 'B') {
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_kBgTop, _kSurface2, _kBgBottom],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: -120,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _kAccentColor.withOpacity(0.14),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -110,
            left: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _kPrimaryColor.withOpacity(0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          _buildTipoB(),
        ],
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kBgTop, _kSurface2, _kBgBottom],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: _buildTipoA(),
    );
  }

  // -----------------------------------------------------------------------
  // TIPO B (sem etapas – igual ao original, mas com foco automático)
  // -----------------------------------------------------------------------

  Widget _buildTipoB() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTipoBSection(
            title: 'Informações do Documento',
            children: [
              _buildTipoBResponsiveFieldGroup([
                _buildTipoBInfoField(
                  label: 'Data (dd/MM/yyyy)',
                  value: _dataController.text,
                  icon: Icons.calendar_today_outlined,
                ),
                _buildTipoBInfoField(
                  label: 'Turno',
                  value: _turnoInfoController.text,
                  icon: Icons.schedule,
                ),
              ]),
            ],
          ),
          _buildTipoBSection(
            title: 'Identificação da Produção',
            children: [
              _buildArtigoEsperadoInfo(),
              _buildTipoBResponsiveFieldGroup([
                _buildOrdemProducaoFieldTipoB(),
                _buildArtigoField(),
                _buildDetalheDropdownTipoB(),
                _buildTextField(
                  _qtdeController,
                  'Quantidade',
                  Icons.add_task,
                  isNumeric: true,
                ),
                _buildPaleteFieldTipoB(),
              ]),
              const SizedBox(height: 2),
              const Text(
                'Palete permitido: PA-L1-R500-D-P1',
                style: TextStyle(
                  color: _kTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          _buildTipoBSection(
            title: 'Controle de Qualidade',
            children: [
              _buildTipoBResponsiveFieldGroup([
                _buildOperadorDropdown(),
                // _buildSetorDropdown(),
                _buildDefeitoDropdownTipoB(),
              ]),
            ],
          ),
          const SizedBox(height: 8),
          _buildBotaoConfirmar(),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // TIPO A – ETAPA 1: IDENTIFICAÇÃO
  // -----------------------------------------------------------------------

  Widget _buildTipoA() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildTurnoHeader(widget.turnoLetra),
          _buildIndicadorEtapas(),
          const SizedBox(height: 16),

          if (_etapaA == _EtapaA.identificacao) ...[
            _buildCardSection('Etapa 1 — Identificação', [
              _buildOperadorDropdown(),
              _buildOperador2Dropdown(),
              _buildSetorDropdown(),
              if (!_isRevisao) _buildMaquinaDropdown(),
              if (!_isRevisao) _buildMaquina2Dropdown(),
            ]),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _etapa1Completa ? _avancarParaProducao : null,
                icon: const Icon(Icons.arrow_forward, color: Colors.white),
                label: const Text(
                  'AVANÇAR PARA PRODUÇÃO',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _etapa1Completa
                      ? _kPrimaryColor
                      : Colors.grey.shade800,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ] else ...[
            // ── Resumo da etapa 1 (somente leitura) ──────────────────────
            _buildResumoIdentificacao(),
            const SizedBox(height: 12),

            // ── Etapa 2: Produção ─────────────────────────────────────────
            _buildCardSection('Etapa 2 — Produção', [
              _buildArtigoEsperadoInfo(),
              _buildArtigoField(),
              _buildTextField(
                _detalheController,
                'Detalhe (Lote)',
                Icons.info_outline,
                readOnly: true,
              ),
              _buildTextField(
                _qtdeController,
                'Quantidade',
                Icons.add_task,
                isNumeric: true,
              ),
              if ((_operador2CdUserSelecionado ?? '').trim().isNotEmpty)
                _buildTextField(
                  _qtde2Controller,
                  'Quantidade Operador 2',
                  Icons.add_task,
                  isNumeric: true,
                ),
            ]),
            const SizedBox(height: 20),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _voltarParaIdentificacao,
                  icon: const Icon(
                    Icons.arrow_back,
                    color: _kTextSecondary,
                    size: 18,
                  ),
                  label: const Text(
                    'VOLTAR',
                    style: TextStyle(color: _kTextSecondary),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _kBorderSoft),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _buildBotaoConfirmar()),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // INDICADOR DE ETAPAS
  // -----------------------------------------------------------------------

  Widget _buildIndicadorEtapas() {
    if (widget.tipo != 'A') return const SizedBox.shrink();

    final etapa1Ativa = _etapaA == _EtapaA.identificacao;

    return Row(
      children: [
        _buildEtapaChip(
          '1',
          'Identificação',
          etapa1Ativa || _etapaA != _EtapaA.identificacao,
          !etapa1Ativa,
        ),
        Expanded(
          child: Container(
            height: 2,
            color: !etapa1Ativa ? _kAccentColor : _kBorderSoft,
          ),
        ),
        _buildEtapaChip('2', 'Produção', !etapa1Ativa, false),
      ],
    );
  }

  Widget _buildEtapaChip(
    String numero,
    String label,
    bool ativa,
    bool completa,
  ) {
    final color = completa
        ? Colors.green
        : ativa
        ? _kAccentColor
        : _kTextSecondary.withOpacity(0.4);

    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.15),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: completa
                ? Icon(Icons.check, size: 16, color: color)
                : Text(
                    numero,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // RESUMO ETAPA 1 (exibido na etapa 2)
  // -----------------------------------------------------------------------

  Widget _buildResumoIdentificacao() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Operador: ${_operadorController.text}',
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_operador2Controller.text.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Segundo operador: ${_operador2Controller.text}',
                    style: const TextStyle(
                      color: _kTextSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  'Setor: ${_setorSelecionado?.nome ?? "—"}'
                  '$_resumoMaquinas',
                  style: const TextStyle(color: _kTextSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _voltarParaIdentificacao,
            child: const Icon(
              Icons.edit_outlined,
              color: _kAccentColor,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // CAMPO OPERADOR (dropdown com nomes da API)
  // -----------------------------------------------------------------------

  Widget _buildOperadorDropdown() {
    final temOperador =
        (_operadorCdUserSelecionado ?? '').isNotEmpty &&
        _operadorController.text.isNotEmpty;
    final semUsuarios = _usuariosOperadores.isEmpty;
    final totalOperadores = _usuariosOperadores.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _loadingUsuariosOperadores
          ? _buildCampoSelecao(
              controller: _operadorController,
              label: 'Operador',
              hint: 'Carregando operadores...',
              icon: Icons.badge,
              selecionado: false,
              habilitado: false,
              onTap: null,
              helperText: null,
            )
          : _buildCampoSelecao(
              controller: _operadorController,
              label: 'Operador',
              hint: semUsuarios
                  ? 'Nenhum operador encontrado'
                  : 'Selecione o operador',
              icon: Icons.badge,
              selecionado: temOperador,
              habilitado: !semUsuarios,
              onTap: semUsuarios ? null : () => _abrirSeletorOperador(),
              helperText: semUsuarios
                  ? null
                  : '$totalOperadores operadores disponíveis',
              mostrarLimpar: temOperador,
              onClear: () {
                setState(() {
                  _operadorCdUserSelecionado = null;
                  _operadorController.clear();
                });
              },
            ),
    );
  }

  Widget _buildOperador2Dropdown() {
    final temOperador =
        (_operador2CdUserSelecionado ?? '').isNotEmpty &&
        _operador2Controller.text.isNotEmpty;
    final semUsuarios = _usuariosOperadores.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _loadingUsuariosOperadores
          ? _buildCampoSelecao(
              controller: _operador2Controller,
              label: 'Segundo operador (opcional)',
              hint: 'Carregando operadores...',
              icon: Icons.badge_outlined,
              selecionado: false,
              habilitado: false,
              onTap: null,
              helperText: null,
            )
          : _buildCampoSelecao(
              controller: _operador2Controller,
              label: 'Segundo operador (opcional)',
              hint: semUsuarios
                  ? 'Nenhum operador encontrado'
                  : 'Selecione o operador',
              icon: Icons.badge_outlined,
              selecionado: temOperador,
              habilitado: !semUsuarios,
              onTap: semUsuarios
                  ? null
                  : () => _abrirSeletorOperador(segundo: true),
              helperText: null,
              mostrarLimpar: temOperador,
              onClear: () {
                setState(() {
                  _operador2CdUserSelecionado = null;
                  _operador2Controller.clear();
                  _qtde2Controller.clear();
                });
              },
            ),
    );
  }

  Widget _buildArtigoEsperadoInfo() {
    if (_artigoEsperadoId.isEmpty && _artigoEsperadoNome.isEmpty) {
      return const SizedBox.shrink();
    }

    final label = _artigoEsperadoNome.isNotEmpty
        ? _artigoEsperadoNome
        : 'ID ${_artigoEsperadoId}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorderSoft),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: _kAccentColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Artigo esperado: $label',
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // CAMPO ARTIGO (coletor HID – sem botão de ícone, foco automático)
  // -----------------------------------------------------------------------

  Widget _buildArtigoField() {
    final temProduto = _artigoController.text.isNotEmpty;
    final mostrarCamera = !temProduto && widget.tipo != 'B';
    final labelCampo = widget.tipo == 'B' ? 'Objeto' : 'Artigo';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Stack(
        children: [
          // Campo visual
          TextFormField(
            controller: _artigoController,
            readOnly: true,
            style: const TextStyle(color: _kTextPrimary),
            decoration: InputDecoration(
              labelText: labelCampo,
              labelStyle: const TextStyle(color: _kTextSecondary),
              hintText: _coletorArtigoAtivo
                  ? 'Aguardando bipe...'
                  : widget.tipo == 'B'
                  ? 'Toque para camera, coletor ou manual'
                  : 'Toque para ativar coletor',
              hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 13),
              prefixIcon: const Icon(
                Icons.inventory_2_outlined,
                color: _kAccentColor,
              ),
              suffixIcon: temProduto
                  ? IconButton(
                      icon: const Icon(Icons.close, color: _kTextSecondary),
                      onPressed: _limparArtigoSelecionado,
                    )
                  : widget.tipo == 'B'
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.edit_note,
                            color: _kAccentColor,
                          ),
                          tooltip: 'Selecionar manualmente',
                          onPressed: _abrirFluxoManualArtigoTipoB,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.qr_code_scanner,
                            color: _kAccentColor,
                          ),
                          tooltip: 'Ler artigo',
                          onPressed: _escolherModoLeituraArtigo,
                        ),
                      ],
                    )
                  : _coletorArtigoAtivo
                  ? const SizedBox.shrink()
                  : const Icon(Icons.sensors_off, color: _kTextSecondary),
              filled: true,
              fillColor: temProduto
                  ? Colors.green.withOpacity(0.07)
                  : _coletorArtigoAtivo
                  ? _kAccentColor.withOpacity(0.07)
                  : _kSurface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _kBorderSoft),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: temProduto
                      ? Colors.green.withOpacity(0.5)
                      : _coletorArtigoAtivo
                      ? _kAccentColor
                      : _kBorderSoft,
                  width: _coletorArtigoAtivo ? 2 : 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _kAccentColor, width: 2),
              ),
            ),
            onTap: _coletorArtigoAtivo ? null : _escolherModoLeituraArtigo,
          ),

          // Campo HID invisível
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_coletorArtigoAtivo,
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: _coletorArtigoController,
                  focusNode: _coletorArtigoFocus,
                  keyboardType: TextInputType.none,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {
                    SystemChannels.textInput.invokeMethod('TextInput.hide');
                  },
                  onSubmitted: (value) {
                    final code = value.trim();
                    _coletorArtigoController.clear();
                    setState(() => _coletorArtigoAtivo = false);
                    FocusScope.of(context).unfocus();
                    if (code.isNotEmpty) _processarBuscaProduto(code);
                  },
                ),
              ),
            ),
          ),

          // Botão de câmera
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: !mostrarCamera
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.qr_code_scanner,
                        color: _kAccentColor,
                        size: 22,
                      ),
                      onPressed: _escolherModoLeituraArtigo,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // DROPDOWNS (iguais ao original)
  // -----------------------------------------------------------------------

  Widget _buildDefeitoDropdownTipoB() {
    final selecionado =
        (_defeitoSelecionadoCodigo ?? '').isNotEmpty &&
        _defeitoController.text.isNotEmpty;
    final habilitado = !_loadingDefeitosTipoB;
    final hint = _loadingDefeitosTipoB
        ? 'Carregando defeitos...'
        : _defeitosTipoB.isEmpty
        ? 'Nenhum defeito encontrado'
        : 'Selecione o defeito';
    final helperText = _loadingDefeitosTipoB
        ? 'Consultando defeitos cadastrados'
        : _defeitosTipoB.isEmpty
        ? 'Não foi possível obter defeitos da API'
        : '${_defeitosTipoB.length} defeitos cadastrados';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _buildCampoSelecao(
        controller: _defeitoController,
        label: 'Defeito',
        hint: hint,
        icon: Icons.warning_amber_outlined,
        selecionado: selecionado,
        habilitado: habilitado,
        onTap: habilitado ? _abrirSeletorDefeitoTipoB : null,
        helperText: helperText,
        mostrarLimpar: selecionado,
        onClear: () {
          setState(() {
            _defeitoSelecionadoCodigo = null;
            _defeitoController.clear();
          });
        },
      ),
    );
  }

  Future<void> _abrirSelecaoPaleteTipoB() async {
    final selecionado = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Selecionar Palete',
                  style: TextStyle(
                    color: _kTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.warehouse_outlined,
                    color: _kAccentColor,
                  ),
                  title: const Text(
                    _kPaleteTipoBFixo,
                    style: TextStyle(
                      color: _kTextPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Único palete permitido para este apontamento',
                    style: TextStyle(color: _kTextSecondary),
                  ),
                  onTap: () => Navigator.pop(ctx, _kPaleteTipoBFixo),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selecionado == null) return;
    setState(() => _palletController.text = selecionado);
  }

  Widget _buildOrdemProducaoFieldTipoB() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _ordemProducaoController,
        readOnly: true,
        style: const TextStyle(color: _kTextPrimary),
        decoration: InputDecoration(
          labelText: 'Ordem de Produção',
          hintText: 'Preenchimento bloqueado',
          labelStyle: const TextStyle(color: _kTextSecondary),
          hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 13),
          prefixIcon: const Icon(
            Icons.confirmation_number_outlined,
            color: _kAccentColor,
          ),
          suffixIcon: _buscandoOrdemProducao
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _kAccentColor,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh, color: _kTextSecondary),
                  tooltip: 'Reconsultar Ordem de Produção',
                  onPressed: _cdObjReal.trim().isEmpty
                      ? null
                      : () => _buscarOrdemProducaoParaObjeto(_cdObjReal),
                ),
          filled: true,
          fillColor: _kSurface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _kBorderSoft),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _kAccentColor, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildPaleteFieldTipoB() {
    final selecionado =
        _palletController.text.trim().toUpperCase() == _kPaleteTipoBFixo;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _buildCampoSelecao(
        controller: _palletController,
        label: 'Palete',
        hint: 'Selecione o palete',
        icon: Icons.warehouse_outlined,
        selecionado: selecionado,
        habilitado: true,
        onTap: _abrirSelecaoPaleteTipoB,
        helperText: 'Somente $_kPaleteTipoBFixo',
      ),
    );
  }

  Widget _buildDetalheDropdownTipoB() {
    final possuiOpcoes = _lotesDisponiveis.isNotEmpty;
    final valorAtual = possuiOpcoes &&
            _lotesDisponiveis.any(
              (item) => (item['detalheID'] ?? '').toString() == _detalheReal,
            )
        ? _detalheReal
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Detalhe',
          labelStyle: const TextStyle(color: _kTextSecondary),
          prefixIcon: const Icon(Icons.info_outline, color: _kAccentColor),
          filled: true,
          fillColor: _kSurface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _kBorderSoft),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _kAccentColor, width: 2),
          ),
          helperText: possuiOpcoes
              ? '${_lotesDisponiveis.length} lotes disponiveis'
              : 'Selecione ou leia um artigo para carregar os lotes',
          helperStyle: const TextStyle(color: _kTextSecondary, fontSize: 11),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            dropdownColor: _kSurface,
            hint: const Text(
              'Selecione o detalhe',
              style: TextStyle(color: _kTextSecondary),
            ),
            value: valorAtual,
            items: _lotesDisponiveis.map((item) {
              final codigo = (item['detalheID'] ?? '').toString();
              final detalhe = (item['detalhe'] ?? '').toString();
              return DropdownMenuItem<String>(
                value: codigo,
                child: Text(
                  detalhe,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _kTextPrimary),
                ),
              );
            }).toList(),
            onChanged: !possuiOpcoes
                ? null
                : (value) {
                    if (value == null) return;
                    final selecionado = _lotesDisponiveis.firstWhere(
                      (item) => (item['detalheID'] ?? '').toString() == value,
                    );
                    setState(() {
                      _detalheReal = value;
                      _detalheController.text =
                          (selecionado['detalhe'] ?? '').toString();
                    });
                  },
          ),
        ),
      ),
    );
  }

  Widget _buildSetorDropdown() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _loadingSetores
        ? _buildCampoSelecao(
            controller: _setorController,
            label: 'Setor',
            hint: 'Carregando setores...',
            icon: Icons.apartment,
            selecionado: false,
            habilitado: false,
            onTap: null,
            helperText: null,
          )
        : _buildCampoSelecao(
            controller: _setorController,
            label: 'Setor',
            hint: _setores.isEmpty
                ? 'Nenhum setor encontrado'
                : 'Selecione um setor',
            icon: Icons.apartment,
            selecionado: _setorSelecionado != null,
            habilitado: _setores.isNotEmpty,
            onTap: _setores.isEmpty ? null : _abrirSeletorSetor,
            helperText: _setores.isEmpty
                ? null
                : '${_setores.length} setores disponíveis',
            mostrarLimpar: _setorSelecionado != null,
            onClear: () {
              setState(() {
                _setorSelecionado = null;
                _setorController.clear();
                _maquinas = [];
                _maquinaSelecionada = null;
                _maquinaSelecionadaSecundaria = null;
                _maquinaController.clear();
                _maquina2Controller.clear();
              });
            },
          ),
  );

  Widget _buildMaquinaDropdown() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _loadingMaquinas
        ? _buildCampoSelecao(
            controller: _maquinaController,
            label: 'Máquina',
            hint: 'Carregando máquinas...',
            icon: Icons.settings,
            selecionado: false,
            habilitado: false,
            onTap: null,
            helperText: null,
          )
        : _buildCampoSelecao(
            controller: _maquinaController,
            label: 'Máquina',
            hint: _setorSelecionado == null
                ? 'Selecione um setor primeiro'
                : _maquinas.isEmpty
                ? 'Nenhuma máquina encontrada'
                : 'Selecione uma máquina',
            icon: Icons.settings,
            selecionado: _maquinaSelecionada != null,
            habilitado: _setorSelecionado != null,
            onTap: _setorSelecionado == null
                ? null
                : () => _abrirSeletorMaquina(),
            helperText: _setorSelecionado == null
                ? 'Selecione um setor primeiro'
                : _maquinas.isEmpty
                ? 'Nenhuma máquina disponível para este setor'
                : '${_maquinas.length} máquinas disponíveis',
            mostrarLimpar: _maquinaSelecionada != null,
            onClear: () {
              setState(() {
                _maquinaSelecionada = null;
                _maquinaController.clear();
              });
            },
          ),
  );

  Widget _buildMaquina2Dropdown() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _loadingMaquinas
        ? _buildCampoSelecao(
            controller: _maquina2Controller,
            label: 'Máquina 2 (opcional)',
            hint: 'Carregando máquinas...',
            icon: Icons.settings_applications,
            selecionado: false,
            habilitado: false,
            onTap: null,
            helperText: null,
          )
        : _buildCampoSelecao(
            controller: _maquina2Controller,
            label: 'Máquina 2 (opcional)',
            hint: _setorSelecionado == null
                ? 'Selecione um setor primeiro'
                : _maquinas.isEmpty
                ? 'Nenhuma máquina encontrada'
                : 'Selecione a segunda máquina',
            icon: Icons.settings_applications,
            selecionado: _maquinaSelecionadaSecundaria != null,
            habilitado: _setorSelecionado != null,
            onTap: _setorSelecionado == null
                ? null
                : () => _abrirSeletorMaquina(segunda: true),
            helperText: _setorSelecionado == null
                ? 'Selecione um setor primeiro'
                : _maquinas.isEmpty
                ? 'Nenhuma máquina disponível para este setor'
                : 'Opcional: selecione se o operador atuar em duas máquinas',
            mostrarLimpar: _maquinaSelecionadaSecundaria != null,
            onClear: () {
              setState(() {
                _maquinaSelecionadaSecundaria = null;
                _maquina2Controller.clear();
              });
            },
          ),
  );

  // -----------------------------------------------------------------------
  // WIDGETS GENÉRICOS
  // -----------------------------------------------------------------------

  Widget _buildTurnoHeader(String letra) => Container(
    padding: const EdgeInsets.all(15),
    margin: const EdgeInsets.only(bottom: 20),
    decoration: BoxDecoration(
      color: _kSurface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _kBorderSoft),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TURNO ATUAL',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _kTextSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _descricaoTurno(letra),
                style: const TextStyle(
                  color: _kTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildCardSection(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: _kSurface2,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _kBorderSoft),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: _kTextSecondary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 15),
        ...children,
      ],
    ),
  );

  Widget _buildTipoBSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: _kSurface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorderSoft),
        boxShadow: [
          BoxShadow(
            color: _kPrimaryColor.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _kTextPrimary,
              ),
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTipoBInfoField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _kTextSecondary),
          prefixIcon: Icon(icon, color: _kAccentColor),
          filled: true,
          fillColor: _kSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _kBorderSoft),
          ),
        ),
        child: Text(
          value,
          style: const TextStyle(
            color: _kTextPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildTipoBResponsiveFieldGroup(List<Widget> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final columns = availableWidth >= 980
            ? 3
            : availableWidth >= 640
            ? 2
            : 1;
        const spacing = 16.0;
        final double targetWidth = columns == 1
            ? availableWidth
            : math.min(
                math.max(
                  (availableWidth - spacing * (columns - 1)) / columns,
                  250,
                ),
                420,
              );

        return Wrap(
          spacing: spacing,
          runSpacing: 0,
          children: fields
              .map((field) => SizedBox(width: targetWidth, child: field))
              .toList(),
        );
      },
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isNumeric = false,
    bool readOnly = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      readOnly: readOnly,
      style: const TextStyle(color: _kTextPrimary),
      keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kTextSecondary),
        prefixIcon: Icon(icon, color: _kAccentColor),
        filled: true,
        fillColor: readOnly ? _kSurface : _kSurface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kBorderSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kBorderSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kAccentColor, width: 2),
        ),
      ),
    ),
  );

  Widget _buildBotaoConfirmar() => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: _isLoading ? null : _enviar,
      style: ElevatedButton.styleFrom(
        backgroundColor: _kPrimaryColor,
        disabledBackgroundColor: Colors.grey,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: _isLoading
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Text(
              'CONFIRMAR',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
    ),
  );
}

class ScannerPage extends StatelessWidget {
  final String modo;
  final String titulo;

  const ScannerPage({super.key, this.modo = 'all', this.titulo = 'Scanner'});

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _MacScannerPage(modo: modo, titulo: titulo);
    }
    return _AndroidScannerPage(modo: modo, titulo: titulo);
  }
}

class _MacScannerPage extends StatefulWidget {
  final String modo;
  final String titulo;

  const _MacScannerPage({required this.modo, required this.titulo});

  @override
  State<_MacScannerPage> createState() => _MacScannerPageState();
}

class _MacScannerPageState extends State<_MacScannerPage>
    with SingleTickerProviderStateMixin {
  late MobileScannerController _controller;
  bool _hasScanned = false;
  bool _torchOn = false;
  bool? _cameraPermissionGranted;
  late AnimationController _laserAnim;
  late Animation<double> _laserPos;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.unrestricted,
      autoStart: true,
      facing: CameraFacing.back,
      onPermissionSet: (granted) {
        if (!mounted) return;
        setState(() => _cameraPermissionGranted = granted);
      },
      formats: _resolverFormatosMac(),
    );

    _laserAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _laserPos = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _laserAnim, curve: Curves.easeInOut));
  }

  List<BarcodeFormat>? _resolverFormatosMac() {
    if (widget.modo == 'qr') {
      return const [BarcodeFormat.qrCode];
    }
    return null;
  }

  @override
  void dispose() {
    _controller.dispose();
    _laserAnim.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final isBarcodeMode = widget.modo == 'barcode';

    for (final barcode in capture.barcodes) {
      final String raw = _extrairTextoCodigo(barcode);
      if (raw.isEmpty) continue;

      final String somenteNumeros = raw.replaceAll(RegExp(r'\D'), '');
      final bool manterBruto =
          !isBarcodeMode &&
          (barcode.format == BarcodeFormat.qrCode || raw.startsWith('{'));
      final String valorLido = manterBruto
          ? raw
          : (somenteNumeros.isNotEmpty ? somenteNumeros : raw);

      _hasScanned = true;
      _controller.stop();

      Future.delayed(Duration.zero, () {
        if (mounted) Navigator.pop(context, valorLido);
      });
      break;
    }
  }

  String _extrairTextoCodigo(Barcode barcode) {
    final fromRaw = (barcode.rawValue ?? '').trim();
    if (fromRaw.isNotEmpty) return fromRaw;

    final fromDisplay = (barcode.displayValue ?? '').trim();
    if (fromDisplay.isNotEmpty) return fromDisplay;

    final bytes = barcode.rawBytes;
    if (bytes != null && bytes.isNotEmpty) {
      final decodedUtf8 = _decodificarTextoConfiavel(bytes, utf8);
      if (decodedUtf8 != null) return decodedUtf8;

      final decodedLatin1 = _decodificarTextoConfiavel(bytes, latin1);
      if (decodedLatin1 != null) return decodedLatin1;
    }

    return '';
  }

  String? _decodificarTextoConfiavel(List<int> bytes, Encoding encoding) {
    try {
      final decoded = encoding.decode(bytes).trim();
      if (decoded.isEmpty) return null;

      const int minCharCodeImprimivel = 32;
      const int maxCharCodeImprimivel = 126;
      int total = 0;
      int imprimiveis = 0;

      for (final rune in decoded.runes) {
        total++;
        final bool isWhitespace = rune == 9 || rune == 10 || rune == 13;
        final bool isPrintableAscii =
            rune >= minCharCodeImprimivel && rune <= maxCharCodeImprimivel;
        if (isWhitespace || isPrintableAscii) {
          imprimiveis++;
        }
      }

      if (total == 0) return null;

      final confiabilidade = imprimiveis / total;
      if (confiabilidade < 0.95) return null;

      return decoded;
    } catch (_) {
      return null;
    }
  }

  Widget _buildScannerError(MobileScannerException error) {
    final isMacOs = defaultTargetPlatform == TargetPlatform.macOS;
    final details = error.errorDetails;
    final message = details?.message ?? '';

    String titulo = 'Falha ao iniciar a câmera';
    String descricao = 'Não foi possível abrir a câmera.';

    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        titulo = 'Permissão de câmera negada';
        descricao = isMacOs
            ? 'Ative em Ajustes do macOS > Privacidade e Segurança > Câmera.'
            : 'Conceda permissão de câmera para continuar.';
        break;
      case MobileScannerErrorCode.unsupported:
        titulo = 'Câmera não suportada';
        descricao = 'Este dispositivo não suporta leitura por câmera.';
        break;
      case MobileScannerErrorCode.controllerUninitialized:
      case MobileScannerErrorCode.genericError:
        break;
    }

    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 44),
          const SizedBox(height: 12),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            descricao,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: () async {
              try {
                await _controller.stop();
                await _controller.start();
              } catch (_) {}
            },
            icon: const Icon(Icons.refresh, color: _kAccentColor),
            label: const Text(
              'Tentar novamente',
              style: TextStyle(color: _kAccentColor),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBarcode = widget.modo == 'barcode';
    final isMacOs = defaultTargetPlatform == TargetPlatform.macOS;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: _kTextPrimary,
        title: Text(widget.titulo),
        actions: [
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            tooltip: 'Trocar câmera',
            onPressed: _controller.switchCamera,
          ),
          IconButton(
            icon: Icon(
              isMacOs
                  ? Icons.lightbulb_outline
                  : _torchOn
                  ? Icons.flashlight_off
                  : Icons.flashlight_on,
            ),
            color: _torchOn ? _kAccentColor : _kTextSecondary,
            tooltip: isMacOs ? 'Flash indisponível no Mac' : 'Flash',
            onPressed: isMacOs
                ? null
                : () {
                    _controller.toggleTorch();
                    setState(() => _torchOn = !_torchOn);
                  },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          // Ajuste de janela para códigos de barras longos (boletos)
          final windowW = isBarcode ? w * 0.92 : w * 0.72;
          final windowH = isBarcode ? w * 0.35 : w * 0.72;
          final left = (w - windowW) / 2;
          final top = (h - windowH) / 2 - 20;

          return Stack(
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                onScannerStarted: (_) {
                  if (_cameraPermissionGranted != true && mounted) {
                    setState(() => _cameraPermissionGranted = true);
                  }
                },
                errorBuilder: (context, error, child) =>
                    _buildScannerError(error),
                placeholderBuilder: (context, child) => const ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: CircularProgressIndicator(color: _kAccentColor),
                  ),
                ),
              ),
              // Overlay escuro
              CustomPaint(
                size: Size(w, h),
                painter: _ScanOverlayPainter(
                  left: left,
                  top: top,
                  width: windowW,
                  height: windowH,
                  radius: isBarcode ? 8.0 : 14.0,
                ),
              ),
              // Cantoneiras
              Positioned(
                left: left,
                top: top,
                child: SizedBox(
                  width: windowW,
                  height: windowH,
                  child: CustomPaint(
                    painter: _CornerPainter(
                      color: _kAccentColor,
                      thickness: 3.5,
                      cornerLength: 24.0,
                      radius: isBarcode ? 8.0 : 14.0,
                    ),
                  ),
                ),
              ),
              // Linha Laser Animada
              Positioned(
                left: left + 8,
                top: top + 6,
                width: windowW - 16,
                height: windowH - 12,
                child: AnimatedBuilder(
                  animation: _laserPos,
                  builder: (_, __) {
                    final laserY = _laserPos.value * (windowH - 12 - 2);
                    return Stack(
                      children: [
                        Positioned(
                          top: laserY,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: _kAccentColor,
                              boxShadow: [
                                BoxShadow(
                                  color: _kAccentColor.withOpacity(0.5),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              // Instrução inferior
              Positioned(
                bottom: 52,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    Icon(
                      isBarcode ? Icons.barcode_reader : Icons.qr_code_scanner,
                      color: Colors.white60,
                      size: 26,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isBarcode
                          ? 'Centralize o código de barras longo na área'
                          : 'Aponte para o QR Code ou código de barras',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AndroidScannerPage extends StatefulWidget {
  final String modo;
  final String titulo;

  const _AndroidScannerPage({required this.modo, required this.titulo});

  @override
  State<_AndroidScannerPage> createState() => _AndroidScannerPageState();
}

class _AndroidScannerPageState extends State<_AndroidScannerPage>
    with SingleTickerProviderStateMixin {
  late MobileScannerController _controller;
  bool _hasScanned = false;
  bool _torchOn = false;
  bool? _cameraPermissionGranted;
  late AnimationController _laserAnim;
  late Animation<double> _laserPos;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.unrestricted,
      detectionTimeoutMs: 100,
      autoStart: true,
      facing: CameraFacing.back,
      cameraResolution: const Size(1280, 720),
      onPermissionSet: (granted) {
        if (!mounted) return;
        setState(() => _cameraPermissionGranted = granted);
      },
      formats: _resolverFormatosMobile(),
    );

    _laserAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _laserPos = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _laserAnim, curve: Curves.easeInOut));
  }

  List<BarcodeFormat>? _resolverFormatosMobile() {
    if (widget.modo == 'qr') {
      return const [BarcodeFormat.qrCode];
    }
    if (widget.modo == 'barcode') {
      return const [
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.codabar,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.itf,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.pdf417,
      ];
    }
    if (widget.modo == 'all') {
      return const [
        BarcodeFormat.qrCode,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.codabar,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.itf,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.pdf417,
      ];
    }
    return null;
  }

  @override
  void dispose() {
    _controller.dispose();
    _laserAnim.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    for (final barcode in capture.barcodes) {
      final raw = _extrairTextoCodigo(barcode);
      final valorLido = _normalizarCodigoLido(raw);
      if (valorLido.isEmpty) continue;

      _hasScanned = true;
      _controller.stop();

      Future.delayed(Duration.zero, () {
        if (mounted) Navigator.pop(context, valorLido);
      });
      break;
    }
  }

  String _normalizarCodigoLido(String value) {
    return value.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
  }

  String _extrairTextoCodigo(Barcode barcode) {
    final fromRaw = (barcode.rawValue ?? '').trim();
    if (fromRaw.isNotEmpty) return fromRaw;

    final fromDisplay = (barcode.displayValue ?? '').trim();
    if (fromDisplay.isNotEmpty) return fromDisplay;

    final bytes = barcode.rawBytes;
    if (bytes != null && bytes.isNotEmpty) {
      final decodedUtf8 = _decodificarTextoConfiavel(bytes, utf8);
      if (decodedUtf8 != null) return decodedUtf8;

      final decodedLatin1 = _decodificarTextoConfiavel(bytes, latin1);
      if (decodedLatin1 != null) return decodedLatin1;
    }

    return '';
  }

  String? _decodificarTextoConfiavel(List<int> bytes, Encoding encoding) {
    try {
      final decoded = encoding.decode(bytes).trim();
      if (decoded.isEmpty) return null;

      const int minCharCodeImprimivel = 32;
      const int maxCharCodeImprimivel = 126;
      int total = 0;
      int imprimiveis = 0;

      for (final rune in decoded.runes) {
        total++;
        final bool isWhitespace = rune == 9 || rune == 10 || rune == 13;
        final bool isPrintableAscii =
            rune >= minCharCodeImprimivel && rune <= maxCharCodeImprimivel;
        if (isWhitespace || isPrintableAscii) {
          imprimiveis++;
        }
      }

      if (total == 0) return null;

      final confiabilidade = imprimiveis / total;
      if (confiabilidade < 0.95) return null;

      return decoded;
    } catch (_) {
      return null;
    }
  }

  Widget _buildScannerError(MobileScannerException error) {
    final details = error.errorDetails;
    final message = details?.message ?? '';

    String titulo = 'Falha ao iniciar a câmera';
    String descricao = 'Não foi possível abrir a câmera.';

    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        titulo = 'Permissão de câmera negada';
        descricao = 'Conceda permissão de câmera para continuar.';
        break;
      case MobileScannerErrorCode.unsupported:
        titulo = 'Câmera não suportada';
        descricao = 'Este dispositivo não suporta leitura por câmera.';
        break;
      case MobileScannerErrorCode.controllerUninitialized:
      case MobileScannerErrorCode.genericError:
        break;
    }

    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 44),
          const SizedBox(height: 12),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            descricao,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: () async {
              try {
                await _controller.stop();
                await _controller.start();
              } catch (_) {}
            },
            icon: const Icon(Icons.refresh, color: _kAccentColor),
            label: const Text(
              'Tentar novamente',
              style: TextStyle(color: _kAccentColor),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBarcode = widget.modo == 'barcode';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: _kTextPrimary,
        title: Text(widget.titulo),
        actions: [
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: _controller.switchCamera,
          ),
          IconButton(
            icon: Icon(_torchOn ? Icons.flashlight_off : Icons.flashlight_on),
            color: _torchOn ? _kAccentColor : _kTextSecondary,
            onPressed: () {
              _controller.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final windowW = isBarcode ? w * 0.92 : w * 0.72;
          final windowH = isBarcode ? w * 0.35 : w * 0.72;
          final left = (w - windowW) / 2;
          final top = (h - windowH) / 2 - 20;

          return Stack(
            children: [
              MobileScanner(
                controller: _controller,
                fit: BoxFit.cover,
                scanWindow: Rect.fromLTWH(left, top, windowW, windowH),
                onDetect: _onDetect,
                onScannerStarted: (_) {
                  if (_cameraPermissionGranted != true && mounted) {
                    setState(() => _cameraPermissionGranted = true);
                  }
                },
                errorBuilder: (context, error, child) =>
                    _buildScannerError(error),
                placeholderBuilder: (context, child) => const ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: CircularProgressIndicator(color: _kAccentColor),
                  ),
                ),
              ),
              CustomPaint(
                size: Size(w, h),
                painter: _ScanOverlayPainter(
                  left: left,
                  top: top,
                  width: windowW,
                  height: windowH,
                  radius: isBarcode ? 8.0 : 14.0,
                ),
              ),
              Positioned(
                left: left,
                top: top,
                child: SizedBox(
                  width: windowW,
                  height: windowH,
                  child: CustomPaint(
                    painter: _CornerPainter(
                      color: _kAccentColor,
                      thickness: 3.5,
                      cornerLength: 24.0,
                      radius: isBarcode ? 8.0 : 14.0,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: left + 8,
                top: top + 6,
                width: windowW - 16,
                height: windowH - 12,
                child: AnimatedBuilder(
                  animation: _laserPos,
                  builder: (_, __) {
                    final laserY = _laserPos.value * (windowH - 12 - 2);
                    return Stack(
                      children: [
                        Positioned(
                          top: laserY,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: _kAccentColor,
                              boxShadow: [
                                BoxShadow(
                                  color: _kAccentColor.withOpacity(0.5),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Positioned(
                bottom: 52,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    Icon(
                      isBarcode ? Icons.barcode_reader : Icons.qr_code_scanner,
                      color: Colors.white60,
                      size: 26,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isBarcode
                          ? 'Centralize o código de barras longo na área'
                          : 'Aponte para o QR Code ou código de barras',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  final double left, top, width, height, radius;
  _ScanOverlayPainter({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final windowRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, width, height),
      Radius.circular(radius),
    );
    final paint = Paint()..color = Colors.black.withOpacity(0.62);
    final path = Path()
      ..addRect(fullRect)
      ..addRRect(windowRRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter old) =>
      old.left != left ||
      old.top != top ||
      old.width != width ||
      old.height != height;
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness, cornerLength, radius;
  _CornerPainter({
    required this.color,
    required this.thickness,
    required this.cornerLength,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height, l = cornerLength, r = radius;

    canvas.drawLine(Offset(0, l), Offset(0, r), paint);
    canvas.drawArc(
      Rect.fromLTWH(0, 0, r * 2, r * 2),
      3.14159,
      3.14159 / 2,
      false,
      paint,
    );
    canvas.drawLine(Offset(r, 0), Offset(l, 0), paint);

    canvas.drawLine(Offset(w - l, 0), Offset(w - r, 0), paint);
    canvas.drawArc(
      Rect.fromLTWH(w - r * 2, 0, r * 2, r * 2),
      -3.14159 / 2,
      3.14159 / 2,
      false,
      paint,
    );
    canvas.drawLine(Offset(w, r), Offset(w, l), paint);

    canvas.drawLine(Offset(0, h - l), Offset(0, h - r), paint);
    canvas.drawArc(
      Rect.fromLTWH(0, h - r * 2, r * 2, r * 2),
      3.14159 / 2,
      3.14159 / 2,
      false,
      paint,
    );
    canvas.drawLine(Offset(r, h), Offset(l, h), paint);

    canvas.drawLine(Offset(w - l, h), Offset(w - r, h), paint);
    canvas.drawArc(
      Rect.fromLTWH(w - r * 2, h - r * 2, r * 2, r * 2),
      0,
      3.14159 / 2,
      false,
      paint,
    );
    canvas.drawLine(Offset(w, h - r), Offset(w, h - l), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.color != color || old.thickness != thickness;
}
