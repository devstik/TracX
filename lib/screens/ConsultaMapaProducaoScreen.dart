import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../services/estoque_db_helper.dart';

// **********************************************
// 1. CONFIGURAÇÃO E MODELO DE DADOS
// **********************************************

/// Define todas as constantes de configuração, URLs e credenciais.
abstract class AppConstants {
  // Configurações Comuns
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

  // --- CORES TEMA ---
  static final Color primaryColor = Colors.red.shade700;
  static final Color secondaryColor = Colors.grey.shade600;
  static final Color backgroundColor = Colors.grey.shade50;
}

/// Gerencia o cache de dados em memória para evitar consultas repetidas.
abstract class CacheManager {
  // Armazena o nome do produto (objeto)
  static final Map<int, String> produtosNomeCache = {};
  // Armazena o detalhe/lote do produto
  static final Map<int, String> produtosDetalheCache = {};

  static String? prodApiKey; // Chave de API para o endpoint de produtos

  static void clear() {
    produtosNomeCache.clear();
    produtosDetalheCache.clear();
    prodApiKey = null;
  }
}

/// Modelo de dados simplificado para o resultado da consulta por data.
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

/// Exceção customizada para erros de API.
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

/// Classe responsável por todas as interações com as APIs.
abstract class ApiService {
  /// Obtém uma chave de API (Bearer Token) através do processo de autenticação.
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

    // Regex para extrair o JWT (token)
    final RegExp exp = RegExp("(ey[^\"'\\s]+)");
    final RegExpMatch? match = exp.firstMatch(redirect ?? '');

    if (match != null) {
      return match.group(1)!;
    }

    throw ApiException('Não foi possível extrair a chave da API.');
  }

  /// Consulta o endpoint de Produtos e armazena nomes e detalhes no cache.
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
                // Armazena nome (objeto) e detalhe (lote)
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

  /// Executa a consulta de mapas de produção para uma data específica.
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

    // Filtra a lista para incluir apenas a operacaoId desejada.
    return registros.where((registro) {
      return registro['operacaoId'] == AppConstants.operacaoIdFiltro;
    }).toList();
  }
}

// **********************************************
// 3. INTERFACE DO USUÁRIO (WIDGETS)
// **********************************************

/// Classe principal da tela de consulta de mapas.
class ConsultaMapaProducaoScreen extends StatefulWidget {
  const ConsultaMapaProducaoScreen({super.key});

  @override
  State<ConsultaMapaProducaoScreen> createState() =>
      _ConsultaMapaProducaoScreenState();
}

/// Mixin para métodos utilitários de UI, limpando a classe State.
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

  // Variáveis para feedback de progresso
  int _diasTotais = 0;
  int _diasProcessados = 0;

  @override
  void initState() {
    super.initState();
    _carregarCatalogoLocal(); // Carrega dados do banco para a memória
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

  // --- LÓGICA DE NEGÓCIOS / API ---
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

      // 1. Busca no Banco
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

      // --- A LOGICA DE CORTE ---
      // Se o banco retornou QUALQUER coisa para esse período, e não inclui hoje,
      // nós assumimos que o banco já tem a "verdade" do período.
      if (listaLocal.isNotEmpty && !datasDesejadasIso.contains(hojeIso)) {
        setState(() {
          _resultados = listaLocal;
          _loading = false; // MATA O LOADING NA HORA
        });
        return;
      }

      // Se o banco está totalmente vazio para o período, aí sim ele busca uma única vez
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
        if (id != null && !CacheManager.produtosNomeCache.containsKey(id))
          idsSemNome.add(id);
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

  // --- WIDGETS DE UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(title: const Text('Consultar Mapas de Produção')),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildFormArea(),
                  const SizedBox(height: 24),
                  _buildObjetoResumoSection(),

                  // Só mostra o progresso se NÃO houver resultados na tela
                  // ou se estiver carregando o dia de hoje.
                  if (_loading && _resultados.isEmpty)
                    _LoadingFeedback(
                      diasTotais: _diasTotais,
                      diasProcessados: _diasProcessados,
                    ),
                ]),
              ),
            ),

            // Se tiver resultados, mostra. Se não tiver nada e parou de carregar, avisa.
            if (_resultados.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
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
                  child: Text('Nenhum mapa registrado para este período.'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormArea() {
    return Column(
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
              const SizedBox(width: 16),
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
        const SizedBox(height: 16),
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
              backgroundColor: AppConstants.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildObjetoResumoSection() {
    final objetos = _agruparObjetos();
    if (objetos.isEmpty) {
      return const SizedBox.shrink();
    }

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

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.search, color: AppConstants.primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Pesquisar por Objeto',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppConstants.primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _objetoFiltroController,
              decoration: InputDecoration(
                hintText: 'Digite o nome ou código do objeto',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Total geral: ${formatter.format(totalGeral)} metros',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: objetosFiltrados.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhum objeto encontrado.',
                        style: TextStyle(color: AppConstants.secondaryColor),
                      ),
                    )
                  : ListView.separated(
                      itemCount: objetosFiltrados.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final item = objetosFiltrados[index];
                        return ListTile(
                          title: Text(item.nome),
                          subtitle: Text(
                            'ID: ${item.produtoId} • Lote: ${item.detalhe}',
                          ),
                          trailing: Text(
                            formatter.format(item.quantidade),
                            style: TextStyle(
                              color: AppConstants.primaryColor,
                              fontWeight: FontWeight.bold,
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
  }
}

// --- WIDGETS AUXILIARES (COMPONENTES) ---

/// Campo de entrada de data com seletor (DatePicker).
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
            data: ThemeData.light().copyWith(
              colorScheme: ColorScheme.light(
                primary: AppConstants.primaryColor,
                onPrimary: Colors.white,
                onSurface: Colors.black,
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
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        suffixIcon: Icon(
          Icons.calendar_today,
          color: AppConstants.secondaryColor,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      validator: (value) =>
          value == null || value.isEmpty ? 'Selecione a data' : null,
    );
  }
}

/// Feedback visual durante o carregamento de dados.
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

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Total de dias para busca: $diasTotais.',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: progresso,
          backgroundColor: Colors.grey.shade300,
          color: AppConstants.primaryColor,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progresso: $percentual%',
                style: const TextStyle(fontSize: 14),
              ),
              Text(
                'Dias: $diasProcessados de $diasTotais',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.primaryColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Status: $statusText',
          style: TextStyle(
            color: AppConstants.secondaryColor,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        CircularProgressIndicator(color: AppConstants.primaryColor),
      ],
    );
  }
}

// **********************************************
// 4. CARTÃO DE RESULTADO FINAL (Otimizado)
// **********************************************

class _MapaCard extends StatefulWidget {
  final MapaResultado resultado;

  const _MapaCard({required this.resultado});

  @override
  State<_MapaCard> createState() => _MapaCardState();
}

class _MapaCardState extends State<_MapaCard> {
  // Formatador para a quantidade (ex: 12.000,50)
  final NumberFormat _quantityFormat = NumberFormat('#,##0.##', 'pt_BR');
  // Formatador para o total (garante 2 casas decimais)
  final NumberFormat _totalFormat = NumberFormat('#,##0.00', 'pt_BR');

  /// Busca o nome do produto no cache. Retorna null se não encontrado.
  String? _getProductName(int? produtoId) {
    if (produtoId == null) return null;
    return CacheManager.produtosNomeCache[produtoId];
  }

  /// Busca o detalhe (Lote) do produto no cache.
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

    // 1. FILTRAR REGISTROS: Quantidade > 0 E Nome encontrado no cache.
    final filteredRegistros = widget.resultado.registros.where((registro) {
      final produtoId = registro['produtoId'] as int?;
      final quantidade = registro['quantidade'];

      final isQuantityValid = quantidade is num && quantidade > 0;
      final isNameFound = _getProductName(produtoId) != null;

      return isQuantityValid && isNameFound;
    }).toList();

    // 2. CALCULAR SOMA TOTAL DA QUANTIDADE (Metros)
    final double totalQuantidade = filteredRegistros.fold(0.0, (sum, registro) {
      final quantidade = registro['quantidade'];
      return sum + (quantidade is num ? quantidade : 0.0);
    });

    // Se não houver registros após o filtro, não exibe o card.
    if (filteredRegistros.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalQuantidadeFormatada = _totalFormat.format(totalQuantidade);
    final totalRegistros = filteredRegistros.length;
    final subtitleText = '$totalQuantidadeFormatada metros';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        collapsedBackgroundColor: Colors.white,
        iconColor: AppConstants.primaryColor,
        collapsedIconColor: AppConstants.primaryColor,
        leading: Icon(
          Icons.calendar_today,
          color: AppConstants.primaryColor,
          size: 28,
        ),
        title: Text(
          'Data: $dataFormatada',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: AppConstants.primaryColor,
          ),
        ),
        subtitle: Text(
          subtitleText,
          style: TextStyle(color: AppConstants.secondaryColor, fontSize: 14),
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
                padding: const EdgeInsets.only(left: 20, right: 20, bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppConstants.backgroundColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
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
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              detalheProduto,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                                color: AppConstants.secondaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$quantidadeFormatada', //
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppConstants.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 8.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total do dia',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppConstants.secondaryColor,
                  ),
                ),
                Text(
                  '$totalQuantidadeFormatada metros',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
