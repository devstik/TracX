import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tracx/models/registro.dart';
import 'package:tracx/services/movimentacao_service.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:tracx/screens/qr_scanner_screen.dart';
import 'package:tracx/services/datawedge_service.dart';

// =========================================================================
// PALETA OFICIAL (PADRAO HOME + SPLASH)
// =========================================================================
const Color _kPrimaryColor = Color(0xFFD8B840);
const Color _kAccentColor = Color(0xFFE8CE7A);

const Color _kBgTop = Color(0xFF020617);
const Color _kBgBottom = Color(0xFF0F172A);

const Color _kSurface = Color(0xFF111827);
const Color _kSurface2 = Color(0xFF172033);
const Color _kSurface3 = Color(0xFF1E293B);

const Color _kTextPrimary = Color(0xFFF8FAFC);
const Color _kTextSecondary = Color(0xFFCBD5E1);

// borda mais visivel
const Color _kBorderSoft = Color(0xFF334155);

class Localizacaoscreen extends StatefulWidget {
  final String conferente;
  final bool isAdmin;

  const Localizacaoscreen({
    super.key,
    required this.conferente,
    required this.isAdmin,
  });

  @override
  _LocalizacaoscreenState createState() => _LocalizacaoscreenState();
}

class _LocalizacaoscreenState extends State<Localizacaoscreen>
    with SingleTickerProviderStateMixin {
  static const String _ADMIN_MOVE_PASSWORD = 'admin123456';

  late TabController _tabController;

  String _searchQuery = '';
  DateTime? _filterDate;
  final Map<String, double> _mapaGramaturas = {};

  final Map<String, Future<List<Registro>>> _futureMap = {};
  Timer? _tempoNaMaquinaTimer;

  static const Map<String, int> _locOrder = {
    'Mesas': 3,
    'Imatecs': 4,
    'Imatec 01': 4,
    'Imatec 02': 4,
    'Imatec 03': 4,
    'Imatec 04': 4,
    'Imatec 05': 4,
    'Imatec 06': 4,
    'Imatec 07': 4,
    'Imatec 08': 4,
    'Imatec 09': 4,
    'Imatec 10': 4,
    'Imatec 11': 4,
    'Imatec 12': 4,
    'Imatec 13': 4,
    'Controle de Qualidade': 5,
    'Apontamento': 6,
    'Túnel': 7,
    'Expedição': 8,
  };

  static const Map<String, String> _tabToFullLoc = {
    'Loc 3': 'Mesas',
    'Loc 4': 'Imatecs',
    'Imatecs': 'Imatec Maq',
    'Loc 5': 'Controle de Qualidade',
    'Loc 6': 'Apontamento',
    'Loc 7': 'Túnel',
    'Loc 8': 'Expedição',
  };

  static const Map<String, String> _tabLabels = {
    'Loc 3': 'Mesas',
    'Loc 4': 'Espera',
    'Imatecs': 'Imatecs',
    'Loc 5': 'Qualidade',
    'Loc 6': 'Apontamento',
    'Loc 7': 'Túnel',
    'Loc 8': 'Expedição',
  };

  static const Map<String, IconData> _tabIcons = {
    'Loc 3': Icons.table_bar_rounded,
    'Loc 4': Icons.pending_actions_rounded,
    'Imatecs': Icons.precision_manufacturing_rounded,
    'Loc 5': Icons.verified_rounded,
    'Loc 6': Icons.assignment_turned_in_rounded,
    'Loc 7': Icons.local_fire_department_rounded,
    'Loc 8': Icons.local_shipping_rounded,
  };

  static const List<String> _tabNames = [
    'Loc 3',
    'Loc 4',
    'Imatecs',
    'Loc 5',
    'Loc 6',
    'Loc 7',
    'Loc 8',
  ];

  static const List<String> _allLocations = [
    'Mesas',
    'Imatecs',
    'Imatec 01',
    'Imatec 02',
    'Imatec 03',
    'Imatec 04',
    'Imatec 05',
    'Imatec 06',
    'Imatec 07',
    'Imatec 08',
    'Imatec 09',
    'Imatec 10',
    'Imatec 11',
    'Imatec 12',
    'Imatec 13',
    'Controle de Qualidade',
    'Apontamento',
    'Túnel',
    'Expedição',
  ];

  static const List<String> _imatecLocations = [
    'Imatec 01',
    'Imatec 02',
    'Imatec 03',
    'Imatec 04',
    'Imatec 05',
    'Imatec 06',
    'Imatec 07',
    'Imatec 08',
    'Imatec 09',
    'Imatec 10',
    'Imatec 11',
    'Imatec 12',
    'Imatec 13',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabNames.length, vsync: this);
    _tempoNaMaquinaTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _tabNames[_tabController.index] == 'Imatecs') {
        setState(() {});
      }
    });

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tempoNaMaquinaTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<List<Registro>> _getFutureForTab(String tabLocation) {
    if (!_futureMap.containsKey(tabLocation)) {
      _futureMap[tabLocation] = _buscarRegistrosPorLocalizacao(tabLocation);
    }
    return _futureMap[tabLocation]!;
  }

  void _reloadAllFutures() {
    _futureMap.clear();
    setState(() {});
  }

  double _parseDoubleLocal(dynamic valor) {
    final texto = (valor ?? '').toString().trim();
    if (texto.isEmpty) return 0.0;
    var normalizado = texto.replaceAll(RegExp(r'\s+'), '');
    if (normalizado.contains(',') && normalizado.contains('.')) {
      normalizado = normalizado.replaceAll('.', '').replaceAll(',', '.');
    } else {
      normalizado = normalizado.replaceAll(',', '.');
    }
    return double.tryParse(normalizado) ?? 0.0;
  }

  String _descricaoProduto(String artigo, String cor) {
    final artigoLimpo = artigo.trim();
    final corLimpa = cor.trim();
    if (artigoLimpo.isEmpty) return corLimpa;
    if (corLimpa.isEmpty) return artigoLimpo;
    return '$artigoLimpo $corLimpa';
  }

  String _normalizarTextoFiltro(dynamic valor) {
    final texto = (valor ?? '').toString().trim().toLowerCase();
    if (texto.isEmpty) return '';
    return texto
        .replaceAll(RegExp(r'[áàãâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòõôö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _textoContemTodosTokens(String texto, String filtro) {
    final base = _normalizarTextoFiltro(texto);
    final tokens = _normalizarTextoFiltro(
      filtro,
    ).split(' ').where((token) => token.isNotEmpty);
    return tokens.every(base.contains);
  }

  Future<void> _garantirMapaGramaturas() async {
    if (_mapaGramaturas.isNotEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('http://168.190.90.2:5000/consulta/allArtigos'),
      );
      if (response.statusCode != 200) return;
      final List<dynamic> dados = jsonDecode(response.body);
      for (final item in dados) {
        if (item is! Map) continue;
        final artigo = _normalizarTextoFiltro(item['Artigo']);
        final gramatura = _parseDoubleLocal(item['Gramatura']);
        if (artigo.isNotEmpty && gramatura > 0) {
          _mapaGramaturas[artigo] = gramatura;
        }
      }
    } catch (_) {}
  }

  double _metrosDoRegistroJson(Map<String, dynamic> jsonItem) {
    final metrosApi = _parseDoubleLocal(jsonItem['Metros']);
    if (metrosApi > 0) return metrosApi;

    final artigo = (jsonItem['Artigo'] ?? '').toString();
    final cor = (jsonItem['Cor'] ?? '').toString();
    final artigoCompleto = _descricaoProduto(artigo, cor);
    final gramatura = _mapaGramaturas[_normalizarTextoFiltro(artigoCompleto)];
    final peso = _parseDoubleLocal(jsonItem['Peso']);
    if (gramatura == null || gramatura <= 0 || peso <= 0) return metrosApi;
    return (peso * 1000) / gramatura;
  }

  DateTime? _parseDataApi(dynamic valor) {
    final texto = (valor ?? '').toString().trim();
    if (texto.isEmpty || texto.toLowerCase() == 'null') return null;
    try {
      return DateTime.parse(texto);
    } catch (_) {
      try {
        return DateFormat('dd/MM/yyyy HH:mm:ss').parseLoose(texto);
      } catch (_) {
        try {
          return DateFormat('dd/MM/yyyy HH:mm').parseLoose(texto);
        } catch (_) {
          return null;
        }
      }
    }
  }

  DateTime _dataEntradaFromJson(Map<String, dynamic> jsonItem) {
    return _parseDataApi(
          jsonItem['DataEntrada'] ??
              jsonItem['dataEntrada'] ??
              jsonItem['data_entrada'] ??
              jsonItem['Data'],
        ) ??
        DateTime.now();
  }

  DateTime? _dataMovimentacaoFromJson(
    Map<String, dynamic> jsonItem, {
    DateTime? fallbackAtivo,
  }) {
    return _parseDataApi(
          jsonItem['DataMovimentacao'] ??
              jsonItem['dataMovimentacao'] ??
              jsonItem['data_movimentacao'] ??
              jsonItem['DataSaida'] ??
              jsonItem['dataSaida'] ??
              jsonItem['data_saida'] ??
              jsonItem['DtMovimentacao'] ??
              jsonItem['DataHoraMovimentacao'],
        ) ??
        fallbackAtivo;
  }

  bool _registroPassaFiltroLocal(Registro registro) {
    if (_filterDate != null) {
      final dataBase = (registro.dataMovimentacao ?? registro.data).toLocal();
      if (dataBase.year != _filterDate!.year ||
          dataBase.month != _filterDate!.month ||
          dataBase.day != _filterDate!.day) {
        return false;
      }
    }

    if (_searchQuery.trim().isEmpty) return true;
    final texto = [
      registro.ordemProducao,
      registro.artigo,
      registro.cor,
      registro.conferente,
      registro.turno,
      registro.numCorte,
      registro.caixa,
      registro.localizacao,
      registro.bocaImatec,
    ].join(' ');
    return _textoContemTodosTokens(texto, _searchQuery);
  }

  Color _getTabColor(String tabLocation) {
    // Mantendo cores por aba no padrao visual da tela
    switch (tabLocation) {
      case 'Loc 3':
        return const Color(0xFF22C55E);
      case 'Loc 4':
        return const Color(0xFFF97316);
      case 'Imatecs':
        return const Color(0xFFFB923C);
      case 'Loc 5':
        return const Color(0xFF38BDF8);
      case 'Loc 6':
        return const Color(0xFFD8B840);
      case 'Loc 7':
        return const Color(0xFFA855F7);
      case 'Loc 8':
        return const Color(0xFF14B8A6);
      default:
        return _kPrimaryColor;
    }
  }

  Future<bool> _verifyPassword(String username, String password) async {
    if (!widget.isAdmin) {
      return false;
    }
    return password == _ADMIN_MOVE_PASSWORD;
  }

  Future<List<Registro>> _buscarRegistrosPorLocalizacao(
    String tabLocation,
  ) async {
    final targetLocation = _tabToFullLoc[tabLocation];
    if (targetLocation == null) return [];

    await _garantirMapaGramaturas();

    if (targetLocation == 'Imatec Maq') {
      return _buscarRegistrosImatecs();
    }

    final dataFormatada = _filterDate != null
        ? DateFormat('yyyy-MM-dd').format(_filterDate!)
        : null;

    try {
      final queryParams = <String, String>{};
      queryParams['localizacao'] = targetLocation;

      if (_searchQuery.isNotEmpty) {
        queryParams['filtro'] = _searchQuery;
      }

      if (dataFormatada != null) {
        queryParams['data'] = dataFormatada;
      }

      final uri = Uri.parse(
        'http://168.190.90.2:5000/consulta/movimentacao',
      ).replace(queryParameters: queryParams);

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);

        final lista = jsonList.map((jsonItem) {
          final item = Map<String, dynamic>.from(jsonItem as Map);
          final dataEntrada = _dataEntradaFromJson(item);
          final localizacao = (jsonItem['Localizacao'] ?? '').toString();
          return Registro(
            id: jsonItem['ID'] is int
                ? jsonItem['ID']
                : int.tryParse(jsonItem['ID']?.toString() ?? ''),
            ordemProducao: jsonItem['NrOrdem'] ?? 0,
            artigo: jsonItem['Artigo'] ?? '',
            cor: jsonItem['Cor'] ?? '',
            quantidade: jsonItem['Quantidade'] ?? 0,
            peso: _parseDoubleLocal(jsonItem['Peso']),
            conferente: jsonItem['Conferente'] ?? '',
            turno: jsonItem['Turno'] ?? '',
            metros: _metrosDoRegistroJson(item),
            numCorte: jsonItem['NumCorte'] ?? '',
            volumeProg: _parseDoubleLocal(jsonItem['VolumeProg']),
            data: dataEntrada,
            dataTingimento: jsonItem['DataTingimento'] ?? '',
            localizacao: localizacao,
            dataMovimentacao: _dataMovimentacaoFromJson(
              item,
              fallbackAtivo: _isImatecLocation(localizacao)
                  ? dataEntrada
                  : null,
            ),
            caixa: jsonItem['Caixa'] ?? '',
            bocaImatec: _bocaImatecFromJson(item),
          );
        }).where(_registroPassaFiltroLocal).toList();

        // MAIS RECENTES PRIMEIRO
        lista.sort((a, b) {
          final da = a.dataMovimentacao ?? a.data;
          final db = b.dataMovimentacao ?? b.data;
          return db.compareTo(da);
        });

        return lista;
      } else {
        throw Exception(
          'Falha ao buscar registros da API: ${response.statusCode}',
        );
      }
    } catch (e) {
      return [];
    }
  }

  Future<List<Registro>> _buscarRegistrosImatecs() async {
    final futures = _imatecLocations
        .map((loc) => _buscarRegistrosPorLocalizacaoDireta(loc))
        .toList();
    final results = await Future.wait(futures);
    final registros = results.expand((items) => items).toList();
    registros.sort((a, b) {
      final da = a.dataMovimentacao ?? a.data;
      final db = b.dataMovimentacao ?? b.data;
      return db.compareTo(da);
    });
    return registros;
  }

  Future<List<Registro>> _buscarRegistrosPorLocalizacaoDireta(
    String targetLocation,
  ) async {
    await _garantirMapaGramaturas();
    final dataFormatada = _filterDate != null
        ? DateFormat('yyyy-MM-dd').format(_filterDate!)
        : null;

    try {
      final queryParams = <String, String>{'localizacao': targetLocation};

      if (_searchQuery.isNotEmpty) {
        queryParams['filtro'] = _searchQuery;
      }

      if (dataFormatada != null) {
        queryParams['data'] = dataFormatada;
      }

      final uri = Uri.parse(
        'http://168.190.90.2:5000/consulta/movimentacao',
      ).replace(queryParameters: queryParams);

      final response = await http.get(uri);
      if (response.statusCode != 200) return [];

      final List<dynamic> jsonList = jsonDecode(response.body);
      return jsonList.map((jsonItem) {
        final item = Map<String, dynamic>.from(jsonItem as Map);
        final dataEntrada = _dataEntradaFromJson(item);
        final localizacao = (jsonItem['Localizacao'] ?? targetLocation)
            .toString();
        return Registro(
          id: jsonItem['ID'] is int
              ? jsonItem['ID']
              : int.tryParse(jsonItem['ID']?.toString() ?? ''),
          ordemProducao: jsonItem['NrOrdem'] ?? 0,
          artigo: jsonItem['Artigo'] ?? '',
          cor: jsonItem['Cor'] ?? '',
          quantidade: jsonItem['Quantidade'] ?? 0,
          peso: _parseDoubleLocal(jsonItem['Peso']),
          conferente: jsonItem['Conferente'] ?? '',
          turno: jsonItem['Turno'] ?? '',
          metros: _metrosDoRegistroJson(item),
          numCorte: jsonItem['NumCorte'] ?? '',
          volumeProg: _parseDoubleLocal(jsonItem['VolumeProg']),
          data: dataEntrada,
          dataTingimento: jsonItem['DataTingimento'] ?? '',
          localizacao: localizacao,
          dataMovimentacao: _dataMovimentacaoFromJson(
            item,
            fallbackAtivo: _isImatecLocation(localizacao) ? dataEntrada : null,
          ),
          caixa: jsonItem['Caixa'] ?? '',
          bocaImatec: _bocaImatecFromJson(item),
        );
      }).where(_registroPassaFiltroLocal).toList();
    } catch (_) {
      return [];
    }
  }

  List<String> _getValidNextOptions(String? currentLocation) {
    if (currentLocation == 'Mesas') {
      return ['Imatecs'];
    } else if (currentLocation == 'Imatecs') {
      return [];
    } else if (_isImatecLocation(currentLocation)) {
      return ['Controle de Qualidade', 'Apontamento'];
    } else if (currentLocation == 'Controle de Qualidade') {
      return ['Apontamento'];
    } else if (currentLocation == 'Apontamento') {
      return ['Túnel'];
    } else if (currentLocation == 'Túnel') {
      return ['Expedição'];
    }
    return [];
  }

  String? _getValidPreviousLocation(String? currentLocation) {
    if (currentLocation == 'Expedição') {
      return 'Túnel';
    } else if (currentLocation == 'Túnel') {
      return 'Apontamento';
    } else if (currentLocation == 'Apontamento') {
      return 'Imatecs';
    } else if (currentLocation == "Controle de Qualidade") {
      return 'Imatecs';
    } else if (_isImatecLocation(currentLocation)) {
      return 'Imatecs';
    } else if (currentLocation == 'Imatecs') {
      return 'Mesas';
    }
    return null;
  }

  bool _isImatecLocation(String? location) {
    if (location == null) return false;
    return _imatecLocations.contains(location.trim());
  }

  bool _requiresImatecCheckin(String? location) {
    return location == 'Imatecs';
  }

  String? _imatecFromQr(String qrCode) {
    final raw = qrCode.trim();
    if (raw.isEmpty) return null;

    if (!raw.startsWith('{') || !raw.endsWith('}')) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final tipo = decoded['tipo']?.toString().trim();
      final validacao = decoded['validacao']?.toString().trim();
      final fluxo = decoded['fluxo']?.toString().trim();
      if (tipo != 'TRACX_IMATEC_CHECKIN' ||
          validacao != 'TRACX_IMATEC_V1' ||
          fluxo != 'LOCALIZACAO_IMATEC') {
        return null;
      }

      final numero = decoded['numero'] is num
          ? (decoded['numero'] as num).toInt()
          : int.tryParse(decoded['numero']?.toString() ?? '');
      final imatec = decoded['imatec']?.toString().trim();
      if (numero == null || numero < 1 || numero > 13) return null;
      final esperado = 'Imatec ${numero.toString().padLeft(2, '0')}';
      if (imatec != esperado) return null;
      return esperado;
    } catch (_) {
      return null;
    }
  }

  String _formatarTempoNaLocalizacao(DateTime? dataMovimentacao) {
    if (dataMovimentacao == null) return 'Sem horário';
    final diff = DateTime.now().difference(dataMovimentacao.toLocal());
    if (diff.inMinutes < 1) return 'Agora';
    if (diff.inHours < 1) return '${diff.inMinutes} min';
    if (diff.inDays < 1) {
      final minutos = diff.inMinutes.remainder(60);
      return minutos == 0
          ? '${diff.inHours} h'
          : '${diff.inHours} h ${minutos} min';
    }
    final horas = diff.inHours.remainder(24);
    return horas == 0 ? '${diff.inDays} d' : '${diff.inDays} d ${horas} h';
  }

  String? _bocaImatecFromJson(Map<String, dynamic> json) {
    final direta =
        json['BocaImatec'] ??
        json['bocaImatec'] ??
        json['Boca'] ??
        json['boca'];
    final diretaTexto = direta?.toString().trim();
    if (diretaTexto != null && diretaTexto.isNotEmpty) return diretaTexto;

    final observacao = (json['Observacao'] ?? json['observacao'])
        ?.toString()
        .trim();
    if (observacao == null || observacao.isEmpty) return null;

    final match = RegExp(
      r'Boca\s+Imatec:\s*([^|]+)',
      caseSensitive: false,
    ).firstMatch(observacao);
    return match?.group(1)?.trim();
  }

  Future<void> _updateRegistroLocationCompleta(
    Registro registro,
    String newLocation,
  ) async {
    try {
      final localizacaoOrigem = registro.localizacao ?? 'N/A';
      final isRollback =
          _locOrder[newLocation]! < _locOrder[registro.localizacao]!;
      final isAdminMove =
          _locOrder[newLocation]! > _locOrder[registro.localizacao]! &&
          !_getValidNextOptions(registro.localizacao).contains(newLocation);

      String tipoMovimentacao;
      if (isRollback) {
        tipoMovimentacao = 'ROLLBACK';
      } else if (isAdminMove) {
        tipoMovimentacao = 'ADMIN';
      } else {
        tipoMovimentacao = 'NORMAL';
      }

      final dataMovimentacao = DateTime.now();

      final sucesso = await MovimentacaoService.registrarMovimentacaoCompleta(
        idRegistro: registro.id,
        idPedido: registro.ordemProducao,
        localizacaoOrigem: localizacaoOrigem,
        localizacaoDestino: newLocation,
        conferente: widget.conferente,
        dataMovimentacao: dataMovimentacao,
        tipoMovimentacao: tipoMovimentacao,
      );

      if (!sucesso) {
        throw Exception(
          'Falha ao registrar movimentação completa no servidor.',
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pedido ${registro.ordemProducao} movido completo para $newLocation!',
          ),
          backgroundColor: _kPrimaryColor,
        ),
      );

      _reloadAllFutures();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar registro completo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handlePartialMove(
    Registro registro,
    String newLocation,
    double metrosMovidos,
  ) async {
    try {
      if ((registro.metros ?? 0.0) < metrosMovidos) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro: Metros a mover maior que o total do pedido.'),
            backgroundColor: Color(0xFFF97316),
          ),
        );
        return;
      }

      final localizacaoOrigem = registro.localizacao ?? 'N/A';
      const tipoMovimentacao = 'PARCIAL';
      final dataMovimentacao = DateTime.now();

      final sucesso = await MovimentacaoService.registrarMovimentacaoParcial(
        idRegistro: registro.id,
        idPedido: registro.ordemProducao,
        localizacaoOrigem: localizacaoOrigem,
        localizacaoDestino: newLocation,
        conferente: widget.conferente,
        dataMovimentacao: dataMovimentacao,
        tipoMovimentacao: tipoMovimentacao,
        metrosMovidos: metrosMovidos,
      );

      if (!sucesso) {
        throw Exception('Falha ao registrar movimentação parcial no servidor.');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pedido ${registro.ordemProducao}: $metrosMovidos m movidos parcialmente para $newLocation!',
          ),
          backgroundColor: const Color(0xFF14B8A6),
        ),
      );

      _reloadAllFutures();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar registro parcial: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showParcialMoveDialog(Registro registro, String nextLoc) async {
    final metrosController = TextEditingController();
    final double maxMetros = registro.metros ?? 0.0;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _kSurface,
          surfaceTintColor: _kSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Mover parcialmente - OP ${registro.ordemProducao}',
            style: const TextStyle(color: _kTextPrimary),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Localização: ${registro.localizacao ?? 'N/A'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _kTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kSurface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBorderSoft),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.straighten,
                        size: 18,
                        color: _kAccentColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Total disponível: ${maxMetros.toStringAsFixed(3)} m',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _kTextPrimary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Destino: $nextLoc',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _kAccentColor,
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: metrosController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(color: _kTextPrimary),
                  decoration: InputDecoration(
                    labelText: 'Metros a mover',
                    labelStyle: const TextStyle(color: _kTextSecondary),
                    hintText: 'Ex: ${(maxMetros / 2).toStringAsFixed(3)}',
                    hintStyle: TextStyle(
                      color: _kTextSecondary.withOpacity(0.7),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kBorderSoft),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kAccentColor),
                    ),
                    suffixText: 'm',
                    suffixStyle: const TextStyle(color: _kTextSecondary),
                    prefixIcon: const Icon(
                      Icons.straighten,
                      color: _kAccentColor,
                    ),
                    helperText: 'Máx: ${maxMetros.toStringAsFixed(3)} m',
                    helperStyle: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: _kTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: _kTextSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final metrosText = metrosController.text.replaceAll(',', '.');
                final metrosMovidos = double.tryParse(metrosText) ?? 0.0;

                if (metrosMovidos <= 0.0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Digite um valor válido em metros.'),
                      backgroundColor: Color(0xFFF97316),
                    ),
                  );
                  return;
                }

                if (metrosMovidos > maxMetros) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'O valor de $metrosMovidos m excede o total disponível de ${maxMetros.toStringAsFixed(3)} m.',
                      ),
                      backgroundColor: const Color(0xFFF97316),
                    ),
                  );
                  return;
                }

                Navigator.pop(context);
                _handlePartialMove(registro, nextLoc, metrosMovidos);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryColor,
                foregroundColor: const Color(0xFF020617),
              ),
              child: const Text('Mover parcialmente'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleRollback(Registro registro, String previousLoc) async {
    final confirmAction = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kSurface,
        surfaceTintColor: _kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirmar retorno do pedido',
          style: TextStyle(color: _kTextPrimary),
        ),
        content: Text(
          'Ao retornar o pedido ${registro.ordemProducao}, ele será movido para $previousLoc. Deseja continuar?',
          style: const TextStyle(color: _kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: _kTextSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Retornar',
              style: TextStyle(color: Color(0xFFF97316)),
            ),
          ),
        ],
      ),
    );

    if (confirmAction == true) {
      await _updateRegistroLocationCompleta(registro, previousLoc);
    }
  }

  Future<void> _handleDelete(Registro registro) async {
    final confirmAction = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kSurface,
        surfaceTintColor: _kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirmar exclusão',
          style: TextStyle(color: _kTextPrimary),
        ),
        content: Text(
          'Tem certeza que deseja Excluir permanentemente o pedido ${registro.ordemProducao}? Esta ação não pode ser desfeita.',
          style: const TextStyle(color: _kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: _kTextSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmAction == true) {
      try {
        final localizacaoAtual = registro.localizacao ?? 'N/A';
        final DateTime dataMovimentacao = DateTime.now();

        final sucesso = await MovimentacaoService.registrarMovimentacaoCompleta(
          idRegistro: registro.id,
          idPedido: registro.ordemProducao,
          localizacaoOrigem: localizacaoAtual,
          localizacaoDestino: 'Excluído',
          conferente: widget.conferente,
          dataMovimentacao: dataMovimentacao,
          tipoMovimentacao: 'EXCLUSAO',
        );

        if (!sucesso) {
          throw Exception('Falha ao registrar exclusão no servidor.');
        }

        _reloadAllFutures();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pedido ${registro.ordemProducao} excluído com sucesso!',
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir registro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showAdminMoveDialog(Registro registro) async {
    final passwordController = TextEditingController();
    String? currentSelectedLoc;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter dialogSetState) {
            final availableLocations = _allLocations
                .where((loc) => loc != registro.localizacao)
                .toList();

            return AlertDialog(
              backgroundColor: _kSurface,
              surfaceTintColor: _kSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Movimentação admin',
                style: TextStyle(color: _kTextPrimary),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mover o Pedido ${registro.ordemProducao} de ${registro.localizacao ?? 'N/A'} para:',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _kTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      dropdownColor: _kSurface2,
                      decoration: InputDecoration(
                        labelText: 'Destino',
                        labelStyle: const TextStyle(color: _kTextSecondary),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kBorderSoft),
                        ),
                      ),
                      value: currentSelectedLoc,
                      hint: const Text(
                        'Selecione a Loc de destino',
                        style: TextStyle(color: _kTextSecondary),
                      ),
                      items: availableLocations.map((loc) {
                        return DropdownMenuItem(
                          value: loc,
                          child: Text(
                            loc,
                            style: const TextStyle(color: _kTextPrimary),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        dialogSetState(() {
                          currentSelectedLoc = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      style: const TextStyle(color: _kTextPrimary),
                      decoration: InputDecoration(
                        labelText: 'Senha de administrador',
                        labelStyle: const TextStyle(color: _kTextSecondary),
                        prefixIcon: const Icon(
                          Icons.lock,
                          color: _kAccentColor,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kBorderSoft),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kAccentColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: _kTextSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: currentSelectedLoc == null
                      ? null
                      : () async {
                          final password = passwordController.text;

                          if (password.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Digite a senha de administrador.',
                                ),
                                backgroundColor: Color(0xFFF97316),
                              ),
                            );
                            return;
                          }

                          final isVerified = await _verifyPassword(
                            widget.conferente,
                            password,
                          );

                          if (isVerified) {
                            Navigator.pop(context);
                            await _updateRegistroLocationCompleta(
                              registro,
                              currentSelectedLoc!,
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Senha de administrador inválida. Tente novamente.',
                                ),
                                backgroundColor: Color(0xFFEF4444),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: const Color(0xFF020617),
                  ),
                  child: const Text('Mover'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showHistoricoMovimentacao(Registro registro) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final historico = await MovimentacaoService.buscarHistorico(
      registro.ordemProducao,
    );

    if (!mounted) return;

    Navigator.pop(context);

    // MAIS RECENTES PRIMEIRO
    historico.sort((a, b) => b.dataMovimentacao.compareTo(a.dataMovimentacao));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kSurface,
        surfaceTintColor: _kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Histórico da OP ${registro.ordemProducao}',
          style: const TextStyle(color: _kTextPrimary),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: historico.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 48, color: _kTextSecondary),
                      const SizedBox(height: 10),
                      const Text(
                        'Nenhuma movimentação registrada.',
                        style: TextStyle(color: _kTextSecondary),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: historico.length,
                  itemBuilder: (context, index) {
                    final mov = historico[index];

                    final dataFormatada = DateFormat(
                      'dd/MM/yy HH:mm',
                    ).format(mov.dataMovimentacao.toLocal());

                    final tipoColor = _getColorForTipo(mov.tipoMovimentacao);

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      elevation: 0,
                      color: _kSurface2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: _kBorderSoft, width: 1),
                      ),
                      child: ListTile(
                        leading: Icon(
                          _getIconForTipo(mov.tipoMovimentacao),
                          color: tipoColor,
                          size: 26,
                        ),
                        title: Text(
                          '${mov.localizacaoOrigem} -> ${mov.localizacaoDestino}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: _kTextPrimary,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 12,
                                    color: _kTextSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    dataFormatada,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _kTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.person,
                                    size: 12,
                                    color: _kTextSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    mov.conferente,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _kTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: tipoColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: tipoColor.withOpacity(0.4),
                                  ),
                                ),
                                child: Text(
                                  mov.tipoMovimentacao,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: tipoColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar', style: TextStyle(color: _kAccentColor)),
          ),
        ],
      ),
    );
  }

  IconData _getIconForTipo(String tipo) {
    switch (tipo) {
      case 'NORMAL':
        return Icons.arrow_forward_ios_rounded;
      case 'ROLLBACK':
        return Icons.undo_rounded;
      case 'ADMIN':
        return Icons.security_rounded;
      case 'EXCLUSAO':
        return Icons.delete_forever_rounded;
      case 'PARCIAL':
        return Icons.content_cut_rounded;
      default:
        return Icons.help;
    }
  }

  Color _getColorForTipo(String tipo) {
    switch (tipo) {
      case 'NORMAL':
        return const Color(0xFF22C55E);
      case 'ROLLBACK':
        return const Color(0xFFF97316);
      case 'ADMIN':
        return const Color(0xFFEF4444);
      case 'EXCLUSAO':
        return Colors.red.shade900;
      case 'PARCIAL':
        return const Color(0xFF14B8A6);
      default:
        return _kTextSecondary;
    }
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onPressed,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 10.0),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isDestructive ? FontWeight.bold : FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoveButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required VoidCallback? onPressed,
    Color foregroundColor = Colors.white,
    BorderSide? side,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
        side: side,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _escolherModoLeituraImatec(Registro registro) async {
    final modo = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _kSurface,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ler QR da Imatec - OP ${registro.ordemProducao}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _kTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Escolha como deseja ler a etiqueta da máquina.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _kTextSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              _buildMoveButton(
                icon: Icons.photo_camera_rounded,
                label: 'Ler com câmera',
                backgroundColor: _kPrimaryColor,
                foregroundColor: _kBgTop,
                onPressed: () => Navigator.pop(context, 'camera'),
              ),
              const SizedBox(height: 10),
              _buildMoveButton(
                icon: Icons.document_scanner_rounded,
                label: 'Ler com coletor',
                backgroundColor: const Color(0xFF14B8A6),
                foregroundColor: _kBgTop,
                onPressed: () => Navigator.pop(context, 'coletor'),
              ),
            ],
          ),
        );
      },
    );

    if (modo == 'camera') {
      if (!mounted) return null;
      return Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const QrScannerScreen()),
      );
    }
    if (modo == 'coletor') {
      return _aguardarQrImatecColetor(registro);
    }
    return null;
  }

  Future<String?> _aguardarQrImatecColetor(Registro registro) async {
    DataWedgeService.scanData.value = null;
    DataWedgeService.init();

    var concluido = false;
    late VoidCallback listener;
    listener = () {
      if (concluido) return;
      final scanned = DataWedgeService.scanData.value;
      if (scanned == null || scanned.trim().isEmpty) return;
      concluido = true;
      DataWedgeService.scanData.value = null;
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(scanned.trim());
      }
    };

    DataWedgeService.scanData.addListener(listener);
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            backgroundColor: _kSurface,
            surfaceTintColor: _kSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Text(
              'Coletor - OP ${registro.ordemProducao}',
              style: const TextStyle(
                color: _kTextPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.document_scanner_rounded,
                  color: Color(0xFF14B8A6),
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  registro.artigo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Bipe a etiqueta da Imatec no coletor. Apenas este pedido será enviado para check-in.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _kTextSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  concluido = true;
                  Navigator.pop(context);
                },
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: _kTextSecondary),
                ),
              ),
            ],
          );
        },
      );
    } finally {
      DataWedgeService.scanData.removeListener(listener);
      DataWedgeService.scanData.value = null;
    }
  }

  Future<void> _showImatecCheckinDialog(Registro registro) async {
    String selectedImatec = '';
    String selectedBoca = '';
    String qrCode = '';

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            final canConfirm =
                selectedImatec.isNotEmpty &&
                selectedBoca.isNotEmpty &&
                qrCode.isNotEmpty;

            return AlertDialog(
              backgroundColor: _kSurface,
              surfaceTintColor: _kSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: Text(
                'Check-in Imatec - OP ${registro.ordemProducao}',
                style: const TextStyle(
                  color: _kTextPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _kSurface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kBorderSoft),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            registro.artigo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _kTextPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${registro.metrosFormatados} m | Caixa ${registro.caixa?.isNotEmpty == true ? registro.caixa : '0'}',
                            style: const TextStyle(color: _kTextSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: selectedImatec.isEmpty
                            ? _kSurface2
                            : const Color(0xFF22C55E).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedImatec.isEmpty
                              ? _kBorderSoft
                              : const Color(0xFF22C55E),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selectedImatec.isEmpty
                                ? Icons.precision_manufacturing_outlined
                                : Icons.precision_manufacturing_rounded,
                            color: selectedImatec.isEmpty
                                ? _kTextSecondary
                                : const Color(0xFF22C55E),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedImatec.isEmpty
                                  ? 'Bipe o QR da Imatec para identificar a máquina'
                                  : 'Máquina identificada: $selectedImatec',
                              style: TextStyle(
                                color: selectedImatec.isEmpty
                                    ? _kTextSecondary
                                    : _kTextPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final result = await _escolherModoLeituraImatec(
                          registro,
                        );
                        if (result == null || result.trim().isEmpty) return;
                        final parsed = _imatecFromQr(result);
                        if (parsed == null) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'QR da Imatec inválido. Use a etiqueta oficial gerada na aba Livre > Imatecs.',
                              ),
                              backgroundColor: Color(0xFFEF4444),
                            ),
                          );
                          return;
                        }
                        dialogSetState(() {
                          qrCode = result.trim();
                          selectedImatec = parsed;
                          selectedBoca = '';
                        });
                      },
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: Text(
                        qrCode.isEmpty ? 'Ler QR da Imatec' : 'Trocar QR',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kAccentColor,
                        side: const BorderSide(color: _kAccentColor),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    if (selectedImatec.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Onde o material está rodando?',
                        style: TextStyle(
                          color: _kTextPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final boca in const [
                            'Boca 1',
                            'Boca 2',
                            'Boca 1 e 2',
                          ])
                            ChoiceChip(
                              label: Text(boca),
                              selected: selectedBoca == boca,
                              showCheckmark: true,
                              selectedColor: _kPrimaryColor,
                              backgroundColor: _kSurface2,
                              side: BorderSide(
                                color: selectedBoca == boca
                                    ? _kPrimaryColor
                                    : _kBorderSoft,
                              ),
                              labelStyle: TextStyle(
                                color: selectedBoca == boca
                                    ? _kBgTop
                                    : _kTextPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                              onSelected: (_) {
                                dialogSetState(() => selectedBoca = boca);
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: _kTextSecondary),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: canConfirm
                      ? () async {
                          Navigator.pop(context);
                          await _registrarCheckinImatec(
                            registro,
                            selectedImatec,
                            selectedBoca,
                            qrCode,
                          );
                        }
                      : null,
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('Confirmar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimaryColor,
                    foregroundColor: _kBgTop,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _registrarCheckinImatec(
    Registro registro,
    String imatec,
    String bocaImatec,
    String qrCode,
  ) async {
    try {
      final sucesso = await MovimentacaoService.registrarMovimentacaoCompleta(
        idRegistro: registro.id,
        idPedido: registro.ordemProducao,
        localizacaoOrigem: registro.localizacao ?? 'Imatecs',
        localizacaoDestino: imatec,
        conferente: widget.conferente,
        dataMovimentacao: DateTime.now(),
        tipoMovimentacao: 'CHECKIN_IMATEC',
        qrCode: qrCode,
        observacao:
            'Check-in de material na $imatec | Boca Imatec: $bocaImatec',
        bocaImatec: bocaImatec,
      );

      if (!sucesso) {
        throw Exception('Falha ao registrar check-in da Imatec.');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'OP ${registro.ordemProducao} transferida para $imatec - $bocaImatec.',
          ),
          backgroundColor: const Color(0xFF22C55E),
        ),
      );
      _reloadAllFutures();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro no check-in Imatec: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showMoveAndDeleteSheet(Registro registro) {
    final currentLoc = registro.localizacao;
    final nextOptions = _getValidNextOptions(currentLoc);
    final previousLoc = _getValidPreviousLocation(currentLoc);
    final canRollback = previousLoc != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: _kSurface,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.only(
                top: 25,
                left: 20,
                right: 20,
                bottom: 30,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ações do pedido ${registro.ordemProducao}',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: _kTextPrimary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Localização Atual: ${currentLoc ?? 'N/A'} (Metros: ${(registro.metros ?? 0.0).toStringAsFixed(3)})',
                      style: const TextStyle(
                        color: _kTextSecondary,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 25, color: _kBorderSoft),

                    if (_requiresImatecCheckin(currentLoc))
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Check-in obrigatório:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _kTextSecondary,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildMoveButton(
                            icon: Icons.qr_code_scanner_rounded,
                            label: 'Ler QR e enviar para IMATEC',
                            backgroundColor: const Color(0xFFF97316),
                            foregroundColor: _kBgTop,
                            onPressed: () {
                              Navigator.pop(context);
                              _showImatecCheckinDialog(registro);
                            },
                          ),
                        ],
                      )
                    else if (nextOptions.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Próximas etapas:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _kTextSecondary,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 12),

                          ...nextOptions.map(
                            (nextLoc) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _buildMoveButton(
                                icon: Icons.content_cut_rounded,
                                label: 'Parcial para ${nextLoc.toUpperCase()}',
                                backgroundColor: const Color(0xFF14B8A6),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showParcialMoveDialog(registro, nextLoc);
                                },
                              ),
                            ),
                          ),

                          ...nextOptions.map(
                            (nextLoc) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _buildMoveButton(
                                icon: Icons.arrow_forward_ios_rounded,
                                label: 'Completo para ${nextLoc.toUpperCase()}',
                                backgroundColor: _kPrimaryColor,
                                onPressed: () {
                                  Navigator.pop(context);
                                  _updateRegistroLocationCompleta(
                                    registro,
                                    nextLoc,
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      )
                    else if (currentLoc == 'Expedição')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildMoveButton(
                          icon: Icons.check_circle_outline_rounded,
                          label: 'Movimento finalizado',
                          onPressed: null,
                          backgroundColor: Colors.green.shade900.withOpacity(
                            0.15,
                          ),
                          foregroundColor: Colors.green.shade200,
                          side: BorderSide(
                            color: Colors.green.shade700,
                            width: 1,
                          ),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10.0),
                        child: Text(
                          'Nenhuma movimentação disponível para esta etapa.',
                          style: TextStyle(color: _kTextSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    const SizedBox(height: 15),
                    const Divider(height: 20, color: _kBorderSoft),

                    if (canRollback || widget.isAdmin)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Ações especiais:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _kTextSecondary,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),

                          _buildActionTile(
                            icon: Icons.history_rounded,
                            title: 'Ver histórico de movimentações',
                            color: _kAccentColor,
                            onPressed: () {
                              Navigator.pop(context);
                              _showHistoricoMovimentacao(registro);
                            },
                          ),

                          if (canRollback)
                            _buildActionTile(
                              icon: Icons.undo_rounded,
                              title:
                                  'Retornar para ${previousLoc!.toUpperCase()}',
                              color: const Color(0xFFF97316),
                              onPressed: () {
                                Navigator.pop(context);
                                _handleRollback(registro, previousLoc);
                              },
                            ),

                          if (widget.isAdmin)
                            Column(
                              children: [
                                const Divider(height: 20, color: _kBorderSoft),
                                _buildActionTile(
                                  icon: Icons.security_rounded,
                                  title: 'Movimentação admin direta',
                                  color: const Color(0xFFEF4444),
                                  isDestructive: true,
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _showAdminMoveDialog(registro);
                                  },
                                ),
                                _buildActionTile(
                                  icon: Icons.delete_forever_rounded,
                                  title: 'Excluir pedido',
                                  color: Colors.red.shade900,
                                  isDestructive: true,
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _handleDelete(registro);
                                  },
                                ),
                              ],
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  void _showSearchDialog() {
    final searchController = TextEditingController(text: _searchQuery);
    DateTime? tempFilterDate = _filterDate;

    Future<void> _selectDate(StateSetter dialogSetState) async {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: tempFilterDate ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2101),
      );
      if (picked != null && picked != tempFilterDate) {
        dialogSetState(() {
          tempFilterDate = picked;
        });
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter dialogSetState) {
            return AlertDialog(
              backgroundColor: _kSurface,
              surfaceTintColor: _kSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Filtrar pedidos',
                style: TextStyle(color: _kTextPrimary),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      keyboardType: TextInputType.text,
                      style: const TextStyle(color: _kTextPrimary),
                      decoration: InputDecoration(
                        hintText: 'Digite OP ou artigo...',
                        hintStyle: TextStyle(
                          color: _kTextSecondary.withOpacity(0.7),
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: _kAccentColor,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kBorderSoft),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kAccentColor),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: _kBorderSoft),
                      ),
                      leading: const Icon(
                        Icons.calendar_today,
                        color: _kAccentColor,
                      ),
                      title: Text(
                        tempFilterDate == null
                            ? 'Filtrar por data'
                            : 'Data: ${DateFormat('dd/MM/yyyy').format(tempFilterDate!)}',
                        style: const TextStyle(color: _kTextPrimary),
                      ),
                      trailing: tempFilterDate != null
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                color: Color(0xFFEF4444),
                              ),
                              onPressed: () => dialogSetState(() {
                                tempFilterDate = null;
                              }),
                            )
                          : const Icon(
                              Icons.arrow_drop_down,
                              color: _kTextSecondary,
                            ),
                      onTap: () => _selectDate(dialogSetState),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: _kTextSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _searchQuery = searchController.text.trim();
                      _filterDate = tempFilterDate;
                    });

                    _reloadAllFutures();
                    Navigator.pop(context);

                    String filterMsg = 'Filtro aplicado';
                    if (_searchQuery.isNotEmpty && _filterDate != null) {
                      filterMsg =
                          'Filtros: "$_searchQuery" e ${DateFormat('dd/MM/yyyy').format(_filterDate!)}';
                    } else if (_searchQuery.isNotEmpty) {
                      filterMsg = 'Filtro: "$_searchQuery"';
                    } else if (_filterDate != null) {
                      filterMsg =
                          'Filtro: ${DateFormat('dd/MM/yyyy').format(_filterDate!)}';
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(filterMsg),
                        duration: const Duration(seconds: 2),
                        backgroundColor: _kPrimaryColor,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Aplicar filtro'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentTabIndex = _tabController.index;
    final currentTabName = _tabNames[currentTabIndex];

    final isFilterActive = _searchQuery.isNotEmpty || _filterDate != null;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_kBgTop, _kBgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            elevation: 0,
            centerTitle: true,
            backgroundColor: _kBgBottom,
            foregroundColor: _kTextPrimary,
            title: const Text(
              'Localização',
              style: TextStyle(
                color: _kTextPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  isFilterActive ? Icons.filter_alt : Icons.search,
                  color: Colors.white,
                ),
                onPressed: _showSearchDialog,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                    _filterDate = null;
                  });

                  _reloadAllFutures();

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Atualizando...'),
                      duration: Duration(seconds: 1),
                      backgroundColor: Color(0xFF22C55E),
                    ),
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              _buildStageSelector(currentTabName),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: _tabNames
                      .map((tabName) => _buildRegistroTab(tabName))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageSelector(String currentTabName) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: _kBgBottom.withOpacity(0.92),
        border: const Border(bottom: BorderSide(color: _kBorderSoft)),
      ),
      child: SizedBox(
        height: 74,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: _tabNames.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final tabName = _tabNames[index];
            final selected = tabName == currentTabName;
            final color = _getTabColor(tabName);
            final label = _tabLabels[tabName] ?? tabName;
            final icon = _tabIcons[tabName] ?? Icons.location_on_rounded;

            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                _tabController.animateTo(index);
                setState(() {});
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 142 : 112,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected ? color.withOpacity(0.18) : _kSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? color : _kBorderSoft,
                    width: selected ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: selected ? color : _kSurface3,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        color: selected ? _kBgTop : _kTextSecondary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            tabName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? color : _kTextSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _kTextPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRegistroTab(String tabLocation) {
    final actualLocation = _tabToFullLoc[tabLocation];
    final headerColor = _getTabColor(tabLocation);
    final isFilterActive = _searchQuery.isNotEmpty || _filterDate != null;

    return FutureBuilder<List<Registro>>(
      future: _getFutureForTab(tabLocation),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _kAccentColor),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 60, color: Colors.red.shade300),
                const SizedBox(height: 10),
                Text(
                  'Erro ao carregar dados',
                  style: TextStyle(fontSize: 18, color: Colors.red.shade700),
                ),
                const SizedBox(height: 5),
                Text(
                  '${snapshot.error}',
                  style: const TextStyle(fontSize: 12, color: _kTextSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final registros = snapshot.data ?? [];

        if (registros.isEmpty) {
          String msg = isFilterActive
              ? 'Nenhum pedido encontrado com o filtro aplicado em ${actualLocation?.toUpperCase() ?? tabLocation}'
              : 'Nenhum registro encontrado para ${actualLocation?.toUpperCase() ?? tabLocation}';

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isFilterActive ? Icons.search_off : Icons.layers_clear,
                    size: 60,
                    color: headerColor.withOpacity(0.7),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    msg,
                    style: const TextStyle(
                      color: _kTextSecondary,
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (isFilterActive) ...[
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Limpar filtros'),
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                          _filterDate = null;
                        });
                        _reloadAllFutures();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: headerColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
          itemCount: registros.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildTabSummaryHeader(
                tabLocation: tabLocation,
                actualLocation: actualLocation,
                count: registros.length,
                color: headerColor,
                isFilterActive: isFilterActive,
              );
            }

            final r = registros[index - 1];
            return _buildRegistroCard(r, headerColor);
          },
        );
      },
    );
  }

  Widget _buildTabSummaryHeader({
    required String tabLocation,
    required String? actualLocation,
    required int count,
    required Color color,
    required bool isFilterActive,
  }) {
    final label = _tabLabels[tabLocation] ?? actualLocation ?? tabLocation;
    final icon = _tabIcons[tabLocation] ?? Icons.location_on_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorderSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _kBgTop, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isFilterActive ? 'Filtro aplicado' : 'Pedidos ativos',
                  style: const TextStyle(
                    color: _kTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.45)),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegistroCard(Registro r, Color headerColor) {
    final dateFormat = DateFormat('dd/MM HH:mm');
    final dataEntradaFormatada = dateFormat.format(r.data.toLocal());
    final dataReferenciaLocalizacao = r.dataMovimentacao ?? r.data;
    final dataMovimentacaoFormatada = r.dataMovimentacao != null
        ? dateFormat.format(r.dataMovimentacao!.toLocal())
        : dataEntradaFormatada;
    final caixa = r.caixa != null && r.caixa!.trim().isNotEmpty
        ? r.caixa!.trim()
        : '0';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _kSurface.withOpacity(0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorderSoft),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showMoveAndDeleteSheet(r),
          onLongPress: () => _showMoveAndDeleteSheet(r),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: headerColor.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: headerColor.withOpacity(0.5)),
                      ),
                      child: Icon(
                        Icons.assignment_rounded,
                        color: headerColor,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OP ${r.ordemProducao}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _kTextPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            r.artigo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _kTextPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              height: 1.18,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildLocationPill(r.localizacao ?? 'N/A', headerColor),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoStrip(
                  icon: Icons.palette_outlined,
                  label: 'Cor',
                  value: r.cor,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        icon: Icons.straighten_rounded,
                        label: 'Metros',
                        value: '${(r.metros ?? 0).toStringAsFixed(3)} m',
                        color: _kPrimaryColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricTile(
                        icon: Icons.scale_rounded,
                        label: 'Peso',
                        value: '${r.peso.toStringAsFixed(3)} kg',
                        color: const Color(0xFF38BDF8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        icon: Icons.inventory_2_outlined,
                        label: 'Caixa',
                        value: caixa,
                        color: const Color(0xFF14B8A6),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricTile(
                        icon: Icons.content_cut_rounded,
                        label: 'Corte',
                        value: r.numCorte?.trim().isNotEmpty == true
                            ? r.numCorte!.trim()
                            : 'N/A',
                        color: const Color(0xFFF97316),
                      ),
                    ),
                  ],
                ),
                if (_isImatecLocation(r.localizacao)) ...[
                  const SizedBox(height: 10),
                  _buildInfoStrip(
                    icon: Icons.timer_rounded,
                    label: 'Tempo na máquina',
                    value: _formatarTempoNaLocalizacao(
                      dataReferenciaLocalizacao,
                    ),
                    color: const Color(0xFF38BDF8),
                  ),
                  if ((r.bocaImatec ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildInfoStrip(
                      icon: Icons.call_split_rounded,
                      label: 'Boca',
                      value: r.bocaImatec!.trim(),
                      color: const Color(0xFFF59E0B),
                    ),
                  ],
                ],
                if (_requiresImatecCheckin(r.localizacao)) ...[
                  const SizedBox(height: 12),
                  _buildImatecCheckinBanner(r),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kSurface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _kBorderSoft),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoRow(
                              Icons.person_outline,
                              'Conf.: ${r.conferente}',
                              color: _kTextSecondary,
                            ),
                          ),
                          Expanded(
                            child: _buildInfoRow(
                              Icons.layers_outlined,
                              'Qtd: ${r.quantidade}',
                              color: _kTextSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoRow(
                              Icons.login_rounded,
                              'Entrada: $dataEntradaFormatada',
                              color: const Color(0xFF22C55E),
                            ),
                          ),
                          Expanded(
                            child: _buildInfoRow(
                              Icons.update_rounded,
                              'Mov.: $dataMovimentacaoFormatada',
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _showMoveAndDeleteSheet(r),
                    icon: const Icon(Icons.touch_app_rounded, size: 18),
                    label: const Text('Ações'),
                    style: TextButton.styleFrom(
                      foregroundColor: headerColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationPill(String label, Color color) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 112),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kSurface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderSoft),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoStrip({
    required IconData icon,
    required String label,
    required String value,
    Color color = _kTextSecondary,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kSurface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderSoft),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              color: _kTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kTextPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImatecCheckinBanner(Registro registro) {
    return Material(
      color: const Color(0xFFF97316).withOpacity(0.14),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showImatecCheckinDialog(registro),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF97316), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF97316),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: _kBgTop,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Check-in Imatec',
                      style: TextStyle(
                        color: _kTextPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Bipe o QR da máquina Imatec.',
                      style: TextStyle(
                        color: _kTextSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Color(0xFFF97316),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, {required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
