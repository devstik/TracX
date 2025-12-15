import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
// Note: Certifique-se de que os imports abaixo estão corretos no seu projeto
import '../models/estoque_item.dart';
import '../services/estoque_db_helper.dart';
import '../services/auth_service.dart';

class MapaProducaoScreen extends StatefulWidget {
  const MapaProducaoScreen({super.key});

  @override
  State<MapaProducaoScreen> createState() => _MapaProducaoScreenState();
}

class _MapaProducaoScreenState extends State<MapaProducaoScreen> {
  // --- CONSTANTES DO SISTEMA ---
  static const String _empresaId = '2';
  static const String _tipoDocumentoId = '62';
  static const String _operacaoId = '142';
  static const String _finalidadeId = '7';
  static const String _centroCustosId = '13';
  static const String _localizacaoId = '2026';

  final EstoqueDbHelper _dbHelper = EstoqueDbHelper();
  List<EstoqueItem> _estoqueCache = [];

  static const Map<String, String> _turnoNomeParaIdMap = {
    'Manhã': '3',
    'Tarde': '4',
    'Noite': '6',
  };

  static const String _consultaEstoquePath =
      '/Servidor_2.7.0_api/forcadevendas/lancamentodeestoque/consultar';

  final _formKey = GlobalKey<FormState>();
  final String _baseUrl = 'visions.topmanager.com.br';
  final String _mapaPath =
      '/Servidor_2.7.0_api/logtechwms/itemdemapadeproducao/incluir';
  final String _ordensFabricacaoPath =
      '/Servidor_2.8.0_api/logtechwms/itemdemapadeproducao/ordensdefabricacao';

  // ✅ FLAG DE CONTROLE
  bool _isProcessingScan = false;
  bool _loading = false;
  bool _buscandoOrdemProducao = false;

  // --- CONTROLLERS ---
  final TextEditingController _dataController = TextEditingController();
  final TextEditingController _turnoController = TextEditingController();
  final TextEditingController _ordemProducaoController =
      TextEditingController();
  final TextEditingController _produtoController = TextEditingController();
  final TextEditingController _loteController = TextEditingController();
  final TextEditingController _quantidadeController = TextEditingController();
  final TextEditingController _palletController = TextEditingController();

  // FocusNodes
  final FocusNode _produtoFocusNode = FocusNode(); // <-- Adicionado
  final FocusNode _hardwareScannerFocusNode = FocusNode();
  final TextEditingController _hardwareScannerController =
      TextEditingController();

  int? _objetoID;
  int? _detalheID;

  @override
  void initState() {
    super.initState();
    _dataController.text = DateFormat('dd/MM/yyyy').format(DateTime.now());
    _determinarTurnoAtual();
    _inicializarEstoqueLocal();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_hardwareScannerFocusNode);
        print('[FLUXO] Foco inicial automático aplicado ao campo de scanner.');
        _showSnackBar(
          'PRONTO PARA BIPAR: Pressione o botão físico do coletor.',
          isError: false,
          duration: const Duration(seconds: 3),
        );
      }
    });
  }

  // --- FUNÇÕES DE CONTROLE DE ESTOQUE (SQLite e Cache) ---
  Future<void> _inicializarEstoqueLocal({bool isRetry = false}) async {
    print(
      '[DB] Inicializando Estoque Local: Consultando API e salvando no DB.',
    );
    final token = await AuthService.obterTokenAplicacao();

    if (token == null || await AuthService.isOfflineModeActive()) {
      print(
        '[ERRO_TOKEN] Usando modo OFFLINE. DB não será inicializado pela API.',
      );

      final List<EstoqueItem> itensLocais = await _dbHelper.getAllEstoque();
      if (mounted) {
        setState(() {
          _estoqueCache = itensLocais;
        });
      } else {
        _estoqueCache = itensLocais;
      }
      print(
        '[CACHE] Cache carregado do DB local com ${itensLocais.length} itens.',
      );
      return;
    }

    try {
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

        final List<EstoqueItem> estoqueItens = itensJson
            .where(
              (e) =>
                  e is Map && e['objetoID'] != null && e['detalheID'] != null,
            )
            .map((e) => EstoqueItem.fromMap(e as Map<String, dynamic>))
            .toList();

        await _dbHelper.insertAllEstoque(estoqueItens);
        print(
          '[DB] ${estoqueItens.length} itens de estoque salvos/atualizados no SQLite.',
        );

        if (!mounted) return;

        if (mounted) {
          setState(() {
            _estoqueCache = estoqueItens;
          });
        } else {
          _estoqueCache = estoqueItens;
        }
        print(
          '[CACHE] Cache em memória carregado com ${estoqueItens.length} itens.',
        );
      } else if (response.statusCode == 401 && !isRetry) {
        print(
          '[DB] Token expirado/inválido (401). Forçando renovação e retry...',
        );
        await AuthService.clearToken(); // Chama a função para limpar o token
        await _inicializarEstoqueLocal(isRetry: true); // Tenta novamente
        return;
      } else {
        print(
          '[ERRO_HTTP_INIT] HTTP ${response.statusCode}: Falha ao carregar estoque inicial. ${response.body}',
        );
        if (!mounted) return;
        _showSnackBar(
          'Falha ao carregar estoque inicial (código: ${response.statusCode}).',
          isError: true,
        );
      }
    } catch (e) {
      print('[ERRO_REDE_INIT] Falha na inicialização de rede do estoque: $e');
      if (!mounted) return;
      _showSnackBar(
        'Falha de rede ao carregar o estoque inicial.',
        isError: true,
      );
    }
  }

  EstoqueItem? _consultarDetalheNoCache(int objetoID, String detalheLote) {
    if (_estoqueCache.isEmpty) {
      print('[CACHE] Cache em memória vazio. Tentando consultar DB...');
      return null;
    }

    final int? detalheIDQrCode = int.tryParse(detalheLote);

    for (final item in _estoqueCache) {
      if (item.objetoID != objetoID) {
        continue;
      }

      final String itemDetalheText = item.detalhe.trim().toUpperCase();
      final String qrDetalheText = detalheLote.trim().toUpperCase();

      bool isMatch = false;

      if (detalheIDQrCode != null && item.detalheID == detalheIDQrCode) {
        isMatch = true;
      } else if (itemDetalheText == qrDetalheText) {
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

  Future<void> _consultarDetalheDoObjeto(
    String cdObj, {
    String? detalheQrCode,
  }) async {
    final int? objetoID = int.tryParse(cdObj);

    if (objetoID == null) {
      if (mounted)
        _showSnackBar('Código do Objeto inválido no QR Code.', isError: true);
      return;
    }

    print('[CONSULTA] Iniciando busca por ObjetoID=$objetoID...');

    EstoqueItem? itemObjeto = _estoqueCache.firstWhereOrNull(
      (item) => item.objetoID == objetoID,
    );

    if (itemObjeto == null) {
      print(
        '[CONSULTA] Objeto não achado no Cache de Memória. Buscando no SQLite...',
      );
      itemObjeto = await _dbHelper.getEstoqueItem(objetoID);
    }

    if (itemObjeto == null) {
      print(
        '[CONSULTA] Item ObjetoID=$objetoID NÃO encontrado no cache local/sqlite.',
      );
      _limparCamposObjeto();
      if (mounted) {
        _showSnackBar(
          'Objeto $cdObj não encontrado no estoque local. Verifique se o item existe e se o cache foi atualizado.',
          isError: true,
        );
      }
      return;
    }

    print('[CONSULTA] Item Objeto encontrado: ${itemObjeto.objeto}');

    if (mounted) {
      setState(() {
        _objetoID = itemObjeto!.objetoID;
        // Preenche o controller usado pelo RawAutocomplete
        _produtoController.text = itemObjeto!.objeto;
      });
    }

    if (detalheQrCode != null && detalheQrCode.isNotEmpty) {
      print(
        '[CONSULTA] Detalhe no QR Code: "$detalheQrCode". Buscando no Cache...',
      );

      final EstoqueItem? itemLocalDetalhe = _consultarDetalheNoCache(
        objetoID,
        detalheQrCode,
      );

      if (itemLocalDetalhe != null) {
        await _preencherCamposComDetalhe(itemLocalDetalhe, 'Cache Local');
        if (mounted) {
          _showSnackBar(
            'Detalhes do objeto e lote carregados via Cache Local (Rápido).',
          );
        }
        return;
      }

      print(
        '[FALLBACK] Detalhe não encontrado no cache. Tentando consultar API...',
      );
      final EstoqueItem? itemDaApi = await _consultarDetalheNaApi(
        objetoID,
        detalheQrCode,
      );

      if (itemDaApi != null) {
        await _preencherCamposComDetalhe(itemDaApi, 'API (Fallback)');
        if (mounted)
          _showSnackBar('Detalhes do objeto e lote carregados via API.');
      } else {
        _limparDetalheComErro(objetoID, detalheQrCode);
      }
    } else {
      await _preencherCamposComDetalhe(itemObjeto!, 'Cache (Objeto Padrão)');
      if (mounted)
        _showSnackBar(
          'Detalhes do objeto carregados (Sem Detalhe no QR Code).',
        );
    }

    print('[PREENCHIMENTO FINAL] ObjetoID=$_objetoID, DetalheID=$_detalheID');
  }

  Future<void> _pesquisarObjetoDigitado() async {
    final codigoDigitado = _produtoController.text.trim();
    if (codigoDigitado.isEmpty) {
      _showSnackBar(
        'Informe o código do objeto para pesquisar.',
        isError: true,
      );
      return;
    }

    if (int.tryParse(codigoDigitado) != null) {
      await _consultarDetalheDoObjeto(codigoDigitado);
    } else {
      final item = _estoqueCache.firstWhereOrNull(
        (e) => e.objeto.toLowerCase().contains(codigoDigitado.toLowerCase()),
      );
      if (item != null) {
        await _preencherCamposComDetalhe(item, 'Pesquisa Manual');
      } else {
        _showSnackBar('Objeto não encontrado no cache.', isError: true);
      }
    }
  }

  Future<void> _preencherCamposComDetalhe(
    EstoqueItem item,
    String source,
  ) async {
    if (mounted) {
      setState(() {
        _objetoID = item.objetoID;
        _produtoController.text = item.objeto;
        _detalheID = item.detalheID;
        _loteController.text = item.detalhe;
      });
    } else {
      _objetoID = item.objetoID;
      _produtoController.text = item.objeto;
      _detalheID = item.detalheID;
      _loteController.text = item.detalhe;
    }
    print(
      '[PREENCHIMENTO] Detalhe/Lote VALIDADO por $source - ID: ${item.detalheID}, Texto: ${item.detalhe}',
    );
    await _buscarOrdemProducaoParaObjeto(item.objetoID);
  }

  void _limparDetalheComErro(int objetoID, String detalheQrCode) {
    if (!mounted) return;
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
    if (!mounted) return;
    setState(() {
      _objetoID = null;
      _detalheID = null;
      _produtoController.clear();
      _loteController.clear();
      _ordemProducaoController.clear();
    });
  }

  Future<void> _buscarOrdemProducaoParaObjeto(int objetoID) async {
    final bool isOffline = await AuthService.isOfflineModeActive();
    if (isOffline) {
      if (mounted) {
        _showSnackBar(
          'Modo offline ativo. Não foi possível consultar a Ordem de Produção.',
          isError: true,
        );
      }
      return;
    }

    final token = await AuthService.obterTokenLogtech();
    if (token == null) {
      if (mounted) {
        _showSnackBar(
          'Falha na autenticação ao consultar Ordens de Produção.',
          isError: true,
        );
      }
      return;
    }

    final queryParams = {
      'empresaID': _empresaId,
      'objetoID': objetoID.toString(),
      'dataInicial': _obterPrimeiroDiaDoMesIso(),
    };

    if (mounted) {
      setState(() => _buscandoOrdemProducao = true);
    } else {
      _buscandoOrdemProducao = true;
    }

    try {
      final uri = Uri.https(_baseUrl, _ordensFabricacaoPath, queryParams);
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final dynamic decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : null;
      final List<dynamic> ordens = _normalizarRespostaOrdens(decoded);
      final Iterable<int?> ordensExtraidas =
          ordens.map<int?>((o) => _extrairIdOrdem(o));
      final int? ordemSelecionada = ordensExtraidas.firstWhere(
        (value) => value != null,
        orElse: () => null,
      );

      if (ordemSelecionada != null) {
        _ordemProducaoController.text = ordemSelecionada.toString();
        print(
          '[ORDEM] Ordem de Produção preenchida automaticamente: $ordemSelecionada',
        );
      } else {
        _ordemProducaoController.clear();
        if (mounted) {
          _showSnackBar(
            'Nenhuma Ordem de Produção foi retornada para este objeto.',
            isError: true,
          );
        }
      }
    } catch (e) {
      print('[ERRO_ORDEM] Falha ao buscar ordens de produção: $e');
      if (mounted) {
        _showSnackBar(
          'Erro ao consultar Ordens de Produção. Informe o valor manualmente.',
          isError: true,
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

  String _obterPrimeiroDiaDoMesIso() {
    DateTime referencia = DateTime.now();
    final textoData = _dataController.text.trim();
    if (textoData.isNotEmpty) {
      try {
        referencia = DateFormat('dd/MM/yyyy').parseStrict(textoData);
      } catch (_) {
        // mantém data atual caso parse falhe
      }
    }
    final primeiroDia = DateTime(referencia.year, referencia.month, 1);
    return DateFormat("yyyy-MM-dd'T'00:00:00").format(primeiroDia);
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
    if (item is String) {
      return int.tryParse(item.trim());
    }

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
        final dynamic valor = item[chave];
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

  Future<EstoqueItem?> _consultarDetalheNaApi(
    int objetoID,
    String detalheLote,
  ) async {
    final token = await AuthService.obterTokenAplicacao();

    if (token == null || await AuthService.isOfflineModeActive()) {
      print(
        '[ERRO_TOKEN] Falha na autenticação ou modo offline ativo. Não consulta API.',
      );
      return null;
    }

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
              if (itemJson['objetoID'] != objetoID) {
                continue;
              }

              final int? apiDetalheID = itemJson['detalheID'] is int
                  ? itemJson['detalheID']
                  : int.tryParse(itemJson['detalheID']?.toString() ?? '');
              final String apiDetalheText =
                  (itemJson['detalhe']?.toString() ?? '').trim().toUpperCase();
              final String qrDetalheText = detalheLote.trim().toUpperCase();

              bool isMatch = false;

              if (detalheIDQrCode != null && apiDetalheID == detalheIDQrCode) {
                isMatch = true;
              } else if (apiDetalheText == qrDetalheText) {
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

  void _determinarTurnoAtual() {
    final now = DateTime.now();
    final hour = now.hour;

    String turnoNome;

    if (hour >= 6 && hour < 14) {
      turnoNome = 'Manhã';
    } else if (hour >= 14 && hour < 22) {
      turnoNome = 'Tarde';
    } else {
      turnoNome = 'Noite';
    }

    _turnoController.text = turnoNome;
    print('[TURNO] Turno atual detectado e preenchido: $turnoNome');
  }

  @override
  void dispose() {
    // ⚠️ Disposição de Controllers e FocusNodes
    _dataController.dispose();
    _turnoController.dispose();
    _ordemProducaoController.dispose();
    _produtoController.dispose();
    _loteController.dispose();
    _quantidadeController.dispose();
    _palletController.dispose();
    _hardwareScannerController.dispose();
    _hardwareScannerFocusNode.dispose();
    _produtoFocusNode.dispose(); // <-- Limpeza do novo FocusNode
    super.dispose();
  }

  // FUNÇÃO PARA RE-FOCAR A LEITURA (SIMPLIFICADA)
  Future<void> _reFocarScanner() async {
    // ⚠️ Verifica se já está em processamento
    if (_isProcessingScan) {
      _showSnackBar(
        'Aguarde: Um QR Code já está em processamento.',
        isError: true,
      );
      return;
    }

    FocusScope.of(context).unfocus();

    // Limpa o campo antes de focar para garantir que a próxima leitura seja limpa
    _hardwareScannerController.clear();
    print('[FLUXO] Re-focando campo de scanner. Limpando o valor anterior.');

    // 1. Foca o campo de texto invisível
    FocusScope.of(context).requestFocus(_hardwareScannerFocusNode);

    // 2. Avisa o usuário
    _showSnackBar(
      'PRONTO PARA BIPAR: Campo de leitura re-focado.',
      isError: false,
      duration: const Duration(seconds: 3),
    );
  }

  // FUNÇÃO QUE PROCESSA O RESULTADO INJETADO PELO HARDWARE (Disparado por ENTER ou Plano B)
  void _onHardwareScanSubmitted(String rawQrCode) async {
    // ⚠️ VERIFICAÇÃO DE BLOQUEIO: Garante que não haja execução duplicada
    if (_isProcessingScan) {
      print('[FLUXO] Processo já ativo. Ignorando chamada duplicada.');
      return;
    }

    // 1. Bloqueia o processo e inicia o loading
    if (mounted) {
      setState(() {
        _loading = true;
        _isProcessingScan = true;
      });
    }

    // Garante que o teclado desapareça imediatamente
    FocusScope.of(context).unfocus();

    if (rawQrCode.isEmpty) {
      _showSnackBar(
        'Leitura de QR Code cancelada ou sem resultado.',
        isError: true,
      );
      // O desbloqueio será feito no bloco finally
      return;
    }

    print(
      '[FLUXO] onFieldSubmitted DISPARADO. Resultado do scanner: $rawQrCode',
    );

    try {
      final qrData = _parseQrCodeJson(rawQrCode);

      if (qrData != null) {
        final String? cdObj = qrData['CdObj']?.toString();
        final String? detalheQrCode = qrData['Detalhe']?.toString();

        if (cdObj != null && cdObj.isNotEmpty) {
          await _consultarDetalheDoObjeto(cdObj, detalheQrCode: detalheQrCode);
        } else {
          _showSnackBar(
            'QR Code lido, mas está inválido (CdObj não encontrado).',
            isError: true,
          );
        }
      }
    } catch (e) {
      print('[ERRO_SCANNER] Erro durante o processamento do QR Code: $e');
      if (mounted)
        _showSnackBar(
          'Erro grave ao processar o QR Code. Consulte o log.',
          isError: true,
        );
    } finally {
      // 2. Desbloqueia e limpa (Bloco Finally para segurança)
      if (mounted) {
        // O campo não será mais utilizado após essa limpeza.
        _hardwareScannerController.clear();
        setState(() {
          _loading = false;
          _isProcessingScan = false;
        });
        // Re-foca o scanner para o próximo item
        FocusScope.of(context).requestFocus(_hardwareScannerFocusNode);
      }
    }
  }

  // FUNÇÃO PARA ANALISAR O JSON DO QR CODE
  Map<String, dynamic>? _parseQrCodeJson(String rawQrCode) {
    String cleanedQrCode = rawQrCode.trim();

    // Correção de JSON para casos em que o DataWedge injeta mal a aspa final
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
      if (decoded is Map<String, dynamic> && decoded.containsKey('CdObj')) {
        print('[PARSER] JSON válido encontrado e pronto para consulta.');
        return decoded;
      }
      _showSnackBar(
        'QR Code lido não contém o formato JSON esperado (Falta CdObj).',
        isError: true,
      );
      return null;
    } catch (e) {
      print('[PARSER_ERRO] Falha ao decodificar JSON: $e');
      _showSnackBar(
        'QR Code lido não é um JSON válido. Verifique o formato.',
        isError: true,
      );
      return null;
    }
  }

  // FUNÇÃO DE SALVAR (Mantida)
  Future<void> _salvarMapa() async {
    if (_loading || _isProcessingScan) {
      return;
    }

    final String turnoNome = _turnoController.text.trim();
    final String? turnoIdStr = _turnoNomeParaIdMap[turnoNome];

    if (_ordemProducaoController.text.isEmpty) {
      _showSnackBar(
        'É necessário abrir uma Ordem de Fabricação antes de salvar.',
        isError: true,
      );
      return;
    }

    if (_dataController.text.isEmpty ||
        _quantidadeController.text.isEmpty ||
        _produtoController.text.isEmpty ||
        _loteController.text.isEmpty ||
        _palletController.text.isEmpty) {
      _showSnackBar(
        'Por favor, preencha todos os campos obrigatórios.',
        isError: true,
      );
      return;
    }

    if (turnoIdStr == '6') {
      _showSnackBar(
        'Antes de salvar, verifique se existe um mapa de produção aberto com turno Noite.',
        isError: true,
      );
      return;
    }

    if (turnoIdStr == null) {
      _showSnackBar('O Turno preenchido é inválido para envio.', isError: true);
      return;
    }

    if (_objetoID == null || _detalheID == null) {
      _showSnackBar(
        'Os IDs do Objeto e Detalhe não foram definidos. Selecione um item da lista ou leia o QR Code.',
        isError: true,
      );
      return;
    }

    final double? quantidade = double.tryParse(
      _quantidadeController.text.trim().replaceAll(',', '.'),
    );
    if (quantidade == null) {
      _showSnackBar('A quantidade informada é inválida.', isError: true);
      return;
    }
    final double quantidadeNormalizada = double.parse(
      quantidade.toStringAsFixed(6),
    );

    final String palletTexto = _palletController.text.trim();
    final int? pallet = int.tryParse(palletTexto);
    if (pallet == null) {
      _showSnackBar('O campo Pallet deve ser numérico.', isError: true);
      return;
    }

    final String dataTexto = _dataController.text.trim();
    final String? dataIso = _parseDataBrToIso(dataTexto);
    if (dataIso == null) {
      _showSnackBar('Data inválida para envio/consulta.', isError: true);
      return;
    }

    final bool isOffline = await AuthService.isOfflineModeActive();
    if (isOffline) {
      _showSnackBar(
        'Modo offline ativo. Conecte-se e faça login para enviar ao servidor.',
        isError: true,
      );
      return;
    }

    final token = await AuthService.obterTokenLogtech();

    if (token == null) {
      _showSnackBar(
        'Falha na autenticação. Não é possível salvar na API.',
        isError: true,
      );
      return;
    }

    final int? turnoIdInt = turnoIdStr != null
        ? int.tryParse(turnoIdStr)
        : null;
    if (turnoIdInt == null) {
      _showSnackBar('Turno selecionado inválido.', isError: true);
      return;
    }
    final int? ordemProducaoId = int.tryParse(
      _ordemProducaoController.text.trim(),
    );
    if (ordemProducaoId == null) {
      _showSnackBar('Ordem de Produção inválida.', isError: true);
      return;
    }

    if (mounted) setState(() => _loading = true);

    final payload = {
      'EmpresaID': int.tryParse(_empresaId) ?? 0,
      'OperacaoID': int.tryParse(_operacaoId) ?? 0,
      'TipoDeDocumentoID': int.tryParse(_tipoDocumentoId) ?? 0,
      'FinalidadeID': int.tryParse(_finalidadeId) ?? 0,
      'CentroDeCustosID': int.tryParse(_centroCustosId) ?? 0,
      'LocalizacaoID': int.tryParse(_localizacaoId) ?? 0,
      'Data': dataIso,
      'TurnoID': turnoIdInt,
      'OrdemProducaoID': ordemProducaoId,
      'ProdutoID': _objetoID!,
      'LoteID': _detalheID!,
      'UnidadeMedida': 'MT',
      'Quantidade': quantidadeNormalizada,
      'Pallet': pallet,
    };

    print('[SALVAR] Payload de envio: $payload');
    print('[SALVAR] JSON: ${jsonEncode(payload)}');

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
        if (mounted) {
          _showSnackBar('Mapa de produção salvo com sucesso!');
          // Limpar campos após sucesso, exceto data e turno
          _ordemProducaoController.clear();
          _produtoController.clear();
          _loteController.clear();
          _quantidadeController.clear();
          _palletController.clear();
          _objetoID = null;
          _detalheID = null;
          _reFocarScanner();
        }
        print('[SALVAR] Sucesso: Documento salvo.');
      } else {
        print('[ERRO_SALVAR] HTTP ${response.statusCode}: ${response.body}');
        String extraMensagem = '';
        if (response.body.isNotEmpty) {
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map<String, dynamic>) {
              final erroId = decoded['erro']?.toString() ?? '';
              if (erroId.contains('TbMppFachada_ValorInvalidoExcecao005')) {
                extraMensagem =
                    ' Verifique se existe mapa de produção para esta data.';
              } else if (decoded['Message'] != null) {
                extraMensagem = ' ${decoded['Message']}';
              }
            }
          } catch (_) {
            // Ignora erros de parsing e mantém mensagem extra vazia
          }
        }
        if (mounted) {
          _showSnackBar(
            'Erro ${response.statusCode} ao salvar.$extraMensagem',
            isError: true,
          );
        }
      }
    } catch (e) {
      if (mounted) _showSnackBar('Falha de rede ao salvar: $e', isError: true);
      print('[ERRO_REDE] Falha de rede ao salvar: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnackBar(
    String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade600,
        duration: duration,
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
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // CAMPO DE TEXTO OCULTO PARA RECEBER A LEITURA DO HARDWARE
                  SizedBox(
                    height: 0,
                    width: 0,
                    child: Opacity(
                      opacity: 0,
                      child: TextFormField(
                        controller: _hardwareScannerController,
                        focusNode: _hardwareScannerFocusNode,
                        keyboardType: TextInputType.none,
                        onChanged: (value) {
                          if (value.isNotEmpty) {
                            if (value.endsWith('}') && !_isProcessingScan) {
                              _onHardwareScanSubmitted(value);
                            }
                          }
                        },
                        onFieldSubmitted: _onHardwareScanSubmitted,
                      ),
                    ),
                  ),

                  _buildFormSection(
                    title: 'Informações do Documento',
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
                        readOnly: true,
                      ),
                    ],
                  ),
                  _buildFormSection(
                    title: 'Identificação da Produção',
                    children: [
                      _buildField(
                        label: 'Ordem de Produção',
                        controller: _ordemProducaoController,
                        keyboardType: TextInputType.number,
                        readOnly: true,
                        suffixIcon: _buildOrdemProducaoSuffix(),
                      ),
                      _buildObjetoAutocompleteField(),
                      _buildField(
                        label: 'Detalhe',
                        controller: _loteController,
                      ),
                      _buildField(
                        label: 'Quantidade',
                        controller: _quantidadeController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      _buildField(
                        label: 'Pallet',
                        controller: _palletController,
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_loading || _isProcessingScan)
                          ? null
                          : _salvarMapa,
                      icon: (_loading || _isProcessingScan)
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
                        (_loading || _isProcessingScan)
                            ? 'Consultando/Salvando...'
                            : 'Salvar Mapa',
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    ),
                ]
        ),),),
        ],
      ),
    );
  }

  Widget _buildFormSection({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _buildResponsiveFieldGroup(children),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveFieldGroup(List<Widget> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth;
        final int columns = _resolveColumnCount(availableWidth);
        final double spacing = columns == 1 ? 0 : 16;
        final double targetWidth = columns == 1
            ? availableWidth
            : math.min(
                math.max(
                  (availableWidth - spacing * (columns - 1)) / columns,
                  260,
                ),
                420,
              );

        return Wrap(
          spacing: spacing,
          runSpacing: 16,
          children: fields
              .map(
                (field) => SizedBox(
                  width: targetWidth,
                  child: field,
                ),
              )
              .toList(),
        );
      },
    );
  }

  int _resolveColumnCount(double width) {
    if (width >= 1100) return 3;
    if (width >= 720) return 2;
    return 1;
  }

  Widget? _buildOrdemProducaoSuffix() {
    if (_buscandoOrdemProducao) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ),
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: 'Reconsultar Ordens de Produção',
      onPressed:
          (_objetoID == null) ? null : () => _buscarOrdemProducaoParaObjeto(_objetoID!),
    );
  }

  Widget _buildObjetoAutocompleteField() {
    return RawAutocomplete<EstoqueItem>(
      textEditingController: _produtoController,
      focusNode: _produtoFocusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<EstoqueItem>.empty();
        }
        return _estoqueCache.where((EstoqueItem option) {
          final String input = textEditingValue.text.toLowerCase();
          return option.objeto.toLowerCase().contains(input) ||
              option.detalhe.toLowerCase().contains(input);
        });
      },
      displayStringForOption: (EstoqueItem option) => option.objeto,
      onSelected: (EstoqueItem selection) async {
        await _preencherCamposComDetalhe(selection, 'Autocomplete');
      },
      fieldViewBuilder: (
        BuildContext context,
        TextEditingController controller,
        FocusNode focusNode,
        VoidCallback onFieldSubmitted,
      ) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Objeto',
            hintText: 'Digite código ou nome',
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
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: _pesquisarObjetoDigitado,
            ),
          ),
          validator: (value) {
            return value == null || value.isEmpty ? 'Campo obrigatório' : null;
          },
          onFieldSubmitted: (_) => _pesquisarObjetoDigitado(),
        );
      },
      optionsViewBuilder: (
        BuildContext context,
        AutocompleteOnSelected<EstoqueItem> onSelected,
        Iterable<EstoqueItem> options,
      ) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 380,
              height: 250,
              child: ListView.builder(
                padding: const EdgeInsets.all(8.0),
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final EstoqueItem option = options.elementAt(index);
                  return ListTile(
                    title: Text(
                      option.objeto,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Detalhe/Lote: ${option.detalhe}',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? hint,
    bool readOnly = false,
    TextInputAction? textInputAction,
    void Function(String value)? onFieldSubmitted,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
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
        suffixIcon: suffixIcon,
      ),
      validator: (value) {
        if (controller == _produtoController ||
            controller == _loteController ||
            controller == _dataController ||
            controller == _ordemProducaoController ||
            controller == _quantidadeController ||
            controller == _palletController) {
          return value == null || value.isEmpty ? 'Campo obrigatório' : null;
        }
        return null;
      },
    );
  }
}

// Extensão necessária para o método firstWhereOrNull na lista de EstoqueItem
extension EstoqueListExtensions on List<EstoqueItem> {
  EstoqueItem? firstWhereOrNull(bool Function(EstoqueItem element) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
