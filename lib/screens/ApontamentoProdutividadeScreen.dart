import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_helper;

// =========================================================================
// CONFIGURAÇÃO DE REDE
// =========================================================================
const String _kBaseUrlFlask = "http://168.190.90.2:5000";
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
            .map(
              (e) => UsuarioOperador.fromJson(Map<String, dynamic>.from(e)),
            )
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
  const ProducaoTabsScreen({super.key});
  @override
  State<ProducaoTabsScreen> createState() => _ProducaoTabsScreenState();
}

class _ProducaoTabsScreenState extends State<ProducaoTabsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
          bottom: TabBar(
            controller: _tabController,
            labelColor: _kTextPrimary,
            unselectedLabelColor: _kTextSecondary,
            indicatorColor: _kAccentColor,
            tabs: const [
              Tab(text: 'Tipo A', icon: Icon(Icons.factory_outlined)),
              Tab(text: 'Tipo B', icon: Icon(Icons.high_quality_outlined)),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            FormularioGeral(tipo: 'A', turno: turnoNum, turnoLetra: turnoLetra),
            FormularioGeral(tipo: 'B', turno: turnoNum, turnoLetra: turnoLetra),
          ],
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

  const FormularioGeral({
    required this.tipo,
    required this.turno,
    required this.turnoLetra,
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
  final _operadorController = TextEditingController();
  final _defeitoController = TextEditingController();
  String? _operadorCdUserSelecionado;
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
  bool _loadingSetores = false;
  bool _loadingMaquinas = false;

  // ── Produto selecionado ───────────────────────────────────────────────
  String _cdObjReal = "";
  String _detalheReal = "";
  bool _isLoading = false;

  // ── Estado visual do coletor ──────────────────────────────────────────
  bool _coletorArtigoAtivo = false;

  bool get _isRevisao =>
      _setorSelecionado != null &&
      _setorSelecionado!.nome.toUpperCase().trim().contains(_kSetorSemMaquina);

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
    if (widget.tipo == 'A') {
      _carregarSetores();
      _carregarUsuariosOperadores();
    }
  }

  @override
  void dispose() {
    _artigoController.dispose();
    _detalheController.dispose();
    _qtdeController.dispose();
    _operadorController.dispose();
    _defeitoController.dispose();
    _coletorArtigoController.dispose();
    _coletorArtigoFocus.dispose();
    super.dispose();
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

  Future<void> _carregarUsuariosOperadores() async {
    if (_loadingUsuariosOperadores) return;
    setState(() => _loadingUsuariosOperadores = true);
    try {
      final usuarios = await UsuarioOperadorService.buscarUsuarios();
      if (!mounted) return;
      setState(() => _usuariosOperadores = usuarios);
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
      setState(() => _setores = setores);
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
    });
    try {
      final maquinas = await SetorMaquinaService.buscarMaquinas(setorId);
      setState(() => _maquinas = maquinas);
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

      final produto = await DatabaseService.buscarProduto(
        buscadoObjID,
        buscadoDetID,
      );

      if (produto != null) {
        setState(() {
          _artigoController.text = produto['objeto'] ?? "";
          _detalheController.text = produto['detalhe'] ?? "";
          _cdObjReal = produto['objetoID'] ?? "";
          _detalheReal = produto['detalheID'] ?? "";
          _coletorArtigoAtivo = false;
        });
        _showSnack("Produto encontrado!", Colors.green);
        FocusScope.of(context).unfocus();
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

        setState(() {
          _artigoController.text =
              nomeProduto; // Mostra o nome do produto na tela
          _detalheController.text =
              nmLot; // Mostra o NOME do lote/detalhe na tela
          _cdObjReal = objetoID; // Guarda o código do objeto para envio
          _detalheReal =
              detalheID; // ✅ CORRIGIDO: Guarda o NÚMERO (ID) do detalhe para envio ao SQL
          _coletorArtigoAtivo = false;
        });
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

  // -----------------------------------------------------------------------
  // ENVIO
  // -----------------------------------------------------------------------

  Future<void> _enviar() async {
    if (_cdObjReal.isEmpty) return _showSnack("Bipe um Artigo", Colors.orange);

    if (widget.tipo == 'B') {
      if (_defeitoController.text.trim().isEmpty) {
        return _showSnack("Preencha o campo Defeito", Colors.orange);
      }
    }

    if (widget.tipo == 'A') {
      if (_setorSelecionado == null) {
        return _showSnack("Selecione o Setor", Colors.orange);
      }
      if (!_isRevisao && _maquinaSelecionada == null) {
        return _showSnack("Selecione a Máquina", Colors.orange);
      }
      if ((_operadorCdUserSelecionado ?? '').trim().isEmpty) {
        return _showSnack("Selecione o Operador", Colors.orange);
      }
    }

    if (_qtdeController.text.trim().isEmpty ||
        int.tryParse(_qtdeController.text) == null) {
      return _showSnack("Preencha a quantidade corretamente", Colors.orange);
    }

    setState(() => _isLoading = true);

    final endpoint = widget.tipo == 'A'
        ? '/apontamento/tipoA'
        : '/apontamento/tipoB';

    final payload = widget.tipo == 'A'
        ? {
            "Setor": _setorSelecionado!.codigo,
            "Maq": _isRevisao ? 0 : _maquinaSelecionada!.codigo,
            "Operador": _operadorCdUserSelecionado,
            "Qtde": int.tryParse(_qtdeController.text) ?? 0,
            "Artigo": _cdObjReal,
            "Detalhe": _detalheReal,
            "turno": widget.turno,
          }
        : {
            "Artigo": _cdObjReal,
            "Detalhe": _detalheReal,
            "Defeito": _defeitoController.text,
            "Qtde": int.tryParse(_qtdeController.text) ?? 0,
            "turno": widget.turno,
          };

    try {
      final resp = await http.post(
        Uri.parse("$_kBaseUrlFlask$endpoint"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      if (resp.statusCode == 201) {
        _showSnack("Salvo com sucesso!", Colors.green);
        _limpar();
      } else {
        _showSnack("Erro ao salvar: ${resp.statusCode}", Colors.red);
      }
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
    _operadorController.clear();
    _coletorArtigoController.clear();
    _defeitoController.clear();
    _operadorCdUserSelecionado = null;
    _cdObjReal = "";
    _detalheReal = "";

    if (widget.tipo == 'A') {
      setState(() {
        _etapaA = _EtapaA.identificacao;
        _setorSelecionado = null;
        _maquinaSelecionada = null;
        _maquinas = [];
        _coletorArtigoAtivo = false;
      });
    } else {
      setState(() {
        _coletorArtigoAtivo = false;
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ativarColetorArtigo(),
      );
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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kBgTop, _kSurface2, _kBgBottom],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: widget.tipo == 'A' ? _buildTipoA() : _buildTipoB(),
    );
  }

  // -----------------------------------------------------------------------
  // TIPO B (sem etapas – igual ao original, mas com foco automático)
  // -----------------------------------------------------------------------

  Widget _buildTipoB() {
    // Foca no coletor do artigo ao montar a tela Tipo B
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_coletorArtigoAtivo && _cdObjReal.isEmpty) _ativarColetorArtigo();
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildTurnoHeader(widget.turnoLetra),
          _buildCardSection('Qualidade', [
            _buildArtigoField(),
            if (_isLoading) const LinearProgressIndicator(color: _kAccentColor),
            _buildTextField(
              _detalheController,
              'Detalhe (Lote)',
              Icons.info_outline,
              readOnly: true,
            ),
            _buildTextField(
              _defeitoController,
              'Defeito',
              Icons.warning_amber_outlined,
            ),
            _buildTextField(
              _qtdeController,
              'Quantidade',
              Icons.add_task,
              isNumeric: true,
            ),
          ]),
          const SizedBox(height: 20),
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
              _buildSetorDropdown(),
              if (!_isRevisao) _buildMaquinaDropdown(),
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
              _buildArtigoField(),
              if (_isLoading)
                const LinearProgressIndicator(color: _kAccentColor),
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
                const SizedBox(height: 2),
                Text(
                  'Setor: ${_setorSelecionado?.nome ?? "—"}'
                  '${_isRevisao ? "" : "  •  Máquina: ${_maquinaSelecionada?.nome ?? "—"}"}',
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
    final valorSelecionado = _operadorCdUserSelecionado;
    final valorValido =
        valorSelecionado != null &&
        _usuariosOperadores.any((u) => u.cdUser == valorSelecionado);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _loadingUsuariosOperadores
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(
                  color: _kAccentColor,
                  strokeWidth: 2,
                ),
              ),
            )
          : DropdownButtonFormField<String>(
              value: valorValido ? valorSelecionado : null,
              dropdownColor: _kSurface,
              isExpanded: true,
              style: const TextStyle(color: _kTextPrimary),
              decoration: InputDecoration(
                labelText: 'Operador',
                labelStyle: const TextStyle(color: _kTextSecondary),
                prefixIcon: const Icon(Icons.badge, color: _kAccentColor),
                suffixIcon: temOperador
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.arrow_drop_down, color: _kTextSecondary),
                filled: true,
                fillColor: temOperador
                    ? Colors.green.withOpacity(0.07)
                    : _kSurface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _kBorderSoft),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: temOperador
                        ? Colors.green.withOpacity(0.5)
                        : _kBorderSoft,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _kAccentColor, width: 2),
                ),
              ),
              hint: Text(
                semUsuarios ? 'Nenhum operador encontrado' : 'Selecione o operador',
                style: const TextStyle(color: _kTextSecondary),
              ),
              items: _usuariosOperadores
                  .map(
                    (usuario) => DropdownMenuItem<String>(
                      value: usuario.cdUser,
                      child: Text(
                        usuario.nmUser,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: semUsuarios
                  ? null
                  : (value) {
                      if (value == null) {
                        setState(() {
                          _operadorCdUserSelecionado = null;
                          _operadorController.clear();
                        });
                        return;
                      }
                      String nome = '';
                      for (final usuario in _usuariosOperadores) {
                        if (usuario.cdUser == value) {
                          nome = usuario.nmUser;
                          break;
                        }
                      }
                      setState(() {
                        _operadorCdUserSelecionado = value;
                        _operadorController.text = nome;
                      });
                    },
            ),
    );
  }

  // -----------------------------------------------------------------------
  // CAMPO ARTIGO (coletor HID – sem botão de ícone, foco automático)
  // -----------------------------------------------------------------------

  Widget _buildArtigoField() {
    final temProduto = _artigoController.text.isNotEmpty;

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
              labelText: 'Artigo',
              labelStyle: const TextStyle(color: _kTextSecondary),
              hintText: _coletorArtigoAtivo
                  ? 'Aguardando bipe...'
                  : 'Toque em 🎯 para ativar coletor',
              hintStyle: const TextStyle(color: _kTextSecondary, fontSize: 13),
              prefixIcon: const Icon(
                Icons.inventory_2_outlined,
                color: _kAccentColor,
              ),
              suffixIcon: temProduto
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : _coletorArtigoAtivo
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(12.0),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _kAccentColor,
                        ),
                      ),
                    )
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
            onTap: _coletorArtigoAtivo ? null : _ativarColetorArtigo,
          ),

          // Campo HID invisível
          Positioned.fill(
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
                onTap: () => setState(() => _coletorArtigoAtivo = true),
              ),
            ),
          ),

          // Botão de câmera
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: temProduto
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
                      onPressed: () async {
                        final String? code = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ScannerPage(
                              modo: 'all',
                              titulo: 'Ler Artigo',
                            ),
                          ),
                        );
                        if (code != null && code.isNotEmpty) {
                          _processarBuscaProduto(code);
                        }
                      },
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

  Widget _buildSetorDropdown() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _loadingSetores
        ? const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(
                color: _kAccentColor,
                strokeWidth: 2,
              ),
            ),
          )
        : DropdownButtonFormField<Setor>(
            value: _setorSelecionado,
            dropdownColor: _kSurface,
            style: const TextStyle(color: _kTextPrimary),
            decoration: InputDecoration(
              labelText: 'Setor',
              labelStyle: const TextStyle(color: _kTextSecondary),
              prefixIcon: const Icon(Icons.apartment, color: _kAccentColor),
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
                borderSide: const BorderSide(color: _kAccentColor, width: 2),
              ),
            ),
            hint: const Text(
              'Selecione um setor',
              style: TextStyle(color: _kTextSecondary),
            ),
            items: _setores
                .map(
                  (setor) => DropdownMenuItem<Setor>(
                    value: setor,
                    child: Text(
                      setor.nome,
                      style: const TextStyle(color: _kTextPrimary),
                    ),
                  ),
                )
                .toList(),
            onChanged: (setor) {
              setState(() {
                _setorSelecionado = setor;
                _maquinaSelecionada = null;
                _maquinas = [];
              });
              if (setor != null &&
                  !setor.nome.toUpperCase().trim().contains(
                    _kSetorSemMaquina,
                  )) {
                _carregarMaquinas(setor.codigo);
              }
            },
          ),
  );

  Widget _buildMaquinaDropdown() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _loadingMaquinas
        ? const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(
                color: _kAccentColor,
                strokeWidth: 2,
              ),
            ),
          )
        : Opacity(
            opacity: _setorSelecionado == null ? 0.45 : 1.0,
            child: IgnorePointer(
              ignoring: _setorSelecionado == null,
              child: DropdownButtonFormField<Maquina>(
                value: _maquinaSelecionada,
                dropdownColor: _kSurface,
                style: const TextStyle(color: _kTextPrimary),
                decoration: InputDecoration(
                  labelText: 'Máquina',
                  labelStyle: const TextStyle(color: _kTextSecondary),
                  prefixIcon: const Icon(Icons.settings, color: _kAccentColor),
                  filled: true,
                  fillColor: _setorSelecionado == null ? _kSurface : _kSurface2,
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
                  helperText: _setorSelecionado == null
                      ? 'Selecione um setor primeiro'
                      : null,
                  helperStyle: const TextStyle(
                    color: _kTextSecondary,
                    fontSize: 11,
                  ),
                ),
                hint: Text(
                  _setorSelecionado == null
                      ? 'Aguardando setor...'
                      : _maquinas.isEmpty
                      ? 'Nenhuma máquina encontrada'
                      : 'Selecione uma máquina',
                  style: const TextStyle(color: _kTextSecondary),
                ),
                items: _maquinas
                    .map(
                      (maq) => DropdownMenuItem<Maquina>(
                        value: maq,
                        child: Text(
                          maq.nome,
                          style: const TextStyle(color: _kTextPrimary),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _setorSelecionado == null
                    ? null
                    : (maq) => setState(() => _maquinaSelecionada = maq),
              ),
            ),
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'TURNO ATUAL',
          style: TextStyle(fontWeight: FontWeight.w800, color: _kTextSecondary),
        ),
        Chip(
          label: Text(
            letra,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          backgroundColor: _kPrimaryColor,
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
      // macOS: aceita qualquer formato
      formats: null,
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
      detectionSpeed: DetectionSpeed.noDuplicates,
      detectionTimeoutMs: 400,
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
            icon: Icon(
              _torchOn ? Icons.flashlight_off : Icons.flashlight_on,
            ),
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
