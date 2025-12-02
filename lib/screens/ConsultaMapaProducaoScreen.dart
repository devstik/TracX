import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

/// 1. CONFIGURAÇÃO E MODELO DE DADOS
// **********************************************

/// Define todas as constantes, URLs e credenciais da aplicação.
abstract class AppConfig {
  // Configurações Comuns
  static const String empresaId = '2';
  static const int operacaoIdFiltro = 142;

  // --- WMS (MAPAS DE PRODUÇÃO) ---
  static const String authEndpointWMS =
      'https://visions.topmanager.com.br/auth/api/usuarios/entrar?identificadorDaAplicacao=LogTech_WMS&chaveDaAplicacaoExterna=uvkmv%2BQHum%2FXhF8grWeW4nKmzKFRk4UwJk74x7FnZbGC6ECvl4nbxUf3h7L%2BCGk25qqSA8QOJoovrJtUJlXlsWQ%3D%3D&enderecoDeRetorno=http://qualquer';
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

/// Variáveis globais para cache e autenticação (armazenadas em memória).
abstract class GlobalState {
  // Armazena apenas o nome do objeto
  static final Map<int, String> produtosCache = {};
  // Armazena o detalhe/lote
  static final Map<int, String> detalhesCache = {};

  static String? prodApiKey; // Chave de API para o endpoint de produtos
}

/// Modelo de dados para um resultado de mapa (uma data e seus registros).
class MapaResultado {
  final DateTime data;
  final List<Map<String, dynamic>> registros;

  const MapaResultado({required this.data, required this.registros});
}

/// 2. SERVIÇO DE API
// **********************************************

/// Classe responsável por todas as interações com a API.
class ApiService {
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
      throw Exception('Falha na autenticação (Status: ${response.statusCode})');
    }

    final body = jsonDecode(response.body);
    final redirect = body['redirecionarPara']?.toString();

    // Regex para extrair o JWT (token) do token de redirecionamento.
    final RegExp exp = RegExp("(ey[^\"'\\s]+)");
    final RegExpMatch? match = exp.firstMatch(redirect!);

    if (match != null) {
      return match.group(1)!;
    }

    throw Exception('Não foi possível extrair a chave da API.');
  }

  /// Consulta o endpoint de Força de Vendas e armazena os nomes e detalhes dos produtos no cache.
  static Future<void> consultarEArmazenarNomes(Set<int> produtosIds) async {
    if (GlobalState.prodApiKey == null) return;

    final uri = Uri.https(AppConfig.baseUrlProd, AppConfig.prodPath, {
      'empresaID': AppConfig.empresaId,
    });

    try {
      final http.Response response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer ${GlobalState.prodApiKey}'},
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        if (decoded is List) {
          for (final item in decoded) {
            // Adaptação para a estrutura 'lancamentodeestoque/consultar'
            if (item is Map<String, dynamic> &&
                item['objetoID'] is int &&
                item['objeto'] is String) {
              final id = item['objetoID'] as int;
              final nome = item['objeto'] as String;
              final detalhe = item['detalhe'] as String?; // Captura o detalhe

              if (produtosIds.contains(id)) {
                // Armazena apenas o nome
                GlobalState.produtosCache[id] = nome;

                // Armazena o detalhe no novo cache
                GlobalState.detalhesCache[id] = detalhe ?? '--';
              }
            }
          }
        }
      } else {
        throw Exception(
          'Falha ao consultar nomes de produto (Status: ${response.statusCode})',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Executa a consulta de mapas de produção para uma data específica.
  static Future<List<Map<String, dynamic>>> consultarMapaPorData({
    required String apiKeyWMS,
    required String isoDate,
  }) async {
    final uri = Uri.https(AppConfig.baseUrlWMS, AppConfig.mapaPath, {
      'empresaID': AppConfig.empresaId,
      'tipoDeDocumentoID': AppConfig.tipoDocumentoId,
      'data': isoDate,
    });

    final http.Response response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $apiKeyWMS'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Falha na consulta do mapa (Status: ${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    List<Map<String, dynamic>> registros = [];

    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) registros.add(item);
      }
    } else if (decoded is Map<String, dynamic>) {
      registros.add(decoded);
    }

    // ✅ FILTRAGEM LOCAL: Filtra a lista para incluir apenas a operacaoId desejada.
    final registrosFiltrados = registros.where((registro) {
      return registro['operacaoId'] == AppConfig.operacaoIdFiltro;
    }).toList();

    return registrosFiltrados;
  }
}

/// 3. INTERFACE DO USUÁRIO (WIDGETS)
// **********************************************

class ConsultaMapaProducaoScreen extends StatefulWidget {
  const ConsultaMapaProducaoScreen({super.key});

  @override
  State<ConsultaMapaProducaoScreen> createState() =>
      _ConsultaMapaProducaoScreenState();
}

class _ConsultaMapaProducaoScreenState
    extends State<ConsultaMapaProducaoScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _dataInicialController = TextEditingController();
  final TextEditingController _dataFinalController = TextEditingController();

  bool _loading = false;
  List<MapaResultado> _resultados = [];

  // Variáveis para feedback de progresso
  int _diasTotais = 0;
  int _diasProcessados = 0;
  // Tempo médio de resposta da API (usado para estimativa de tempo)
  static const int _avgApiTimeMs = 3200;

  @override
  void dispose() {
    _dataInicialController.dispose();
    _dataFinalController.dispose();
    super.dispose();
  }

  // --- LÓGICA DE NEGÓCIOS / API ---

  Future<void> _consultar() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final dataInicial = _parseData(_dataInicialController.text.trim());
    final dataFinal = _parseData(_dataFinalController.text.trim());

    if (dataInicial == null ||
        dataFinal == null ||
        dataFinal.isBefore(dataInicial)) {
      _showSnackBar('Verifique o período de datas.', isError: true);
      return;
    }

    final diasTotais = dataFinal.difference(dataInicial).inDays + 1;

    setState(() {
      _loading = true;
      _resultados = [];
      _diasTotais = diasTotais;
      _diasProcessados = 0;
      GlobalState.produtosCache.clear();
      GlobalState.detalhesCache.clear(); // Limpa o novo cache de detalhes
    });

    final startTime = DateTime.now();

    try {
      // 1. AUTENTICAÇÃO WMS (MAPAS)
      final apiKeyWMS = await ApiService.authenticate(
        endpoint: AppConfig.authEndpointWMS,
        email: AppConfig.authEmailWMS,
        senha: AppConfig.authSenhaWMS,
        usuarioId: AppConfig.authUsuarioIdWMS,
      );

      final List<MapaResultado> novosResultados = [];
      final Set<int> produtosIdsParaConsultar = {};

      // 2. CONSULTA SEQUENCIAL DE MAPAS DE PRODUÇÃO POR DIA
      for (
        DateTime data = dataInicial;
        !data.isAfter(dataFinal);
        data = data.add(const Duration(days: 1))
      ) {
        final isoDate = DateFormat("yyyy-MM-dd'T'00:00:00").format(data);

        // Atualiza o dia processado ANTES da chamada da API
        setState(() {
          _diasProcessados = data.difference(dataInicial).inDays;
        });

        final registrosFiltrados = await ApiService.consultarMapaPorData(
          apiKeyWMS: apiKeyWMS,
          isoDate: isoDate,
        );

        if (registrosFiltrados.isNotEmpty) {
          novosResultados.add(
            MapaResultado(data: data, registros: registrosFiltrados),
          );
          // Coleta IDs de produtos únicos
          for (final registro in registrosFiltrados) {
            if (registro['produtoId'] is int) {
              produtosIdsParaConsultar.add(registro['produtoId'] as int);
            }
          }
        }

        // Atualiza o dia processado DEPOIS da chamada da API
        setState(
          () => _diasProcessados = data.difference(dataInicial).inDays + 1,
        );
      }

      // 3. AUTENTICAÇÃO E CONSULTA DE NOMES E DETALHES DE PRODUTOS
      if (produtosIdsParaConsultar.isNotEmpty) {
        // Autenticação Força de Vendas para Produtos
        GlobalState.prodApiKey = await ApiService.authenticate(
          endpoint: AppConfig.authEndpointProd,
          email: AppConfig.authEmailProd,
          senha: AppConfig.authSenhaProd,
          usuarioId: AppConfig.authUsuarioIdProd,
        );

        await ApiService.consultarEArmazenarNomes(produtosIdsParaConsultar);
      }

      // 4. FINALIZAÇÃO
      final totalTime = DateTime.now().difference(startTime).inSeconds;

      setState(() {
        _resultados = novosResultados;
        _diasProcessados = _diasTotais;
      });

      _showSnackBar(
        'Consulta finalizada. ${novosResultados.length} dia(s) com dados). Tempo: ${totalTime}s',
      );
    } catch (e) {
      _showSnackBar('Erro na consulta: ${e.toString()}', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // Funções Utilitárias de UI

  DateTime? _parseData(String value) {
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(value);
    } catch (_) {
      return null;
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade600,
      ),
    );
  }

  // --- WIDGETS DE UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Consultar Mapas'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _buildFormArea(),
              const SizedBox(height: 24),
              Expanded(child: _buildResultsArea()),
            ],
          ),
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
                child: _buildDateField(
                  label: 'Data Inicial',
                  controller: _dataInicialController,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDateField(
                  label: 'Data Final',
                  controller: _dataFinalController,
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
            label: Text(_loading ? 'Consultando...' : 'Consultar Mapas'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField({
    required String label,
    required TextEditingController controller,
  }) {
    Future<void> selectDate() async {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2101),
        locale: const Locale('pt', 'BR'),
        builder: (context, child) {
          return Theme(
            data: ThemeData.light().copyWith(
              colorScheme: ColorScheme.light(
                primary: Colors.red.shade700,
                onPrimary: Colors.white,
                onSurface: Colors.black,
              ),
              buttonTheme: const ButtonThemeData(
                textTheme: ButtonTextTheme.primary,
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
        suffixIcon: const Icon(Icons.calendar_today, color: Colors.grey),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      validator: (value) =>
          value == null || value.isEmpty ? 'Selecione a data' : null,
    );
  }

  Widget _buildResultsArea() {
    if (_loading) {
      return _buildLoadingFeedback();
    }

    if (_resultados.isEmpty) {
      return Center(
        child: Text(
          'Nenhum mapa encontrado para o período informado ou nenhum registro com Operação ID ${AppConfig.operacaoIdFiltro}.',
          style: TextStyle(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      itemCount: _resultados.length,
      itemBuilder: (_, index) {
        final resultado = _resultados[index];
        return _MapaCard(resultado: resultado);
      },
    );
  }

  Widget _buildLoadingFeedback() {
    final progresso = _diasTotais == 0 ? 0.0 : _diasProcessados / _diasTotais;
    final percentual = (progresso * 100).toStringAsFixed(0);

    // Indicador de status atualizado para refletir o dia real sendo processado
    final statusText = _diasProcessados < _diasTotais
        ? 'Consultando dia: ${_diasProcessados + 1} de $_diasTotais'
        : 'Finalizando e buscando detalhes dos produtos...';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Buscando dados. Total de dias no período: $_diasTotais.',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        // Barra de Progresso Linear
        LinearProgressIndicator(
          value: progresso,
          backgroundColor: Colors.grey.shade300,
          color: Colors.red.shade700,
        ),
        const SizedBox(height: 8),
        // Indicador de Progresso (X de Y dias e %)
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
                'Dias: $_diasProcessados de $_diasTotais',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Indicador de status
        Text(
          'Status: $statusText',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        const CircularProgressIndicator(color: Colors.red),
      ],
    );
  }
}

// **********************************************
// 4. CARTÃO DE RESULTADO OTIMIZADO (AJUSTADO)
// **********************************************

class _MapaCard extends StatefulWidget {
  final MapaResultado resultado;

  const _MapaCard({required this.resultado});

  @override
  State<_MapaCard> createState() => _MapaCardState();
}

class _MapaCardState extends State<_MapaCard> {
  bool _isExpanded = false;
  // Formatador para a quantidade (ex: 12.000,50)
  final NumberFormat _quantityFormat = NumberFormat('#,##0.##', 'pt_BR');

  // Formatador para o total (garante 2 casas decimais para metros)
  final NumberFormat _totalFormat = NumberFormat('#,##0.00', 'pt_BR');

  /// Busca o nome do produto no cache global (GlobalState.produtosCache).
  ///
  /// ✅ Retorna null se o ID não for encontrado no cache, indicando
  /// que o item deve ser filtrado (oculto).
  String? _getNomeProduto(int? produtoId) {
    if (produtoId == null) return null; // Sem ID não exibe

    final nomeEmCache = GlobalState.produtosCache[produtoId];

    if (nomeEmCache == null) {
      return null; // Retorna null para itens que não acharam nome (não foram encontrados no estoque)
    }

    return nomeEmCache;
  }

  @override
  Widget build(BuildContext context) {
    final dataFormatada = DateFormat(
      'dd/MM/yyyy',
    ).format(widget.resultado.data);

    // 1. FILTRAR REGISTROS:
    // Critério A: Quantidade > 0
    // Critério B: Nome encontrado no cache (não é nulo)
    final filteredRegistros = widget.resultado.registros.where((registro) {
      final produtoId = registro['produtoId'] as int?;
      final quantidade = registro['quantidade'];

      // Filtro A: Quantidade deve ser maior que zero
      final isQuantityValid = quantidade is num && quantidade > 0;

      // Filtro B: Nome do produto deve ser encontrado
      final isNameFound = _getNomeProduto(produtoId) != null;

      return isQuantityValid && isNameFound;
    }).toList();

    // 2. CALCULAR SOMA TOTAL DA QUANTIDADE (Metros)
    double totalQuantidade = filteredRegistros.fold(0.0, (sum, registro) {
      final quantidade = registro['quantidade'];
      return sum + (quantidade is num ? quantidade : 0.0);
    });

    // 3. FORMATAR TEXTOS
    final totalQuantidadeFormatada = _totalFormat.format(totalQuantidade);
    final totalRegistros = filteredRegistros.length;
    final subtitleText = 'Soma total metros: $totalQuantidadeFormatada';

    // Altura calculada para o conteúdo da lista (Baseado no número de registros FILTRADOS)
    final double contentHeight = totalRegistros * 65.0;

    // Se não houver registros após o filtro, o card não será exibido.
    if (totalRegistros == 0) {
      return const SizedBox.shrink(); // Widget vazio
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 6, // Maior elevação para destaque
      child: ExpansionTile(
        onExpansionChanged: (bool expanded) {
          setState(() {
            _isExpanded = expanded;
          });
        },
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        // Design do Tile Principal
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        collapsedBackgroundColor: Colors.white,
        // Mantido apenas o ícone de data para a quebra principal
        iconColor: Colors.red.shade700,
        collapsedIconColor: Colors.red.shade700,
        leading: Icon(
          Icons.calendar_today,
          color: Colors.red.shade700,
          size: 28,
        ),
        title: Text(
          'Data: $dataFormatada',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.red.shade700,
          ),
        ),
        // Subtítulo exibe a soma total de metros
        subtitle: Text(
          subtitleText,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
        // Conteúdo da Expansão
        children: [
          // Solução para o travamento: Define uma altura fixa para a lista aninhada.
          SizedBox(
            // Define uma altura máxima para o conteúdo (Altura por item * número de itens)
            height: contentHeight,
            child: ListView.builder(
              physics:
                  const NeverScrollableScrollPhysics(), // Evita scroll duplo
              padding: EdgeInsets.zero,
              itemCount: totalRegistros,
              itemBuilder: (context, index) {
                final registro = filteredRegistros[index]; // Usa lista FILTRADA
                final produtoId = registro['produtoId'] as int?;
                final quantidade = registro['quantidade'];

                // Garantido que o nome não será nulo neste ponto devido ao filtro.
                final nomeProduto = _getNomeProduto(produtoId)!;

                // Formata a quantidade para exibição detalhada
                final quantidadeFormatada = quantidade != null
                    ? '(${_quantityFormat.format(quantidade)})'
                    : '(??)';

                return Padding(
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: 8,
                    top: 0,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      // ✅ NOVO: Usamos Row para alinhar lado a lado
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          // Ocupa o espaço restante e permite quebra de linha
                          child: Text(
                            nomeProduto,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // A quantidade fica à direita e não quebra linha
                        Text(
                          quantidadeFormatada,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8), // Espaçamento final
        ],
      ),
    );
  }
}
