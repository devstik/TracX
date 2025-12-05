import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart'; // Importação necessária para o SQLite
// Importações Corrigidas para o formato relativo:
import '../models/estoque_item.dart'; // Certifique-se de que este arquivo existe
import '../services/estoque_db_helper.dart'; // Certifique-se de que este arquivo existe
import '../services/auth_service.dart';
// IMPORTAÇÃO DA NOVA TELA DO LEITOR (usando flutter_zxing)
import 'qr_scanner_screen.dart';

class MapaProducaoScreen extends StatefulWidget {
  const MapaProducaoScreen({super.key});

  @override
  State<MapaProducaoScreen> createState() => _MapaProducaoScreenState();
}

class _MapaProducaoScreenState extends State<MapaProducaoScreen> {
  static const String _empresaId = '2';
  static const String _tipoDocumentoId = '62';
  static const String _operacaoId = '62';
  static const String _finalidadeId = '7';
  static const String _centroCustosId = '13';
  static const String _localizacaoId = '2026';

  // ✅ Instância do DB Helper
  final EstoqueDbHelper _dbHelper = EstoqueDbHelper();

  // ✅ NOVO: Cache do estoque em memória para buscas rápidas
  List<EstoqueItem> _estoqueCache = [];

  // Mapeamento para converter o NOME do turno para o ID numérico (para o Payload)
  static const Map<String, String> _turnoNomeParaIdMap = {
    'Manhã': '3',
    'Tarde': '4',
    'Noite': '6',
  };

  // Endpoint de Consulta para Objeto/Detalhe
  static const String _consultaEstoquePath =
      '/Servidor_2.7.0_api/forcadevendas/lancamentodeestoque/consultar';

  final _formKey = GlobalKey<FormState>();
  final String _baseUrl = 'visions.topmanager.com.br';
  final String _mapaPath =
      '/Servidor_2.8.0_api/logtechwms/itemdemapadeproducao/incluir';
  bool _loading = false;

  final TextEditingController _dataController = TextEditingController();
  final TextEditingController _turnoController = TextEditingController();
  final TextEditingController _ordemProducaoController =
      TextEditingController();
  final TextEditingController _produtoController = TextEditingController();
  final TextEditingController _loteController = TextEditingController();
  final TextEditingController _unidadeMedidaController =
      TextEditingController();
  final TextEditingController _quantidadeController = TextEditingController();

  // Variáveis para armazenar os IDs numéricos para o payload de _salvarMapa
  int? _objetoID;
  int? _detalheID;

  @override
  void initState() {
    super.initState();
    _dataController.text = DateFormat('dd/MM/yyyy').format(DateTime.now());
    _determinarTurnoAtual();
    // ✅ NOVO: Inicia a consulta e cache do estoque ao iniciar a tela
    _inicializarEstoqueLocal();
  }

  // --- FUNÇÕES DE CONTROLE DE ESTOQUE (SQLite e Cache) ---

  // ✅ Função para consultar a API (TUDO) e popular o SQLite (Cache Inicial)
  Future<void> _inicializarEstoqueLocal() async {
    print(
      '[DB] Inicializando Estoque Local: Consultando API e salvando no DB.',
    );
    final token = await AuthService.obterTokenAplicacao();

    if (token == null) {
      print('[ERRO_TOKEN] Falha na autenticação ao inicializar DB.');
      // Continua, mas sem dados de estoque
      return;
    }

    try {
      // 1. Consulta a API sem filtros para obter a lista completa
      final uri = Uri.https(_baseUrl, _consultaEstoquePath, {
        'empresaID': _empresaId,
      });

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> itensJson = [];
        if (decoded is List) {
          itensJson = decoded;
        } else if (decoded is Map<String, dynamic>) {
          itensJson = [decoded];
        }

        // 2. Converte JSON para o modelo EstoqueItem, filtrando nulos
        final List<EstoqueItem> estoqueItens = itensJson
            .where(
              (e) =>
                  e is Map && e['objetoID'] != null && e['detalheID'] != null,
            )
            .map((e) => EstoqueItem.fromMap(e as Map<String, dynamic>))
            .toList();

        // 3. Salva a lista INTEIRA no SQLite
        await _dbHelper.insertAllEstoque(estoqueItens);
        print(
          '[DB] ${estoqueItens.length} itens de estoque salvos/atualizados no SQLite.',
        );

        // ✅ NOVO: Carrega o cache em memória após salvar no DB
        setState(() {
          _estoqueCache = estoqueItens;
        });
        print(
          '[CACHE] Cache em memória carregado com ${_estoqueCache.length} itens.',
        );
      } else {
        print(
          '[ERRO_HTTP_INIT] HTTP ${response.statusCode}: Falha ao carregar estoque inicial. ${response.body}',
        );
        _showSnackBar(
          'Falha ao carregar estoque inicial (código: ${response.statusCode}).',
          isError: true,
        );
      }
    } catch (e) {
      print('[ERRO_REDE_INIT] Falha na inicialização de rede do estoque: $e');
      _showSnackBar(
        'Falha de rede ao carregar o estoque inicial.',
        isError: true,
      );
    }
  }

  // ✅ NOVO: Função para buscar Objeto e Detalhe diretamente no cache em memória (PRIORIDADE)
  EstoqueItem? _consultarDetalheNoCache(int objetoID, String detalheLote) {
    if (_estoqueCache.isEmpty) {
      print('[CACHE] Cache em memória vazio.');
      return null;
    }

    final int? detalheIDQrCode = int.tryParse(detalheLote);

    for (final item in _estoqueCache) {
      // 1. Verifica o ObjetoID
      if (item.objetoID != objetoID) {
        continue;
      }

      // 2. Verifica o Detalhe (ID ou Texto)
      final String itemDetalheText = item.detalhe.trim().toUpperCase();
      final String qrDetalheText = detalheLote.trim().toUpperCase();

      bool isMatch = false;

      if (detalheIDQrCode != null && item.detalheID == detalheIDQrCode) {
        // Match por Detalhe ID
        isMatch = true;
      } else if (itemDetalheText == qrDetalheText) {
        // Match por Texto do Detalhe
        isMatch = true;
      }

      if (isMatch) {
        print('[CACHE] Detalhe/Lote encontrado no cache local.');
        return item;
      }
    }
    print(
      '[CACHE] Detalhe/Lote não encontrado no cache local para ObjetoID=$objetoID.',
    );
    return null;
  }

  // ✅ REVISADO: Função principal de consulta (SQLite > API)
  Future<void> _consultarDetalheDoObjeto(
    String cdObj, {
    String? detalheQrCode,
  }) async {
    final int? objetoID = int.tryParse(cdObj);

    if (objetoID == null) {
      _showSnackBar('Código do Objeto inválido no QR Code.', isError: true);
      return;
    }

    // --- 1. BUSCA DO OBJETO no SQLite (CACHE RÁPIDO) ---
    // Mesmo que só retorne um item, é usado para validar se o ObjetoID existe.
    print('[CONSULTA] Tentando buscar ObjetoID=$objetoID no SQLite...');
    EstoqueItem? itemLocalObjeto = await _dbHelper.getEstoqueItem(objetoID);

    if (itemLocalObjeto == null) {
      print(
        '[CONSULTA] Item ObjetoID=$objetoID NÃO encontrado no cache local.',
      );
      _limparCamposObjeto();
      _showSnackBar(
        'Objeto $cdObj não encontrado no estoque local. Verifique se o item existe e se o cache foi atualizado.',
        isError: true,
      );
      return;
    }

    // Preenche o Objeto (Produto)
    setState(() {
      _objetoID = itemLocalObjeto.objetoID;
      _produtoController.text = itemLocalObjeto.objeto;
    });

    // --- 2. VALIDAÇÃO E BUSCA DO DETALHE (Lote) ---
    if (detalheQrCode != null && detalheQrCode.isNotEmpty) {
      // ✅ 2A. Tenta buscar o detalhe COMPLETO no CACHE (PRIORIDADE)
      final EstoqueItem? itemLocalDetalhe = _consultarDetalheNoCache(
        objetoID,
        detalheQrCode,
      );

      if (itemLocalDetalhe != null) {
        // Encontrado localmente!
        _preencherCamposComDetalhe(itemLocalDetalhe, 'Cache Local');
        _showSnackBar(
          'Detalhes do objeto e lote carregados via Cache Local (Rápido).',
        );
        return; // ✅ TERMINA AQUI se achou localmente
      }

      // ✅ 2B. Não encontrado localmente. Tenta buscar na API (FALLBACK LENTO)
      print(
        '[FALLBACK] Detalhe não encontrado no cache. Tentando consultar API...',
      );
      final EstoqueItem? itemDaApi = await _consultarDetalheNaApi(
        objetoID,
        detalheQrCode,
      );

      if (itemDaApi != null) {
        // Encontrado na API.
        _preencherCamposComDetalhe(itemDaApi, 'API (Fallback)');
        // Opcional: Poderia salvar o novo item no _estoqueCache e DB aqui.
        _showSnackBar('Detalhes do objeto e lote carregados.');
      } else {
        // 2C. Não encontrado na API. Limpa e mostra erro.
        _limparDetalheComErro(objetoID, detalheQrCode);
      }
    } else {
      // D. Se o QR Code NÃO forneceu o Detalhe: Usa o valor do banco de dados (Fallback original)
      _preencherCamposComDetalhe(itemLocalObjeto, 'Cache (Objeto Padrão)');
      _showSnackBar('Detalhes do objeto carregados.');
    }

    print('[PREENCHIMENTO FINAL] ObjetoID=$_objetoID, DetalheID=$_detalheID');
  }

  // Funções Auxiliares de Preenchimento/Limpeza
  void _preencherCamposComDetalhe(EstoqueItem item, String source) {
    setState(() {
      _objetoID = item.objetoID;
      _produtoController.text = item.objeto; // Já deveria estar preenchido
      _detalheID = item.detalheID;
      _loteController.text = item.detalhe;
    });
    print(
      '[PREENCHIMENTO] Detalhe/Lote VALIDADO por $source - ID: ${item.detalheID}, Texto: ${item.detalhe}',
    );
  }

  void _limparDetalheComErro(int objetoID, String detalheQrCode) {
    setState(() {
      _detalheID = null;
      _loteController.clear();
    });
    print(
      '[ERRO] Detalhe/Lote "$detalheQrCode" não encontrado para ObjetoID=$objetoID (Local e API).',
    );
    _showSnackBar(
      'Não foi encontrado o detalhe/lote desse artigo. Campo "Detalhe" limpo.',
      isError: true,
    );
  }

  void _limparCamposObjeto() {
    setState(() {
      _objetoID = null;
      _detalheID = null;
      _produtoController.clear();
      _loteController.clear();
    });
  }

  // ✅ REVISADO: Função para consultar a API (APENAS FALLBACK)
  Future<EstoqueItem?> _consultarDetalheNaApi(
    int objetoID,
    String detalheLote,
  ) async {
    final token = await AuthService.obterTokenAplicacao();

    if (token == null) {
      print('[ERRO_TOKEN] Falha na autenticação ao consultar Detalhe na API.');
      return null;
    }

    // Tenta obter o detalheID se o valor do QR Code for um número
    final int? detalheIDQrCode = int.tryParse(detalheLote);

    try {
      final uri = Uri.https(_baseUrl, _consultaEstoquePath, {
        'empresaID': _empresaId,
        'objetoID': objetoID.toString(),
        'detalhe': detalheLote,
      });

      print(
        '[API] Consultando Detalhe na API (FALLBACK): ObjetoID=$objetoID, Detalhe=$detalheLote',
      );
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> itensJson = [];

        if (decoded is List && decoded.isNotEmpty) {
          itensJson = decoded;
        } else if (decoded is Map<String, dynamic>) {
          itensJson = [decoded];
        }

        if (itensJson.isNotEmpty) {
          for (final itemJson in itensJson) {
            if (itemJson is Map<String, dynamic>) {
              // 1. VERIFICAÇÃO DE OBJETOID: O ObjetoID retornado deve ser o solicitado
              if (itemJson['objetoID'] != objetoID) {
                continue; // Ignora este item
              }

              final int? apiDetalheID = itemJson['detalheID'] is int
                  ? itemJson['detalheID']
                  : int.tryParse(itemJson['detalheID']?.toString() ?? '');
              final String apiDetalheText =
                  (itemJson['detalhe']?.toString() ?? '').trim().toUpperCase();
              final String qrDetalheText = detalheLote.trim().toUpperCase();

              bool isMatch = false;

              // 2. VERIFICAÇÃO DE DETALHE: Prioriza a correspondência por ID
              if (detalheIDQrCode != null && apiDetalheID == detalheIDQrCode) {
                isMatch = true;
              } else if (apiDetalheText == qrDetalheText) {
                // Correspondência pelo TEXTO do Detalhe
                isMatch = true;
              }

              if (isMatch && itemJson['detalheID'] != null) {
                return EstoqueItem.fromMap(itemJson);
              }
            }
          }
        }
        print(
          '[API] Nenhum Detalhe correspondente encontrado na API (Fallback).',
        );
        return null;
      } else {
        print(
          '[ERRO_HTTP_DETALHE] HTTP ${response.statusCode}: Falha ao buscar detalhe específico (API). ${response.body}',
        );
        return null;
      }
    } catch (e) {
      print('[ERRO_REDE_DETALHE] Falha de rede ao buscar detalhe (API): $e');
      return null;
    }
  }

  // --- FUNÇÕES DE UI E OUTROS CONTROLES ---

  // Função para determinar o turno e preencher o controlador
  void _determinarTurnoAtual() {
    final now = DateTime.now();
    final hour = now.hour;

    String turnoNome;

    if (hour >= 6 && hour < 14) {
      turnoNome = 'Manhã'; // ID: 3
    } else if (hour >= 14 && hour < 22) {
      turnoNome = 'Tarde'; // ID: 4
    } else {
      turnoNome = 'Noite'; // ID: 6
    }

    _turnoController.text = turnoNome;
    print('[TURNO] Turno atual detectado e preenchido: $turnoNome');
  }

  @override
  void dispose() {
    _dataController.dispose();
    _turnoController.dispose();
    _ordemProducaoController.dispose();
    _produtoController.dispose();
    _loteController.dispose();
    _unidadeMedidaController.dispose();
    _quantidadeController.dispose();
    super.dispose();
  }

  // FUNÇÃO PARA INICIAR O LEITOR DE QR CODE E PROCESSAR O RESULTADO
  Future<void> _iniciarLeituraQrCode() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    print('[FLUXO] Iniciando leitor de QR Code...');

    final result = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const QrScannerScreen()));

    if (result != null && result is String && result.isNotEmpty) {
      print('[FLUXO] Resultado do scanner recebido: $result');
      final qrData = _parseQrCodeJson(result);

      if (qrData != null) {
        final String? cdObj = qrData['CdObj']?.toString();
        // ✅ NOVO: Captura o campo 'Detalhe' do JSON
        final String? detalheQrCode = qrData['Detalhe']?.toString();

        if (cdObj != null && cdObj.isNotEmpty) {
          // ✅ Chamada correta utilizando o parâmetro nomeado
          await _consultarDetalheDoObjeto(cdObj, detalheQrCode: detalheQrCode);
        } else {
          _showSnackBar('QR Code lido, mas está inválido.', isError: true);
        }
      }
    } else {
      _showSnackBar(
        'Leitura de QR Code cancelada ou sem resultado.',
        isError: true,
      );
    }

    setState(() => _loading = false);
  }

  // FUNÇÃO PARA ANALISAR O JSON DO QR CODE
  Map<String, dynamic>? _parseQrCodeJson(String rawQrCode) {
    String cleanedQrCode = rawQrCode.trim();
    // WORKAROUND: Tenta corrigir o JSON inválido
    if (cleanedQrCode.endsWith('"}') && cleanedQrCode.contains(':')) {
      int lastQuoteIndex = cleanedQrCode.lastIndexOf('"');
      if (lastQuoteIndex == cleanedQrCode.length - 2) {
        String potentialNumber = cleanedQrCode.substring(
          cleanedQrCode.lastIndexOf(':') + 1,
          lastQuoteIndex,
        );

        if (int.tryParse(potentialNumber) != null) {
          cleanedQrCode =
              cleanedQrCode.substring(0, lastQuoteIndex) +
              cleanedQrCode.substring(lastQuoteIndex + 1);
        }
      }
    }

    try {
      final decoded = jsonDecode(cleanedQrCode);
      // Manteve-se a verificação de 'CdObj' como obrigatória para a consulta no banco
      if (decoded is Map<String, dynamic> && decoded.containsKey('CdObj')) {
        return decoded;
      }
      _showSnackBar(
        'QR Code lido não contém o formato JSON esperado.',
        isError: true,
      );
      return null;
    } catch (e) {
      _showSnackBar('QR Code lido não é um JSON válido.', isError: true);
      return null;
    }
  }

  // FUNÇÃO DE SALVAR
  Future<void> _salvarMapa() async {
    FocusScope.of(context).unfocus();

    final String turnoNome = _turnoController.text.trim();
    final String? turnoId = _turnoNomeParaIdMap[turnoNome];

    if (_dataController.text.isEmpty ||
        _ordemProducaoController.text.isEmpty ||
        _unidadeMedidaController.text.isEmpty ||
        _quantidadeController.text.isEmpty ||
        _produtoController.text.isEmpty ||
        _loteController.text.isEmpty) {
      _showSnackBar(
        'Por favor, preencha todos os campos obrigatórios.',
        isError: true,
      );
      return;
    }

    if (turnoId == null) {
      _showSnackBar('O Turno preenchido é inválido para envio.', isError: true);
      return;
    }

    if (_objetoID == null || _detalheID == null) {
      _showSnackBar(
        'Os IDs do Objeto e Detalhe não foram definidos. Obrigatoriamente, leia o QR Code e garanta que o Detalhe/Lote existe.',
        isError: true,
      );
      return;
    }

    final double? quantidade = double.tryParse(
      _quantidadeController.text.trim().replaceAll(',', '.'), // Permite vírgula
    );
    if (quantidade == null) {
      _showSnackBar('A quantidade informada é inválida.', isError: true);
      return;
    }

    final payload = {
      'empresaId': _empresaId,
      'operacaoId': _operacaoId,
      'tipoDeDocumentoId': _tipoDocumentoId,
      'finalidadeId': _finalidadeId,
      'centroDeCustosId': _centroCustosId,
      'localizacaoId': _localizacaoId,
      'data': _parseDataBrToIso(_dataController.text.trim()) ?? '',
      'turnoId': turnoId,
      'ordemProducaoId': _ordemProducaoController.text.trim(),
      'produtoId': _objetoID.toString(),
      'loteId': _detalheID.toString(),
      'unidadeDeMedida': _unidadeMedidaController.text.trim(),
      'quantidade': quantidade.toString(),
    };

    setState(() => _loading = true);
    final token = await AuthService.obterTokenAplicacao();

    if (token == null) {
      setState(() => _loading = false);
      _showSnackBar('Falha na autenticação ao salvar.', isError: true);
      return;
    }

    try {
      final uri = Uri.https(_baseUrl, _mapaPath);

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _showSnackBar('Mapa de produção salvo com sucesso!');
        // Limpar campos
        _ordemProducaoController.clear();
        _unidadeMedidaController.clear();
        _quantidadeController.clear();
        // o fluxo de repetição, como estava no código original.
      } else {
        print('[ERRO_SALVAR] HTTP ${response.statusCode}: ${response.body}');
        _showSnackBar(
          'Erro ${response.statusCode} ao salvar. ${jsonDecode(response.body)['Message'] ?? ''}',
          isError: true,
        );
      }
    } catch (e) {
      _showSnackBar('Falha de rede ao salvar: $e', isError: true);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade600,
      ),
    );
  }

  String? _parseDataBrToIso(String dataBr) {
    try {
      final parsed = DateFormat('dd/MM/yyyy').parseStrict(dataBr);
      return DateFormat("yyyy-MM-dd'T'00:00:00").format(parsed);
    } catch (_) {
      return null;
    }
  }

  // --- WIDGETS DE UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Mapa de Produção'),
        centerTitle: true,
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
            onPressed: _loading ? null : _iniciarLeituraQrCode,
            tooltip: 'Ler QR Code e Consultar Detalhes',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Informações do Documento',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildField(
                    label: 'Data (dd/MM/yyyy)',
                    controller: _dataController,
                    hint: '24/11/2025',
                    keyboardType: TextInputType.datetime,
                    readOnly: false, // Mantido editável (padrão)
                  ),
                  _buildField(
                    label: 'Turno',
                    controller: _turnoController,
                    readOnly: true, // ÚNICO CAMPO NÃO EDITÁVEL
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Identificação da Produção',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildField(
                    label: 'Ordem de Produção',
                    controller: _ordemProducaoController,
                    keyboardType: TextInputType.number,
                    readOnly: false, // Editável
                  ),
                  _buildField(
                    label: 'Objeto',
                    controller: _produtoController,
                    readOnly:
                        false, // AGORA EDITÁVEL (Removido 'readOnly: true')
                  ),
                  _buildField(
                    label: 'Detalhe',
                    controller: _loteController,
                    readOnly:
                        false, // AGORA EDITÁVEL (Removido 'readOnly: true')
                  ),
                  _buildField(
                    label: 'Unidade de Medida',
                    controller: _unidadeMedidaController,
                    readOnly: false, // Editável
                  ),
                  _buildField(
                    label: 'Quantidade',
                    controller: _quantidadeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    readOnly: false, // Editável
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _salvarMapa,
                  icon: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _loading ? 'Consultando/Salvando...' : 'Salvar Mapa',
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? hint,
    bool readOnly = false, // Padrão 'false' para permitir edição
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 380),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        readOnly:
            readOnly, // Usa o valor passado, que é 'true' apenas para o Turno
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        // A validação de Objeto/Detalhe agora só verifica se estão vazios,
        // mas o salvamento ainda exige os IDs (_objetoID e _detalheID)
        // obtidos pelo QR Code.
        validator: (value) {
          if (controller == _produtoController ||
              controller == _loteController ||
              controller == _dataController ||
              controller == _ordemProducaoController ||
              controller == _unidadeMedidaController ||
              controller == _quantidadeController) {
            return value == null || value.isEmpty ? 'Campo obrigatório' : null;
          }
          return null;
        },
      ),
    );
  }
}
