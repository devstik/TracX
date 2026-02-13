import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../services/estoque_db_helper.dart';

// =========================================================================
// 🎨 PALETA OFICIAL (PADRÃO HOME + SPLASH)
// =========================================================================
const Color _kPrimaryColor = Color(0xFF2563EB); // Azul principal (moderno)
const Color _kAccentColor = Color(0xFF60A5FA); // Azul claro premium

const Color _kBgTop = Color(0xFF050A14);
const Color _kBgBottom = Color(0xFF0B1220);

const Color _kSurface = Color(0xFF101B34);
const Color _kSurface2 = Color(0xFF0F172A);

const Color _kTextPrimary = Color(0xFFF9FAFB);
const Color _kTextSecondary = Color(0xFF9CA3AF);

// borda mais visível
const Color _kBorderSoft = Color(0x33FFFFFF);

// **********************************************
// 1. CONFIGURAÇÃO E MODELO DE DADOS
// **********************************************

abstract class AppConstants {
  static const String empresaId = '2';
  static const int operacaoIdFiltro = 142;

  // --- WMS (MAPAS DE PRODUÇÃO) ---
  static const String authEndpointWMS =
      'https://visions.topmanager.com.br/auth/api/usuarios/entrar?identificadorDaAplicacao=LogTech_WMS&chaveDaAplicacaoExterna=uvkmv%2BQHum%2FXhF8grWeW4nKmzKFRk4UwJk74x7FnZbGC6ECvl4nbxUf3h7L%2BCGk25qSA8QOJoovrJtUJlXlsWQ%3D%3D&enderecoDeRetorno=http://qualquer';
  static const String authEmailWMS = 'suporte.wms';
  static const String authSenhaWMS = '123456';
  static const int authUsuarioIdWMS = 21578;
  static const String baseUrlWMS = 'visions.topmanager.com.br';
  static const String mapaPath =
      '/Servidor_2.8.0_api/logtechwms/itemdemapadeproducao/consultar';
  static const String tipoDocumentoId = '62';

  // --- FORÇA DE VENDAS (PRODUTOS) ---
  static const String authEndpointProd =
      'https://visions.topmanager.com.br/auth/api/usuarios/entrar?identificadorDaAplicacao=ForcaDeVendas&chaveDaAplicacaoExterna=2awwG8Tqp12sJtzQcyYIzVrYfQNmMg0crxWq8ohNQMlQU4cU5lvO1Y%2FGNN0hbkAD0JNPPQz3489u8paqUO3jOg%3D%3D&enderecoDeRetorno=http://qualquer';
  static const String authEmailProd = 'Stik.ForcaDeVendas';
  static const String authSenhaProd = '123456';
  static const int authUsuarioIdProd = 15980;
  static const String baseUrlProd = 'visions.topmanager.com.br';
  static const String prodPath =
      '/Servidor_2.7.0_api/forcadevendas/lancamentodeestoque/consultar';
}

abstract class CacheManager {
  static final Map<int, String> produtosNomeCache = {};
  static final Map<int, String> produtosDetalheCache = {};

  static String? prodApiKey;

  static void clear() {
    produtosNomeCache.clear();
    produtosDetalheCache.clear();
    prodApiKey = null;
  }
}

class MapaResultado {
  final DateTime data;
  final List<Map<String, dynamic>> registros;

  const MapaResultado({required this.data, required this.registros});
}

class _ObjetoResumo {
  final int produtoId;
  final String nome;
  final String detalhe;
  double quantidade;

  _ObjetoResumo({
    required this.produtoId,
    required this.nome,
    required this.detalhe,
    required this.quantidade,
  });
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

abstract class ApiService {
  static Future<String> authenticate({
    required String endpoint,
    required String email,
    required String senha,
    required int usuarioId,
  }) async {
    final response = await http.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'senha': senha,
        'usuarioID': usuarioId,
      }),
    );

    if (response.statusCode != 200) {
      throw ApiException(
        'Falha na autenticação (Status: ${response.statusCode})',
      );
    }

    final body = jsonDecode(response.body);
    final redirect = body['redirecionarPara']?.toString();

    final RegExp exp = RegExp("(ey[^\"'\\s]+)");
    final RegExpMatch? match = exp.firstMatch(redirect ?? '');

    if (match != null) {
      return match.group(1)!;
    }

    throw ApiException('Não foi possível extrair a chave da API.');
  }

  static Future<void> cacheProductDetails(Set<int> produtosIds) async {
    if (CacheManager.prodApiKey == null) return;

    final uri = Uri.https(AppConstants.baseUrlProd, AppConstants.prodPath, {
      'empresaID': AppConstants.empresaId,
    });

    try {
      final http.Response response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer ${CacheManager.prodApiKey}'},
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic> && item['objetoID'] is int) {
              final id = item['objetoID'] as int;

              if (produtosIds.contains(id)) {
                CacheManager.produtosNomeCache[id] =
                    item['objeto'] as String? ?? 'Nome N/A';
                CacheManager.produtosDetalheCache[id] =
                    item['detalhe'] as String? ?? '--';
              }
            }
          }
        }
      } else {
        throw ApiException(
          'Falha ao consultar detalhes de produto (Status: ${response.statusCode})',
        );
      }
    } on Exception catch (e) {
      throw ApiException('Erro ao buscar detalhes de produto: ${e.toString()}');
    }
  }

  static Future<List<Map<String, dynamic>>> fetchMapByDate({
    required String apiKeyWMS,
    required String isoDate,
  }) async {
    final uri = Uri.https(AppConstants.baseUrlWMS, AppConstants.mapaPath, {
      'empresaID': AppConstants.empresaId,
      'tipoDeDocumentoID': AppConstants.tipoDocumentoId,
      'data': isoDate,
    });

    final http.Response response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $apiKeyWMS'},
    );

    if (response.statusCode != 200) {
      throw ApiException(
        'Falha na consulta do mapa (Status: ${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    List<Map<String, dynamic>> registros = [];

    if (decoded is List) {
      registros.addAll(decoded.whereType<Map<String, dynamic>>());
    } else if (decoded is Map<String, dynamic>) {
      registros.add(decoded);
    }

    return registros.where((registro) {
      return registro['operacaoId'] == AppConstants.operacaoIdFiltro;
    }).toList();
  }
}

// **********************************************
// 3. INTERFACE DO USUÁRIO (WIDGETS)
// **********************************************

class ConsultaMapaProducaoScreen extends StatefulWidget {
  const ConsultaMapaProducaoScreen({super.key});

  @override
  State<ConsultaMapaProducaoScreen> createState() =>
      _ConsultaMapaProducaoScreenState();
}

mixin UiUtils on State<ConsultaMapaProducaoScreen> {
  DateTime? parseDate(String value) {
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(value);
    } on FormatException {
      return null;
    }
  }

  void showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade600,
      ),
    );
  }
}

class _ConsultaMapaProducaoScreenState extends State<ConsultaMapaProducaoScreen>
    with UiUtils {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _dataInicialController = TextEditingController();
  final TextEditingController _dataFinalController = TextEditingController();
  final TextEditingController _objetoFiltroController = TextEditingController();
  String _objetoFiltro = '';

  bool _loading = false;
  List<MapaResultado> _resultados = [];

  int _diasTotais = 0;
  int _diasProcessados = 0;

  @override
  void initState() {
    super.initState();
    _carregarCatalogoLocal();
    _objetoFiltroController.addListener(() {
      setState(() {
        _objetoFiltro = _objetoFiltroController.text.trim().toLowerCase();
      });
    });
  }

  Future<void> _carregarCatalogoLocal() async {
    final dbHelper = EstoqueDbHelper();
    final catalogo = await dbHelper.getCatalogoMap();

    catalogo.forEach((id, info) {
      CacheManager.produtosNomeCache[id] = info['nome']!;
      CacheManager.produtosDetalheCache[id] = info['detalhe']!;
    });
  }

  @override
  void dispose() {
    _dataInicialController.dispose();
    _dataFinalController.dispose();
    _objetoFiltroController.dispose();
    super.dispose();
  }

  String? _nomeProduto(int? produtoId) {
    if (produtoId == null) return null;
    return CacheManager.produtosNomeCache[produtoId];
  }

  String _detalheProduto(int? produtoId) {
    if (produtoId == null) return 'Lote: N/A';
    final detalhe = CacheManager.produtosDetalheCache[produtoId];
    return detalhe ?? 'N/A';
  }

  List<_ObjetoResumo> _agruparObjetos() {
    final mapa = <int, _ObjetoResumo>{};
    for (final resultado in _resultados) {
      for (final registro in resultado.registros) {
        final produtoId = registro['produtoId'] as int?;
        final nome = _nomeProduto(produtoId);
        final quantidade = registro['quantidade'];
        final quantidadeNum = quantidade is num ? quantidade.toDouble() : 0.0;

        if (produtoId == null || nome == null || quantidadeNum <= 0) continue;

        mapa.putIfAbsent(
          produtoId,
          () => _ObjetoResumo(
            produtoId: produtoId,
            nome: nome,
            detalhe: _detalheProduto(produtoId),
            quantidade: 0,
          ),
        );
        mapa[produtoId]!.quantidade += quantidadeNum;
      }
    }

    final lista = mapa.values.toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return lista;
  }

  Future<void> _consultar() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final dataInicial = parseDate(_dataInicialController.text.trim());
    final dataFinal = parseDate(_dataFinalController.text.trim());

    if (dataInicial == null ||
        dataFinal == null ||
        dataFinal.isBefore(dataInicial)) {
      showSnackBar('Período de datas inválido.', isError: true);
      return;
    }

    final List<String> datasDesejadasIso = [];
    for (
      DateTime d = dataInicial;
      !d.isAfter(dataFinal);
      d = d.add(const Duration(days: 1))
    ) {
      datasDesejadasIso.add(DateFormat("yyyy-MM-dd'T'00:00:00").format(d));
    }

    try {
      final dbHelper = EstoqueDbHelper();
      final String hojeIso = DateFormat(
        "yyyy-MM-dd'T'00:00:00",
      ).format(DateTime.now());

      final db = await dbHelper.database;
      final List<Map<String, dynamic>> registrosBrutos = await db.query(
        'mapa_producao',
        where: 'data_iso BETWEEN ? AND ?',
        whereArgs: [datasDesejadasIso.first, datasDesejadasIso.last],
      );

      Map<String, List<Map<String, dynamic>>> mapaAgrupado = {};
      for (var reg in registrosBrutos) {
        final dIso = reg['data_iso'] as String;
        mapaAgrupado
            .putIfAbsent(dIso, () => [])
            .add(Map<String, dynamic>.from(reg));
      }

      final List<MapaResultado> listaLocal = mapaAgrupado.entries.map((e) {
        return MapaResultado(data: DateTime.parse(e.key), registros: e.value);
      }).toList();

      listaLocal.sort((a, b) => b.data.compareTo(a.data));

      if (listaLocal.isNotEmpty && !datasDesejadasIso.contains(hojeIso)) {
        setState(() {
          _resultados = listaLocal;
          _loading = false;
        });
        return;
      }

      setState(() {
        _resultados = listaLocal;
        _loading = true;
        _diasTotais = datasDesejadasIso.length;
        _diasProcessados = mapaAgrupado.length;
      });

      _sincronizarFaltantesEmBackground(
        dataInicial,
        dataFinal,
        hojeIso,
        mapaAgrupado.keys.toSet(),
      );
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _sincronizarFaltantesEmBackground(
    DateTime inicio,
    DateTime fim,
    String hojeIso,
    Set<String> diasNoBanco,
  ) async {
    String? token;
    final dbHelper = EstoqueDbHelper();

    try {
      for (
        DateTime d = inicio;
        !d.isAfter(fim);
        d = d.add(const Duration(days: 1))
      ) {
        final iso = DateFormat("yyyy-MM-dd'T'00:00:00").format(d);

        if (!diasNoBanco.contains(iso) || iso == hojeIso) {
          token ??= await ApiService.authenticate(
            endpoint: AppConstants.authEndpointWMS,
            email: AppConstants.authEmailWMS,
            senha: AppConstants.authSenhaWMS,
            usuarioId: AppConstants.authUsuarioIdWMS,
          );

          final novosDados = await ApiService.fetchMapByDate(
            apiKeyWMS: token,
            isoDate: iso,
          );

          if (novosDados.isNotEmpty) {
            await dbHelper.insertMapas(novosDados, iso);

            if (mounted) {
              setState(() {
                _resultados.removeWhere(
                  (r) =>
                      DateFormat("yyyy-MM-dd'T'00:00:00").format(r.data) == iso,
                );
                _resultados.add(MapaResultado(data: d, registros: novosDados));
                _resultados.sort((a, b) => b.data.compareTo(a.data));
              });
            }
          }
        }

        if (mounted && _diasProcessados < _diasTotais) {
          setState(() => _diasProcessados++);
        }
      }

      await _buscarNomesDeProdutosFaltantes();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _buscarNomesDeProdutosFaltantes() async {
    final Set<int> idsSemNome = {};
    for (var res in _resultados) {
      for (var reg in res.registros) {
        final id = reg['produtoId'] as int?;
        if (id != null && !CacheManager.produtosNomeCache.containsKey(id)) {
          idsSemNome.add(id);
        }
      }
    }

    if (idsSemNome.isNotEmpty) {
      CacheManager.prodApiKey ??= await ApiService.authenticate(
        endpoint: AppConstants.authEndpointProd,
        email: AppConstants.authEmailProd,
        senha: AppConstants.authSenhaProd,
        usuarioId: AppConstants.authUsuarioIdProd,
      );

      await ApiService.cacheProductDetails(idsSemNome);

      if (mounted) setState(() {});
    }
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgBottom,

      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        foregroundColor: _kTextPrimary,
        backgroundColor: _kBgBottom,
        title: const Text(
          'Consultar Mapas de Produção',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: 0.2,
          ),
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
      ),

      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildFormArea(),
                  const SizedBox(height: 18),
                  _buildObjetoResumoSection(),

                  if (_loading && _resultados.isEmpty)
                    _LoadingFeedback(
                      diasTotais: _diasTotais,
                      diasProcessados: _diasProcessados,
                    ),
                ]),
              ),
            ),

            if (_resultados.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _MapaCard(resultado: _resultados[index]),
                    childCount: _resultados.length,
                  ),
                ),
              )
            else if (!_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'Nenhum mapa registrado para este período.',
                    style: TextStyle(color: _kTextSecondary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorderSoft, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Form(
            key: _formKey,
            child: Row(
              children: [
                Expanded(
                  child: _DateFieldInput(
                    label: 'Inicial',
                    controller: _dataInicialController,
                    parseDate: parseDate,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateFieldInput(
                    label: 'Final',
                    controller: _dataFinalController,
                    parseDate: parseDate,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _consultar,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search),
              label: Text(_loading ? 'Consultando...' : 'Consultar Período'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: _kPrimaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildObjetoResumoSection() {
    final objetos = _agruparObjetos();
    if (objetos.isEmpty) return const SizedBox.shrink();

    final filtro = _objetoFiltro;
    final objetosFiltrados = filtro.isEmpty
        ? objetos
        : objetos.where((o) {
            final nomeLower = o.nome.toLowerCase();
            return nomeLower.contains(filtro) ||
                o.produtoId.toString().contains(filtro);
          }).toList();

    final totalGeral = objetosFiltrados.fold<double>(
      0,
      (sum, obj) => sum + obj.quantidade,
    );

    final formatter = NumberFormat('#,##0.00', 'pt_BR');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorderSoft, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.search_rounded, color: _kAccentColor),
              SizedBox(width: 8),
              Text(
                'Pesquisar por Objeto',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _kTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _objetoFiltroController,
            style: const TextStyle(color: _kTextPrimary),
            decoration: InputDecoration(
              hintText: 'Digite o nome ou código do objeto',
              hintStyle: TextStyle(color: _kTextSecondary.withOpacity(0.8)),
              prefixIcon: const Icon(Icons.search, color: _kTextSecondary),
              filled: true,
              fillColor: _kSurface2,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: _kBorderSoft),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _kAccentColor, width: 1.6),
              ),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            'Total geral: ${formatter.format(totalGeral)} metros',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: _kTextSecondary,
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            height: 220,
            child: objetosFiltrados.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhum objeto encontrado.',
                      style: TextStyle(color: _kTextSecondary),
                    ),
                  )
                : ListView.separated(
                    itemCount: objetosFiltrados.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: _kBorderSoft.withOpacity(0.4),
                    ),
                    itemBuilder: (_, index) {
                      final item = objetosFiltrados[index];

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          item.nome,
                          style: const TextStyle(
                            color: _kTextPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'ID: ${item.produtoId} • Lote: ${item.detalhe}',
                          style: const TextStyle(
                            color: _kTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Text(
                          formatter.format(item.quantidade),
                          style: const TextStyle(
                            color: _kAccentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- COMPONENTES ---

class _DateFieldInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final DateTime? Function(String) parseDate;

  const _DateFieldInput({
    required this.label,
    required this.controller,
    required this.parseDate,
  });

  @override
  Widget build(BuildContext context) {
    Future<void> selectDate() async {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: parseDate(controller.text) ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2101),
        locale: const Locale('pt', 'BR'),
        builder: (context, child) {
          return Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: _kPrimaryColor,
                onPrimary: Colors.white,
                surface: _kSurface,
                onSurface: _kTextPrimary,
              ),
            ),
            child: child!,
          );
        },
      );

      if (picked != null) {
        controller.text = DateFormat('dd/MM/yyyy').format(picked);
      }
    }

    return TextFormField(
      controller: controller,
      readOnly: true,
      onTap: selectDate,
      style: const TextStyle(color: _kTextPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kTextSecondary),
        filled: true,
        fillColor: _kSurface2,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _kBorderSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kAccentColor, width: 1.6),
        ),
        suffixIcon: const Icon(Icons.calendar_today, color: _kTextSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      validator: (value) =>
          value == null || value.isEmpty ? 'Selecione a data' : null,
    );
  }
}

class _LoadingFeedback extends StatelessWidget {
  final int diasTotais;
  final int diasProcessados;

  const _LoadingFeedback({
    required this.diasTotais,
    required this.diasProcessados,
  });

  @override
  Widget build(BuildContext context) {
    final progresso = diasTotais == 0 ? 0.0 : diasProcessados / diasTotais;
    final percentual = (progresso * 100).toStringAsFixed(0);

    final statusText = diasProcessados < diasTotais
        ? 'Consultando dia ${diasProcessados + 1} de $diasTotais...'
        : 'Finalizando e buscando detalhes dos produtos...';

    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorderSoft, width: 1),
      ),
      child: Column(
        children: [
          Text(
            'Total de dias para busca: $diasTotais.',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _kTextPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: progresso,
              backgroundColor: _kSurface2,
              color: _kAccentColor,
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progresso: $percentual%',
                style: const TextStyle(color: _kTextSecondary, fontSize: 13),
              ),
              Text(
                'Dias: $diasProcessados/$diasTotais',
                style: const TextStyle(
                  color: _kAccentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            statusText,
            style: const TextStyle(
              color: _kTextSecondary,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          const CircularProgressIndicator(color: _kAccentColor),
        ],
      ),
    );
  }
}

// **********************************************
// 4. CARTÃO DE RESULTADO FINAL
// **********************************************

class _MapaCard extends StatefulWidget {
  final MapaResultado resultado;

  const _MapaCard({required this.resultado});

  @override
  State<_MapaCard> createState() => _MapaCardState();
}

class _MapaCardState extends State<_MapaCard> {
  final NumberFormat _quantityFormat = NumberFormat('#,##0.##', 'pt_BR');
  final NumberFormat _totalFormat = NumberFormat('#,##0.00', 'pt_BR');

  String? _getProductName(int? produtoId) {
    if (produtoId == null) return null;
    return CacheManager.produtosNomeCache[produtoId];
  }

  String _getProductDetail(int? produtoId) {
    if (produtoId == null) return 'Lote: N/A';
    final detalhe = CacheManager.produtosDetalheCache[produtoId];
    return 'Lote: ${detalhe ?? 'N/A'}';
  }

  @override
  Widget build(BuildContext context) {
    final dataFormatada = DateFormat(
      'dd/MM/yyyy',
    ).format(widget.resultado.data);

    final filteredRegistros = widget.resultado.registros.where((registro) {
      final produtoId = registro['produtoId'] as int?;
      final quantidade = registro['quantidade'];

      final isQuantityValid = quantidade is num && quantidade > 0;
      final isNameFound = _getProductName(produtoId) != null;

      return isQuantityValid && isNameFound;
    }).toList();

    final double totalQuantidade = filteredRegistros.fold(0.0, (sum, registro) {
      final quantidade = registro['quantidade'];
      return sum + (quantidade is num ? quantidade : 0.0);
    });

    if (filteredRegistros.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalQuantidadeFormatada = _totalFormat.format(totalQuantidade);
    final totalRegistros = filteredRegistros.length;
    final subtitleText = '$totalQuantidadeFormatada metros';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorderSoft, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Theme(
        data: ThemeData.dark().copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          collapsedIconColor: _kAccentColor,
          iconColor: _kAccentColor,
          backgroundColor: Colors.transparent,
          collapsedBackgroundColor: Colors.transparent,
          leading: const Icon(
            Icons.calendar_today_rounded,
            color: _kAccentColor,
            size: 24,
          ),
          title: Text(
            'Data: $dataFormatada',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: _kTextPrimary,
            ),
          ),
          subtitle: Text(
            subtitleText,
            style: const TextStyle(color: _kTextSecondary, fontSize: 13),
          ),
          children: [
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: totalRegistros,
              itemBuilder: (context, index) {
                final registro = filteredRegistros[index];
                final produtoId = registro['produtoId'] as int?;
                final quantidade = registro['quantidade'];

                final nomeProduto = _getProductName(produtoId)!;
                final detalheProduto = _getProductDetail(produtoId);

                final quantidadeFormatada = quantidade != null
                    ? _quantityFormat.format(quantidade)
                    : '??';

                return Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 10,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _kSurface2.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _kBorderSoft, width: 1),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nomeProduto,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: _kTextPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                detalheProduto,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                  color: _kTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          quantidadeFormatada,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _kAccentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total do dia',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _kTextSecondary,
                    ),
                  ),
                  Text(
                    '$totalQuantidadeFormatada metros',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _kAccentColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
