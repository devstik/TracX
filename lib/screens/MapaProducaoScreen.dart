import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
// ⚠️ IMPORTAÇÃO CORRIGIDA PARA O FORMATO RELATIVO:
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

  // ✅ NOVO: Mapeamento para converter o NOME do turno para o ID numérico (para o Payload)
  static const Map<String, String> _turnoNomeParaIdMap = {
    'Manhã': '3', // Exemplo de ID
    'Tarde': '4', // Exemplo de ID
    'Noite': '6', // Exemplo de ID
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
    _determinarTurnoAtual(); // ✅ Chama a função para preencher o Turno
  }

  // ✅ NOVO: Função para determinar o turno e preencher o controlador
  void _determinarTurnoAtual() {
    final now = DateTime.now();
    final hour = now.hour;

    String turnoNome;

    // Definição dos turnos com base na hora atual
    // Ajuste as horas conforme a sua necessidade real (os IDs são de exemplo acima)
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

    // 1. Navega para a tela do scanner e espera pelo resultado (usando flutter_zxing)
    final result = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const QrScannerScreen()));

    // 2. Processa o resultado retornado
    if (result != null && result is String && result.isNotEmpty) {
      print('[FLUXO] Resultado do scanner recebido: $result');
      final qrData = _parseQrCodeJson(result);

      if (qrData != null) {
        final String? cdObj = qrData['CdObj']?.toString();

        if (cdObj != null && cdObj.isNotEmpty) {
          print(
            '[FLUXO] CdObj extraído: $cdObj. Será usado como ObjetoID para consulta.',
          );

          // 3. Consulta a API para buscar na lista
          await _consultarDetalheDoObjeto(cdObj);
        } else {
          print('[ERRO_QR] CdObj vazio ou nulo no JSON lido.');
          _showSnackBar(
            'QR Code lido, mas CdObj está vazio ou inválido.',
            isError: true,
          );
        }
      }
    } else {
      print('[FLUXO] Leitura de QR Code cancelada ou sem resultado.');
      _showSnackBar(
        'Leitura de QR Code cancelada ou sem resultado.',
        isError: true,
      );
    }

    setState(() => _loading = false);
  }

  // FUNÇÃO PARA ANALISAR O JSON DO QR CODE (COM CORREÇÃO PARA O ERRO DA ASPA EXTRA)
  Map<String, dynamic>? _parseQrCodeJson(String rawQrCode) {
    String cleanedQrCode = rawQrCode.trim();
    print('CONTEÚDO LIDO: $cleanedQrCode');

    // 💡 WORKAROUND: Tenta corrigir o JSON inválido como: {"CdObj":95857"}
    if (cleanedQrCode.endsWith('"}') && cleanedQrCode.contains(':')) {
      int lastQuoteIndex = cleanedQrCode.lastIndexOf('"');

      // Verifica se a aspa é a penúltima antes do '}' e se há um número antes dela
      if (lastQuoteIndex == cleanedQrCode.length - 2) {
        String potentialNumber = cleanedQrCode.substring(
          cleanedQrCode.lastIndexOf(':') + 1,
          lastQuoteIndex,
        );

        if (int.tryParse(potentialNumber) != null) {
          cleanedQrCode =
              cleanedQrCode.substring(0, lastQuoteIndex) +
              cleanedQrCode.substring(lastQuoteIndex + 1);
          print(
            '[ALERTA_JSON_CORRIGIDO] String QR Code corrigida para: $cleanedQrCode',
          );
        }
      }
    }

    try {
      final decoded = jsonDecode(cleanedQrCode);
      if (decoded is Map<String, dynamic> && decoded.containsKey('CdObj')) {
        return decoded;
      }
      print(
        '[ERRO_JSON] QR Code não contém o formato JSON esperado com chave "CdObj".',
      );
      _showSnackBar(
        'QR Code lido não contém o formato JSON esperado.',
        isError: true,
      );
      return null;
    } catch (e) {
      print('[ERRO_JSON] QR Code lido não é um JSON válido. Erro: $e');
      _showSnackBar('QR Code lido não é um JSON válido.', isError: true);
      return null;
    }
  }

  // FUNÇÃO PARA CONSULTAR O DETALHE NA API (SEM FILTRO NA URL E BUSCANDO NA LISTA)
  Future<void> _consultarDetalheDoObjeto(String cdObj) async {
    final token = await AuthService.obterTokenAplicacao();

    if (token == null) {
      print('[ERRO_TOKEN] Falha na autenticação. Token não obtido.');
      _showSnackBar('Falha na autenticação. Token não obtido.', isError: true);
      return;
    }

    try {
      // 1. Consulta a API sem o objetoID como filtro na URL (consulta ampla)
      final uri = Uri.https(_baseUrl, _consultaEstoquePath, {
        'empresaID': _empresaId,
        // Remove 'objetoID': cdObj, para realizar a consulta completa
      });

      print('[CONSULTA] URI de Consulta: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token', // Envia o token de autenticação
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        print('[CONSULTA] Resposta HTTP 200 recebida.');
        final decoded = jsonDecode(response.body);

        List<dynamic> itens = [];
        if (decoded is List) {
          itens = decoded;
        } else if (decoded is Map<String, dynamic>) {
          // Trata o caso de um único item ser retornado como mapa, transformando em lista
          itens = [decoded];
        }

        // 2. Iterar e procurar o item na lista onde 'objetoID' coincide com o CdObj lido
        final itemData = itens.firstWhere(
          // O critério de busca é item['objetoID'] == cdObj (lido do QR Code)
          (item) =>
              item is Map<String, dynamic> &&
              item['objetoID']?.toString() == cdObj,
          orElse: () => null,
        );

        // 3. Processar o item encontrado
        if (itemData != null && itemData is Map<String, dynamic>) {
          setState(() {
            // Associa os IDs numéricos para o payload final (_salvarMapa)
            _objetoID = itemData['objetoID'] as int?;
            _detalheID = itemData['detalheID'] as int?;

            // Preenche SOMENTE os campos de objeto e detalhe (com a descrição/nome)
            _produtoController.text =
                itemData['objeto']?.toString() ??
                ''; // Objeto (descrição) -> _produtoController
            _loteController.text =
                itemData['detalhe']?.toString() ??
                ''; // Detalhe (descrição) -> _loteController

            // ⚠️ NÃO PREENCHE _unidadeMedidaController e _quantidadeController
          });

          print(
            '[CONSULTA] Dados preenchidos: ObjetoID=$_objetoID, DetalheID=$_detalheID',
          );
          _showSnackBar('Detalhes do objeto carregados com sucesso.');
        } else {
          print('[CONSULTA] Item não encontrado na lista com objetoID=$cdObj.');
          _showSnackBar(
            'Objeto não encontrado na lista retornada pela API com o código $cdObj.',
            isError: true,
          );
        }
      } else {
        print('[ERRO_HTTP] HTTP ${response.statusCode}: ${response.body}');
        _showSnackBar(
          'Erro ${response.statusCode} ao consultar a lista de detalhes.',
          isError: true,
        );
      }
    } catch (e) {
      print('[ERRO_REDE] Falha na consulta de rede: $e');
      _showSnackBar('Falha de rede na consulta: $e', isError: true);
    }
  }

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
            onPressed: _loading
                ? null
                : _iniciarLeituraQrCode, // Chama a função que inicia o scanner
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
                  ),
                  _buildField(
                    label: 'Turno',
                    controller: _turnoController,
                    readOnly:
                        true, // ✅ Adicionado para ser apenas informativo e preenchido
                    // Removido: keyboardType: TextInputType.number,
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
                    // Deixado para preenchimento manual ou outro fluxo
                  ),
                  _buildField(
                    label: 'Objeto',
                    controller: _produtoController,
                    readOnly: true, // Preenchido pela API
                  ),
                  _buildField(
                    label: 'Detalhe',
                    controller: _loteController,
                    readOnly: true, // Preenchido pela API
                  ),
                  _buildField(
                    label: 'Unidade de Medida',
                    controller: _unidadeMedidaController,
                    // Deixado para preenchimento manual ou outro fluxo
                  ),
                  _buildField(
                    label: 'Quantidade',
                    controller: _quantidadeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    // Deixado para preenchimento manual ou outro fluxo
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
    bool readOnly = false,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 380),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        readOnly: readOnly,
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
        // A Ordem de Produção é o único campo não preenchido que deve ser validado
        validator: (value) {
          // A validação agora não exige que Turno, Ordem de Produção ou Quantidade sejam preenchidos
          // se forem preenchidos automaticamente (Turno) ou forem opcionais (outros).
          // Manteremos a validação original do seu código:
          if (controller == _ordemProducaoController ||
              controller == _quantidadeController ||
              controller == _turnoController) {
            return null; // Não exige validação para campos a serem preenchidos pelo usuário
          }
          return value == null || value.isEmpty ? 'Campo obrigatório' : null;
        },
      ),
    );
  }

  Future<void> _consultarMapa() async {
    FocusScope.of(context).unfocus();
    final dataBr = _dataController.text.trim();
    if (dataBr.isEmpty) {
      _showSnackBar('Informe a Data para consultar.', isError: true);
      return;
    }

    final dataIso = _parseDataBrToIso(dataBr);
    if (dataIso == null) {
      _showSnackBar('Data inválida. Use o formato dd/MM/yyyy.', isError: true);
      return;
    }

    setState(() => _loading = true);
    try {
      final uri = Uri.https(_baseUrl, _mapaPath, {
        'empresaID': _empresaId,
        'tipoDeDocumentoID': _tipoDocumentoId,
        'data': dataIso,
      });

      print('[MapaProducao] Consultando: $uri');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List && decoded.isNotEmpty) {
          final first = decoded.first;
          if (first is Map<String, dynamic>) {
            _preencherCampos(first);
            _showSnackBar('Dados carregados com sucesso.');
            print('[MapaProducao] Dados recebidos: $first');
          } else {
            _showSnackBar('Estrutura da lista inesperada.', isError: true);
            print('[MapaProducao][ERRO] Estrutura inesperada: $decoded');
          }
        } else if (decoded is Map<String, dynamic>) {
          _preencherCampos(decoded);
          _showSnackBar('Dados carregados com sucesso.');
          print('[MapaProducao] Dados recebidos: $decoded');
        } else {
          _showSnackBar('Retorno inesperado do servidor.', isError: true);
          print('[MapaProducao][ERRO] Retorno inesperado: $decoded');
        }
      } else {
        print(
          '[MapaProducao][ERRO] HTTP ${response.statusCode}: ${response.body}',
        );
        _showSnackBar(
          'Erro ${response.statusCode} ao consultar o mapa.',
          isError: true,
        );
      }
    } catch (e) {
      print('[MapaProducao][ERRO] Falha na consulta: $e');
      _showSnackBar('Falha na consulta: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _preencherCampos(Map<String, dynamic> data) {
    void setField(TextEditingController controller, List<String> keys) {
      for (final key in keys) {
        if (data.containsKey(key) && data[key] != null) {
          controller.text = data[key].toString();
          return;
        }
      }
    }

    // Mantido para a função _consultarMapa() original, se for usada.
    setField(_dataController, ['data']);
    // Ao consultar, se vier o ID, ele preenche o campo Turno com o ID.
    // Se você sempre quiser o NOME, mesmo após a consulta, é necessário um mapeamento reverso.
    setField(_turnoController, ['turnoId', 'turnoID']);
    setField(_ordemProducaoController, ['ordemProducaoId', 'ordemProducaoID']);
    setField(_produtoController, ['produtoId', 'produtoID']);
    setField(_loteController, ['loteId', 'loteID']);
    setField(_unidadeMedidaController, ['unidadeDeMedida']);
    setField(_quantidadeController, ['quantidade']);
  }

  // FUNÇÃO DE SALVAR
  Future<void> _salvarMapa() async {
    FocusScope.of(context).unfocus();

    // 1. Obtém o NOME do turno preenchido automaticamente (ex: 'Manhã')
    final String turnoNome = _turnoController.text.trim();

    // 2. Tenta obter o ID numérico a partir do nome
    final String? turnoId = _turnoNomeParaIdMap[turnoNome];

    // Validação básica dos campos
    if (_dataController.text.isEmpty ||
        turnoNome
            .isEmpty || // Garante que o campo foi preenchido (automaticamente ou manualmente)
        _ordemProducaoController.text.isEmpty ||
        _unidadeMedidaController.text.isEmpty ||
        _quantidadeController.text.isEmpty) {
      _showSnackBar(
        'Por favor, preencha todos os campos obrigatórios (Data, Turno, Ordem, UM, Quantidade).',
        isError: true,
      );
      return;
    }

    // 3. Validação do ID do Turno
    if (turnoId == null) {
      print(
        '[ERRO_SALVAR] Nome do turno ("$turnoNome") não mapeado para um ID.',
      );
      _showSnackBar(
        'O Turno preenchido é inválido para envio (Nome não encontrado no mapeamento).',
        isError: true,
      );
      return;
    }

    // Verifica se os IDs do produto/detalhe foram obtidos pela consulta do QR Code
    if (_objetoID == null || _detalheID == null) {
      print(
        '[ERRO_SALVAR] IDs de Objeto/Detalhe estão nulos. Consulta falhou?',
      );
      _showSnackBar(
        'Obrigatório ler o QR Code para obter os IDs do Objeto e Detalhe.',
        isError: true,
      );
      return;
    }

    // Tenta validar a quantidade como número
    final double? quantidade = double.tryParse(
      _quantidadeController.text.trim(),
    );
    if (quantidade == null) {
      _showSnackBar('A quantidade informada é inválida.', isError: true);
      return;
    }

    // 4. Monta o payload usando o ID numérico do Turno
    final payload = {
      'empresaId': _empresaId,
      'operacaoId': _operacaoId,
      'tipoDeDocumentoId': _tipoDocumentoId,
      'finalidadeId': _finalidadeId,
      'centroDeCustosId': _centroCustosId,
      'localizacaoId': _localizacaoId,
      'data': _parseDataBrToIso(_dataController.text.trim()) ?? '',
      'turnoId': turnoId, // ✅ USANDO O ID NUMÉRICO
      'ordemProducaoId': _ordemProducaoController.text.trim(),
      // Usando os IDs numéricos OBTIDOS (objetoID e detalheID)
      'produtoId': _objetoID.toString(),
      'loteId': _detalheID.toString(),
      'unidadeDeMedida': _unidadeMedidaController.text.trim(),
      'quantidade': quantidade.toString(), // Usa o valor numérico validado
    };

    print('[SALVAR] Payload preparado para envio: $payload');
    _showSnackBar('Payload pronto para envio, IDs numéricos inclusos.');

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
}
