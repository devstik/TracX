import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_helper;
import 'ApontamentoProdutividadeScreen.dart' as apontamento;

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

  static Future<Map<String, dynamic>?> buscarProdutoNormalizado(
    String objetoID,
    String detalheID,
  ) async {
    final db = await database;
    final objetoNormalizado = _normalizarCodigoConsulta(objetoID);
    final detalheNormalizado = _normalizarCodigoConsulta(detalheID);
    final results = await db.rawQuery(
      '''
      SELECT *
      FROM $_tableProdutos
      WHERE (objetoID = ? OR ltrim(objetoID, '0') = ?)
        AND (detalheID = ? OR ltrim(detalheID, '0') = ?)
      LIMIT 1
      ''',
      [objetoID, objetoNormalizado, detalheID, detalheNormalizado],
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

  static Future<List<Map<String, dynamic>>> buscarPorObjetoIDNormalizado(
    String objetoID,
  ) async {
    final db = await database;
    final objetoNormalizado = _normalizarCodigoConsulta(objetoID);
    return await db.rawQuery(
      '''
      SELECT *
      FROM $_tableProdutos
      WHERE objetoID = ? OR ltrim(objetoID, '0') = ?
      ''',
      [objetoID, objetoNormalizado],
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

class _EditorRegistroApontamentoSheet extends StatefulWidget {
  final String endpoint;
  final Map<String, dynamic> item;
  final int registroId;

  const _EditorRegistroApontamentoSheet({
    required this.endpoint,
    required this.item,
    required this.registroId,
  });

  @override
  State<_EditorRegistroApontamentoSheet> createState() =>
      _EditorRegistroApontamentoSheetState();
}

class _EditorRegistroApontamentoSheetState
    extends State<_EditorRegistroApontamentoSheet> {
  final _formKey = GlobalKey<FormState>();
  final _artigoController = TextEditingController();
  final _artigoCodigoController = TextEditingController();
  final _detalheController = TextEditingController();
  final _detalheCodigoController = TextEditingController();
  final _qtdeController = TextEditingController();
  final _defeitoController = TextEditingController();

  List<apontamento.UsuarioOperador> _operadores = [];
  List<apontamento.Setor> _setores = [];
  List<apontamento.Maquina> _maquinas = [];

  String? _operadorSelecionado;
  apontamento.Setor? _setorSelecionado;
  apontamento.Maquina? _maquinaSelecionada;
  int _turnoSelecionado = 8;

  bool _carregando = true;
  bool _salvando = false;

  bool get _isTipoA => widget.endpoint == 'tipoA';
  bool get _isRevisao =>
      (_setorSelecionado?.nome.toUpperCase().trim().contains('REVISAO') ??
          false);

  @override
  void initState() {
    super.initState();
    _preencherCamposIniciais();
    _carregarOpcoes();
  }

  @override
  void dispose() {
    _artigoController.dispose();
    _artigoCodigoController.dispose();
    _detalheController.dispose();
    _detalheCodigoController.dispose();
    _qtdeController.dispose();
    _defeitoController.dispose();
    super.dispose();
  }

  String _primeiroTextoPreenchido(List<dynamic> valores) {
    for (final valor in valores) {
      final texto = (valor ?? '').toString().trim();
      if (texto.isNotEmpty && texto.toLowerCase() != 'null') {
        return texto;
      }
    }
    return '';
  }

  void _preencherCamposIniciais() {
    final artigoCodigo = _normalizarCodigo(
      widget.item['Artigo'] ?? widget.item['artigo'],
    );
    final detalheCodigo = _normalizarCodigo(
      widget.item['Detalhe'] ?? widget.item['detalhe'],
    );

    _artigoController.text = _primeiroTextoPreenchido([
      widget.item['NomeArtigo'],
      widget.item['nomeArtigo'],
      widget.item['NmObj'],
      artigoCodigo,
    ]);
    _artigoCodigoController.text = artigoCodigo;
    _detalheController.text = _primeiroTextoPreenchido([
      widget.item['DetalheNome'],
      widget.item['detalheNome'],
      widget.item['NmLot'],
      detalheCodigo,
    ]);
    _detalheCodigoController.text = detalheCodigo;
    _qtdeController.text = (widget.item['Qtde'] ?? '').toString().trim();
    _defeitoController.text = (widget.item['Defeito'] ?? '').toString().trim();
    _operadorSelecionado = (widget.item['Operador'] ?? '').toString().trim();
    _turnoSelecionado = _turnoParaValor(
      widget.item['Turno'] ?? widget.item['turno'],
    );
  }

  Future<void> _carregarOpcoes() async {
    try {
      final results = await Future.wait([
        apontamento.UsuarioOperadorService.buscarUsuarios(),
        apontamento.SetorMaquinaService.buscarSetores(),
      ]);

      final operadores = results[0] as List<apontamento.UsuarioOperador>;
      final setores = results[1] as List<apontamento.Setor>;
      final setorCodigo = _toInt(widget.item['Setor'] ?? widget.item['setor']);

      apontamento.Setor? setorSelecionado;
      for (final setor in setores) {
        if (setor.codigo == setorCodigo) {
          setorSelecionado = setor;
          break;
        }
      }

      List<apontamento.Maquina> maquinas = [];
      apontamento.Maquina? maquinaSelecionada;

      if (_isTipoA && setorSelecionado != null && !_nomeSetorRevisao(setorSelecionado)) {
        maquinas = await apontamento.SetorMaquinaService.buscarMaquinas(
          setorSelecionado.codigo,
        );
        final maquinaCodigo = _toInt(widget.item['Maq']);
        for (final maquina in maquinas) {
          if (maquina.codigo == maquinaCodigo) {
            maquinaSelecionada = maquina;
            break;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _operadores = operadores;
        _setores = setores;
        _setorSelecionado = setorSelecionado;
        _maquinas = maquinas;
        _maquinaSelecionada = maquinaSelecionada;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao carregar dados para edição.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool _nomeSetorRevisao(apontamento.Setor setor) {
    return setor.nome.toUpperCase().trim().contains('REVISAO');
  }

  int _turnoParaValor(dynamic raw) {
    final texto = (raw ?? '').toString().trim().toUpperCase();
    if (texto == 'A' || texto == '8') return 8;
    if (texto == 'B' || texto == '9') return 9;
    if (texto == 'C' || texto == '10') return 10;
    return int.tryParse(texto) ?? 8;
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  String _normalizarCodigo(dynamic raw) {
    final valor = (raw ?? '').toString().trim();
    if (valor.isEmpty) return '';
    final n = num.tryParse(valor);
    if (n == null) return valor;
    if (n == n.toInt()) return n.toInt().toString();
    return valor;
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _kTextSecondary),
      prefixIcon: Icon(icon, color: _kAccentColor),
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
    );
  }

  Future<void> _trocarSetor(apontamento.Setor? setor) async {
    setState(() {
      _setorSelecionado = setor;
      _maquinaSelecionada = null;
      _maquinas = [];
    });

    if (!_isTipoA || setor == null || _nomeSetorRevisao(setor)) return;

    final maquinas = await apontamento.SetorMaquinaService.buscarMaquinas(
      setor.codigo,
    );
    if (!mounted) return;
    setState(() {
      _maquinas = maquinas;
    });
  }

  Map<String, dynamic> _montarPayload() {
    final payload = <String, dynamic>{
      'Turno': _turnoSelecionado,
      'Operador': _operadorSelecionado,
      'Setor': _setorSelecionado?.codigo,
      'Artigo': _artigoCodigoController.text.trim(),
      'Detalhe': _detalheCodigoController.text.trim(),
      'Qtde': int.tryParse(_qtdeController.text.trim()),
    };

    if (_isTipoA && !_isRevisao) {
      payload['Maq'] = _maquinaSelecionada?.codigo;
    }

    if (!_isTipoA) {
      payload['Defeito'] = _defeitoController.text.trim();
    }

    payload.removeWhere(
      (key, value) => value == null || (value is String && value.trim().isEmpty),
    );
    return payload;
  }

  String _mensagemErro(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'] ?? decoded['message'];
        if (error != null && error.toString().trim().isNotEmpty) {
          return error.toString().trim();
        }
      }
    } catch (_) {
      // Mantem fallback abaixo.
    }
    return 'Erro ao atualizar registro (${response.statusCode}).';
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    if (!_formKey.currentState!.validate()) return;

    final payload = _montarPayload();
    if (payload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum dado válido para atualizar.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final response = await http.patch(
        Uri.parse(
          "$_kBaseUrlFlask/apontamento/${widget.endpoint}/${widget.registroId}",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registro atualizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensagemErro(response)),
          backgroundColor: Colors.red,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erro ao atualizar registro.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _salvando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.92),
          decoration: const BoxDecoration(
            color: _kBgBottom,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: _carregando
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: _kAccentColor),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Editar registro',
                                    style: TextStyle(
                                      color: _kTextPrimary,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'ID ${widget.registroId} • ${_isTipoA ? 'Tipo A' : 'Tipo B'}',
                                    style: const TextStyle(
                                      color: _kTextSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _salvando
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.close,
                                color: _kTextSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        DropdownButtonFormField<int>(
                          initialValue: _turnoSelecionado,
                          dropdownColor: _kSurface,
                          style: const TextStyle(color: _kTextPrimary),
                          decoration: _inputDecoration(
                            'Turno',
                            Icons.schedule_outlined,
                          ),
                          items: const [
                            DropdownMenuItem(value: 8, child: Text('Turno A')),
                            DropdownMenuItem(value: 9, child: Text('Turno B')),
                            DropdownMenuItem(value: 10, child: Text('Turno C')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _turnoSelecionado = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _operadores.any(
                                (op) => op.cdUser == _operadorSelecionado,
                              )
                              ? _operadorSelecionado
                              : null,
                          dropdownColor: _kSurface,
                          style: const TextStyle(color: _kTextPrimary),
                          decoration: _inputDecoration(
                            'Operador',
                            Icons.person_outline,
                          ),
                          items: _operadores
                              .map(
                                (op) => DropdownMenuItem<String>(
                                  value: op.cdUser,
                                  child: Text('${op.nmUser} (${op.cdUser})'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _operadorSelecionado = value),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Selecione o operador';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<apontamento.Setor>(
                          initialValue: _setorSelecionado,
                          dropdownColor: _kSurface,
                          style: const TextStyle(color: _kTextPrimary),
                          decoration: _inputDecoration(
                            'Setor',
                            Icons.apartment_outlined,
                          ),
                          items: _setores
                              .map(
                                (setor) => DropdownMenuItem<apontamento.Setor>(
                                  value: setor,
                                  child: Text(setor.nome),
                                ),
                              )
                              .toList(),
                          onChanged: _salvando ? null : _trocarSetor,
                          validator: (value) {
                            if (value == null) return 'Selecione o setor';
                            return null;
                          },
                        ),
                        if (_isTipoA && !_isRevisao) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<apontamento.Maquina>(
                            initialValue: _maquinaSelecionada,
                            dropdownColor: _kSurface,
                            style: const TextStyle(color: _kTextPrimary),
                            decoration: _inputDecoration(
                              'Máquina',
                              Icons.precision_manufacturing_outlined,
                            ),
                            items: _maquinas
                                .map(
                                  (maq) => DropdownMenuItem<apontamento.Maquina>(
                                    value: maq,
                                    child: Text(maq.nome),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _maquinaSelecionada = value),
                            validator: (value) {
                              if (_isTipoA && !_isRevisao && value == null) {
                                return 'Selecione a máquina';
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _artigoController,
                          style: const TextStyle(color: _kTextPrimary),
                          readOnly: true,
                          decoration: _inputDecoration(
                            'Artigo',
                            Icons.inventory_2_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _artigoCodigoController,
                          style: const TextStyle(color: _kTextPrimary),
                          decoration: _inputDecoration(
                            'Código do Artigo',
                            Icons.tag_outlined,
                          ).copyWith(
                            helperText: 'Para alterar, informe o código do artigo.',
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Informe o código do artigo';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _detalheController,
                          style: const TextStyle(color: _kTextPrimary),
                          readOnly: true,
                          decoration: _inputDecoration(
                            'Lote',
                            Icons.qr_code_2_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _detalheCodigoController,
                          style: const TextStyle(color: _kTextPrimary),
                          decoration: _inputDecoration(
                            'Código do Lote',
                            Icons.tag_outlined,
                          ).copyWith(
                            helperText: 'Para alterar, informe o código do lote.',
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Informe o código do lote';
                            }
                            return null;
                          },
                        ),
                        if (!_isTipoA) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _defeitoController,
                            style: const TextStyle(color: _kTextPrimary),
                            decoration: _inputDecoration(
                              'Defeito',
                              Icons.warning_amber_rounded,
                            ),
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty) {
                                return 'Informe o defeito';
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _qtdeController,
                          style: const TextStyle(color: _kTextPrimary),
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration(
                            'Quantidade',
                            Icons.pin_outlined,
                          ),
                          validator: (value) {
                            final numero = int.tryParse((value ?? '').trim());
                            if (numero == null || numero <= 0) {
                              return 'Informe uma quantidade válida';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _salvando ? null : _salvar,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kPrimaryColor,
                              disabledBackgroundColor: Colors.grey,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _salvando
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'SALVAR ALTERAÇÕES',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class ArtigosApiAuthService {
  static const String _tokenKey = 'jwt_token';
  static const String _expiryKey = 'jwt_expiry';
  static const String _loginUrl =
      'https://mediumpurple-loris-159660.hostingersite.com/auth/login';

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
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': 'anderson', 'password': '142046'}),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final token = json['accessToken']?.toString();
        if (token == null || token.isEmpty) {
          debugPrint('[REG_ARTIGO][AUTH] Login JWT sem accessToken');
          return null;
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, token);
        await prefs.setString(
          _expiryKey,
          DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
        );
        debugPrint(
          '[REG_ARTIGO][AUTH] Token JWT renovado com sucesso tamanho=${token.length}',
        );
        return token;
      }

      debugPrint(
        '[REG_ARTIGO][AUTH] Erro login JWT ${response.statusCode}: ${response.body}',
      );
    } catch (e) {
      debugPrint('[REG_ARTIGO][AUTH] Erro login JWT: $e');
    }
    return null;
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

class _ListaDadosGeral extends StatefulWidget {
  final String endpoint;
  const _ListaDadosGeral({required this.endpoint});

  @override
  State<_ListaDadosGeral> createState() => _ListaDadosGeralState();
}

class _ListaDadosGeralState extends State<_ListaDadosGeral> {
  static const int _kPageSize = 20;

  final TextEditingController _buscaController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Map<String, Map<String, String>?> _cacheArtigosApi = {};
  final Set<String> _artigosEmEnriquecimento = {};

  String _termoBusca = '';
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _catalogoInicializado = false;
  bool _enriquecimentoCompletoIniciado = false;
  String? _erro;

  List<Map<String, dynamic>> _todosDados = [];
  List<Map<String, dynamic>> _dadosVisiveis = [];
  Map<String, String> _mapaOperadores = {};
  Map<String, String> _mapaMaquinas = {};
  int _indiceCarregado = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _carregarDadosIniciais();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _recarregarDados() {
    setState(() {
      _erro = null;
      _isLoading = true;
      _isLoadingMore = false;
      _todosDados = [];
      _dadosVisiveis = [];
      _indiceCarregado = 0;
      _mapaOperadores = {};
      _mapaMaquinas = {};
      _artigosEmEnriquecimento.clear();
      _enriquecimentoCompletoIniciado = false;
    });
    _carregarDadosIniciais();
  }

  void _onScroll() {
    if (_termoBusca.trim().isNotEmpty) return;
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 320) {
      return;
    }
    _carregarProximaPagina();
  }

  int? _obterRegistroId(Map<String, dynamic> item) {
    final raw = item['Id'] ?? item['id'];
    if (raw == null) return null;
    if (raw is int) return raw;
    return int.tryParse(raw.toString());
  }

  void _mostrarSnack(String msg, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _abrirEditorRegistro(Map<String, dynamic> item) async {
    final registroId = _obterRegistroId(item);
    if (registroId == null) {
      _mostrarSnack('Registro sem ID para edição.', Colors.orange);
      return;
    }

    final alterado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditorRegistroApontamentoSheet(
        endpoint: widget.endpoint,
        item: Map<String, dynamic>.from(item),
        registroId: registroId,
      ),
    );

    if (alterado == true && mounted) {
      _recarregarDados();
    }
  }

  Future<void> _carregarDadosIniciais() async {
    _inicializarCatalogoEmSegundoPlano();

    try {
      final resultados = await Future.wait([
        _buscarMapaOperadores(),
        http.get(
          Uri.parse("$_kBaseUrlFlask/apontamento/${widget.endpoint}"),
        ),
      ]);

      final mapaOperadores = resultados[0] as Map<String, String>;
      final response = resultados[1] as http.Response;

      if (response.statusCode != 200) {
        throw Exception("Status: ${response.statusCode}");
      }

      final List<dynamic> dadosBrutos = jsonDecode(response.body);
      final setores = <String>{};
      final processados = <Map<String, dynamic>>[];

      for (final item in dadosBrutos) {
        final registro = Map<String, dynamic>.from(item as Map);
        final setor = _normalizarCodigo(registro['Setor'] ?? registro['setor']);
        final maq = _normalizarCodigo(registro['Maq']);
        final maq2 = _normalizarCodigo(registro['Maq2']);

        if (setor.isNotEmpty && maq.isNotEmpty && int.tryParse(maq) != null) {
          setores.add(setor);
        }
        if (widget.endpoint == 'tipoA' &&
            setor.isNotEmpty &&
            maq2.isNotEmpty &&
            maq2 != '0' &&
            int.tryParse(maq2) != null) {
          setores.add(setor);
        }
        processados.add(registro);
      }

      final dadosOrdenados = processados.reversed.toList();

      if (!mounted) return;
      setState(() {
        _mapaOperadores = mapaOperadores;
        _todosDados = dadosOrdenados;
        _dadosVisiveis = [];
        _indiceCarregado = 0;
        _erro = null;
        _isLoading = false;
      });

      await _carregarProximaPagina();
      _carregarMapaMaquinasEmSegundoPlano(setores);
      _enriquecerTodosOsItensEmSegundoPlano();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = "Erro ao conectar: $e";
        _isLoading = false;
      });
    }
  }

  void _inicializarCatalogoEmSegundoPlano() {
    if (_catalogoInicializado) return;
    _catalogoInicializado = true;
    _garantirCatalogoProdutos();
  }

  bool get _temMaisDados => _indiceCarregado < _todosDados.length;

  Future<void> _carregarProximaPagina() async {
    if (_isLoadingMore || !_temMaisDados || !mounted) return;

    setState(() => _isLoadingMore = true);

    final fim = math.min(_indiceCarregado + _kPageSize, _todosDados.length);
    final novosItens = _todosDados.sublist(_indiceCarregado, fim);
    for (final item in novosItens) {
      _aplicarCamposBasicos(item);
    }

    setState(() {
      _dadosVisiveis.addAll(novosItens);
      _indiceCarregado = fim;
      _isLoadingMore = false;
    });
  }

  void _aplicarCamposBasicos(
    Map<String, dynamic> item, {
    Map<String, String>? mapaOperadores,
  }) {
    final operadores = mapaOperadores ?? _mapaOperadores;
    final objId = _normalizarCodigo(item['Artigo'] ?? item['artigo']);
    final detId = _normalizarCodigo(item['Detalhe'] ?? item['detalhe']);
    final nomeDoRegistro = _extrairProdutoDoRegistro(item);

    if ((item['NomeArtigo'] ?? '').toString().trim().isEmpty) {
      if (nomeDoRegistro != null) {
        item['NomeArtigo'] = nomeDoRegistro['nome'];
        item['DetalheNome'] = nomeDoRegistro['detalhe'] ?? '';
      } else if (objId.isNotEmpty) {
        item['NomeArtigo'] = "Artigo $objId";
        item['DetalheNome'] = '';
      } else {
        item['NomeArtigo'] = "Sem CÃ³digo";
        item['DetalheNome'] = '';
      }
    }

    item['ArtigoLabel'] = objId.isEmpty ? '-' : objId;
    item['DetalheLabel'] = detId.isEmpty ? '-' : detId;
    item['OperadorLabel'] = _formatarOperador(item['Operador'], operadores);

    final setor = item['Setor'] ?? item['setor'];
    final maq1Label = _formatarMaquina(item['Maq'], setor, _mapaMaquinas);
    item['Maq1Label'] = maq1Label;

    final maq2Raw = _normalizarCodigo(item['Maq2']);
    if (widget.endpoint == 'tipoA' && maq2Raw.isNotEmpty && maq2Raw != '0') {
      final maq2Label = _formatarMaquina(item['Maq2'], setor, _mapaMaquinas);
      item['Maq2Label'] = maq2Label;
      item['MaqLabel'] = "Maq 1: $maq1Label | Maq 2: $maq2Label";
    } else {
      item['Maq2Label'] = null;
      item['MaqLabel'] = maq1Label;
    }
  }

  bool _nomeArtigoResolvido(dynamic raw) {
    final nome = (raw ?? '').toString().trim();
    if (nome.isEmpty) return false;
    if (nome == 'Sem CÃƒÂ³digo' || nome == 'Sem Código') return false;
    return !nome.startsWith('Artigo ');
  }

  Future<void> _enriquecerTodosOsItensEmSegundoPlano() async {
    if (_enriquecimentoCompletoIniciado) return;
    _enriquecimentoCompletoIniciado = true;

    final gruposPorChave = <String, List<Map<String, dynamic>>>{};
    for (final item in _todosDados) {
      final objId = _normalizarCodigo(item['Artigo'] ?? item['artigo']);
      if (objId.isEmpty) continue;

      final nomeAtual = (item['NomeArtigo'] ?? '').toString().trim();
      if (_nomeArtigoResolvido(nomeAtual)) continue;

      final detId = _normalizarCodigo(item['Detalhe'] ?? item['detalhe']);
      final chave = '$objId|$detId';
      gruposPorChave.putIfAbsent(chave, () => []).add(item);
    }

    for (final entry in gruposPorChave.entries) {
      if (!mounted) return;
      if (_artigosEmEnriquecimento.contains(entry.key)) continue;

      final referencia = entry.value.first;
      final objId = _normalizarCodigo(
        referencia['Artigo'] ?? referencia['artigo'],
      );
      final detId = _normalizarCodigo(
        referencia['Detalhe'] ?? referencia['detalhe'],
      );

      _artigosEmEnriquecimento.add(entry.key);
      final resultado = await _resolverProduto(referencia, objId, detId);
      _artigosEmEnriquecimento.remove(entry.key);

      if (!mounted || resultado == null) continue;

      setState(() {
        for (final item in entry.value) {
          item['NomeArtigo'] = resultado['nome'] ?? item['NomeArtigo'];
          item['DetalheNome'] = resultado['detalhe'] ?? item['DetalheNome'];
          _aplicarCamposBasicos(item);
        }
      });
    }
  }

  Future<void> _carregarMapaMaquinasEmSegundoPlano(Set<String> setores) async {
    final mapa = await _buscarMapaMaquinas(setores);
    if (!mounted || mapa.isEmpty) return;

    setState(() {
      _mapaMaquinas = mapa;
      for (final item in _todosDados) {
        _aplicarCamposBasicos(item);
      }
    });
  }

  Future<Map<String, String>?> _resolverProduto(
    Map<String, dynamic> item,
    String objId,
    String detId,
  ) async {
    Map<String, dynamic>? produto = await _buscarProdutoLocal(objId, detId);
    if (produto != null &&
        (produto['objeto']?.toString().trim().isNotEmpty ?? false)) {
      return {
        'nome': produto['objeto'].toString().trim(),
        'detalhe': (produto['detalhe'] ?? '').toString().trim(),
      };
    }

    final nomeDoRegistro = _extrairProdutoDoRegistro(item);
    if (nomeDoRegistro != null) return nomeDoRegistro;

    return await _buscarProdutoNaApi(objId, detId);
  }

  String _normalizarTextoBusca(dynamic valor) {
    const substituicoes = {
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'õ': 'o',
      'ô': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
    };

    final texto = (valor ?? '').toString().trim().toLowerCase();
    if (texto.isEmpty) return '';

    final buffer = StringBuffer();
    for (final char in texto.split('')) {
      buffer.write(substituicoes[char] ?? char);
    }
    return buffer.toString();
  }

  List<String> _tokenizarBusca(String termo) {
    return _normalizarTextoBusca(termo)
        .split(RegExp(r'\s+'))
        .map((parte) => parte.trim())
        .where((parte) => parte.isNotEmpty)
        .toList();
  }

  String _textoBuscaRegistro(Map<String, dynamic> registro) {
    return _normalizarTextoBusca([
      _tituloArtigo(registro),
      registro['NomeArtigo'],
      registro['DetalheNome'],
      registro['ArtigoLabel'],
      registro['DetalheLabel'],
      registro['Artigo'],
      registro['artigo'],
      registro['Detalhe'],
      registro['detalhe'],
      registro['OperadorLabel'],
      registro['Operador'],
      registro['MaqLabel'],
      registro['Maq1Label'],
      registro['Maq2Label'],
      registro['Setor'],
      registro['setor'],
      registro['Defeito'],
      registro['Qtde'],
      _mapearTurno(registro['Turno'] ?? registro['turno']),
      _formatarDataBR(registro['Data'] ?? registro['data']),
    ].join(' '));
  }

  List<dynamic> _filtrarDados(List<dynamic> dados) {
    final tokens = _tokenizarBusca(_termoBusca);
    if (tokens.isEmpty) return dados;

    return dados.where((item) {
      final registro = Map<String, dynamic>.from(item as Map);
      final textoBusca = _textoBuscaRegistro(registro);
      return tokens.every(textoBusca.contains);
    }).toList();
  }

  String _primeiroTextoPreenchido(
    Map<String, dynamic> item,
    List<String> chaves,
  ) {
    for (final chave in chaves) {
      final valor = (item[chave] ?? '').toString().trim();
      if (valor.isNotEmpty &&
          valor.toLowerCase() != 'null' &&
          !valor.toLowerCase().startsWith('desconhecido')) {
        return valor;
      }
    }
    return '';
  }

  Map<String, String>? _extrairProdutoDoRegistro(Map<String, dynamic> item) {
    var nome = _primeiroTextoPreenchido(item, [
      'NomeArtigo',
      'nomeArtigo',
      'NmObj',
      'Descricao',
      'descricao',
      'objeto',
      'Produto',
      'produto',
    ]);
    if (!_nomeArtigoResolvido(nome)) {
      nome = _primeiroTextoPreenchido(item, [
        'NmObj',
        'Descricao',
        'descricao',
        'objeto',
        'Produto',
        'produto',
      ]);
    }
    if (nome.isEmpty || !_nomeArtigoResolvido(nome)) return null;

    return {
      'nome': nome,
      'detalhe': _primeiroTextoPreenchido(item, [
        'DetalheNome',
        'detalheNome',
        'NmLot',
        'detalhe',
        'Detalhe',
      ]),
    };
  }

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

  Future<Map<String, String>> _buscarMapaOperadores() async {
    try {
      final response = await http.get(
        Uri.parse("$_kBaseUrlFlask/consultar/usuarios"),
        headers: {"Content-Type": "application/json"},
      );
      if (response.statusCode != 200) return {};

      final List<dynamic> data = jsonDecode(response.body);
      final mapa = <String, String>{};

      for (final item in data) {
        final registro = Map<String, dynamic>.from(item as Map);
        final codigo = (registro['CdUser'] ?? '').toString().trim();
        final nome = (registro['NmUser'] ?? '').toString().trim();
        if (codigo.isNotEmpty && nome.isNotEmpty) {
          mapa[codigo] = nome;
        }
      }

      return mapa;
    } catch (_) {
      return {};
    }
  }

  String _formatarOperador(
    dynamic operadorRaw,
    Map<String, String> mapaOperadores,
  ) {
    final codigo = (operadorRaw ?? '').toString().trim();
    if (codigo.isEmpty) return "N/A";

    final nome = mapaOperadores[codigo];
    if (nome == null || nome.isEmpty) return "ID $codigo";
    return "$nome (ID $codigo)";
  }

  String _normalizarCodigo(dynamic raw) {
    final valor = (raw ?? '').toString().trim();
    if (valor.isEmpty) return '';
    final n = num.tryParse(valor);
    if (n == null) return valor;
    if (n == n.toInt()) return n.toInt().toString();
    return valor;
  }

  String _tituloArtigo(Map<String, dynamic> item) {
    final nome = (item['NomeArtigo'] ?? 'N/A').toString().trim();
    final detalheNome = (item['DetalheNome'] ?? '').toString().trim();
    final isPreto = nome.toUpperCase().contains('PRETO');
    if (isPreto && detalheNome.isNotEmpty) {
      return '$nome - $detalheNome';
    }
    return nome;
  }

  Future<void> _garantirCatalogoProdutos() async {
    try {
      final total = await DatabaseService.contarProdutos();
      final precisaSincronizar = await DatabaseService.precisaSincronizar();
      if (total == 0 || precisaSincronizar) {
        await DatabaseService.sincronizarTodosProdutos();
      }
    } catch (_) {
      // Mantem fluxo da tela mesmo que a sincronizacao falhe.
    }
  }

  Future<Map<String, dynamic>?> _buscarProdutoLocal(
    String objId,
    String detId,
  ) async {
    debugPrint('[REG_ARTIGO][LOCAL] Buscando objId=$objId detId=$detId');
    Map<String, dynamic>? produto;
    if (detId.isNotEmpty) {
      produto = await DatabaseService.buscarProduto(objId, detId);
      produto ??= await DatabaseService.buscarProdutoNormalizado(objId, detId);
      if (produto != null) {
        debugPrint(
          '[REG_ARTIGO][LOCAL] Encontrado por objeto+detalhe: ${produto['objeto']}',
        );
      }
    }

    if (produto != null) return produto;

    final produtosMesmoObjeto = await DatabaseService.buscarPorObjetoID(objId);
    final produtosMesmoObjetoNormalizado = produtosMesmoObjeto.isNotEmpty
        ? produtosMesmoObjeto
        : await DatabaseService.buscarPorObjetoIDNormalizado(objId);
    if (produtosMesmoObjetoNormalizado.isEmpty) {
      debugPrint('[REG_ARTIGO][LOCAL] Nao encontrado objId=$objId detId=$detId');
      return null;
    }

    if (detId.isNotEmpty) {
      final detalheNormalizado = detId.replaceFirst(RegExp(r'^0+'), '');
      for (final p in produtosMesmoObjetoNormalizado) {
        final d = (p['detalheID'] ?? '').toString().trim();
        final dNorm = d.replaceFirst(RegExp(r'^0+'), '');
        if (d == detId || dNorm == detalheNormalizado) {
          debugPrint(
            '[REG_ARTIGO][LOCAL] Encontrado por objeto com detalhe normalizado: ${p['objeto']}',
          );
          return p;
        }
      }
    }

    debugPrint(
      '[REG_ARTIGO][LOCAL] Encontrado por objeto sem detalhe exato: ${produtosMesmoObjetoNormalizado.first['objeto']}',
    );
    return produtosMesmoObjetoNormalizado.first;
  }

  Future<Map<String, String>?> _buscarProdutoNaApi(
    String objId,
    String detId,
  ) async {
    final chaveCache = '$objId|$detId';
    final resultadoEmCache = _cacheArtigosApi[chaveCache];
    if (resultadoEmCache != null) {
      debugPrint(
        '[REG_ARTIGO][API] Cache hit objId=$objId detId=$detId resultado=$resultadoEmCache',
      );
      return resultadoEmCache;
    }

    try {
      debugPrint('[REG_ARTIGO][API] Consultando objId=$objId detId=$detId');
      final token = await ArtigosApiAuthService.obterToken();
      final uri = Uri.parse(
        "https://mediumpurple-loris-159660.hostingersite.com/api/artigos?CdObj=$objId",
      );
      http.Response response;
      var usandoAuth = token != null && token.isNotEmpty;

      if (usandoAuth) {
        debugPrint(
          '[REG_ARTIGO][API] Tentando com Authorization objId=$objId tokenLength=${token.length}',
        );
        response = await http.get(
          uri,
          headers: {'Authorization': 'Bearer $token'},
        );
      } else {
        debugPrint(
          '[REG_ARTIGO][API] Token ausente, tentando sem Authorization objId=$objId',
        );
        response = await http.get(uri);
      }

      if (response.statusCode != 200 && usandoAuth) {
        debugPrint(
          '[REG_ARTIGO][API] Falha com Authorization objId=$objId detId=$detId status=${response.statusCode}. Tentando sem Authorization.',
        );
        final respostaSemAuth = await http.get(uri);
        if (respostaSemAuth.statusCode == 200) {
          response = respostaSemAuth;
          usandoAuth = false;
          debugPrint(
            '[REG_ARTIGO][API] Sucesso sem Authorization objId=$objId detId=$detId',
          );
        } else {
          debugPrint(
            '[REG_ARTIGO][API] Falha sem Authorization objId=$objId detId=$detId status=${respostaSemAuth.statusCode} body=${respostaSemAuth.body}',
          );
        }
      }

      if (response.statusCode != 200) {
        debugPrint(
          '[REG_ARTIGO][API] HTTP ${response.statusCode} objId=$objId detId=$detId usandoAuth=$usandoAuth body=${response.body}',
        );
        return null;
      }

      final dynamic decoded =
          response.body.isNotEmpty ? jsonDecode(response.body) : null;
      final List<dynamic> data = decoded is Map<String, dynamic>
          ? (decoded['data'] as List<dynamic>? ?? const [])
          : (decoded is List ? decoded : const []);

      debugPrint(
        '[REG_ARTIGO][API] Retorno objId=$objId detId=$detId quantidade=${data.length}',
      );

      if (data.isEmpty) {
        debugPrint('[REG_ARTIGO][API] Nenhum artigo retornado para objId=$objId');
        return null;
      }

      final detalheNormalizado = detId.replaceFirst(RegExp(r'^0+'), '');
      final detalheNumero = int.tryParse(detId);
      Map<String, dynamic>? artigoSelecionado;
      Map<String, dynamic>? primeiroRegistro;

      for (final item in data) {
        if (item is! Map) continue;
        final registro = Map<String, dynamic>.from(item);
        primeiroRegistro ??= registro;

        final lotes = registro['CdLot'];
        if (detalheNumero != null && lotes is List && lotes.contains(detalheNumero)) {
          artigoSelecionado = registro;
          debugPrint(
            '[REG_ARTIGO][API] Match por detalhe numerico objId=$objId detId=$detId nome=${registro['NmObj']}',
          );
          break;
        }

        if (lotes is List) {
          final encontrouPorTexto = lotes.any((lote) {
            final loteNormalizado = lote
                .toString()
                .trim()
                .replaceFirst(RegExp(r'^0+'), '');
            return loteNormalizado == detalheNormalizado;
          });
          if (encontrouPorTexto) {
            artigoSelecionado = registro;
            debugPrint(
              '[REG_ARTIGO][API] Match por detalhe texto objId=$objId detId=$detId nome=${registro['NmObj']}',
            );
            break;
          }
        }
      }

      artigoSelecionado ??= primeiroRegistro;
      if (artigoSelecionado == null) {
        debugPrint(
          '[REG_ARTIGO][API] Nenhum registro selecionado para objId=$objId detId=$detId',
        );
        return null;
      }

      final resultado = {
        'nome': _primeiroTextoPreenchido(artigoSelecionado, [
          'NmObj',
          'NomeArtigo',
          'objeto',
        ]),
        'detalhe': _primeiroTextoPreenchido(artigoSelecionado, [
          'NmLot',
          'DetalheNome',
          'detalhe',
        ]),
      };

      if (resultado['nome']!.isEmpty) {
        debugPrint(
          '[REG_ARTIGO][API] Registro sem nome objId=$objId detId=$detId registro=$artigoSelecionado',
        );
        return null;
      }

      debugPrint(
        '[REG_ARTIGO][API] Nome resolvido objId=$objId detId=$detId nome=${resultado['nome']} detalhe=${resultado['detalhe']}',
      );
      _cacheArtigosApi[chaveCache] = resultado;
      return resultado;
    } catch (e) {
      debugPrint(
        '[REG_ARTIGO][API] Erro ao consultar objId=$objId detId=$detId erro=$e',
      );
      return null;
    }
  }

  String _chaveMaquina(String setor, String codigo) => '$setor|$codigo';

  Future<Map<String, String>> _buscarMapaMaquinas(Set<String> setores) async {
    final mapa = <String, String>{};
    if (setores.isEmpty) return mapa;

    for (final setor in setores) {
      try {
        final response = await http.get(
          Uri.parse("$_kBaseUrlFlask/consulta/maquinas?setor=$setor"),
          headers: {"Content-Type": "application/json"},
        );
        if (response.statusCode != 200) continue;

        final List<dynamic> data = jsonDecode(response.body);
        for (final item in data) {
          final registro = Map<String, dynamic>.from(item as Map);
          final codigo = (registro['Codigo'] ?? '').toString().trim();
          final nome = (registro['Nome'] ?? '').toString().trim();
          if (codigo.isNotEmpty && nome.isNotEmpty) {
            mapa[_chaveMaquina(setor, codigo)] = nome;
          }
        }
      } catch (_) {
        // Ignora falha de setor específico e continua o restante.
      }
    }

    return mapa;
  }

  String _formatarMaquina(
    dynamic maquinaRaw,
    dynamic setorRaw,
    Map<String, String> mapaMaquinas,
  ) {
    final valor = _normalizarCodigo(maquinaRaw);
    if (valor.isEmpty) return "N/A";
    if (valor == "0") return "N/A";

    // Se já veio com nome (ex: "MAQ X (ID 12)"), mantém como está.
    if (int.tryParse(valor) == null) return valor;

    final codigo = valor;
    final setor = _normalizarCodigo(setorRaw);
    if (setor.isNotEmpty) {
      final nome = mapaMaquinas[_chaveMaquina(setor, codigo)];
      if (nome != null && nome.isNotEmpty) return "$nome (ID $codigo)";
    }
    return "ID $codigo";
  }

  // --- BUSCAR DADOS DA API E CRUZAR COM O SQLITE ---
  Future<List<dynamic>> _buscarDados() async {
    try {
      await _garantirCatalogoProdutos();

      final mapaOperadores = await _buscarMapaOperadores();
      final response = await http.get(
        Uri.parse(
          "$_kBaseUrlFlask/apontamento/${widget.endpoint}",
        ), // Usando a URL correta do Flask
      );

      if (response.statusCode == 200) {
        List<dynamic> dados = jsonDecode(response.body);
        final setores = <String>{};

        for (final item in dados) {
          final setor = _normalizarCodigo(item['Setor'] ?? item['setor']);
          final maq = _normalizarCodigo(item['Maq']);
          final maq2 = _normalizarCodigo(item['Maq2']);
          if (setor.isNotEmpty && maq.isNotEmpty && int.tryParse(maq) != null) {
            setores.add(setor);
          }
          if (widget.endpoint == 'tipoA' &&
              setor.isNotEmpty &&
              maq2.isNotEmpty &&
              maq2 != '0' &&
              int.tryParse(maq2) != null) {
            setores.add(setor);
          }
        }

        final mapaMaquinas = await _buscarMapaMaquinas(setores);

        // Associa o codigo ao nome do artigo consultando o SQLite local.
        bool sincronizacaoReforcoExecutada = false;
        for (var item in dados) {
          final objId = _normalizarCodigo(item['Artigo'] ?? item['artigo']);
          final detId = _normalizarCodigo(item['Detalhe'] ?? item['detalhe']);
          final nomeDoRegistro = _extrairProdutoDoRegistro(item);

          if (objId.isNotEmpty) {
            debugPrint(
              '[REG_ARTIGO][FLOW] Resolvendo objId=$objId detId=$detId endpoint=${widget.endpoint}',
            );
            final produtoApi = await _buscarProdutoNaApi(objId, detId);
            if (produtoApi != null) {
              item['NomeArtigo'] = produtoApi['nome'];
              item['DetalheNome'] = produtoApi['detalhe'] ?? '';
              debugPrint(
                '[REG_ARTIGO][FLOW] Nome vindo da API objId=$objId nome=${item['NomeArtigo']}',
              );
            }
            if (produtoApi == null) {
              Map<String, dynamic>? produto = await _buscarProdutoLocal(
                objId,
                detId,
              );

              if (produto == null) {
                if (!sincronizacaoReforcoExecutada) {
                  await DatabaseService.sincronizarTodosProdutos();
                  sincronizacaoReforcoExecutada = true;
                  debugPrint(
                    '[REG_ARTIGO][FLOW] Reforcando sincronizacao local objId=$objId detId=$detId',
                  );
                }
                produto = await _buscarProdutoLocal(objId, detId);
              }

              if (produto != null &&
                  (produto['objeto']?.toString().trim().isNotEmpty ?? false)) {
                item['NomeArtigo'] = produto['objeto'].toString().trim();
                item['DetalheNome'] =
                    (produto['detalhe'] ?? '').toString().trim();
                debugPrint(
                  '[REG_ARTIGO][FLOW] Nome vindo do SQLite objId=$objId nome=${item['NomeArtigo']}',
                );
              } else if (nomeDoRegistro != null) {
                item['NomeArtigo'] = nomeDoRegistro['nome'];
                item['DetalheNome'] = nomeDoRegistro['detalhe'] ?? '';
                debugPrint(
                  '[REG_ARTIGO][FLOW] Nome vindo do registro base objId=$objId nome=${item['NomeArtigo']}',
                );
              } else {
                item['NomeArtigo'] = "Artigo $objId";
                item['DetalheNome'] = '';
                debugPrint(
                  '[REG_ARTIGO][FLOW] Fallback final objId=$objId exibindo=${item['NomeArtigo']}',
                );
              }
            }
          } else {
            item['NomeArtigo'] = "Sem Código";
            item['DetalheNome'] = '';
          }

          if (objId.isEmpty && nomeDoRegistro != null) {
            item['NomeArtigo'] = nomeDoRegistro['nome'];
            item['DetalheNome'] = nomeDoRegistro['detalhe'] ?? '';
            debugPrint(
              '[REG_ARTIGO][FLOW] Nome sem codigo veio do registro base nome=${item['NomeArtigo']}',
            );
          }

          item['ArtigoLabel'] = objId.isEmpty ? '-' : objId;
          item['DetalheLabel'] = detId.isEmpty ? '-' : detId;

          item['OperadorLabel'] = _formatarOperador(
            item['Operador'],
            mapaOperadores,
          );
          final setor = item['Setor'] ?? item['setor'];
          final maq1Label = _formatarMaquina(item['Maq'], setor, mapaMaquinas);
          item['Maq1Label'] = maq1Label;

          final maq2Raw = _normalizarCodigo(item['Maq2']);
          if (widget.endpoint == 'tipoA' &&
              maq2Raw.isNotEmpty &&
              maq2Raw != '0') {
            final maq2Label = _formatarMaquina(item['Maq2'], setor, mapaMaquinas);
            item['Maq2Label'] = maq2Label;
            item['MaqLabel'] = "Maq 1: $maq1Label | Maq 2: $maq2Label";
          } else {
            item['Maq2Label'] = null;
            item['MaqLabel'] = maq1Label;
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
    final buscaAtiva = _termoBusca.trim().isNotEmpty;
    final dadosBase = buscaAtiva ? _todosDados : _dadosVisiveis;
    final dadosFiltrados = _filtrarDados(dadosBase);

    if (_isLoading && _todosDados.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: _kAccentColor),
      );
    }

    if (_erro != null && _todosDados.isEmpty) {
      return _buildErrorPlaceholder(_erro!);
    }

    return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _buscaController,
                    onChanged: (value) {
                      setState(() {
                        _termoBusca = value;
                      });
                      if (value.trim().isNotEmpty) {
                        _enriquecerTodosOsItensEmSegundoPlano();
                      }
                    },
                    style: const TextStyle(color: _kTextPrimary),
                    decoration: InputDecoration(
                      hintText: 'Pesquisar por nome ou artigo',
                      hintStyle: const TextStyle(color: _kTextSecondary),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: _kTextSecondary,
                      ),
                      suffixIcon: _termoBusca.trim().isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _buscaController.clear();
                                setState(() {
                                  _termoBusca = '';
                                });
                              },
                              icon: const Icon(
                                Icons.close,
                                color: _kTextSecondary,
                              ),
                            ),
                      filled: true,
                      fillColor: _kSurface,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _kBorderSoft),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _kAccentColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      buscaAtiva
                          ? '${dadosFiltrados.length} de ${_todosDados.length} registros'
                          : '${_dadosVisiveis.length} de ${_todosDados.length} registros carregados',
                      style: const TextStyle(
                        color: _kTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      buscaAtiva
                          ? 'Mostrando resultados filtrados.'
                          : 'Toque em um card para editar. Role para carregar mais.',
                      style: const TextStyle(
                        color: _kTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: dadosFiltrados.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.search_off_outlined,
                              color: _kTextSecondary,
                              size: 42,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Nenhum registro corresponde à pesquisa.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _kTextSecondary),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: buscaAtiva ? null : _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: dadosFiltrados.length + (_isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= dadosFiltrados.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: _kAccentColor,
                              ),
                            ),
                          );
                        }
                        final item = dadosFiltrados[index];
                        return widget.endpoint == "tipoA"
                            ? _buildCardProducao(item)
                            : _buildCardQualidade(item);
                      },
                    ),
            ),
          ],
        );
  }

  Widget _buildCardProducao(Map<String, dynamic> item) {
    final tituloArtigo = _tituloArtigo(item);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _abrirEditorRegistro(item),
        borderRadius: BorderRadius.circular(16),
        child: Container(
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
                    tituloArtigo,
                    style: const TextStyle(
                      color: _kTextPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildBadge(
                      "Turno ${_mapearTurno(item['Turno'] ?? item['turno'])}",
                    ),
                    const SizedBox(height: 8),
                    const Icon(
                      Icons.edit_outlined,
                      color: _kTextSecondary,
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Cód: ${item['ArtigoLabel'] ?? item['Artigo'] ?? '-'} | Lote: ${item['DetalheLabel'] ?? item['Detalhe'] ?? '-'}",
              style: const TextStyle(color: _kAccentColor, fontSize: 12),
            ),
            const Divider(height: 24, color: _kBorderSoft),
            _buildDataPoint(
              Icons.person_outline,
              "Operador",
              item['OperadorLabel']?.toString(),
            ),
            _buildDataPoint(
              Icons.precision_manufacturing_outlined,
              item['Maq2Label'] == null ? "Máquina" : "Máquina 1",
              (item['Maq1Label'] ?? item['MaqLabel'])?.toString(),
            ),
            if (item['Maq2Label'] != null)
              _buildDataPoint(
                Icons.precision_manufacturing_outlined,
                "Máquina 2",
                item['Maq2Label']?.toString(),
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
        ),
      ),
    );
  }

  Widget _buildCardQualidade(Map<String, dynamic> item) {
    final tituloArtigo = _tituloArtigo(item);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _abrirEditorRegistro(item),
        borderRadius: BorderRadius.circular(16),
        child: Container(
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
                          tituloArtigo,
                          style: const TextStyle(
                            color: _kTextPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _buildBadge(
                            "Turno ${_mapearTurno(item['turno'] ?? item['Turno'])}",
                            color: Colors.orangeAccent,
                          ),
                          const SizedBox(height: 8),
                          const Icon(
                            Icons.edit_outlined,
                            color: _kTextSecondary,
                            size: 18,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Cód: ${item['ArtigoLabel'] ?? item['Artigo'] ?? '-'} | Lote: ${item['DetalheLabel'] ?? item['Detalhe'] ?? '-'}",
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                    ),
                  ),
                  const Divider(height: 24, color: _kBorderSoft),
                  _buildDataPoint(
                    Icons.person_outline,
                    "Operador",
                    item['OperadorLabel']?.toString(),
                  ),
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
        ),
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
        color: color.withValues(alpha: 0.2),
        border: Border.all(color: color.withValues(alpha: 0.5)),
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
