import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_helper;

// =========================================================================
// CONFIGURAÇÃO DE REDE E PALETA OFICIAL
// =========================================================================
const String _kBaseUrlFlask = "http://168.190.90.2:5000";
const String _kTopManagerUrl = "visions.topmanager.com.br";
const String _kPathConsulta =
    "/Servidor_2.7.0_api/forcadevendas/lancamentodeestoque/consultar";

const Color _kPrimaryColor = Color(0xFF2563EB); // Azul principal (moderno)
const Color _kAccentColor = Color(0xFF60A5FA); // Azul claro premium
const Color _kBgTop = Color(0xFF050A14);
const Color _kBgBottom = Color(0xFF0B1220);
const Color _kSurface = Color(0xFF101B34);
const Color _kSurface2 = Color(0xFF0F172A);
const Color _kTextPrimary = Color(0xFFF9FAFB);
const Color _kTextSecondary = Color(0xFF9CA3AF);
const Color _kBorderSoft = Color(0x33FFFFFF);

// =========================================================================
// DATABASE SERVICE (SQLITE) - ASSOCIADO PARA BUSCAR O NOME DO ARTIGO
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
    return now.difference(lastSyncDate).inHours >= 24;
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
      String? token = await AuthService.obterToken();
      if (token == null) return false;

      final uri = Uri.https(_kTopManagerUrl, _kPathConsulta, {
        "objetoID": "",
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

// =========================================================================
// TELA DE REGISTROS / CONSULTA
// =========================================================================
class RegistrosApontamento extends StatefulWidget {
  const RegistrosApontamento({super.key});

  @override
  State<RegistrosApontamento> createState() => _RegistrosApontamentoState();
}

class _RegistrosApontamentoState extends State<RegistrosApontamento>
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgBottom,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: _kBgBottom,
        foregroundColor: _kTextPrimary,
        iconTheme: const IconThemeData(color: _kTextPrimary),
        title: const Text(
          'Lista de Apontamentos',
          style: TextStyle(color: _kTextPrimary, fontWeight: FontWeight.bold),
        ),
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
          indicatorColor: _kAccentColor,
          labelColor: _kTextPrimary,
          unselectedLabelColor: _kTextSecondary,
          tabs: const [
            Tab(text: 'Tipo A', icon: Icon(Icons.analytics_outlined)),
            Tab(text: 'Tipo B', icon: Icon(Icons.fact_check_outlined)),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_kBgTop, _kSurface2, _kBgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: TabBarView(
          controller: _tabController,
          children: const [
            _ListaDadosGeral(endpoint: "tipoA"),
            _ListaDadosGeral(endpoint: "tipoB"),
          ],
        ),
      ),
    );
  }
}

class _ListaDadosGeral extends StatelessWidget {
  final String endpoint;
  const _ListaDadosGeral({required this.endpoint});

  // --- MAPEAR TURNOS ---
  String _mapearTurno(dynamic turnoRaw) {
    if (turnoRaw == null) return "N/A";
    String t = turnoRaw.toString();
    if (t == "8") return "A";
    if (t == "9") return "B";
    if (t == "10") return "C";
    return t;
  }

  // --- FORMATAR DATA PARA O PADRÃO BRASILEIRO ---
  String _formatarDataBR(dynamic dateRaw) {
    if (dateRaw == null) return "N/A";
    String d = dateRaw.toString();
    try {
      DateTime dt = DateTime.parse(d);
      return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      if (d.length >= 10 && d.contains('-')) {
        var parts = d.substring(0, 10).split('-');
        if (parts.length == 3) return "${parts[2]}/${parts[1]}/${parts[0]}";
      }
      return d;
    }
  }

  // --- BUSCAR DADOS DA API E CRUZAR COM O SQLITE ---
  Future<List<dynamic>> _buscarDados() async {
    try {
      final response = await http.get(
        Uri.parse(
          "$_kBaseUrlFlask/apontamento/$endpoint",
        ), // Usando a URL correta do Flask
      );

      if (response.statusCode == 200) {
        List<dynamic> dados = jsonDecode(response.body);

        // Associa o código ao Nome do Artigo consultando o banco local
        for (var item in dados) {
          String objId = item['Artigo']?.toString() ?? "";
          String detId = (item['Detalhe'] ?? item['detalhe'])?.toString() ?? "";

          if (objId.isNotEmpty) {
            final produto = await DatabaseService.buscarProduto(objId, detId);
            if (produto != null && produto['objeto'] != null) {
              item['NomeArtigo'] = produto['objeto']; // Pegou o nome do Banco!
            } else {
              item['NomeArtigo'] = "Desconhecido ($objId)";
            }
          } else {
            item['NomeArtigo'] = "Sem Código";
          }
        }

        return dados.reversed.toList();
      } else {
        throw Exception("Status: ${response.statusCode}");
      }
    } catch (e) {
      throw Exception("Erro ao conectar: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _buscarDados(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _kAccentColor),
          );
        }
        if (snapshot.hasError) {
          return _buildErrorPlaceholder(snapshot.error.toString());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text(
              "Nenhum registro encontrado.",
              style: TextStyle(color: _kTextSecondary),
            ),
          );
        }

        final dados = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: dados.length,
          itemBuilder: (context, index) {
            final item = dados[index];
            return endpoint == "tipoA"
                ? _buildCardProducao(item)
                : _buildCardQualidade(item);
          },
        );
      },
    );
  }

  Widget _buildCardProducao(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderSoft),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item['NomeArtigo'] ?? 'N/A', // O Nome associado!
                    style: const TextStyle(
                      color: _kTextPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildBadge(
                  "Turno ${_mapearTurno(item['Turno'] ?? item['turno'])}",
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Cód: ${item['Artigo']} | Lote: ${item['Detalhe'] ?? '-'}",
              style: const TextStyle(color: _kAccentColor, fontSize: 12),
            ),
            const Divider(height: 24, color: _kBorderSoft),
            _buildDataPoint(
              Icons.person_outline,
              "Operador",
              item['Operador']?.toString(),
            ),
            _buildDataPoint(
              Icons.precision_manufacturing_outlined,
              "Máquina",
              item['Maq']?.toString(),
            ),
            _buildDataPoint(
              Icons.add_box_outlined,
              "Quantidade",
              item['Qtde']?.toString(),
              highlight: true,
            ),
            _buildDataPoint(
              Icons.calendar_today_outlined,
              "Data",
              _formatarDataBR(item['Data'] ?? item['data']),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardQualidade(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderSoft),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 160,
            decoration: const BoxDecoration(
              color: Colors.orangeAccent,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item['NomeArtigo'] ?? 'N/A', // O Nome associado!
                          style: const TextStyle(
                            color: _kTextPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildBadge(
                        "Turno ${_mapearTurno(item['turno'] ?? item['Turno'])}",
                        color: Colors.orangeAccent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Cód: ${item['Artigo']} | Lote: ${item['Detalhe'] ?? '-'}",
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                    ),
                  ),
                  const Divider(height: 24, color: _kBorderSoft),
                  _buildDataPoint(
                    Icons.warning_amber_rounded,
                    "Defeito",
                    item['Defeito']?.toString(),
                  ),
                  _buildDataPoint(
                    Icons.remove_circle_outline,
                    "Qtde Defeituosa",
                    item['Qtde']?.toString(),
                    highlight: true,
                    highlightColor: Colors.orangeAccent,
                  ),
                  _buildDataPoint(
                    Icons.calendar_today_outlined,
                    "Registro",
                    _formatarDataBR(item['data'] ?? item['Data']),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataPoint(
    IconData icon,
    String label,
    String? value, {
    bool highlight = false,
    Color highlightColor = _kAccentColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _kTextSecondary),
          const SizedBox(width: 8),
          Text(
            "$label: ",
            style: const TextStyle(
              color: _kTextSecondary,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? 'N/A',
              style: TextStyle(
                color: highlight ? highlightColor : _kTextPrimary,
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, {Color color = _kPrimaryColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        border: Border.all(color: color.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            const Text(
              "Erro de conexão",
              style: TextStyle(
                color: _kTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _kTextSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
