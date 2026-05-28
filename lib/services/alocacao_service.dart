import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracx/services/padrao_caixa_service.dart';

/// Modelo mínimo que representa os dados retornados pelo endpoint de alocações.
class AlocacaoEntry {
  const AlocacaoEntry({
    required this.codSku,
    required this.endereco,
    required this.produto,
    required this.qtAlocada,
    required this.qtSaldoInicial,
    required this.qtMovEntrada,
    required this.qtMovRetorno,
    required this.qtMovSaida,
    required this.qtSaldoFinal,
    required this.dataAtualizacao,
    required this.id,
    required this.qtMaxima,
    required this.detalhe,
    required this.detalheId,
    required this.nmLot,
    this.saldoInicialInformado = false,
    this.saldoFinalInformado = false,
    int? qtCaixaP,
    int? qtCaixaG,
    int? qtEnfestado,
    int? qtEnfraldado,
  }) : _qtCaixaP = qtCaixaP ?? 0,
       _qtCaixaG = qtCaixaG ?? 0,
       _qtEnfestado = qtEnfestado ?? 0,
       _qtEnfraldado = qtEnfraldado ?? 0;

  final int codSku;
  final String endereco;
  final String produto;
  final int qtAlocada;
  final int qtSaldoInicial;
  final int qtMovEntrada;
  final int qtMovRetorno;
  final int qtMovSaida;
  final int qtSaldoFinal;
  final int qtMaxima;
  final String nmLot;
  final DateTime? dataAtualizacao;
  final int? id;
  final String detalhe;
  final int detalheId;
  final bool saldoInicialInformado;
  final bool saldoFinalInformado;
  final int? _qtCaixaP;
  final int? _qtCaixaG;
  final int? _qtEnfestado;
  final int? _qtEnfraldado;

  int get qtCaixaP => _qtCaixaP ?? 0;
  int get qtCaixaG => _qtCaixaG ?? 0;
  int get qtEnfestado => _qtEnfestado ?? 0;
  int get qtEnfraldado => _qtEnfraldado ?? 0;

  AlocacaoEntry copyWith({
    int? qtAlocada,
    int? qtSaldoInicial,
    int? qtMovEntrada,
    int? qtMovRetorno,
    int? qtMovSaida,
    int? qtSaldoFinal,
  }) {
    return AlocacaoEntry(
      codSku: codSku,
      endereco: endereco,
      produto: produto,
      qtAlocada: qtAlocada ?? this.qtAlocada,
      qtSaldoInicial: qtSaldoInicial ?? this.qtSaldoInicial,
      qtMovEntrada: qtMovEntrada ?? this.qtMovEntrada,
      qtMovRetorno: qtMovRetorno ?? this.qtMovRetorno,
      qtMovSaida: qtMovSaida ?? this.qtMovSaida,
      qtSaldoFinal: qtSaldoFinal ?? this.qtSaldoFinal,
      dataAtualizacao: dataAtualizacao,
      id: id,
      qtMaxima: qtMaxima,
      detalhe: detalhe,
      detalheId: detalheId,
      nmLot: nmLot,
      saldoInicialInformado: saldoInicialInformado,
      saldoFinalInformado: saldoFinalInformado,
      qtCaixaP: qtCaixaP,
      qtCaixaG: qtCaixaG,
      qtEnfestado: qtEnfestado,
      qtEnfraldado: qtEnfraldado,
    );
  }

  factory AlocacaoEntry.fromJson(Map<String, dynamic> json) {
    final dataString = json['DataAtualizacao'] ?? json['dataAtualizacao'];
    final data = _parseDateTimeFlexible(dataString);

    ({bool found, dynamic value}) firstKeyValue(List<String> keys) {
      for (final key in keys) {
        if (json.containsKey(key)) {
          return (found: true, value: json[key]);
        }
      }
      return (found: false, value: null);
    }

    int? tryParseIntNullable(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      if (text.isEmpty) return null;
      return int.tryParse(text) ?? _toInt(value);
    }

    int resolveDetalheId() {
      // O backend (ex.: ajustar_embalagem) usa o campo numérico `Detalhe`.
      // Alguns endpoints retornam também `DetalheID`/`LoteID` (ou lote textual),
      // então mantemos fallback, mas priorizamos o `Detalhe`/`CdLot` quando presentes
      // (mesmo que sejam 0).
      final detalheLookup = firstKeyValue([
        'Detalhe',
        'detalhe',
        'CdLot',
        'cdLot',
        'CdLote',
        'cdLote',
        'DetalheID',
        'DetalheId',
        'detalheId',
        'detalheID',
        'LoteID',
        'LoteId',
        'loteId',
      ]);
      if (!detalheLookup.found) return 0;
      return _toInt(detalheLookup.value);
    }

    final detalheIdResolved = resolveDetalheId();
    final detalheRaw =
        json['Detalhe'] ??
        json['detalhe'] ??
        json['Lote'] ??
        json['lote'] ??
        json['CdLot'] ??
        json['cdLot'] ??
        json['CdLote'] ??
        json['cdLote'] ??
        json['Detalhe'] ??
        json['LoteID'] ??
        json['loteId'] ??
        '';
    final qtAlocada = _toInt(json['QtAlocada']);
    final saldoFinalLookup = firstKeyValue([
      'QtSaldoFinal',
      'qtSaldoFinal',
      'SaldoFinal',
      'saldoFinal',
      'QtSaldo',
      'qtSaldo',
      'Saldo',
      'QtFinal',
    ]);
    final qtSaldoFinalParsed = saldoFinalLookup.found
        ? tryParseIntNullable(saldoFinalLookup.value)
        : null;
    final saldoFinalInformado =
        saldoFinalLookup.found && qtSaldoFinalParsed != null;
    final qtMovEntrada = _toInt(
      json['QtMovEntrada'] ?? json['MovEntrada'] ?? json['qtMovEntrada'],
    );
    final qtMovRetorno = _toInt(
      json['QtMovRetorno'] ?? json['MovRetorno'] ?? json['qtMovRetorno'],
    );
    final qtMovSaida = _toInt(
      json['QtMovSaida'] ?? json['MovSaida'] ?? json['qtMovSaida'],
    );
    final saldoInicialLookup = firstKeyValue([
      'QtSaldoInicial',
      'qtSaldoInicial',
      'SaldoInicial',
      'saldoInicial',
    ]);
    final qtSaldoInicialParsed = saldoInicialLookup.found
        ? tryParseIntNullable(saldoInicialLookup.value)
        : null;
    final saldoInicialInformado =
        saldoInicialLookup.found && qtSaldoInicialParsed != null;
    return AlocacaoEntry(
      codSku: _toInt(
        json['CodSKU'] ??
            json['codSku'] ??
            json['CdObj'] ??
            json['cdObj'] ??
            json['ObjetoID'] ??
            json['objetoId'] ??
            json['ProdutoID'] ??
            json['produtoId'],
      ),
      endereco: (json['Endereco'] ?? json['endereco'] ?? '').toString().trim(),
      produto: (json['Produto'] ?? json['produto'] ?? '').toString().trim(),
      qtAlocada: qtAlocada,
      qtSaldoInicial: qtSaldoInicialParsed ?? qtAlocada,
      qtMovEntrada: qtMovEntrada,
      qtMovRetorno: qtMovRetorno,
      qtMovSaida: qtMovSaida,
      qtSaldoFinal: qtSaldoFinalParsed ?? qtAlocada,
      qtMaxima: _toInt(
        json['QtMaxima'] ??
            json['qtmaxima'] ??
            json['QtMax'] ??
            json['QtMaximaPalete'] ??
            json['QtMaxima_Palete'] ??
            json['Qtmaxima'],
      ),
      detalhe: detalheRaw.toString().trim(),
      detalheId: detalheIdResolved,
      nmLot:
          (json['NmLot'] ??
                  json['NmLOT'] ??
                  json['NmLotagem'] ??
                  json['NmLote'] ??
                  json['NmLotagem'] ??
                  json['NmLotes'] ??
                  '')
              .toString()
              .trim(),
      saldoInicialInformado: saldoInicialInformado,
      saldoFinalInformado: saldoFinalInformado,
      qtCaixaP: _toInt(json['QtCaixaP'] ?? json['qt_caixa_p']),
      qtCaixaG: _toInt(json['QtCaixaG'] ?? json['qt_caixa_g']),
      qtEnfestado: _toInt(json['QtEnfestado'] ?? json['qt_enfestado']),
      qtEnfraldado: _toInt(json['QtEnfraldado'] ?? json['qt_enfraldado']),
      dataAtualizacao: data,
      id: _toInt(json['ID']),
    );
  }
}

class MovimentoEntry {
  const MovimentoEntry({
    required this.endereco,
    required this.codSku,
    required this.detalheId,
    required this.tpMov,
    required this.qtMovida,
    required this.dataMovimento,
  });

  final String endereco;
  final int codSku;
  final int detalheId;
  final int tpMov;
  final double qtMovida;
  final DateTime? dataMovimento;

  factory MovimentoEntry.fromJson(Map<String, dynamic> json) {
    return MovimentoEntry(
      endereco: (json['Endereco'] ?? json['endereco'] ?? '').toString().trim(),
      codSku: _toInt(
        json['CodSKU'] ??
            json['codSku'] ??
            json['CdObj'] ??
            json['cdObj'] ??
            json['ObjetoID'] ??
            json['objetoId'] ??
            json['ProdutoID'] ??
            json['produtoId'],
      ),
      detalheId: _toInt(
        json['Detalhe'] ??
            json['detalhe'] ??
            json['DetalheID'] ??
            json['detalheId'] ??
            json['LoteID'] ??
            json['loteId'] ??
            json['CdLot'] ??
            json['cdLot'] ??
            json['CdLote'] ??
            json['cdLote'],
      ),
      tpMov: _toInt(json['TpMov'] ?? json['tpMov']),
      qtMovida: _toDouble(json['QtMovida'] ?? json['qtMovida']),
      dataMovimento: _parseDataMovimento(
        json['DataMovimento'] ?? json['dataMovimento'],
      ),
    );
  }
}

class CanceladoSaldoEntry {
  const CanceladoSaldoEntry({
    required this.codSku,
    required this.cdLot,
    required this.qtCancelada,
    required this.qtAlocada,
    required this.qtDisponivel,
  });

  final int codSku;
  final int cdLot;
  final double qtCancelada;
  final double qtAlocada;
  final double qtDisponivel;

  factory CanceladoSaldoEntry.fromJson(Map<String, dynamic> json) {
    return CanceladoSaldoEntry(
      codSku: _toInt(json['CdObj'] ?? json['CodSKU'] ?? json['codSku']),
      cdLot: _toInt(json['CdLot'] ?? json['Detalhe'] ?? json['cdLot']),
      qtCancelada: _toDouble(json['QtCancelada']),
      qtAlocada: _toDouble(json['QtAlocada']),
      qtDisponivel: _toDouble(json['QtDisponivel']),
    );
  }
}

class NotaCanceladaEntry {
  const NotaCanceladaEntry({
    required this.codSku,
    required this.lote,
    required this.sku,
    required this.qtRco,
  });

  final int codSku;
  final String lote;
  final String sku;
  final double qtRco;

  factory NotaCanceladaEntry.fromJson(Map<String, dynamic> json) {
    return NotaCanceladaEntry(
      codSku: _toInt(json['Cod_SKU'] ?? json['CodSKU'] ?? json['codSku']),
      lote: (json['Lote'] ?? json['lote'] ?? '').toString().trim(),
      sku: (json['SKU'] ?? json['sku'] ?? '').toString().trim(),
      qtRco: _toDouble(json['QtRco'] ?? json['qtRco'] ?? json['Quantidade']),
    );
  }
}

class PaleteEmbalagemItemEntry {
  const PaleteEmbalagemItemEntry({
    required this.endereco,
    required this.codSku,
    required this.detalhe,
    required this.descricao,
    required this.qtAlocada,
    required this.qtCaixaP,
    required this.qtCaixaG,
    required this.qtEnfestado,
    required this.qtEnfraldado,
  });

  final String endereco;
  final int codSku;
  final int detalhe;
  final String descricao;
  final double qtAlocada;
  final int qtCaixaP;
  final int qtCaixaG;
  final int qtEnfestado;
  final int qtEnfraldado;

  factory PaleteEmbalagemItemEntry.fromJson(Map<String, dynamic> json) {
    return PaleteEmbalagemItemEntry(
      endereco: (json['Endereco'] ?? json['endereco'] ?? '').toString().trim(),
      codSku: _toInt(json['CodSKU'] ?? json['cod_sku'] ?? json['CdObj']),
      detalhe: _toInt(json['Detalhe'] ?? json['detalhe'] ?? json['CdLot']),
      descricao:
          (json['Descricao'] ??
                  json['descricao'] ??
                  json['Produto'] ??
                  json['produto'] ??
                  '')
              .toString()
              .trim(),
      qtAlocada: _toDouble(
        json['QtSaldoFinal'] ??
            json['qtSaldoFinal'] ??
            json['SaldoFinal'] ??
            json['saldoFinal'] ??
            json['QtSaldo'] ??
            json['qtSaldo'] ??
            json['QtAlocada'] ??
            json['qt_alocada'] ??
            json['Quantidade'],
      ),
      qtCaixaP: _toInt(json['QtCaixaP'] ?? json['qt_caixa_p']),
      qtCaixaG: _toInt(json['QtCaixaG'] ?? json['qt_caixa_g']),
      qtEnfestado: _toInt(json['QtEnfestado'] ?? json['qt_enfestado']),
      qtEnfraldado: _toInt(json['QtEnfraldado'] ?? json['qt_enfraldado']),
    );
  }
}

class AlocacaoService {
  AlocacaoService._internal();

  static const String _baseUrl = 'http://168.190.90.2:5000';
  static const String _nodeUrlPrefKey = 'sync_node_base_url';
  static const String _defaultNodeUrl =
      'https://api.stiktech.com.br';
  static const String _listarAlocacaoPath =
      '$_baseUrl/consulta/wms/listar_alocacao';
  static const String _listarMovimentosPath =
      '$_baseUrl/consulta/wms/movimentos';
  static const String _movimentarPaletePath =
      '$_baseUrl/consulta/wms/movimentar';
  static const String _transferirPaleteEmbalagemPath =
      '$_baseUrl/consulta/wms/transferir_palete_embalagem';
  static const String _alocarEmbalagemPath =
      '$_baseUrl/consulta/wms/alocar_embalagem';
  static const String _paleteRelatorioPath =
      '$_baseUrl/consulta/wms/palete/relatorio';
  static const String _paleteBuscaArtigoPath =
      '$_baseUrl/consulta/wms/palete/busca_artigo';
  static const String _paleteItensEmbalagemPath =
      '$_baseUrl/consulta/wms/palete/itens_embalagem';
  static const String _ajustarPaleteEmbalagemPath =
      '$_baseUrl/consulta/wms/palete/ajustar_embalagem';
  static const String _auditarPaletePath =
      '$_baseUrl/consulta/wms/palete/auditar';
  static const String _saidaEmbalagemPath =
      '$_baseUrl/consulta/wms/saida_embalagem';
  static const String _canceladosSaldoPath =
      '$_baseUrl/consulta/wms/cancelados/saldo';
  static const String _canceladosAlocarPath =
      '$_baseUrl/consulta/wms/cancelados/alocar';
  static const String _notasCanceladasBasePath =
      '$_baseUrl/consulta/wms/notas_canceladas';
  static const String _gerarAlocacaoPath =
      '$_baseUrl/consulta/wms/gerar_alocacao';
  static const String _atualizarQtMaximaPath =
      '$_baseUrl/consulta/wms/atualizar_qtmaxima';
  static const Duration _listarAlocacaoTimeout = Duration(seconds: 45);
  static const Duration _listarMovimentosTimeout = Duration(seconds: 60);
  static const Duration _paleteRelatorioTimeout = Duration(seconds: 45);
  static const Duration _buscarArtigoTimeout = Duration(seconds: 30);

  static final AlocacaoService _instance = AlocacaoService._internal();

  factory AlocacaoService() => _instance;

  void _perfLog(String etapa, int elapsedMs, [String? detalhe]) {
    if (!kDebugMode) return;
    final suffix = detalhe == null || detalhe.isEmpty ? '' : ' | $detalhe';
    debugPrint('⏱️ [SEPARACAO_PERF] $etapa: ${elapsedMs} ms$suffix');
  }

  /// Busca alocações filtrando por SKUs no servidor (menos dados trafegados).
  /// Passa [skus] como parâmetro `cod_skus` separado por vírgula.
  /// Em caso de falha, faz fallback para [listarAlocacoes].
  Future<List<AlocacaoEntry>> listarAlocacoesFiltradas(Set<String> skus) async {
    if (skus.isEmpty) return listarAlocacoes();
    final stopwatch = Stopwatch()..start();
    final skuParam = skus.join(',');
    final uri = Uri.parse(
      _listarAlocacaoPath,
    ).replace(queryParameters: {'cod_skus': skuParam});
    try {
      final response = await http
          .get(uri)
          .timeout(
            _listarAlocacaoTimeout,
            onTimeout: () =>
                throw Exception('Timeout ao consultar alocações filtradas.'),
          );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          _perfLog(
            'HTTP listar_alocacao [filtrada]',
            stopwatch.elapsedMilliseconds,
            'skus=${skus.length} rows=${decoded.length}',
          );
          return decoded
              .whereType<Map<String, dynamic>>()
              .map(AlocacaoEntry.fromJson)
              .toList();
        }
      }
    } catch (e) {
      debugPrint(
        '⚠️ Falha ao consultar alocações filtradas ($e). Usando lista completa.',
      );
    }
    // Fallback: busca todas (servidor pode não suportar o filtro)
    return listarAlocacoes();
  }

  Future<List<AlocacaoEntry>> listarAlocacoes() async {
    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse(_listarAlocacaoPath);
    final response = await http
        .get(uri)
        .timeout(
          _listarAlocacaoTimeout,
          onTimeout: () => throw Exception('Timeout ao consultar alocações.'),
        );

    if (response.statusCode != 200) {
      throw Exception(
        'Erro ao buscar alocações (Status ${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Formato inesperado recebido ao listar alocações.');
    }
    _perfLog(
      'HTTP listar_alocacao [base]',
      stopwatch.elapsedMilliseconds,
      'rows=${decoded.length}',
    );

    const String enderecoFiltroLog = 'PA-L1-R1-D-P2';
    final filteredForLog = decoded.whereType<Map<String, dynamic>>().where(
      (entry) =>
          (entry['Endereco'] ?? entry['endereco'] ?? '')
              .toString()
              .trim()
              .toUpperCase() ==
          enderecoFiltroLog,
    );

    // Loga apenas as alocações do endereço solicitado para inspeção no terminal.
    // ignore: avoid_print

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(AlocacaoEntry.fromJson)
        .toList();
  }

  Future<List<MovimentoEntry>> listarMovimentos() async {
    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse(_listarMovimentosPath);
    final response = await http
        .get(uri)
        .timeout(
          _listarMovimentosTimeout,
          onTimeout: () => throw Exception('Timeout ao consultar movimentos.'),
        );

    if (response.statusCode != 200) {
      throw Exception(
        'Erro ao buscar movimentos (Status ${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Formato inesperado recebido ao listar movimentos.');
    }
    _perfLog(
      'HTTP movimentos',
      stopwatch.elapsedMilliseconds,
      'rows=${decoded.length}',
    );

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(MovimentoEntry.fromJson)
        .toList();
  }

  Future<List<AlocacaoEntry>> listarAlocacoesComMovimentos() async {
    final results = await Future.wait([listarAlocacoes(), listarMovimentos()]);
    final alocacoes = results[0] as List<AlocacaoEntry>;
    final movimentos = results[1] as List<MovimentoEntry>;

    return _mesclarAlocacoesComMovimentos(alocacoes, movimentos);
  }

  List<AlocacaoEntry> _mesclarAlocacoesComMovimentos(
    List<AlocacaoEntry> alocacoes,
    List<MovimentoEntry> movimentos, {
    Set<int>? skusFiltro,
  }) {
    final Map<String, List<MovimentoEntry>> movimentosPorChave = {};
    final Map<String, List<MovimentoEntry>> movimentosPorEnderecoSku = {};
    final Map<String, _MovimentoInfo> infoPorChave = {};
    for (final mov in movimentos) {
      if (mov.endereco.isEmpty || mov.codSku == 0) continue;
      if (skusFiltro != null && !skusFiltro.contains(mov.codSku)) continue;
      // Não filtramos por tpMov aqui: todos os movimentos são incluídos.
      // _somarMovimentos trata entradas (1, 3) e qualquer outro tipo como saída.
      final key = _buildKey(mov.endereco, mov.codSku, mov.detalheId);
      final enderecoSkuKey = _buildEnderecoSkuKey(mov.endereco, mov.codSku);
      movimentosPorChave.putIfAbsent(key, () => <MovimentoEntry>[]).add(mov);
      movimentosPorEnderecoSku
          .putIfAbsent(enderecoSkuKey, () => <MovimentoEntry>[])
          .add(mov);
      infoPorChave.putIfAbsent(
        key,
        () => _MovimentoInfo(
          endereco: mov.endereco,
          codSku: mov.codSku,
          detalheId: mov.detalheId,
        ),
      );
    }

    if (movimentosPorChave.isEmpty) return alocacoes;

    final Map<String, AlocacaoEntry> basePorChave = {
      for (final entry in alocacoes)
        _buildKey(entry.endereco, entry.codSku, entry.detalheId): entry,
    };

    final List<AlocacaoEntry> merged = alocacoes.map((entry) {
      final key = _buildKey(entry.endereco, entry.codSku, entry.detalheId);
      final movimentosDaChave =
          _resolverMovimentosDaEntrada(
            entry: entry,
            key: key,
            movimentosPorChave: movimentosPorChave,
            movimentosPorEnderecoSku: movimentosPorEnderecoSku,
          ) ??
          const <MovimentoEntry>[];
      final movimentosAjuste = _filtrarMovimentosAposDataBase(
        movimentosDaChave,
        entry.dataAtualizacao,
      );
      final totais = _somarMovimentos(movimentosAjuste);
      final entradas = totais.entradas;
      final saidas = totais.saidas;
      final retornos = totais.retornos;
      // Usa qtSaldoFinal quando o API retorna o saldo atual já calculado;
      // caso contrário cai para qtAlocada (alocação original).
      final saldoInicial = entry.saldoFinalInformado
          ? entry.qtSaldoFinal
          : entry.qtAlocada;
      final saldoFinal = (saldoInicial + entradas + retornos) - saidas;
      return entry.copyWith(
        qtAlocada: saldoFinal.round(),
        qtSaldoInicial: saldoInicial,
        qtMovEntrada: entradas.round(),
        qtMovRetorno: retornos.round(),
        qtMovSaida: saidas.round(),
        qtSaldoFinal: saldoFinal.round(),
      );
    }).toList();

    for (final entry in movimentosPorChave.entries) {
      if (basePorChave.containsKey(entry.key)) continue;
      final info = infoPorChave[entry.key];
      if (info == null) continue;
      final totais = _somarMovimentos(entry.value);
      final saldoFinal = (totais.entradas + totais.retornos) - totais.saidas;
      final detalheId = info.detalheId;
      final detalhe = detalheId > 0 ? detalheId.toString() : '';
      merged.add(
        AlocacaoEntry(
          codSku: info.codSku,
          endereco: info.endereco.trim(),
          produto: 'SKU ${info.codSku}',
          qtAlocada: saldoFinal.round(),
          qtSaldoInicial: 0,
          qtMovEntrada: totais.entradas.round(),
          qtMovRetorno: totais.retornos.round(),
          qtMovSaida: totais.saidas.round(),
          qtSaldoFinal: saldoFinal.round(),
          dataAtualizacao: null,
          id: null,
          qtMaxima: 0,
          detalhe: detalhe,
          detalheId: detalheId,
          nmLot: '',
          qtCaixaP: 0,
          qtCaixaG: 0,
          qtEnfestado: 0,
          qtEnfraldado: 0,
        ),
      );
    }

    return merged;
  }

  Future<List<AlocacaoEntry>> listarRelatorioPalete({
    required String endereco,
  }) async {
    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse(
      '$_paleteRelatorioPath?endereco=${Uri.encodeQueryComponent(endereco)}',
    );
    final response = await http
        .get(uri)
        .timeout(
          _paleteRelatorioTimeout,
          onTimeout: () => throw Exception('Timeout ao consultar palete.'),
        );

    if (response.statusCode != 200) {
      throw Exception(
        'Erro ao buscar palete (Status ${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Formato inesperado recebido ao consultar palete.');
    }
    _perfLog(
      'HTTP palete/relatorio',
      stopwatch.elapsedMilliseconds,
      'endereco=$endereco rows=${decoded.length}',
    );

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(AlocacaoEntry.fromJson)
        .toList();
  }

  Future<List<AlocacaoEntry>> buscarArtigoEmPaletes({
    required String query,
  }) async {
    final uri = Uri.parse(
      '$_paleteBuscaArtigoPath?q=${Uri.encodeQueryComponent(query)}',
    );
    final response = await http
        .get(uri)
        .timeout(
          _buscarArtigoTimeout,
          onTimeout: () => throw Exception('Timeout ao buscar artigo.'),
        );

    if (response.statusCode != 200) {
      throw Exception(
        'Erro ao buscar artigo em paletes (Status ${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception(
        'Formato inesperado recebido ao buscar artigo em paletes.',
      );
    }

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(AlocacaoEntry.fromJson)
        .toList();
  }

  List<MovimentoEntry>? _resolverMovimentosDaEntrada({
    required AlocacaoEntry entry,
    required String key,
    required Map<String, List<MovimentoEntry>> movimentosPorChave,
    required Map<String, List<MovimentoEntry>> movimentosPorEnderecoSku,
  }) {
    final exatos = movimentosPorChave[key];
    if (exatos != null && exatos.isNotEmpty) return exatos;

    final enderecoSkuKey = _buildEnderecoSkuKey(entry.endereco, entry.codSku);
    final candidatos = movimentosPorEnderecoSku[enderecoSkuKey];
    if (candidatos == null || candidatos.isEmpty) return null;

    // Fallback 1: alguns cenários registram movimento com detalhe 0.
    if (entry.detalheId > 0) {
      final detalheZero = candidatos.where((m) => m.detalheId == 0).toList();
      if (detalheZero.isNotEmpty) return detalheZero;
      return null;
    }

    // Fallback 2: alocação sem detalhe numérico, mas movimentos têm 1 único detalhe.
    final detalheUnico = candidatos
        .map((m) => m.detalheId)
        .where((id) => id > 0)
        .toSet();
    if (detalheUnico.length == 1) return candidatos;

    return null;
  }

  List<MovimentoEntry> _filtrarMovimentosAposDataBase(
    List<MovimentoEntry> movimentos,
    DateTime? dataBase,
  ) {
    if (dataBase == null) return movimentos;
    return movimentos.where((mov) {
      final dataMov = mov.dataMovimento;
      if (dataMov == null) return false;
      return dataMov.isAfter(dataBase);
    }).toList();
  }

  _MovimentoTotais _somarMovimentos(Iterable<MovimentoEntry> movimentos) {
    final totais = _MovimentoTotais();
    for (final mov in movimentos) {
      if (mov.tpMov == 1) {
        totais.entradas += mov.qtMovida;
      } else if (mov.tpMov == 3) {
        totais.retornos += mov.qtMovida;
      } else {
        // tpMov=2 (saída) e qualquer tipo não reconhecido são tratados como
        // redução de estoque para evitar sugestão de paletes sem saldo real.
        totais.saidas += mov.qtMovida;
      }
    }
    return totais;
  }

  Future<void> registrarMovimentoPalete({
    required String endereco,
    required int codSku,
    required int detalheId,
    required int tpMov,
    required double quantidade,
    String? detalheRaw,
  }) async {
    if (quantidade <= 0) return;
    final payload = {
      'Endereco': endereco,
      'CodSKU': codSku,
      'CdObj': codSku,
      'Detalhe': detalheRaw?.isNotEmpty == true ? detalheRaw : detalheId,
      'TpMov': tpMov,
      'QtMovida': quantidade,
    };
    final uri = Uri.parse(_movimentarPaletePath);
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Erro ${response.statusCode} ao movimentar palete: ${response.body}',
      );
    }
  }

  Future<Map<String, dynamic>> auditarPalete({
    required String endereco,
    required List<Map<String, dynamic>> itens,
    int? cdUsr,
    String? observacao,
  }) async {
    final payload = {
      'endereco': endereco.trim().toUpperCase(),
      'itens': itens,
      if (cdUsr != null) 'cd_usr': cdUsr,
      if ((observacao ?? '').trim().isNotEmpty)
        'observacao': observacao!.trim(),
    };
    final uri = Uri.parse(_auditarPaletePath);
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw Exception('Timeout ao auditar palete.'),
        );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Erro ${response.statusCode} ao auditar palete: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {'success': true};
  }

  Future<void> registrarTransferenciaEmbalagem({
    required String enderecoOrigem,
    required String enderecoDestino,
    required int codSku,
    required int detalheId,
    required String artigo,
    required double quantidade,
    int qtCaixaP = 0,
    int qtCaixaG = 0,
    int qtEnfestado = 0,
    int qtEnfraldado = 0,
    String? cdUsr,
  }) async {
    final cdUsrNormalizado = int.tryParse((cdUsr ?? '').trim());
    final payload = {
      'endereco_origem': enderecoOrigem,
      'endereco_destino': enderecoDestino,
      'cod_sku': codSku,
      'detalhe': detalheId,
      'artigo': artigo,
      'quantidade': quantidade,
      'qt_caixa_p': qtCaixaP,
      'qt_caixa_g': qtCaixaG,
      'qt_enfestado': qtEnfestado,
      'qt_enfraldado': qtEnfraldado,
      if (cdUsrNormalizado != null) 'cd_usr': cdUsrNormalizado,
    };
    final uri = Uri.parse(_transferirPaleteEmbalagemPath);
    debugPrint('[TRANSFERIR] POST $uri');
    debugPrint('[TRANSFERIR] payload: ${jsonEncode(payload)}');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));
    debugPrint('[TRANSFERIR] status: ${response.statusCode}');
    debugPrint('[TRANSFERIR] body: ${response.body}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Erro ${response.statusCode} ao registrar embalagem: ${response.body}',
      );
    }
  }

  Future<void> alocarEmbalagem({
    required String endereco,
    required int codSku,
    required int detalheId,
    required String artigo,
    required double quantidade,
    required int qtCaixaP,
    required int qtCaixaG,
    required int qtEnfestado,
    required int qtEnfraldado,
    String? cdUsr,
    String origem = 'CANCELADOS',
  }) async {
    final cdUsrNormalizado = int.tryParse((cdUsr ?? '').trim());
    final payload = {
      'endereco': endereco,
      'cod_sku': codSku,
      'detalhe': detalheId,
      'artigo': artigo,
      'quantidade': quantidade,
      'qt_caixa_p': qtCaixaP,
      'qt_caixa_g': qtCaixaG,
      'qt_enfestado': qtEnfestado,
      'qt_enfraldado': qtEnfraldado,
      'origem': origem,
      if (cdUsrNormalizado != null) 'cd_usr': cdUsrNormalizado,
    };
    final uri = Uri.parse(_alocarEmbalagemPath);
    debugPrint('[ALOCAR] POST $uri');
    debugPrint('[ALOCAR] payload: ${jsonEncode(payload)}');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));
    debugPrint('[ALOCAR] status: ${response.statusCode}');
    debugPrint('[ALOCAR] body: ${response.body}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Erro ${response.statusCode} ao registrar embalagem: ${response.body}',
      );
    }
  }

  Future<List<PaleteEmbalagemItemEntry>> consultarItensPaleteParaAjuste({
    required String endereco,
  }) async {
    final end = endereco.trim().toUpperCase();
    final stopwatch = Stopwatch()..start();
    try {
      final itens = await listarItensEmbalagemPalete(endereco: end);
      _perfLog(
        'HTTP consultarItensPaleteParaAjuste [itens_embalagem]',
        stopwatch.elapsedMilliseconds,
        'endereco=$end rows=${itens.length}',
      );
      return itens;
    } catch (_) {
      final relatorio = await listarRelatorioPalete(endereco: end);
      _perfLog(
        'HTTP consultarItensPaleteParaAjuste [relatorio]',
        stopwatch.elapsedMilliseconds,
        'endereco=$end rows=${relatorio.length}',
      );
      return relatorio
          .map(
            (item) => PaleteEmbalagemItemEntry(
              endereco: item.endereco,
              codSku: item.codSku,
              detalhe: item.detalheId,
              descricao: item.produto,
              qtAlocada: item.qtSaldoFinal.toDouble(),
              qtCaixaP: item.qtCaixaP,
              qtCaixaG: item.qtCaixaG,
              qtEnfestado: item.qtEnfestado,
              qtEnfraldado: item.qtEnfraldado,
            ),
          )
          .toList();
    }
  }

  Future<List<PaleteEmbalagemItemEntry>> listarItensEmbalagemPalete({
    required String endereco,
  }) async {
    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse(
      '$_paleteItensEmbalagemPath?endereco=${Uri.encodeQueryComponent(endereco.trim().toUpperCase())}',
    );
    final response = await http
        .get(uri)
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw Exception(
            'Timeout ao consultar itens de embalagem do palete.',
          ),
        );

    if (response.statusCode != 200) {
      throw Exception(
        'Erro ao buscar itens de embalagem (Status ${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception(
        'Formato inesperado recebido ao consultar itens de embalagem.',
      );
    }
    _perfLog(
      'HTTP palete/itens_embalagem',
      stopwatch.elapsedMilliseconds,
      'endereco=${endereco.trim().toUpperCase()} rows=${decoded.length}',
    );

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(PaleteEmbalagemItemEntry.fromJson)
        .toList();
  }

  Future<void> salvarAjusteEmbalagemPalete({
    required String endereco,
    required int codSku,
    required int detalhe,
    required String artigo,
    required int qtCaixaP,
    required int qtCaixaG,
    required int qtEnfestado,
    required int qtEnfraldado,
    String? cdUsr,
    String? nmLot,
  }) async {
    final end = endereco.trim().toUpperCase();
    final cdUsrNormalizado = int.tryParse((cdUsr ?? '').trim());

    final atual = await _buscarItemEmbalagemAtual(
      endereco: end,
      codSku: codSku,
      detalhe: detalhe,
    );
    if (atual == null) {
      await _criarEmbalagemInicialSeNecessario(
        endereco: end,
        codSku: codSku,
        detalhe: detalhe,
        artigo: artigo,
        qtCaixaP: qtCaixaP,
        qtCaixaG: qtCaixaG,
        qtEnfestado: qtEnfestado,
        qtEnfraldado: qtEnfraldado,
        cdUsr: cdUsr,
      );
      return;
    }

    Map<String, dynamic> buildPayload({required int detalheParaEnviar}) {
      // O backend usa estes nomes exatamente (veja ajustar_embalagem_palete).
      return <String, dynamic>{
        'endereco': end,
        'cod_sku': codSku,
        'detalhe': detalheParaEnviar,
        'artigo': artigo,
        if (cdUsrNormalizado != null) 'cd_usr': cdUsrNormalizado,
        'qt_caixa_p': qtCaixaP,
        'qt_caixa_g': qtCaixaG,
        'qt_enfestado': qtEnfestado,
        'qt_enfraldado': qtEnfraldado,
      };
    }

    Future<http.Response> postAjuste() async {
      final payload = buildPayload(detalheParaEnviar: detalhe);

      if (kDebugMode) {
        debugPrint(
          '📦 [AJUSTE_EMBALAGEM] POST '
          'End=$end SKU=$codSku Det=$detalhe '
          'P=$qtCaixaP G=$qtCaixaG ENFE=$qtEnfestado ENFR=$qtEnfraldado',
        );
      }

      final uri = Uri.parse(_ajustarPaleteEmbalagemPath);
      return http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
    }

    final response = await postAjuste();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? detalheErro;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final msg =
              decoded['error'] ?? decoded['message'] ?? decoded['mensagem'];
          if (msg != null && msg.toString().trim().isNotEmpty) {
            detalheErro = msg.toString().trim();
          }
        }
      } catch (_) {}

      if (kDebugMode) {
        debugPrint(
          '❌ [AJUSTE_EMBALAGEM] Falha Status=${response.statusCode} '
          'End=$end SKU=$codSku Det=$detalhe '
          'Body=${response.body}',
        );
      }
      throw Exception(
        'Erro ${response.statusCode} ao salvar ajuste de embalagem: ${detalheErro ?? response.body}',
      );
    }

    await _garantirAjusteRefletidoNaAlocacao(
      endereco: end,
      codSku: codSku,
      detalhe: detalhe,
      artigo: artigo,
      alvoCaixaP: qtCaixaP,
      alvoCaixaG: qtCaixaG,
      alvoEnfestado: qtEnfestado,
      alvoEnfraldado: qtEnfraldado,
      cdUsr: cdUsr,
    );
  }

  Future<void> _criarEmbalagemInicialSeNecessario({
    required String endereco,
    required int codSku,
    required int detalhe,
    required String artigo,
    required int qtCaixaP,
    required int qtCaixaG,
    required int qtEnfestado,
    required int qtEnfraldado,
    String? cdUsr,
  }) async {
    if (qtCaixaP == 0 &&
        qtCaixaG == 0 &&
        qtEnfestado == 0 &&
        qtEnfraldado == 0) {
      return;
    }

    final padrao = await PadraoCaixaService().buscarPadraoPorArtigo(artigo);
    if (padrao == null || padrao.isEmpty) {
      throw Exception(
        'Item sem embalagem cadastrada no palete e sem padrão de caixa para criar o ajuste do artigo "$artigo".',
      );
    }

    final metrosP = _toInt(
      padrao['caixa_p'] ?? padrao['caixaP'] ?? padrao['CaixaP'],
    );
    final metrosG = _toInt(
      padrao['caixa_g'] ?? padrao['caixaG'] ?? padrao['CaixaG'],
    );
    final metrosEnfe = _toInt(padrao['enfestado'] ?? padrao['Enfestado']);
    final metrosEnfr = _toInt(padrao['enfraldado'] ?? padrao['Enfraldado']);

    final quantidade =
        (qtCaixaP * metrosP) +
        (qtCaixaG * metrosG) +
        (qtEnfestado * metrosEnfe) +
        (qtEnfraldado * metrosEnfr);
    if (quantidade <= 0) {
      throw Exception(
        'Não foi possível calcular metragem para cadastrar embalagem inicial do artigo "$artigo".',
      );
    }

    await alocarEmbalagem(
      endereco: endereco,
      codSku: codSku,
      detalheId: detalhe,
      artigo: artigo,
      quantidade: quantidade.toDouble(),
      qtCaixaP: qtCaixaP,
      qtCaixaG: qtCaixaG,
      qtEnfestado: qtEnfestado,
      qtEnfraldado: qtEnfraldado,
      cdUsr: cdUsr,
      origem: 'AJUSTE_INICIAL',
    );

    final criado = await _buscarItemEmbalagemAtual(
      endereco: endereco,
      codSku: codSku,
      detalhe: detalhe,
    );
    if (criado == null) {
      throw Exception(
        'Embalagem inicial enviada, mas o item ainda não aparece no palete.',
      );
    }
  }

  Future<void> _garantirAjusteRefletidoNaAlocacao({
    required String endereco,
    required int codSku,
    required int detalhe,
    required String artigo,
    required int alvoCaixaP,
    required int alvoCaixaG,
    required int alvoEnfestado,
    required int alvoEnfraldado,
    String? cdUsr,
  }) async {
    PaleteEmbalagemItemEntry? atual = await _buscarItemEmbalagemAtual(
      endereco: endereco,
      codSku: codSku,
      detalhe: detalhe,
    );

    final atualP = atual?.qtCaixaP ?? 0;
    final atualG = atual?.qtCaixaG ?? 0;
    final atualEnfe = atual?.qtEnfestado ?? 0;
    final atualEnfr = atual?.qtEnfraldado ?? 0;

    if (atualP == alvoCaixaP &&
        atualG == alvoCaixaG &&
        atualEnfe == alvoEnfestado &&
        atualEnfr == alvoEnfraldado) {
      return;
    }

    final padrao = await PadraoCaixaService().buscarPadraoPorArtigo(artigo);
    if (padrao == null || padrao.isEmpty) {
      throw Exception(
        'Ajuste registrado, mas sem padrão de caixa para sincronizar alocação de embalagem do artigo "$artigo".',
      );
    }

    final metrosP = _toInt(
      padrao['caixa_p'] ?? padrao['caixaP'] ?? padrao['CaixaP'],
    );
    final metrosG = _toInt(
      padrao['caixa_g'] ?? padrao['caixaG'] ?? padrao['CaixaG'],
    );
    final metrosEnfe = _toInt(padrao['enfestado'] ?? padrao['Enfestado']);
    final metrosEnfr = _toInt(padrao['enfraldado'] ?? padrao['Enfraldado']);

    final deltaP = alvoCaixaP - atualP;
    final deltaG = alvoCaixaG - atualG;
    final deltaEnfe = alvoEnfestado - atualEnfe;
    final deltaEnfr = alvoEnfraldado - atualEnfr;

    final saidaP = deltaP < 0 ? -deltaP : 0;
    final saidaG = deltaG < 0 ? -deltaG : 0;
    final saidaEnfe = deltaEnfe < 0 ? -deltaEnfe : 0;
    final saidaEnfr = deltaEnfr < 0 ? -deltaEnfr : 0;

    if (saidaP > 0 || saidaG > 0 || saidaEnfe > 0 || saidaEnfr > 0) {
      final metrosSaida =
          (saidaP * metrosP) +
          (saidaG * metrosG) +
          (saidaEnfe * metrosEnfe) +
          (saidaEnfr * metrosEnfr);
      if (metrosSaida <= 0) {
        throw Exception(
          'Não foi possível calcular metragem de saída para sincronizar embalagem.',
        );
      }
      await registrarSaidaEmbalagem(
        endereco: endereco,
        codSku: codSku,
        detalhe: detalhe,
        artigo: artigo,
        qtCaixaP: saidaP,
        qtCaixaG: saidaG,
        qtEnfestado: saidaEnfe,
        qtEnfraldado: saidaEnfr,
        quantidade: metrosSaida.toDouble(),
        cdUsr: cdUsr,
      );
    }

    final entradaP = deltaP > 0 ? deltaP : 0;
    final entradaG = deltaG > 0 ? deltaG : 0;
    final entradaEnfe = deltaEnfe > 0 ? deltaEnfe : 0;
    final entradaEnfr = deltaEnfr > 0 ? deltaEnfr : 0;

    if (entradaP > 0 || entradaG > 0 || entradaEnfe > 0 || entradaEnfr > 0) {
      final metrosEntrada =
          (entradaP * metrosP) +
          (entradaG * metrosG) +
          (entradaEnfe * metrosEnfe) +
          (entradaEnfr * metrosEnfr);
      if (metrosEntrada <= 0) {
        throw Exception(
          'Não foi possível calcular metragem de entrada para sincronizar embalagem.',
        );
      }
      await alocarEmbalagem(
        endereco: endereco,
        codSku: codSku,
        detalheId: detalhe,
        artigo: artigo,
        quantidade: metrosEntrada.toDouble(),
        qtCaixaP: entradaP,
        qtCaixaG: entradaG,
        qtEnfestado: entradaEnfe,
        qtEnfraldado: entradaEnfr,
        cdUsr: cdUsr,
        origem: 'AJUSTE_SYNC',
      );
    }

    atual = await _buscarItemEmbalagemAtual(
      endereco: endereco,
      codSku: codSku,
      detalhe: detalhe,
    );
    final finalP = atual?.qtCaixaP ?? 0;
    final finalG = atual?.qtCaixaG ?? 0;
    final finalEnfe = atual?.qtEnfestado ?? 0;
    final finalEnfr = atual?.qtEnfraldado ?? 0;

    if (finalP != alvoCaixaP ||
        finalG != alvoCaixaG ||
        finalEnfe != alvoEnfestado ||
        finalEnfr != alvoEnfraldado) {
      throw Exception(
        'Ajuste salvo, mas alocação de embalagem não convergiu '
        '(atual P=$finalP G=$finalG ENFE=$finalEnfe ENFR=$finalEnfr | '
        'alvo P=$alvoCaixaP G=$alvoCaixaG ENFE=$alvoEnfestado ENFR=$alvoEnfraldado).',
      );
    }
  }

  Future<PaleteEmbalagemItemEntry?> _buscarItemEmbalagemAtual({
    required String endereco,
    required int codSku,
    required int detalhe,
  }) async {
    final itens = await listarItensEmbalagemPalete(endereco: endereco);
    final exato = itens.where(
      (item) => item.codSku == codSku && item.detalhe == detalhe,
    );
    if (exato.isNotEmpty) return exato.first;

    final skuOnly = itens.where((item) => item.codSku == codSku).toList();
    if (skuOnly.length == 1) return skuOnly.first;
    return null;
  }

  Future<void> registrarSaidaEmbalagem({
    required String endereco,
    required int codSku,
    required int detalhe,
    required String artigo,
    required int qtCaixaP,
    required int qtCaixaG,
    required int qtEnfestado,
    required int qtEnfraldado,
    double quantidade = 0,
    String? cdUsr,
  }) async {
    final cdUsrNormalizado = int.tryParse((cdUsr ?? '').trim());
    final end = endereco.trim().toUpperCase();
    final payload = {
      // variantes para compatibilidade do backend
      'endereco': end,
      'Endereco': end,
      'EnderecoOrigem': end,
      'cod_sku': codSku,
      'CodSKU': codSku,
      'CdObj': codSku,
      'detalhe': detalhe,
      'Detalhe': detalhe,
      'artigo': artigo,
      'tp_mov': 2,
      'TpMov': 2,
      'qt_caixa_p': qtCaixaP,
      'qt_caixa_g': qtCaixaG,
      'qt_enfestado': qtEnfestado,
      'qt_enfraldado': qtEnfraldado,
      // variantes com inicial maiúscula
      'QtCaixaP': qtCaixaP,
      'QtCaixaG': qtCaixaG,
      'QtEnfestado': qtEnfestado,
      'QtEnfraldado': qtEnfraldado,
      // metragem movida
      'quantidade': quantidade,
      'QtMovidaMetro': quantidade,
      'QtMovida': quantidade,
      if (cdUsrNormalizado != null) 'cd_usr': cdUsrNormalizado,
      if (cdUsrNormalizado != null) 'CdUsr': cdUsrNormalizado,
    };
    final uri = Uri.parse(_saidaEmbalagemPath);
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Erro ${response.statusCode} na saída de embalagem: ${response.body}',
      );
    }
  }

  Future<CanceladoSaldoEntry> consultarSaldoCancelado({
    required int codSku,
    required int cdLot,
    required DateTime dataInicial,
    required DateTime dataFinal,
  }) async {
    final uri = Uri.parse(_canceladosSaldoPath).replace(
      queryParameters: {
        'CdObj': codSku.toString(),
        'CdLot': cdLot.toString(),
        'data_inicial': DateFormat('yyyy-MM-dd').format(dataInicial),
        'data_final': DateFormat('yyyy-MM-dd').format(dataFinal),
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception(
        'Erro ${response.statusCode} ao consultar saldo de cancelados: ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Formato inesperado no saldo de cancelados.');
    }
    return CanceladoSaldoEntry.fromJson(decoded);
  }

  Future<void> alocarItemCancelado({
    required String endereco,
    required int codSku,
    required int cdLot,
    required double quantidade,
    required DateTime dataInicial,
    required DateTime dataFinal,
    required String fonte,
    String? cdUsr,
  }) async {
    final cdUsrNormalizado = int.tryParse((cdUsr ?? '').trim());
    final payload = {
      'Endereco': endereco,
      'CdObj': codSku,
      'CdLot': cdLot,
      'Quantidade': quantidade,
      'DataInicial': DateFormat('yyyy-MM-dd').format(dataInicial),
      'DataFinal': DateFormat('yyyy-MM-dd').format(dataFinal),
      'Fonte': fonte,
      if (cdUsrNormalizado != null) 'CdUsr': cdUsrNormalizado,
    };
    final uri = Uri.parse(_canceladosAlocarPath);
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Erro ${response.statusCode} ao alocar item cancelado: ${response.body}',
      );
    }
  }

  Future<List<NotaCanceladaEntry>> consultarNotasCanceladas({
    required DateTime dataInicial,
    required DateTime dataFinal,
    int? codSku,
    int? cdLot,
  }) async {
    final dataInicialFmt = DateFormat('yyyy-MM-dd').format(dataInicial);
    final dataFinalFmt = DateFormat('yyyy-MM-dd').format(dataFinal);
    final uri =
        Uri.parse(
          '$_notasCanceladasBasePath/$dataInicialFmt/$dataFinalFmt',
        ).replace(
          queryParameters: {
            if (codSku != null) 'sku': codSku.toString(),
            if (cdLot != null && cdLot > 0) 'lote': cdLot.toString(),
          },
        );
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception(
        'Erro ${response.statusCode} ao consultar notas canceladas: ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Formato inesperado na consulta de notas canceladas.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(NotaCanceladaEntry.fromJson)
        .toList(growable: false);
  }

  Future<void> atualizarQtMaxima({
    required String endereco,
    required int qtMaxima,
  }) async {
    if (qtMaxima <= 0) {
      throw Exception('Quantidade máxima inválida.');
    }
    final payload = {'Endereco': endereco, 'QtMaxima': qtMaxima};
    final uri = Uri.parse(_atualizarQtMaximaPath);
    if (kDebugMode) {
      // ignore: avoid_print
      print('[QTMAX] Atualizando via: $uri');
    }
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Erro ${response.statusCode} ao atualizar QtMaxima: ${response.body}',
      );
    }
  }

  Future<void> registrarAuditoriaQtMaxima({
    required String endereco,
    required int quantidadeAnterior,
    required int quantidadeNova,
    required String autorizadorCdUsr,
    required String autorizadorNmUsr,
    required bool sucesso,
    String? erro,
  }) async {
    final payload = {
      'timestamp': DateTime.now().toIso8601String(),
      'endereco': endereco,
      'qt_max_anterior': quantidadeAnterior,
      'qt_max_nova': quantidadeNova,
      'autorizador_cd_usr': autorizadorCdUsr,
      'autorizador_nm_usr': autorizadorNmUsr,
      'sucesso': sucesso,
      'origem': 'palete_relatorios',
      if (erro != null && erro.trim().isNotEmpty) 'erro': erro.trim(),
    };
    await _postNodeWithFallback(
      path: '/consulta/wms/qtmax_auditoria',
      payload: payload,
      operacao: 'registrar auditoria QtMaxima',
    );
  }

  /// Ajuste direto por metros (sem conversão por caixas).
  /// Calcula delta = qtFisica - qtSistema e chama saída ou entrada conforme sinal.
  Future<void> auditarAjusteMetrosPalete({
    required String endereco,
    required int codSku,
    required int detalhe,
    required String artigo,
    required double qtSistema,
    required double qtFisica,
    String? cdUsr,
  }) async {
    final delta = qtFisica - qtSistema;
    if (delta == 0) return;
    final end = endereco.trim().toUpperCase();

    if (delta < 0) {
      // Físico < sistema → saída de metros
      await registrarMovimentoPalete(
        endereco: end,
        codSku: codSku,
        detalheId: detalhe,
        detalheRaw: detalhe > 0 ? detalhe.toString() : null,
        tpMov: 2,
        quantidade: -delta,
      );
    } else {
      // Físico > sistema → entrada de metros
      await registrarMovimentoPalete(
        endereco: end,
        codSku: codSku,
        detalheId: detalhe,
        detalheRaw: detalhe > 0 ? detalhe.toString() : null,
        tpMov: 1,
        quantidade: delta,
      );
    }
  }

  Future<void> auditarAjusteEmbalagemPalete({
    required String endereco,
    required int codSku,
    required int detalhe,
    required String artigo,
    required int qtCaixaP,
    required int qtCaixaG,
    required int qtEnfestado,
    required int qtEnfraldado,
    String? cdUsr,
  }) async {
    await salvarAjusteEmbalagemPalete(
      endereco: endereco,
      codSku: codSku,
      detalhe: detalhe,
      artigo: artigo,
      qtCaixaP: qtCaixaP,
      qtCaixaG: qtCaixaG,
      qtEnfestado: qtEnfestado,
      qtEnfraldado: qtEnfraldado,
      cdUsr: cdUsr,
    );
  }

  Future<List<String>> _resolverNodeBaseUrlsRemotas() async {
    final prefs = await SharedPreferences.getInstance();
    final configured = prefs.getString(_nodeUrlPrefKey)?.trim();

    final baseUrls = <String>[
      if (configured != null && configured.isNotEmpty) configured,
      _defaultNodeUrl,
    ];

    final seen = <String>{};
    final normalized = <String>[];
    for (final raw in baseUrls) {
      final value = raw.trim().replaceAll(RegExp(r'/$'), '');
      if (value.isEmpty || seen.contains(value)) continue;
      final lower = value.toLowerCase();
      // QtMax/auditoria não deve usar API local.
      final isHttps = lower.startsWith('https://');
      final isLocalIp =
          lower.contains('168.190.90.2') ||
          lower.contains('localhost') ||
          lower.contains('127.0.0.1');
      if (!isHttps || isLocalIp) continue;
      seen.add(value);
      normalized.add(value);
    }
    return normalized;
  }

  Future<void> _postNodeWithFallback({
    required String path,
    required Map<String, dynamic> payload,
    required String operacao,
  }) async {
    final bases = await _resolverNodeBaseUrlsRemotas();
    if (bases.isEmpty) {
      throw Exception(
        'Falha ao $operacao. Nenhuma URL remota HTTPS configurada para NodeAPI.',
      );
    }
    String? ultimoErro;

    for (final base in bases) {
      final uri = Uri.parse('$base$path');
      try {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[QTMAX_AUDITORIA] Enviando via: $uri');
        }
        final response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode >= 200 && response.statusCode < 300) return;
        ultimoErro =
            '[$uri] ${response.statusCode}: ${response.body.toString().trim()}';
      } catch (e) {
        ultimoErro = '[$uri] $e';
      }
    }

    throw Exception('Falha ao $operacao. $ultimoErro');
  }
}

class _MovimentoTotais {
  double entradas = 0;
  double retornos = 0;
  double saidas = 0;
}

class _MovimentoInfo {
  _MovimentoInfo({
    required this.endereco,
    required this.codSku,
    required this.detalheId,
  });

  final String endereco;
  final int codSku;
  final int detalheId;
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is String) {
    final trimmed = value.trim();
    final direct = int.tryParse(trimmed);
    if (direct != null) return direct;
    final normalized = trimmed.replaceAll(',', '.');
    final asDouble = double.tryParse(normalized);
    return asDouble?.toInt() ?? 0;
  }
  if (value is double) {
    return value.toInt();
  }
  return 0;
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.')) ?? 0;
  }
  return 0;
}

String _buildKey(String endereco, int codSku, int detalheId) {
  final normalizedEndereco = endereco.trim().toUpperCase();
  return '$normalizedEndereco|$codSku|$detalheId';
}

String _buildEnderecoSkuKey(String endereco, int codSku) {
  final normalizedEndereco = endereco.trim().toUpperCase();
  return '$normalizedEndereco|$codSku';
}

DateTime? _parseDataMovimento(dynamic value) {
  return _parseDateTimeFlexible(value);
}

DateTime? _parseDateTimeFlexible(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;

  try {
    final parsed = HttpDate.parse(raw);
    // O backend local pode serializar datetime SQL local como "GMT".
    // Preservamos o horário textual para não deslocar -3h ao comparar cortes.
    return DateTime(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    );
  } catch (_) {}

  try {
    final parsed = DateTime.parse(raw);
    if (parsed.isUtc) {
      // Mantém horário textual quando vier timezone explícito.
      return DateTime(
        parsed.year,
        parsed.month,
        parsed.day,
        parsed.hour,
        parsed.minute,
        parsed.second,
        parsed.millisecond,
        parsed.microsecond,
      );
    }
    return parsed;
  } catch (_) {}

  // SQL Server costuma retornar "yyyy-MM-dd HH:mm:ss(.SSS)" (sem 'T').
  try {
    return DateFormat('yyyy-MM-dd HH:mm:ss').parseStrict(raw);
  } catch (_) {}
  try {
    return DateFormat('yyyy-MM-dd HH:mm:ss.SSS').parseStrict(raw);
  } catch (_) {}
  try {
    return DateFormat('dd/MM/yyyy HH:mm').parseStrict(raw);
  } catch (_) {}
  try {
    return DateFormat('dd/MM/yyyy HH:mm:ss').parseStrict(raw);
  } catch (_) {}

  return null;
}
