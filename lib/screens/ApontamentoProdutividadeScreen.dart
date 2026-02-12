import 'package:flutter/material.dart';
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
const String _kTopManagerUrl = "visions.topmanager.com.br";
const String _kPathConsulta =
    "/Servidor_2.7.0_api/forcadevendas/lancamentodeestoque/consultar";

const Color _kPrimaryRed = Color(0xFFD32F2F);
const Color _kBackground = Color(0xFFF8F9FA);
const Color _kWhite = Colors.white;

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

  /// Verifica se precisa sincronizar (a cada 24 horas)
  static Future<bool> precisaSincronizar() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_lastSyncKey);

    if (lastSync == null) return true;

    final lastSyncDate = DateTime.parse(lastSync);
    final now = DateTime.now();
    final difference = now.difference(lastSyncDate);

    return difference.inHours >= 24;
  }

  /// Marca a data/hora da última sincronização
  static Future<void> marcarSincronizacao() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
  }

  /// Salva múltiplos produtos no banco local
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

  /// Busca um produto específico no banco local
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

    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }

  /// Busca todos os produtos de um objetoID
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

  /// Limpa todos os produtos (útil para forçar nova sincronização)
  static Future<void> limparProdutos() async {
    final db = await database;
    await db.delete(_tableProdutos);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncKey);
  }

  /// Conta quantos produtos estão no cache
  static Future<int> contarProdutos() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableProdutos',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Sincroniza todos os produtos da API
  static Future<bool> sincronizarTodosProdutos() async {
    try {
      String? token = await AuthService.obterToken();
      if (token == null) return false;

      // Lista de objetoIDs conhecidos ou você pode fazer uma busca mais ampla
      // Para simplificar, vamos buscar sem filtro específico
      final uri = Uri.https(_kTopManagerUrl, _kPathConsulta, {
        "objetoID": "", // Busca todos
        "detalheID": "",
        "empresaID": "2",
        "centroDeCustosID": "13",
        "localizacao": "Expedicao Etq",
      });

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        await salvarProdutos(data.cast<Map<String, dynamic>>());
        await marcarSincronizacao();
        return true;
      }
    } catch (e) {
      debugPrint('[ERRO SYNC] $e');
    }
    return false;
  }
}

// =========================================================================
// AUTH SERVICE (GESTÃO DE TOKEN)
// =========================================================================
class AuthService {
  static const String _tokenKey = 'tokenAplicacao';
  static const String _expiryKey = 'tokenAplicacaoExpiry';
  static const String _authUrl =
      'https://visions.topmanager.com.br/auth/api/usuarios/entrar?identificadorDaAplicacao=ForcaDeVendas&chaveDaAplicacaoExterna=2awwG8Tqp12sJtzQcyYIzVrYfQNmMg0crxWq8ohNQMlQU4cU5lvO1Y%2FGNN0hbkAD0JNPPQz3489u8paqUO3jOg%3D%3D&enderecoDeRetorno=http://qualquer';

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
    return await _renovarToken();
  }

  static Future<String?> _renovarToken() async {
    try {
      final response = await http.post(
        Uri.parse(_authUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "email": "Stik.ForcaDeVendas",
          "senha": "123456",
          "usuarioID": "15980",
        }),
      );
      if (response.statusCode == 200) {
        String token = _extrairToken(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, token);
        await prefs.setString(
          _expiryKey,
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
        );
        return token;
      }
    } catch (e) {
      debugPrint('Erro Auth: $e');
    }
    return null;
  }

  static String _extrairToken(String body) {
    RegExp regex = RegExp(r'(?<==)[\w\.-]+(?=")');
    Match? match = regex.firstMatch(body);
    if (match != null) return match.group(0)!;
    try {
      return jsonDecode(body)['Token'] ?? "";
    } catch (_) {
      return "";
    }
  }
}

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: _kPrimaryRed),
    home: const SplashScreen(),
  ),
);

// =========================================================================
// SPLASH SCREEN (SINCRONIZAÇÃO INICIAL)
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
      backgroundColor: _kPrimaryRed,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.factory_outlined,
                size: 100,
                color: Colors.white,
              ),
              const SizedBox(height: 30),
              const Text(
                'STIK APONTAMENTOS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 50),
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 20),
              Text(
                _status,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
          '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}';
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configurações'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Produtos em cache: $totalProdutos'),
            const SizedBox(height: 8),
            Text('Última sincronização: $ultimaSync'),
            const SizedBox(height: 20),
            const Text(
              'Sincronização automática a cada 24h',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _forcarSincronizacao();
            },
            child: const Text('Sincronizar Agora'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx2) => AlertDialog(
                  title: const Text('Confirmar'),
                  content: const Text('Deseja limpar todo o cache local?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx2, false),
                      child: const Text('Cancelar'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx2, true),
                      child: const Text('Limpar'),
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
            child: const Text('Limpar Cache'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
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
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Sincronizando...'),
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
    int turnoNum = (hour >= 6 && hour < 14)
        ? 8
        : (hour >= 14 && hour < 22)
        ? 9
        : 10;
    String turnoLetra = turnoNum == 8 ? 'A' : (turnoNum == 9 ? 'B' : 'C');
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _kPrimaryRed,
        title: const Text(
          'STIK APONTAMENTOS',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: _mostrarMenuOpcoes,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'PRODUÇÃO (A)', icon: Icon(Icons.factory_outlined)),
            Tab(text: 'QUALIDADE (B)', icon: Icon(Icons.high_quality_outlined)),
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
    );
  }
}

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
  final _artigoController = TextEditingController();
  final _detalheController = TextEditingController();
  final _qtdeController = TextEditingController();
  final _operadorController = TextEditingController();
  final _setorController = TextEditingController();
  final _maqController = TextEditingController();
  final _defeitoController = TextEditingController();

  String _cdObjReal = "";
  String _detalheReal = "";
  bool _isLoading = false;

  @override
  void dispose() {
    _artigoController.dispose();
    _detalheController.dispose();
    _qtdeController.dispose();
    _operadorController.dispose();
    _setorController.dispose();
    _maqController.dispose();
    _defeitoController.dispose();
    super.dispose();
  }

  /// BUSCA NO BANCO LOCAL (SQLITE)
  Future<void> _processarBuscaProduto(String code) async {
    setState(() => _isLoading = true);
    try {
      String buscadoObjID = "";
      String buscadoDetID = "";

      // 1. Extração do JSON do QR Code
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

      // 2. BUSCA NO BANCO LOCAL
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
        });
        debugPrint(
          '✅ Produto encontrado no cache: $_cdObjReal - $_detalheReal',
        );
        _showSnack("Produto encontrado!", Colors.green);
      } else {
        // Se não encontrou no cache, tenta buscar na API como fallback
        await _buscarNaAPI(buscadoObjID, buscadoDetID);
      }
    } catch (e) {
      debugPrint('[ERRO] $e');
      _showSnack("Erro ao buscar produto", Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Fallback: Busca na API se não encontrou no cache
  Future<void> _buscarNaAPI(String objetoID, String detalheID) async {
    try {
      String? token = await AuthService.obterToken();
      final uri = Uri.https(_kTopManagerUrl, _kPathConsulta, {
        "objetoID": objetoID,
        "detalheID": detalheID,
        "empresaID": "2",
        "centroDeCustosID": "13",
        "localizacao": "Expedicao Etq",
      });

      debugPrint('[API REQ] $uri');
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        final itemCorreto = data.firstWhere(
          (item) =>
              item['objetoID'].toString() == objetoID &&
              item['detalheID'].toString() == detalheID,
          orElse: () => null,
        );

        if (itemCorreto != null) {
          // Salva no cache para próximas consultas
          await DatabaseService.salvarProdutos([itemCorreto]);

          setState(() {
            _artigoController.text = itemCorreto['objeto'] ?? "";
            _detalheController.text = itemCorreto['detalhe'] ?? "";
            _cdObjReal = itemCorreto['objetoID'].toString();
            _detalheReal = itemCorreto['detalheID'].toString();
          });
          debugPrint('✅ Produto encontrado na API e salvo no cache');
          _showSnack("Produto encontrado e salvo!", Colors.green);
        } else {
          _showSnack("Produto não encontrado", Colors.orange);
        }
      }
    } catch (e) {
      debugPrint('[ERRO API] $e');
      _showSnack("Produto não encontrado no cache", Colors.orange);
    }
  }

  Future<void> _enviar() async {
    if (_cdObjReal.isEmpty) return _showSnack("Bipe um Artigo", Colors.orange);

    if (widget.tipo == 'B') {
      if (_defeitoController.text.trim().isEmpty) {
        return _showSnack("Preencha o campo Defeito", Colors.orange);
      }
    }

    if (widget.tipo == 'A') {
      if (_setorController.text.trim().isEmpty) {
        return _showSnack("Preencha o campo Setor", Colors.orange);
      }
      if (_maqController.text.trim().isEmpty) {
        return _showSnack("Preencha o campo Máquina", Colors.orange);
      }
      if (_operadorController.text.trim().isEmpty) {
        return _showSnack("Preencha o campo Operador", Colors.orange);
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
            "Setor": _setorController.text,
            "Maq": _maqController.text,
            "Operador": _operadorController.text,
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
    if (widget.tipo == 'B') {
      _defeitoController.clear();
    }
    _cdObjReal = "";
    _detalheReal = "";
  }

  void _showSnack(String msg, Color cor) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: cor));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildTurnoHeader(widget.turnoLetra),
          if (widget.tipo == 'A')
            _buildCardSection('Identificação', [
              _buildScannerField(
                context,
                _operadorController,
                'Bipe o Operador',
                Icons.badge,
              ),
              _buildTextField(_setorController, 'Setor', Icons.apartment),
              _buildTextField(_maqController, 'Máquina', Icons.settings),
            ]),
          _buildCardSection(widget.tipo == 'A' ? 'Produção' : 'Qualidade', [
            _buildScannerField(
              context,
              _artigoController,
              'Bipe o Artigo',
              Icons.qr_code,
              onRead: _processarBuscaProduto,
            ),
            if (_isLoading) const LinearProgressIndicator(color: _kPrimaryRed),
            _buildTextField(
              _detalheController,
              'Detalhe (Lote)',
              Icons.info_outline,
              readOnly: true,
            ),
            if (widget.tipo == 'B')
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
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _enviar,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryRed,
                disabledBackgroundColor: Colors.grey,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'CONFIRMAR',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnoHeader(String letra) => Container(
    padding: const EdgeInsets.all(15),
    margin: const EdgeInsets.only(bottom: 20),
    decoration: BoxDecoration(
      color: _kWhite,
      borderRadius: BorderRadius.circular(15),
      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'TURNO ATUAL',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
        ),
        Chip(
          label: Text(letra, style: const TextStyle(color: Colors.white)),
          backgroundColor: _kPrimaryRed,
        ),
      ],
    ),
  );

  Widget _buildCardSection(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: _kWhite,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 15),
        ...children,
      ],
    ),
  );

  Widget _buildScannerField(
    BuildContext context,
    TextEditingController controller,
    String label,
    IconData icon, {
    Function(String)? onRead,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: _innerTextField(
            controller,
            label,
            icon,
            readOnly: onRead != null,
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filled(
          onPressed: () async {
            final String? code = await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ScannerPage()),
            );
            if (code != null) {
              if (onRead != null) {
                onRead(code);
              } else {
                controller.text = code;
              }
            }
          },
          icon: const Icon(Icons.qr_code_scanner),
          style: IconButton.styleFrom(
            backgroundColor: _kPrimaryRed,
            minimumSize: const Size(55, 55),
          ),
        ),
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
    child: _innerTextField(
      controller,
      label,
      icon,
      isNumeric: isNumeric,
      readOnly: readOnly,
    ),
  );

  Widget _innerTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isNumeric = false,
    bool readOnly = false,
  }) => TextFormField(
    controller: controller,
    readOnly: readOnly,
    keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _kPrimaryRed),
      filled: true,
      fillColor: readOnly ? Colors.grey[200] : _kBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

// =========================================================================
// PÁGINA DO SCANNER
// =========================================================================
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  late MobileScannerController controller;
  bool hasScanned = false;

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scanner'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: MobileScanner(
        controller: controller,
        onDetect: (c) {
          if (c.barcodes.isNotEmpty && !hasScanned) {
            hasScanned = true;
            Navigator.pop(context, c.barcodes.first.rawValue);
          }
        },
      ),
    );
  }
}
