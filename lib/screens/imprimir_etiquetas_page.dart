// ignore_for_file: unused_element, unused_field

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart';

import 'imprimir_etiquetas_prefill.dart';
import '../models/linha_etiqueta_livre.dart';
import '../services/alocacao_service.dart';
import '../services/etiquetas_service.dart';
import '../services/padrao_caixa_service.dart';
import '../services/zebra_printer_service.dart';

enum _EtiquetaModelo { palete, caixa, ordens, operador, carretel, livre }

class _OperadorEtiqueta {
  final String codigo;
  final String nome;

  const _OperadorEtiqueta({required this.codigo, required this.nome});

  factory _OperadorEtiqueta.fromJson(Map<String, dynamic> json) {
    return _OperadorEtiqueta(
      codigo:
          (json['CdUser'] ??
                  json['cdUser'] ??
                  json['cd_user'] ??
                  json['CD_USER'] ??
                  json['Operador'] ??
                  json['operador'] ??
                  json['codigo'] ??
                  json['Codigo'] ??
                  '')
              .toString()
              .trim(),
      nome:
          (json['NmUser'] ??
                  json['nmUser'] ??
                  json['nm_user'] ??
                  json['NM_USER'] ??
                  json['nome'] ??
                  json['Nome'] ??
                  '')
              .toString()
              .trim(),
    );
  }

  String get label => nome.isEmpty ? codigo : '$codigo - $nome';
}

class _OrdemExpedicao {
  const _OrdemExpedicao({
    required this.woid,
    required this.salesOrderId,
    required this.skuCode,
    required this.skuName,
    required this.plant,
    required this.quantity,
    required this.orderType,
    required this.productionFamily,
    required this.skuDescription,
    required this.uom,
    required this.stockLocationName,
    required this.dueDate,
    required this.releaseDate,
    required this.alvo,
    required this.localStock,
  });

  final String woid;
  final String salesOrderId;
  final String skuCode;
  final String skuName;
  final String plant;
  final double quantity;
  final String orderType;
  final String productionFamily;
  final String skuDescription;
  final String uom;
  final String stockLocationName;
  final DateTime? dueDate;
  final DateTime? releaseDate;
  final double alvo;
  final double localStock;

  factory _OrdemExpedicao.fromJson(Map<String, dynamic> json) {
    return _OrdemExpedicao(
      woid: _asText(json['WOID']),
      salesOrderId: _asText(json['SalesOrderID']),
      skuCode: _asText(json['SKUCode']),
      skuName: _asText(json['SKUName']),
      plant: _asText(json['Plant']),
      quantity: _asDouble(json['Quantity']),
      orderType: _asText(json['OrderType']),
      productionFamily: _asText(json['ProductionFamily']),
      skuDescription: _asText(json['SKUDescription']),
      uom: _asText(json['UOM']),
      stockLocationName: _asText(json['StockLocationName']),
      dueDate: _asDate(json['DueDate']),
      releaseDate: _asDate(json['ReleaseDate']),
      alvo: _asDouble(json['Alvo']),
      localStock: _asDouble(json['LocalStock']),
    );
  }

  String get titulo => skuDescription.isEmpty ? skuName : skuDescription;

  static String _asText(dynamic value) => value?.toString().trim() ?? '';

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return 0;
    var normalized = raw.replaceAll(RegExp(r'\s+'), '');
    if (normalized.contains(',') && normalized.contains('.')) {
      normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
    } else if (normalized.contains(',')) {
      normalized = normalized.replaceAll(',', '.');
    }
    return double.tryParse(normalized) ?? 0;
  }

  static DateTime? _asDate(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}

class _LinhaLivreEditor {
  final TextEditingController controller = TextEditingController();
  final TextEditingController fonteController = TextEditingController(
    text: '36',
  );
  TamanhoLinhaLivre tamanho = TamanhoLinhaLivre.medio;
  AlinhamentoLinhaLivre alinhamento = AlinhamentoLinhaLivre.centro;
  bool negrito = false;

  void dispose() {
    controller.dispose();
    fonteController.dispose();
  }
}

class _FioLivreEtiqueta {
  const _FioLivreEtiqueta({
    required this.cor,
    required this.titulo,
    required this.lote,
    required this.codigoBarras,
  });

  final String cor;
  final String titulo;
  final String lote;
  final String codigoBarras;
}

enum _LivreTipoModelo { livre, tipoB, fios }

class EtiquetasPage extends StatefulWidget {
  final int grupoId;

  const EtiquetasPage({super.key, required this.grupoId});

  @override
  State<EtiquetasPage> createState() => _EtiquetasPageState();
}

class _EtiquetasPageState extends State<EtiquetasPage> {
  static const List<Map<String, dynamic>> _fallbackPrinters = [
    {'nome': 'EtqCaixa/Carretel 2', 'ip': '168.190.30.206', 'porta': 9100},
    {'nome': 'EtqCaixa/Carretel', 'ip': '168.190.30.181', 'porta': 9100},
    {'nome': 'EtqManual', 'ip': '168.190.30.172', 'porta': 9100},
  ];
  // ── Palete ───────────────────────────────────────────────────
  final TextEditingController _paleteController = TextEditingController();

  // ── Caixa — busca por nome/código ────────────────────────────
  final TextEditingController _buscaController = TextEditingController();
  int _cdObjSelecionado = 0;
  Map<String, dynamic>? _artigoSelecionadoBusca;
  List<Map<String, dynamic>> _buscaOpcoes = [];
  bool _buscandoOpcoes = false;
  bool _settingBuscaText = false;
  Timer? _buscaDebounce;

  // ── Caixa — dropdown de detalhe/lote ────────────────────────
  List<Map<String, dynamic>> _lotesList = [];
  int _detalheSelecionado = 0;
  bool _carregandoLotes = false;

  // ── Caixa — dados da etiqueta ────────────────────────────────
  final TextEditingController _metrosController = TextEditingController();
  final TextEditingController _ordemController = TextEditingController();
  final TextEditingController _detalheController = TextEditingController();
  final TextEditingController _loteController = TextEditingController();
  final TextEditingController _qtdeController = TextEditingController(
    text: '1',
  );
  String? _operadorCaixaSelecionadoCodigo;

  // ── Caixa — readonly ─────────────────────────────────────────
  final TextEditingController _tipoCaixaController = TextEditingController();

  // ── Caixa — tipo base do artigo (ENFE | ENFR | D | P | G | '')
  // Somente ENFE/ENFR/D são realmente fixos (independem dos metros); um
  // TipoCaixa 'P'/'G' vindo do cadastro do artigo é só um valor legado e
  // não deve travar o resultado — o cálculo por metros/padrao_caixa decide.
  static const _tiposCaixaFixos = ['ENFE', 'ENFR', 'D'];
  String _tipoBaseArticle = '';

  // ── Caixa — faixas de metros (P/G) cadastradas para o artigo atual
  final PadraoCaixaService _padraoCaixaService = PadraoCaixaService();
  int _caixaPMetros = 0;
  int _caixaGMetros = 0;

  // ── Caixa — toggles ──────────────────────────────────────────
  bool _pedidoEspecial = false;
  bool _loteInline = false;

  // ── Operador ─────────────────────────────────────────────────
  final TextEditingController _opQtdeController = TextEditingController(
    text: '1',
  );
  final TextEditingController _opFonteController = TextEditingController(
    text: '72',
  );
  bool _imprimindoOp = false;
  int _opPreview = 0;
  List<_OperadorEtiqueta> _operadores = [];
  bool _carregandoOperadores = false;
  String? _operadorSelecionadoCodigo;

  // ── Carretel — busca por nome/código (mesmo padrão da Caixa) ──
  final TextEditingController _buscaCarretelController =
      TextEditingController();
  int _cdObjCarretelSelecionado = 0;
  List<Map<String, dynamic>> _buscaCarretelOpcoes = [];
  bool _buscandoCarretelOpcoes = false;
  bool _settingBuscaCarretelText = false;
  Timer? _buscaCarretelDebounce;

  // ── Carretel — dados da etiqueta ───────────────────────────────
  final TextEditingController _loteCarretelController =
      TextEditingController();
  final TextEditingController _operadorCarretelController =
      TextEditingController();
  final TextEditingController _qtdeCarretelController = TextEditingController(
    text: '1',
  );
  Map<String, dynamic>? _carretelInfo;
  bool _consultandoCarretel = false;
  bool _imprimindoCarretel = false;

  // ── Etiqueta Livre — tamanho + linhas montadas pelo usuário ────
  final TextEditingController _larguraLivreController =
      TextEditingController(text: '80');
  final TextEditingController _alturaLivreController =
      TextEditingController(text: '50');
  final TextEditingController _qtdeLivreController = TextEditingController(
    text: '1',
  );
  final TextEditingController _tipoBLinha1Controller = TextEditingController();
  final TextEditingController _tipoBLinha2Controller = TextEditingController();
  final TextEditingController _tipoBCodigoController = TextEditingController();
  final TextEditingController _tipoBNumeroController = TextEditingController();
  final TextEditingController _tipoBFonteLinha1Controller =
      TextEditingController(text: '36');
  final TextEditingController _tipoBFonteLinha2Controller =
      TextEditingController(text: '36');
  final TextEditingController _tipoBFonteCodigoController =
      TextEditingController(text: '32');
  final TextEditingController _tipoBFonteNumeroController =
      TextEditingController(text: '72');
  final TextEditingController _tipoBFonteController = TextEditingController(
    text: '36',
  );
  final TextEditingController _fioTituloController = TextEditingController();
  final TextEditingController _fioCorController = TextEditingController();
  final TextEditingController _fioPesoController = TextEditingController();
  final TextEditingController _fioLoteController = TextEditingController();
  final TextEditingController _fioCodigoController = TextEditingController();
  static const List<_FioLivreEtiqueta> _fiosLivre = [
    _FioLivreEtiqueta(
      cor: 'CORÇA',
      titulo: 'Fio Poliester 167/48',
      lote: 'E6',
      codigoBarras: '7896714231136',
    ),
    _FioLivreEtiqueta(
      cor: 'PRETO',
      titulo: 'Fio Poliester 167/48',
      lote: 'E6',
      codigoBarras: '7896714231143',
    ),
    _FioLivreEtiqueta(
      cor: 'ESTANHO',
      titulo: 'Fio Poliester 167/48',
      lote: 'F4',
      codigoBarras: '7896714231150',
    ),
    _FioLivreEtiqueta(
      cor: 'ROYAL',
      titulo: 'Fio Poliester 167/48',
      lote: 'K4',
      codigoBarras: '7896714231167',
    ),
    _FioLivreEtiqueta(
      cor: 'BRANCO',
      titulo: 'Fio Poliester 167/48',
      lote: 'E6',
      codigoBarras: '7896714231174',
    ),
    _FioLivreEtiqueta(
      cor: 'PALHA ITALIANA',
      titulo: 'Fio Poliester 167/48',
      lote: 'F4',
      codigoBarras: '7896714231181',
    ),
    _FioLivreEtiqueta(
      cor: 'REVOLUÇÃO',
      titulo: 'Fio Poliester 167/48',
      lote: 'F4',
      codigoBarras: '7896714231198',
    ),
    _FioLivreEtiqueta(
      cor: 'MANJERICÃO',
      titulo: 'Fio Poliester 167/48',
      lote: 'F4',
      codigoBarras: '7896714231204',
    ),
    _FioLivreEtiqueta(
      cor: 'LARANJA',
      titulo: 'Fio Poliester 150/48',
      lote: 'F4',
      codigoBarras: '7896714231211',
    ),
    _FioLivreEtiqueta(
      cor: 'ROSA SERENO',
      titulo: 'Fio Poliester 167/48',
      lote: 'F4',
      codigoBarras: '7896714231228',
    ),
    _FioLivreEtiqueta(
      cor: 'GEMA',
      titulo: 'Fio Poliester 167/48',
      lote: 'F5',
      codigoBarras: '7896714231235',
    ),
    _FioLivreEtiqueta(
      cor: 'VIOLETA PERFUMADA',
      titulo: 'Fio Poliester 167/48',
      lote: 'F4',
      codigoBarras: '7896714231259',
    ),
    _FioLivreEtiqueta(
      cor: 'VERDE GRAMA',
      titulo: 'Fio Poliester 167/48',
      lote: 'F4',
      codigoBarras: '7896714231266',
    ),
  ];
  _FioLivreEtiqueta _fioLivreSelecionado = _fiosLivre.first;
  _LivreTipoModelo _livreTipoModelo = _LivreTipoModelo.livre;
  final List<_LinhaLivreEditor> _linhasLivre = [
    _LinhaLivreEditor(),
    _LinhaLivreEditor(),
  ];
  bool _imprimindoLivre = false;

  final AlocacaoService _alocacaoService = AlocacaoService();
  final ZebraPrinterService _zebraPrinterService = ZebraPrinterService();
  List<Map<String, dynamic>> _printers = const [];
  String? _selectedPrinterKey;
  String _printerIp = ZebraPrinterService.defaultIp;
  int _printerPort = ZebraPrinterService.defaultPort;

  _EtiquetaModelo _modelo = _EtiquetaModelo.caixa;
  List<PaleteEmbalagemItemEntry> _itens = const [];
  bool _consultando = false;
  bool _consultandoBusca = false;
  bool _imprimindo = false;
  String? _erro;
  String? _paleteConsultado;
  String? _qrPalete;

  // Resultado do buscarArtigoInfo (etapa 1 — somente código)
  Map<String, dynamic>? _artigoInfo;
  // Resultado do buscarEtiquetaCaixaV2 (preenchido ao imprimir)
  Map<String, dynamic>? _etiquetaCaixa;

  // Lote de impressao (LI): quando ativo, as proximas caixas impressas
  // compartilham o mesmo LI retornado pela API.
  bool _manterLoteCaixa = false;
  String? _loteImpressaoCaixa;

  // Ordens
  final TextEditingController _ordemSkuNameController =
      TextEditingController();
  List<Map<String, dynamic>> _ordemArtigoOpcoes = [];
  List<_OrdemExpedicao> _ordensExpedicao = [];
  final Set<String> _ordensExpandidas = {};
  Timer? _ordemBuscaDebounce;
  bool _buscandoOrdemArtigos = false;
  bool _consultandoOrdens = false;
  bool _settingOrdemBuscaText = false;
  int _ordemSkuSelecionado = 0;

  // Flags do artigo
  bool _naoImprimeLoteLinha = false;
  bool _detalheObrigatorio = false;
  bool _temPreto = false;

  // Indica se o detalhe deve ser selecionado em dropdown
  bool get _usaDropdownDetalhe =>
      _artigoInfo != null &&
      (_carregandoLotes ||
          _lotesList.isNotEmpty ||
          _temPreto ||
          _detalheObrigatorio);

  static const TextStyle _dropdownTextStyle = TextStyle(
    color: Color(0xFFF8FAFC),
    fontWeight: FontWeight.w600,
  );

  @override
  void initState() {
    super.initState();
    _aplicarFioLivre(_fioLivreSelecionado, notify: false);
    _carregarImpressora();
    _carregarOperadores();
  }

  void _aplicarFioLivre(_FioLivreEtiqueta fio, {bool notify = true}) {
    void apply() {
      _fioLivreSelecionado = fio;
      _fioTituloController.text = fio.titulo;
      _fioCorController.text = fio.cor;
      _fioPesoController.text = '300g';
      _fioLoteController.text = fio.lote;
      _fioCodigoController.text = fio.codigoBarras;
    }

    if (notify) {
      setState(apply);
    } else {
      apply();
    }
  }

  Future<void> _carregarImpressora() async {
    final lista = await EtiquetasService.buscarImpressoras();
    if (!mounted) return;
    final printers = _normalizarImpressoras(
      lista.isNotEmpty ? lista : _fallbackPrinters,
    );
    setState(() {
      _printers = printers;
      if (_selectedPrinterKey == null && printers.isNotEmpty) {
        _aplicarImpressora(_impressoraPadraoParaModelo(_modelo, printers));
      }
    });
  }

  Future<void> _carregarOperadores() async {
    setState(() => _carregandoOperadores = true);
    try {
      final data = await EtiquetasService.buscarOperadores();
      if (!mounted) return;
      final operadores = data
          .map(_OperadorEtiqueta.fromJson)
          .where((item) => item.codigo.isNotEmpty)
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));
      setState(() {
        _operadores = operadores;
        _carregandoOperadores = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregandoOperadores = false);
    }
  }

  List<Map<String, dynamic>> _normalizarImpressoras(
    List<Map<String, dynamic>> lista,
  ) {
    var nextZebraNumber = 3;
    return lista.map((printer) {
      final ipOriginal = (printer['ip'] ?? '').toString().trim();
      final ip = ipOriginal.split(':').first.trim();
      final portaOriginal = printer['porta'];
      final porta =
          portaOriginal is int
              ? portaOriginal
              : int.tryParse(portaOriginal?.toString() ?? '') ??
                    int.tryParse(ipOriginal.split(':').skip(1).firstOrNull ?? '') ??
                    ZebraPrinterService.defaultPort;
      String nome;
      switch (ip) {
        case '168.190.30.206':
          nome = 'EtqCaixa/Carretel 2';
          break;
        case '168.190.30.181':
          nome = 'EtqCaixa/Carretel';
          break;
        case '168.190.30.74':
          nome = 'Zebra 1';
          break;
        case '168.190.30.172':
          nome = 'EtqManual';
          break;
        default:
          nome = 'Zebra $nextZebraNumber';
          nextZebraNumber++;
      }
      return {
        'key': '$ip:$porta',
        'nome': nome,
        'ip': ip,
        'porta': porta,
      };
    }).toList();
  }

  Map<String, dynamic> _impressoraPadraoParaModelo(
    _EtiquetaModelo modelo,
    List<Map<String, dynamic>> printers,
  ) {
    final ipsPreferenciais = switch (modelo) {
      _EtiquetaModelo.caixa || _EtiquetaModelo.carretel => const [
        '168.190.30.206',
        '168.190.30.181',
      ],
      _EtiquetaModelo.ordens => const [
        '168.190.30.206',
        '168.190.30.181',
      ],
      _EtiquetaModelo.operador || _EtiquetaModelo.livre => const [
        '168.190.30.172',
      ],
      _EtiquetaModelo.palete => const [
        '168.190.30.181',
        '168.190.30.206',
        '168.190.30.172',
      ],
    };

    for (final ipPreferencial in ipsPreferenciais) {
      for (final printer in printers) {
        if ((printer['ip'] ?? '').toString().trim() == ipPreferencial) {
          return printer;
        }
      }
    }
    return printers.first;
  }

  String _printerLabel(Map<String, dynamic> printer) {
    final nome = (printer['nome'] ?? '').toString().trim();
    final ip = (printer['ip'] ?? '').toString().trim();
    final porta = printer['porta'];
    return '$nome ($ip:$porta)';
  }

  void _aplicarImpressora(Map<String, dynamic> printer) {
    _selectedPrinterKey = printer['key'] as String?;
    _printerIp = (printer['ip'] as String?) ?? _printerIp;
    _printerPort = (printer['porta'] as int?) ?? _printerPort;
  }

  bool _garantirImpressoraSelecionada() {
    if (_selectedPrinterKey != null) return true;
    _showSnackBar(
      'Selecione a impressora antes de enviar a impressão.',
      isError: true,
    );
    return false;
  }

  @override
  void dispose() {
    _buscaDebounce?.cancel();
    _paleteController.dispose();
    _buscaController.dispose();
    _metrosController.dispose();
    _ordemController.dispose();
    _detalheController.dispose();
    _loteController.dispose();
    _qtdeController.dispose();
    _tipoCaixaController.dispose();
    _ordemBuscaDebounce?.cancel();
    _ordemSkuNameController.dispose();
    _opQtdeController.dispose();
    _opFonteController.dispose();
    _buscaCarretelDebounce?.cancel();
    _buscaCarretelController.dispose();
    _loteCarretelController.dispose();
    _operadorCarretelController.dispose();
    _qtdeCarretelController.dispose();
    _larguraLivreController.dispose();
    _alturaLivreController.dispose();
    _qtdeLivreController.dispose();
    _tipoBLinha1Controller.dispose();
    _tipoBLinha2Controller.dispose();
    _tipoBCodigoController.dispose();
    _tipoBNumeroController.dispose();
    _tipoBFonteLinha1Controller.dispose();
    _tipoBFonteLinha2Controller.dispose();
    _tipoBFonteCodigoController.dispose();
    _tipoBFonteNumeroController.dispose();
    _tipoBFonteController.dispose();
    _fioTituloController.dispose();
    _fioCorController.dispose();
    _fioPesoController.dispose();
    _fioLoteController.dispose();
    _fioCodigoController.dispose();
    for (final linha in _linhasLivre) {
      linha.dispose();
    }
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────
  // Palete
  // ────────────────────────────────────────────────────────────

  Future<void> _consultar() async {
    final palete = _paleteController.text.trim().toUpperCase();
    if (palete.isEmpty) {
      _showSnackBar('Informe o endereço do palete.', isError: true);
      return;
    }
    setState(() {
      _consultando = true;
      _erro = null;
      _itens = const [];
      _paleteConsultado = palete;
    });
    try {
      final itens = await _alocacaoService.consultarItensPaleteParaAjuste(
        endereco: palete,
      );
      if (!mounted) return;
      setState(() {
        _itens = itens;
        _consultando = false;
      });
      if (itens.isEmpty) {
        _showSnackBar('Nenhum saldo encontrado para $palete.', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
        _consultando = false;
      });
    }
  }

  Future<void> _imprimir() async {
    if (!_garantirImpressoraSelecionada()) return;
    final palete = (_paleteConsultado ?? _paleteController.text)
        .trim()
        .toUpperCase();
    if (palete.isEmpty) {
      _showSnackBar('Informe o endereço do palete.', isError: true);
      return;
    }
    setState(() {
      _imprimindo = true;
      _erro = null;
    });
    try {
      await _zebraPrinterService.imprimirEtiquetaPalete(
        palete: palete,
        ip: _printerIp,
        port: _printerPort,
      );
      if (!mounted) return;
      setState(() => _imprimindo = false);
      _showSnackBar('Comando de impressão enviado.', isError: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _imprimindo = false;
      });
    }
  }

  void _mostrarQrCode() {
    final palete = _paleteController.text.trim().toUpperCase();
    if (palete.isEmpty) {
      _showSnackBar('Informe o endereço do palete.', isError: true);
      return;
    }
    setState(() {
      _qrPalete = palete;
      _paleteConsultado = palete;
      _erro = null;
    });
  }

  // ────────────────────────────────────────────────────────────
  // Caixa — Busca autocomplete
  // ────────────────────────────────────────────────────────────

  void _onBuscaChanged(String value) {
    if (_settingBuscaText) return;
    _buscaDebounce?.cancel();

    // Se tinha item selecionado e o usuário editou o campo, limpa tudo
    if (_cdObjSelecionado > 0) {
      setState(() {
        _cdObjSelecionado = 0;
        _artigoSelecionadoBusca = null;
        _tipoBaseArticle = '';
        _artigoInfo = null;
        _etiquetaCaixa = null;
        _tipoCaixaController.clear();
        _naoImprimeLoteLinha = false;
        _detalheObrigatorio = false;
        _temPreto = false;
        _loteInline = false;
        _lotesList = [];
        _detalheSelecionado = 0;
        _buscaOpcoes = [];
      });
    }

    final q = value.trim();
    if (q.length < 2) {
      setState(() => _buscaOpcoes = []);
      return;
    }

    _buscaDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _pesquisarOpcoes(q);
    });
  }

  Future<void> _pesquisarOpcoes(String q) async {
    setState(() => _buscandoOpcoes = true);
    try {
      final opcoes = await EtiquetasService.buscarArtigosPorNome(q);
      if (!mounted) return;
      setState(() {
        _buscaOpcoes = opcoes;
        _buscandoOpcoes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _buscaOpcoes = [];
        _buscandoOpcoes = false;
      });
    }
  }

  void _selecionarArtigo(Map<String, dynamic> artigo) {
    final cdObj = artigo['CdObj'] as int;
    final nmObj = (artigo['NmObj'] ?? '').toString().trim();
    _settingBuscaText = true;
    _buscaController.text = '$cdObj — $nmObj';
    _settingBuscaText = false;
    setState(() {
      _cdObjSelecionado = cdObj;
      _artigoSelecionadoBusca = artigo;
      _buscaOpcoes = [];
    });
    _buscarArtigo();
  }

  // ────────────────────────────────────────────────────────────
  // Caixa — Etapa 1: Busca do artigo (info + lotes)
  // ────────────────────────────────────────────────────────────

  Future<void> _buscarArtigo() async {
    final cdObj = _cdObjSelecionado > 0
        ? _cdObjSelecionado
        : int.tryParse(_buscaController.text.trim()) ?? 0;

    if (cdObj <= 0) {
      _showSnackBar(
        'Selecione um artigo da lista ou informe o código.',
        isError: true,
      );
      return;
    }
    setState(() {
      _cdObjSelecionado = cdObj;
      _consultandoBusca = true;
      _erro = null;
      _artigoInfo = null;
      _etiquetaCaixa = null;
      _tipoCaixaController.clear();
      _naoImprimeLoteLinha = false;
      _detalheObrigatorio = false;
      _temPreto = false;
      _loteInline = false;
      _lotesList = [];
      _detalheSelecionado = 0;
      _caixaPMetros = 0;
      _caixaGMetros = 0;
    });
    _detalheController.clear();
    _loteController.clear();
    try {
      final data = await EtiquetasService.buscarArtigoInfo(cdObj);
      if (!mounted) return;

      final temPreto = data['TemPreto'] == true;
      final detalheObrig = data['DetalheObrigatorio'] == true;

      final tipoBase = (data['TipoCaixa'] ?? '').toString().trim();
      setState(() {
        _artigoInfo = data;
        _tipoBaseArticle = tipoBase;
        // Tipos fixos preenchem imediatamente; P/G por metros são calculados depois
        _tipoCaixaController.text = _tiposCaixaFixos.contains(tipoBase)
            ? tipoBase
            : '';
        _detalheObrigatorio = detalheObrig;
        _temPreto = temPreto;
        _naoImprimeLoteLinha = data['NaoImprimeLoteLinha'] == true;
        _consultandoBusca = false;
      });
      // Recalcula tipo de caixa caso metros já esteja preenchido
      _atualizarTipoCaixa();
      await _consultarPadraoCaixaArtigo();

      await _carregarLotes(cdObj);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
        _consultandoBusca = false;
      });
    }
  }

  // Calcula P/G a partir dos metros; tipos fixos (ENFE/ENFR/D) não mudam.
  void _atualizarTipoCaixa() {
    if (_tiposCaixaFixos.contains(_tipoBaseArticle)) return;
    final metros = int.tryParse(_metrosController.text.trim()) ?? 0;
    if (metros <= 0) {
      _tipoCaixaController.text = '';
      return;
    }
    // Usa as faixas cadastradas para o artigo (padrao_caixa); se não houver
    // cadastro, cai no limiar genérico de 1200m. Quando cadastrado, só é
    // P/G se bater EXATAMENTE com a caixa cheia — qualquer outro valor
    // vira saldo (S). Se passar de uma caixa cheia, não imprime — o botão
    // Imprimir bloqueia e orienta a imprimir a caixa fechada e o saldo
    // como duas ações separadas.
    if (_caixaPMetros > 0 || _caixaGMetros > 0) {
      if (_bloqueioDivisaoCaixa(metros) != null) {
        _tipoCaixaController.text = 'Feche a caixa primeiro';
      } else if (_caixaPMetros > 0 && metros == _caixaPMetros) {
        _tipoCaixaController.text = 'P';
      } else if (_caixaGMetros > 0 && metros == _caixaGMetros) {
        _tipoCaixaController.text = 'G';
      } else {
        _tipoCaixaController.text = 'S';
      }
    } else {
      _tipoCaixaController.text = metros <= 1200 ? 'P' : 'G';
    }
  }

  // Retorna null se os metros podem ser impressos direto (bate exatamente
  // com P/G, ou é menor que a menor caixa cadastrada — saldo puro, S).
  // Retorna uma mensagem de bloqueio quando os metros equivalem a uma
  // caixa cheia + saldo — nesse caso não imprime nada; o usuário precisa
  // imprimir a caixa fechada e o saldo em duas ações separadas.
  String? _bloqueioDivisaoCaixa(int metros) {
    if (_tiposCaixaFixos.contains(_tipoBaseArticle)) return null;
    final p = _caixaPMetros;
    final g = _caixaGMetros;
    if (p <= 0 && g <= 0) return null;
    if (p > 0 && metros == p) return null;
    if (g > 0 && metros == g) return null;
    if (g > 0 && metros > g) {
      final saldo = metros - g;
      return '${metros}m equivale a 1 caixa G (${g}m) + ${saldo}m de saldo. '
          'Imprima a caixa G primeiro (informe $g), depois imprima o saldo '
          'separadamente (informe $saldo).';
    }
    if (p > 0 && metros > p) {
      final saldo = metros - p;
      return '${metros}m equivale a 1 caixa P (${p}m) + ${saldo}m de saldo. '
          'Imprima a caixa P primeiro (informe $p), depois imprima o saldo '
          'separadamente (informe $saldo).';
    }
    return null;
  }

  // Busca as faixas de caixa (padrao_caixa) do artigo mãe e recalcula o
  // tipo de caixa. Chamado após a busca do artigo e ao pressionar Enter
  // no campo Metros, garantindo que o padrão mais atual seja consultado.
  Future<void> _consultarPadraoCaixaArtigo() async {
    if (_tiposCaixaFixos.contains(_tipoBaseArticle)) return;
    final artigoInfo = _artigoInfo;
    if (artigoInfo == null) return;

    final cdObj = _cdObjSelecionado;
    final nmObj = (artigoInfo['NmObj'] ?? '').toString().trim();
    final artigoMae = _extrairArtigoMae(nmObj);
    Map<String, dynamic>? padrao;
    try {
      padrao = await _padraoCaixaService.buscarPadraoPorArtigo(
        nmObj,
        artigoMae: artigoMae,
      );
    } catch (e) {
      debugPrint('Falha ao consultar padrao de caixa local: $e');
      return;
    }
    final padraoAtual = padrao;
    if (!mounted || _cdObjSelecionado != cdObj || padraoAtual == null) return;

    setState(() {
      _caixaPMetros = _toIntPadrao(padraoAtual['caixa_p']);
      _caixaGMetros = _toIntPadrao(padraoAtual['caixa_g']);
      _atualizarTipoCaixa();
    });
  }

  int _toIntPadrao(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    final normalized = '${value ?? ''}'.trim().replaceAll(',', '.');
    return double.tryParse(normalized)?.round() ?? 0;
  }

  String _extrairArtigoMae(String descricao) {
    final texto = descricao.trim();
    if (texto.isEmpty) return '';
    final match = RegExp(r'(.+?\bmm)', caseSensitive: false).firstMatch(texto);
    if (match != null) return texto.substring(0, match.end).trim();
    return texto;
  }

  Future<void> _carregarLotes(int cdObj) async {
    setState(() => _carregandoLotes = true);
    try {
      final lotes = await EtiquetasService.buscarArtigoLotes(cdObj);
      if (!mounted) return;
      final deveUsarDropdown =
          _temPreto || _detalheObrigatorio || lotes.isNotEmpty;
      final prefill = resolverDetalheAutomatico(
        lotes: lotes,
        temPreto: _temPreto,
        usaDropdownDetalhe: deveUsarDropdown,
        fallback: {
          ...?_artigoSelecionadoBusca,
          ...?_artigoInfo,
        },
      );
      setState(() {
        _lotesList = lotes;
        _carregandoLotes = false;
        _detalheSelecionado = prefill.detalheId;
      });
      _detalheController.text = prefill.detalheTexto;
      _loteController.text = prefill.loteTexto;
    } catch (_) {
      if (!mounted) return;
      setState(() => _carregandoLotes = false);
    }
  }

  void _selecionarDetalhe(int? cdLot) {
    if (cdLot == null) return;
    final lot = _lotesList.firstWhere(
      (l) => _toIntPadrao(l['CdLot']) == cdLot,
      orElse: () => {},
    );
    setState(() {
      _detalheSelecionado = cdLot;
      // Para PRETO: auto-preenche o campo Lote com NmLot
      if (_temPreto && lot.isNotEmpty) {
        final nm = (lot['NmLot'] ?? '').toString().trim();
        if (nm.isNotEmpty) _loteController.text = nm;
      }
    });
  }

  // ────────────────────────────────────────────────────────────
  // Caixa — Etapa 2: Imprimir (valida + v2 + imprime)
  // ────────────────────────────────────────────────────────────

  Future<void> _abrirSeletorDetalhe() async {
    if (_lotesList.isEmpty) return;
    final selecionado = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101B34),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        String filtro = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final termo = filtro.trim().toUpperCase();
            final filtrados = termo.isEmpty
                ? _lotesList
                : _lotesList.where((lot) {
                    final cdLot = _toIntPadrao(lot['CdLot']).toString();
                    final nmLot = (lot['NmLot'] ?? '').toString().toUpperCase();
                    return cdLot.contains(termo) || nmLot.contains(termo);
                  }).toList();

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.78,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _temPreto ? 'Selecionar Cor / Lote' : 'Selecionar detalhe',
                      style: const TextStyle(
                        color: Color(0xFFF8FAFC),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        autofocus: true,
                        onChanged: (value) =>
                            setModalState(() => filtro = value),
                        style: const TextStyle(
                          color: Color(0xFFF8FAFC),
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Filtrar por codigo, cor ou lote',
                          prefixIcon: Icon(Icons.search_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtrados.isEmpty
                          ? const Center(
                              child: Text(
                                'Nenhum lote encontrado',
                                style: TextStyle(color: Color(0xFF94A3B8)),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtrados.length,
                              separatorBuilder: (_, __) => const Divider(
                                height: 1,
                                color: Color(0xFF1E293B),
                              ),
                              itemBuilder: (context, index) {
                                final lot = filtrados[index];
                                final cdLot = _toIntPadrao(lot['CdLot']);
                                final nmLot =
                                    (lot['NmLot'] ?? '').toString().trim();
                                final selected = cdLot == _detalheSelecionado;
                                return ListTile(
                                  leading: Icon(
                                    selected
                                        ? Icons.check_circle_rounded
                                        : Icons.palette_rounded,
                                    color: selected
                                        ? const Color(0xFF22C55E)
                                        : const Color(0xFF60A5FA),
                                  ),
                                  title: Text(
                                    nmLot.isEmpty ? cdLot.toString() : nmLot,
                                    style: const TextStyle(
                                      color: Color(0xFFF8FAFC),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Codigo $cdLot',
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 12,
                                    ),
                                  ),
                                  onTap: () => Navigator.of(ctx).pop(cdLot),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || selecionado == null) return;
    _selecionarDetalhe(selecionado);
  }

  Future<void> _imprimirCaixa() async {
    if (!_garantirImpressoraSelecionada()) return;
    final cdObj = _cdObjSelecionado;
    final metros = _metrosController.text.trim();
    final nrOrdem = _ordemController.text.trim();
    final detalhe = _detalheSelecionado > 0
        ? _detalheSelecionado
        : (int.tryParse(_detalheController.text.trim()) ?? 0);
    final lote = _loteController.text.trim();

    // Validações ao clicar em Imprimir
    if (cdObj <= 0) {
      _showSnackBar('Busque o artigo antes de imprimir.', isError: true);
      return;
    }
    if (metros.isEmpty) {
      _showSnackBar('Informe os metros.', isError: true);
      return;
    }
    if (nrOrdem.isEmpty) {
      _showSnackBar('Informe o numero da ordem.', isError: true);
      return;
    }
    if (_detalheObrigatorio && detalhe <= 0) {
      _showSnackBar(
        'Selecione o Detalhe — obrigatório para este artigo.',
        isError: true,
      );
      return;
    }
    if (_temPreto && detalhe <= 0) {
      _showSnackBar(
        'Artigo PRETO: selecione o Detalhe (Cor / Lote).',
        isError: true,
      );
      return;
    }
    if (_temPreto && lote.isEmpty) {
      _showSnackBar('Artigo PRETO: preencha o campo Lote.', isError: true);
      return;
    }

    await _consultarPadraoCaixaArtigo();
    _atualizarTipoCaixa();

    final metrosInt = int.tryParse(metros) ?? 0;
    final bloqueio = _bloqueioDivisaoCaixa(metrosInt);
    if (bloqueio != null) {
      setState(() => _tipoCaixaController.text = 'Feche a caixa primeiro');
      _showSnackBar(bloqueio, isError: true);
      return;
    }
    final qtde = _qtdeInformada(_qtdeController);
    final confirmouQuantidade = await _confirmarQuantidadeAlta(
      aba: 'Caixa',
      qtde: qtde,
      limite: 100,
    );
    if (!confirmouQuantidade) return;

    final ativouManterLoteAutomaticamente = qtde >= 2 && !_manterLoteCaixa;
    if (ativouManterLoteAutomaticamente) {
      setState(() => _manterLoteCaixa = true);
    }

    setState(() {
      _imprimindo = true;
      _erro = null;
    });
    try {
      for (var i = 0; i < qtde; i++) {
        await _imprimirCaixaSegmento(
          cdObj: cdObj,
          metrosSegmento: metros,
          nrOrdem: nrOrdem,
          detalhe: detalhe,
          lote: lote,
          qtde: 1,
        );
        if (!mounted) return;
      }
      if (!mounted) return;
      setState(() => _imprimindo = false);
      _showSnackBar('Comando de impressão enviado.', isError: false);
      final manterDados = await _perguntarManterDadosEtiqueta();
      if (!mounted) return;
      if (!manterDados) {
        _resetarCaixa();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
        _imprimindo = false;
      });
    } finally {
      if (ativouManterLoteAutomaticamente && mounted) {
        setState(() {
          _manterLoteCaixa = false;
          _loteImpressaoCaixa = null;
        });
      }
    }
  }

  void _aplicarMetrosPorTipoCaixa(String tipo) {
    final metros = tipo == 'P' ? _caixaPMetros : _caixaGMetros;
    if (metros <= 0) {
      _showSnackBar(
        'Nao ha metragem cadastrada para caixa $tipo deste artigo.',
        isError: true,
      );
      return;
    }
    setState(() {
      _metrosController.text = metros.toString();
      _atualizarTipoCaixa();
    });
  }

  // Busca e imprime a etiqueta caixa com os metros informados.
  Future<void> _imprimirCaixaSegmento({
    required int cdObj,
    required String metrosSegmento,
    required String nrOrdem,
    required int detalhe,
    required String lote,
    required int qtde,
  }) async {
    final data = await EtiquetasService.buscarEtiquetaCaixaV2(
      cdObj: cdObj,
      metros: metrosSegmento,
      nrOrdem: nrOrdem,
      detalhe: detalhe,
      lote: lote,
      operador: int.tryParse((_operadorCaixaSelecionadoCodigo ?? '').trim()) ?? 0,
      pedidoEspecial: _pedidoEspecial,
      qtdeImp: qtde,
      loteInline: _loteInline,
      li: _manterLoteCaixa ? _loteImpressaoCaixa : null,
    );

    if (!mounted) return;

    final naoImprime = data['NaoImprimeLoteLinha'] == true;

    if (naoImprime && lote.isNotEmpty && !_loteInline) {
      final nmObj = (data['NmObj'] ?? '').toString();
      final querInline = await _perguntarLoteInline(nmObj);
      if (!mounted) return;
      if (querInline) {
        setState(() => _loteInline = true);
        await _imprimirCaixaSegmento(
          cdObj: cdObj,
          metrosSegmento: metrosSegmento,
          nrOrdem: nrOrdem,
          detalhe: detalhe,
          lote: lote,
          qtde: qtde,
        );
        return;
      }
    }

    setState(() {
      _etiquetaCaixa = data;
      _naoImprimeLoteLinha = naoImprime;
      final li = data['LI']?.toString();
      if (li != null && li.isNotEmpty) {
        _loteImpressaoCaixa = li;
      }
    });

    await _zebraPrinterService.imprimirEtiquetaCaixa(
      dados: data,
      ip: _printerIp,
      port: _printerPort,
    );
  }

  Future<void> _consultarOrdensExpedicao() async {
    FocusScope.of(context).unfocus();
    final skuName = await _resolverSkuNameParaConsultaOrdens();
    if (!mounted) return;
    if (skuName.isEmpty) {
      _showSnackBar(
        'Selecione um artigo da lista ou informe o codigo do SKU.',
        isError: true,
      );
      return;
    }

    setState(() {
      _consultandoOrdens = true;
      _erro = null;
      _ordensExpedicao = [];
      _ordemArtigoOpcoes = [];
    });
    try {
      final data = await EtiquetasService.buscarOrdensExpedicao(
        skuName: skuName,
      );
      if (!mounted) return;
      setState(() {
        _ordensExpedicao = data.map(_OrdemExpedicao.fromJson).toList();
        _ordensExpandidas
          ..clear()
          ..addAll(_ordensExpedicao.map(_ordemKey));
        _consultandoOrdens = false;
      });
      if (_ordensExpedicao.isEmpty) {
        _showSnackBar('Nenhuma ordem encontrada.', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
        _consultandoOrdens = false;
      });
    }
  }

  Future<String> _resolverSkuNameParaConsultaOrdens() async {
    if (_ordemSkuSelecionado > 0) return _ordemSkuSelecionado.toString();

    final texto = _ordemSkuNameController.text.trim();
    if (texto.isEmpty) return '';

    final codigoDireto = int.tryParse(texto);
    if (codigoDireto != null && codigoDireto > 0) {
      return codigoDireto.toString();
    }

    final encontrados = await EtiquetasService.buscarArtigosPorNome(texto);
    if (!mounted) return '';
    if (encontrados.length == 1) {
      _selecionarArtigoOrdem(encontrados.first, consultar: false);
      return _ordemSkuSelecionado > 0 ? _ordemSkuSelecionado.toString() : '';
    }

    setState(() => _ordemArtigoOpcoes = encontrados);
    return '';
  }

  void _onOrdemBuscaChanged(String value) {
    if (_settingOrdemBuscaText) return;
    _ordemBuscaDebounce?.cancel();

    if (_ordemSkuSelecionado > 0) {
      setState(() {
        _ordemSkuSelecionado = 0;
        _ordensExpedicao = [];
        _ordensExpandidas.clear();
        _ordemArtigoOpcoes = [];
      });
    }

    final q = value.trim();
    if (q.length < 2) {
      setState(() => _ordemArtigoOpcoes = []);
      return;
    }

    _ordemBuscaDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _pesquisarArtigosOrdens(q);
    });
  }

  Future<void> _pesquisarArtigosOrdens(String q) async {
    setState(() => _buscandoOrdemArtigos = true);
    try {
      final opcoes = await EtiquetasService.buscarArtigosPorNome(q);
      if (!mounted) return;
      setState(() {
        _ordemArtigoOpcoes = opcoes;
        _buscandoOrdemArtigos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ordemArtigoOpcoes = [];
        _buscandoOrdemArtigos = false;
      });
    }
  }

  void _selecionarArtigoOrdem(
    Map<String, dynamic> artigo, {
    bool consultar = true,
  }) {
    final cdObj = _toIntPadrao(artigo['CdObj']);
    final nmObj = (artigo['NmObj'] ?? '').toString().trim();
    _settingOrdemBuscaText = true;
    _ordemSkuNameController.text = nmObj.isEmpty ? cdObj.toString() : nmObj;
    _settingOrdemBuscaText = false;
    setState(() {
      _ordemSkuSelecionado = cdObj;
      _ordemArtigoOpcoes = [];
    });
    if (consultar) _consultarOrdensExpedicao();
  }

  String _ordemKey(_OrdemExpedicao ordem) {
    final base = ordem.woid.isNotEmpty
        ? ordem.woid
        : '${ordem.skuName}-${ordem.releaseDate}-${ordem.dueDate}';
    return base;
  }

  void _toggleOrdemCard(_OrdemExpedicao ordem) {
    final key = _ordemKey(ordem);
    setState(() {
      if (_ordensExpandidas.contains(key)) {
        _ordensExpandidas.remove(key);
      } else {
        _ordensExpandidas.add(key);
      }
    });
  }

  Future<void> _selecionarOrdemParaCaixa(_OrdemExpedicao ordem) async {
    final deseja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF101B34),
        title: const Text(
          'Imprimir artigo?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Deseja preencher a tela de Caixa com o artigo ${ordem.titulo}?',
          style: const TextStyle(color: Color(0xFFCBD5E1)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('Ir para Caixa'),
          ),
        ],
      ),
    );

    if (deseja != true || !mounted) return;
    await _preencherCaixaComOrdem(ordem);
  }

  Future<void> _preencherCaixaComOrdem(_OrdemExpedicao ordem) async {
    setState(() {
      _erro = null;
      _modelo = _EtiquetaModelo.caixa;
      if (_printers.isNotEmpty) {
        _aplicarImpressora(
          _impressoraPadraoParaModelo(_EtiquetaModelo.caixa, _printers),
        );
      }
    });

    final artigo = await _resolverArtigoDaOrdem(ordem);
    if (!mounted) return;

    if (artigo == null) {
      _showSnackBar(
        'Nao foi possivel localizar o artigo da ordem para preencher a Caixa.',
        isError: true,
      );
      return;
    }

    final cdObj = _toIntPadrao(artigo['CdObj']);
    final nmObj = (artigo['NmObj'] ?? ordem.titulo).toString().trim();
    _settingBuscaText = true;
    _buscaController.text = '$cdObj - $nmObj';
    _settingBuscaText = false;
    _ordemController.text = ordem.woid;
    _metrosController.clear();
    _qtdeController.text = '1';
    setState(() {
      _cdObjSelecionado = cdObj;
      _artigoSelecionadoBusca = artigo;
      _buscaOpcoes = [];
    });
    await _buscarArtigo();
    if (!mounted) return;
    _showSnackBar('Ordem preenchida na aba Caixa.', isError: false);
  }

  Future<Map<String, dynamic>?> _resolverArtigoDaOrdem(
    _OrdemExpedicao ordem,
  ) async {
    final skuCode = ordem.skuCode.isNotEmpty ? ordem.skuCode : ordem.skuName;
    final codigo = int.tryParse(skuCode.trim());
    if (codigo != null && codigo > 0) {
      return {
        'CdObj': codigo,
        'NmObj': ordem.titulo,
      };
    }

    final termos = <String>[
      ordem.skuName,
      ordem.skuDescription,
      ordem.skuCode,
    ].where((item) => item.trim().length >= 2).toList();

    for (final termo in termos) {
      final encontrados = await EtiquetasService.buscarArtigosPorNome(termo);
      if (encontrados.isNotEmpty) return encontrados.first;
    }
    return null;
  }

  String _formatarQuantidadeParaCampo(double value) {
    if (value <= 0) return '';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(
      RegExp(r'\.$'),
      '',
    );
  }

  String _formatarNumeroOrdens(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }

  String _formatarDataOrdem(DateTime? date) {
    if (date == null) return '-';
    final dia = date.day.toString().padLeft(2, '0');
    final mes = date.month.toString().padLeft(2, '0');
    return '$dia/$mes/${date.year}';
  }

  Future<bool> _perguntarManterDadosEtiqueta() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Dados da etiqueta'),
            content: const Text(
              'Deseja manter as informacoes preenchidas para imprimir novamente?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Descartar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Manter'),
              ),
            ],
          ),
        ) ??
        true;
  }

  int _qtdeInformada(TextEditingController controller) {
    final qtde = int.tryParse(controller.text.trim()) ?? 1;
    return math.max(1, qtde);
  }

  Future<bool> _confirmarQuantidadeAlta({
    required String aba,
    required int qtde,
    required int limite,
  }) async {
    if (qtde <= limite) return true;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Quantidade alta'),
            content: Text(
              'Voce informou $qtde impressoes na aba $aba.\n\n'
              'Deseja imprimir mesmo essa quantidade?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Voltar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Imprimir mesmo assim'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _resetarCaixa() {
    _settingBuscaText = true;
    _buscaController.clear();
    _settingBuscaText = false;
    _metrosController.clear();
    _ordemController.clear();
    _detalheController.clear();
    _loteController.clear();
    _qtdeController.text = '1';
    _tipoCaixaController.clear();
    setState(() {
      _cdObjSelecionado = 0;
      _buscaOpcoes = [];
      _operadorCaixaSelecionadoCodigo = null;
      _pedidoEspecial = false;
      _loteInline = false;
      _artigoInfo = null;
      _etiquetaCaixa = null;
      _tipoBaseArticle = '';
      _naoImprimeLoteLinha = false;
      _detalheObrigatorio = false;
      _temPreto = false;
      _lotesList = [];
      _detalheSelecionado = 0;
      _erro = null;
      if (!_manterLoteCaixa) {
        _loteImpressaoCaixa = null;
      }
    });
  }

  // ────────────────────────────────────────────────────────────
  // Carretel — busca de artigo (mesmo padrão da Caixa) + impressão EPL2
  // ────────────────────────────────────────────────────────────

  void _onBuscaCarretelChanged(String value) {
    if (_settingBuscaCarretelText) return;
    _buscaCarretelDebounce?.cancel();

    if (_cdObjCarretelSelecionado > 0) {
      setState(() {
        _cdObjCarretelSelecionado = 0;
        _carretelInfo = null;
        _buscaCarretelOpcoes = [];
      });
    }

    final q = value.trim();
    if (q.length < 2) {
      setState(() => _buscaCarretelOpcoes = []);
      return;
    }

    _buscaCarretelDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _pesquisarOpcoesCarretel(q);
    });
  }

  Future<void> _pesquisarOpcoesCarretel(String q) async {
    setState(() => _buscandoCarretelOpcoes = true);
    try {
      final opcoes = await EtiquetasService.buscarArtigosPorNome(q);
      if (!mounted) return;
      setState(() {
        _buscaCarretelOpcoes = opcoes;
        _buscandoCarretelOpcoes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _buscaCarretelOpcoes = [];
        _buscandoCarretelOpcoes = false;
      });
    }
  }

  void _selecionarArtigoCarretel(Map<String, dynamic> artigo) {
    final cdObj = artigo['CdObj'] as int;
    final nmObj = (artigo['NmObj'] ?? '').toString().trim();
    _settingBuscaCarretelText = true;
    _buscaCarretelController.text = '$cdObj — $nmObj';
    _settingBuscaCarretelText = false;
    setState(() {
      _cdObjCarretelSelecionado = cdObj;
      _buscaCarretelOpcoes = [];
    });
    _buscarArtigoCarretel();
  }

  Future<void> _buscarArtigoCarretel() async {
    final cdObj = _cdObjCarretelSelecionado > 0
        ? _cdObjCarretelSelecionado
        : int.tryParse(_buscaCarretelController.text.trim()) ?? 0;

    if (cdObj <= 0) {
      _showSnackBar(
        'Selecione um artigo da lista ou informe o código.',
        isError: true,
      );
      return;
    }
    setState(() {
      _cdObjCarretelSelecionado = cdObj;
      _consultandoCarretel = true;
      _erro = null;
      _carretelInfo = null;
    });
    try {
      final data = await EtiquetasService.buscarEtiquetaCarretel(
        cdObj: cdObj,
        lote: _loteCarretelController.text,
        operador: _operadorCarretelController.text,
        qtdeImp: _qtdeInformada(_qtdeCarretelController),
      );
      if (!mounted) return;
      setState(() {
        _carretelInfo = data;
        _consultandoCarretel = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
        _consultandoCarretel = false;
      });
    }
  }

  Future<void> _imprimirCarretel() async {
    if (!_garantirImpressoraSelecionada()) return;
    final cdObj = _cdObjCarretelSelecionado;
    if (cdObj <= 0) {
      _showSnackBar('Selecione um artigo antes de imprimir.', isError: true);
      return;
    }
    final nmObjAtual = (_carretelInfo?['NmObj'] ?? '').toString().toUpperCase();
    final loteAtual = _loteCarretelController.text.trim();
    if (nmObjAtual.contains('PRETO') && loteAtual.isEmpty) {
      _showSnackBar('Artigo PRETO: preencha o campo Lote.', isError: true);
      return;
    }
    final qtde = _qtdeInformada(_qtdeCarretelController);
    final confirmouQuantidade = await _confirmarQuantidadeAlta(
      aba: 'Carretel',
      qtde: qtde,
      limite: 400,
    );
    if (!confirmouQuantidade) return;

    setState(() {
      _imprimindoCarretel = true;
      _erro = null;
    });
    try {
      final infoAtual = _carretelInfo;
      if (infoAtual == null) {
        _showSnackBar('Consulte o artigo antes de imprimir.', isError: true);
        setState(() => _imprimindoCarretel = false);
        return;
      }
      final data = Map<String, dynamic>.from(infoAtual)
        ..['Lote'] = _loteCarretelController.text.trim()
        ..['Operador'] = _operadorCarretelController.text.trim()
        ..['QtdeImp'] = qtde;
      setState(() => _carretelInfo = data);

      await _zebraPrinterService.imprimirEtiquetaCarretel(
        dados: data,
        ip: _printerIp,
        port: _printerPort,
      );
      if (!mounted) return;
      setState(() => _imprimindoCarretel = false);
      _showSnackBar('Comando de impressão enviado.', isError: false);
      final manterDados = await _perguntarManterDadosEtiqueta();
      if (!mounted) return;
      if (!manterDados) {
        _resetarCarretel();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
        _imprimindoCarretel = false;
      });
    }
  }

  void _resetarCarretel() {
    _settingBuscaCarretelText = true;
    _buscaCarretelController.clear();
    _settingBuscaCarretelText = false;
    _loteCarretelController.clear();
    _operadorCarretelController.clear();
    _qtdeCarretelController.text = '1';
    setState(() {
      _cdObjCarretelSelecionado = 0;
      _buscaCarretelOpcoes = [];
      _carretelInfo = null;
      _erro = null;
    });
  }

  Future<bool> _perguntarLoteInline(String nmObj) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Impressão de LOTE'),
            content: Text(
              'Este item${nmObj.isNotEmpty ? ' ($nmObj)' : ''} não imprime LOTE '
              'em linha separada (ENFRALDADO/ENFESTADO ou LOTE redundante).\n\n'
              'Deseja imprimir o LOTE ao lado dos metros?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Não'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sim'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _imprimirOperador() async {
    if (!_garantirImpressoraSelecionada()) return;
    final op = int.tryParse((_operadorSelecionadoCodigo ?? '').trim()) ?? 0;
    if (op <= 0) {
      _showSnackBar('Selecione um operador.', isError: true);
      return;
    }
    final qtde = _qtdeInformada(_opQtdeController);
    final confirmouQuantidade = await _confirmarQuantidadeAlta(
      aba: 'Operador',
      qtde: qtde,
      limite: 500,
    );
    if (!confirmouQuantidade) return;

    setState(() {
      _imprimindoOp = true;
      _opPreview = op;
      _erro = null;
    });
    try {
      await _zebraPrinterService.imprimirEtiquetaOperador(
        operador: op,
        quantidade: qtde,
        fonte: _fonteOperador(),
        ip: _printerIp,
        port: _printerPort,
      );
      if (!mounted) return;
      setState(() {
        _imprimindoOp = false;
        _operadorSelecionadoCodigo = null;
        _opPreview = 0;
      });
      _showSnackBar('Comando de impressão enviado.', isError: false);
      _opQtdeController.text = '1';
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _imprimindoOp = false;
      });
    }
  }

  // ────────────────────────────────────────────────────────────
  // Etiqueta Livre
  // ────────────────────────────────────────────────────────────

  void _adicionarLinhaLivre() {
    setState(() => _linhasLivre.add(_LinhaLivreEditor()));
  }

  void _removerLinhaLivre(int index) {
    setState(() {
      _linhasLivre[index].dispose();
      _linhasLivre.removeAt(index);
    });
  }

  Future<void> _imprimirLivre() async {
    if (!_garantirImpressoraSelecionada()) return;
    if (_livreTipoModelo == _LivreTipoModelo.tipoB) {
      await _imprimirLivreTipoB();
      return;
    }
    if (_livreTipoModelo == _LivreTipoModelo.fios) {
      await _imprimirLivreFio();
      return;
    }

    final larguraMm = double.tryParse(
      _larguraLivreController.text.trim().replaceAll(',', '.'),
    );
    final alturaMm = double.tryParse(
      _alturaLivreController.text.trim().replaceAll(',', '.'),
    );
    if (larguraMm == null || larguraMm <= 0) {
      _showSnackBar('Informe a largura da etiqueta (mm).', isError: true);
      return;
    }
    if (alturaMm == null || alturaMm <= 0) {
      _showSnackBar('Informe a altura da etiqueta (mm).', isError: true);
      return;
    }
    final linhas = _linhasLivre
        .where((linha) => linha.controller.text.trim().isNotEmpty)
        .map(
          (linha) => LinhaEtiquetaLivre(
            texto: linha.controller.text.trim(),
            fonte: _fonteLivre(linha),
            tamanho: linha.tamanho,
            alinhamento: linha.alinhamento,
            negrito: linha.negrito,
          ),
        )
        .toList();
    if (linhas.isEmpty) {
      _showSnackBar('Adicione pelo menos uma linha com texto.', isError: true);
      return;
    }
    final qtde = _qtdeInformada(_qtdeLivreController);
    final confirmouQuantidade = await _confirmarQuantidadeAlta(
      aba: 'Manual',
      qtde: qtde,
      limite: 50,
    );
    if (!confirmouQuantidade) return;

    setState(() {
      _imprimindoLivre = true;
      _erro = null;
    });
    try {
      await _zebraPrinterService.imprimirEtiquetaLivre(
        larguraMm: larguraMm,
        alturaMm: alturaMm,
        linhas: linhas,
        qtde: qtde,
        ip: _printerIp,
        port: _printerPort,
      );
      if (!mounted) return;
      setState(() => _imprimindoLivre = false);
      _showSnackBar('Comando de impressão enviado.', isError: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
        _imprimindoLivre = false;
      });
    }
  }

  Future<void> _imprimirLivreTipoB() async {
    final linha1 = _tipoBLinha1Controller.text.trim().toUpperCase();
    final linha2 = _tipoBLinha2Controller.text.trim().toUpperCase();
    final codigo = _tipoBCodigoController.text.trim();
    final numero = _tipoBNumeroController.text.trim();

    if (linha1.isEmpty) {
      _showSnackBar('Informe a primeira linha do Tipo B.', isError: true);
      return;
    }
    if (linha2.isEmpty) {
      _showSnackBar('Informe a segunda linha do Tipo B.', isError: true);
      return;
    }
    if (codigo.isEmpty) {
      _showSnackBar('Informe o COD do Tipo B.', isError: true);
      return;
    }
    if (numero.isEmpty) {
      _showSnackBar('Informe o nÃºmero de destaque do Tipo B.', isError: true);
      return;
    }

    final qtde = _qtdeInformada(_qtdeLivreController);
    final confirmouQuantidade = await _confirmarQuantidadeAlta(
      aba: 'Livre',
      qtde: qtde,
      limite: 50,
    );
    if (!confirmouQuantidade) return;

    setState(() {
      _imprimindoLivre = true;
      _erro = null;
    });
    try {
      await _zebraPrinterService.imprimirEtiquetaLivreTipoB(
        linha1: linha1,
        linha2: linha2,
        codigo: codigo,
        numero: numero,
        fonteLinha1: _fonteTipoB(_tipoBFonteLinha1Controller, fallback: 36),
        fonteLinha2: _fonteTipoB(_tipoBFonteLinha2Controller, fallback: 36),
        fonteCodigo: _fonteTipoB(_tipoBFonteCodigoController, fallback: 32),
        fonteNumero: _fonteTipoB(
          _tipoBFonteNumeroController,
          fallback: 72,
          min: 32,
          max: 112,
        ),
        qtde: qtde,
        ip: _printerIp,
        port: _printerPort,
      );
      if (!mounted) return;
      setState(() => _imprimindoLivre = false);
      _showSnackBar('Comando de impressao enviado.', isError: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
        _imprimindoLivre = false;
      });
    }
  }

  Future<void> _imprimirLivreFio() async {
    final titulo = _fioTituloController.text.trim();
    final cor = _fioCorController.text.trim().toUpperCase();
    final peso = _fioPesoController.text.trim();
    final lote = _fioLoteController.text.trim().toUpperCase();
    final codigo = _fioCodigoController.text.trim();
    if (titulo.isEmpty || cor.isEmpty || peso.isEmpty || lote.isEmpty) {
      _showSnackBar('Preencha os dados da etiqueta de fio.', isError: true);
      return;
    }
    if (codigo.replaceAll(RegExp(r'\D'), '').length != 13) {
      _showSnackBar('Informe um cÃƒÂ³digo de barras EAN-13 vÃƒÂ¡lido.', isError: true);
      return;
    }

    final qtde = _qtdeInformada(_qtdeLivreController);
    final confirmouQuantidade = await _confirmarQuantidadeAlta(
      aba: 'Livre',
      qtde: qtde,
      limite: 50,
    );
    if (!confirmouQuantidade) return;

    setState(() {
      _imprimindoLivre = true;
      _erro = null;
    });
    try {
      await _zebraPrinterService.imprimirEtiquetaLivreFio(
        titulo: titulo,
        cor: cor,
        pesoLiquido: peso,
        lote: lote,
        codigoBarras: codigo,
        qtde: qtde,
        ip: _printerIp,
        port: _printerPort,
      );
      if (!mounted) return;
      setState(() => _imprimindoLivre = false);
      _showSnackBar('Comando de impressÃƒÂ£o enviado.', isError: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
        _imprimindoLivre = false;
      });
    }
  }

  int _fonteLivre(_LinhaLivreEditor linha) {
    final fonte = int.tryParse(linha.fonteController.text.trim()) ?? 36;
    return fonte.clamp(10, 120);
  }

  int _fonteOperador() {
    final fonte = int.tryParse(_opFonteController.text.trim()) ?? 72;
    return fonte.clamp(24, 100);
  }

  int _fonteTipoB(
    TextEditingController controller, {
    required int fallback,
    int min = 18,
    int max = 72,
  }) {
    final fonte = int.tryParse(controller.text.trim()) ?? fallback;
    return fonte.clamp(min, max);
  }

  void _selecionarModelo(_EtiquetaModelo modelo) {
    if (_modelo == modelo) return;
    setState(() {
      _modelo = modelo;
      _erro = null;
      if (_printers.isNotEmpty) {
        _aplicarImpressora(_impressoraPadraoParaModelo(modelo, _printers));
      }
    });
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? const Color(0xFFB91C1C)
            : const Color(0xFF047857),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.dark,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0F172A),
          labelStyle: const TextStyle(color: Color(0xFFCBD5E1)),
          hintStyle: const TextStyle(color: Color(0xFF64748B)),
          helperStyle: const TextStyle(color: Color(0xFF94A3B8)),
          prefixIconColor: const Color(0xFFCBD5E1),
          suffixIconColor: const Color(0xFFCBD5E1),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF60A5FA), width: 2),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF1E293B)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF334155),
            disabledForegroundColor: const Color(0xFF94A3B8),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF93C5FD),
            side: const BorderSide(color: Color(0xFF3B82F6)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF93C5FD)),
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF050A14),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: _pagePadding(context),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 22),
                    _buildModelSelector(),
                    const SizedBox(height: 18),
                    if (_modelo == _EtiquetaModelo.caixa)
                      _buildCaixaPanel()
                    else if (_modelo == _EtiquetaModelo.ordens)
                      _buildOrdensPanel()
                    else if (_modelo == _EtiquetaModelo.carretel)
                      _buildCarretelPanel()
                    else if (_modelo == _EtiquetaModelo.operador)
                      _buildOperadorPanel()
                    else
                      _buildLivrePanel(),
                    const SizedBox(height: 18),
                    if (_erro != null) _buildError(),
                    if (_modelo == _EtiquetaModelo.caixa &&
                        (_artigoInfo != null || _etiquetaCaixa != null))
                      _buildCaixaPreview(),
                    if (_modelo == _EtiquetaModelo.operador && _opPreview > 0)
                      _buildOperadorPreview(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  EdgeInsets _pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 420) {
      return const EdgeInsets.symmetric(horizontal: 12, vertical: 16);
    }
    if (width < 720) {
      return const EdgeInsets.symmetric(horizontal: 16, vertical: 20);
    }
    return const EdgeInsets.all(28);
  }

  bool _isNarrow(BoxConstraints constraints) => constraints.maxWidth < 720;

  double _previewWidth(double available, double maxWidth) =>
      math.min(available, maxWidth);

  BoxDecoration _panelDecoration() {
    return BoxDecoration(
      color: const Color(0xFF101B34),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0x33FFFFFF)),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'Voltar',
          color: Colors.white,
        ),
        const SizedBox(width: 4),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.print_rounded,
            color: Color(0xFF075985),
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Text(
            'Etiquetas',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModelSelector() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E2A44)),
      ),
      child: Row(
        children: [
          _modelOption(
            modelo: _EtiquetaModelo.caixa,
            icon: Icons.qr_code_2_rounded,
            label: 'Caixa',
            subtitle: '',
          ),
          _modelOption(
            modelo: _EtiquetaModelo.carretel,
            icon: Icons.donut_large_rounded,
            label: 'Carretel',
            subtitle: '',
          ),
          _modelOption(
            modelo: _EtiquetaModelo.ordens,
            icon: Icons.assignment_rounded,
            label: 'Ordens',
            subtitle: '',
          ),
          _modelOption(
            modelo: _EtiquetaModelo.operador,
            icon: Icons.badge_rounded,
            label: 'Operador',
            subtitle: '',
          ),
          _modelOption(
            modelo: _EtiquetaModelo.livre,
            icon: Icons.dashboard_customize_rounded,
            label: 'Livre',
            subtitle: '',
          ),
        ],
      ),
    );
  }

  Widget _modelOption({
    required _EtiquetaModelo modelo,
    required IconData icon,
    required String label,
    required String subtitle,
  }) {
    final selected = _modelo == modelo;
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2563EB) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _selecionarModelo(modelo),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: selected
                      ? Colors.white
                      : const Color(0xFF94A3B8),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                       color: selected
                           ? Colors.white
                           : const Color(0xFFCBD5E1),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
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

  // ── Palete ────────────────────────────────────────────────────

  Widget _buildPrinterSelector({required bool enabled}) {
    return DropdownButtonFormField<String>(
      key: ValueKey(_selectedPrinterKey),
      initialValue: _selectedPrinterKey,
      isExpanded: true,
      dropdownColor: const Color(0xFF0F172A),
      style: _dropdownTextStyle,
      iconEnabledColor: const Color(0xFFCBD5E1),
      iconDisabledColor: const Color(0xFF64748B),
      decoration: const InputDecoration(
        labelText: 'Impressora *',
        hintText: 'Selecione a Zebra',
        prefixIcon: Icon(Icons.print_rounded),
        border: OutlineInputBorder(),
      ),
      items: _printers.map((printer) {
        return DropdownMenuItem<String>(
          value: printer['key'] as String,
          child: Text(
            _printerLabel(printer),
            overflow: TextOverflow.ellipsis,
            style: _dropdownTextStyle,
          ),
        );
      }).toList(),
      selectedItemBuilder: (context) => _printers
          .map(
            (printer) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _printerLabel(printer),
                overflow: TextOverflow.ellipsis,
                style: _dropdownTextStyle,
              ),
            ),
          )
          .toList(),
      onChanged: !enabled || _printers.isEmpty
          ? null
          : (value) {
              Map<String, dynamic>? selectedPrinter;
              for (final printer in _printers) {
                if (printer['key'] == value) {
                  selectedPrinter = printer;
                  break;
                }
              }
              if (selectedPrinter == null) return;
              setState(() => _aplicarImpressora(selectedPrinter!));
            },
    );
  }

  Widget _buildPaletePanel() {
    final busy = _consultando || _imprimindo;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = _isNarrow(constraints);
          final printerField = _buildPrinterSelector(enabled: !busy);
          final field = TextField(
            controller: _paleteController,
            enabled: !busy,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _consultar(),
            decoration: const InputDecoration(
              labelText: 'Endere\u00e7o do palete',
              hintText: 'PA-L1-R100-D-P1',
              prefixIcon: Icon(Icons.qr_code_2_rounded),
              border: OutlineInputBorder(),
            ),
          );
          final qrButton = SizedBox(
            height: 56,
            width: narrow ? double.infinity : null,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: busy ? null : _mostrarQrCode,
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('QR Code'),
            ),
          );
          final printButton = SizedBox(
            height: 56,
            width: narrow ? double.infinity : null,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: busy ? null : _imprimir,
              icon: _imprimindo
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.print_rounded),
              label: const Text('Imprimir'),
            ),
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                printerField,
                const SizedBox(height: 10),
                field,
                const SizedBox(height: 10),
                qrButton,
                const SizedBox(height: 10),
                printButton,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: printerField),
              const SizedBox(width: 10),
              Expanded(child: field),
              const SizedBox(width: 10),
              qrButton,
              const SizedBox(width: 10),
              printButton,
            ],
          );
        },
      ),
    );
  }

  Widget _buildOrdensPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('Consultar ordens'),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = _isNarrow(constraints);
              final skuField = _campo(
                controller: _ordemSkuNameController,
                label: 'Material',
                hint: 'Digite o nome ou codigo do artigo',
                icon: Icons.inventory_2_rounded,
                enabled: !_consultandoOrdens,
                onChanged: _onOrdemBuscaChanged,
                onSubmit: _consultarOrdensExpedicao,
                suffix: _buscandoOrdemArtigos
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _ordemSkuSelecionado > 0
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF047857),
                      )
                    : null,
              );
              final consultarButton = SizedBox(
                height: 56,
                width: narrow ? double.infinity : 150,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed:
                      _consultandoOrdens ? null : _consultarOrdensExpedicao,
                  icon: _consultandoOrdens
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search_rounded),
                  label: Text(
                    _consultandoOrdens ? 'Consultando' : 'Consultar',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    skuField,
                    const SizedBox(height: 12),
                    consultarButton,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: skuField),
                  const SizedBox(width: 12),
                  consultarButton,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (_ordemArtigoOpcoes.isNotEmpty) ...[
            _buildOrdensAutocomplete(),
            const SizedBox(height: 16),
          ],
          if (_ordensExpedicao.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DarkMetricPill(
                  label: 'Ordens',
                  value: _ordensExpedicao.length.toString(),
                  icon: Icons.assignment_turned_in_rounded,
                ),
                _DarkMetricPill(
                  label: 'Quantidade',
                  value: _formatarNumeroOrdens(
                    _ordensExpedicao.fold<double>(
                      0,
                      (total, item) => total + item.quantity,
                    ),
                  ),
                  icon: Icons.straighten_rounded,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (_consultandoOrdens)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF60A5FA)),
              ),
            )
          else if (_ordensExpedicao.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search_rounded, color: Color(0xFF94A3B8)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Digite o nome do material, selecione um artigo e consulte as ordens.',
                      style: TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _ordensExpedicao.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _buildOrdemCard(_ordensExpedicao[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildOrdensAutocomplete() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _ordemArtigoOpcoes.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 16, color: Color(0xFF1E293B)),
        itemBuilder: (context, index) {
          final artigo = _ordemArtigoOpcoes[index];
          final cdObj = _toIntPadrao(artigo['CdObj']);
          final nmObj = (artigo['NmObj'] ?? '').toString().trim();
          return InkWell(
            onTap: () => _selecionarArtigoOrdem(artigo),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E40AF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      cdObj.toString(),
                      style: const TextStyle(
                        color: Color(0xFFE0F2FE),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      nmObj.isEmpty ? 'Artigo sem descricao' : nmObj,
                      style: const TextStyle(
                        color: Color(0xFFF8FAFC),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.keyboard_arrow_right_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrdemCard(_OrdemExpedicao ordem) {
    final expanded = _ordensExpandidas.contains(_ordemKey(ordem));
    final unidadeLocal = [
      if (ordem.uom.isNotEmpty) 'Unidade: ${ordem.uom}',
      if (ordem.stockLocationName.isNotEmpty)
        'Local: ${ordem.stockLocationName}',
    ].join('  |  ');
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _toggleOrdemCard(ordem),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.all(expanded ? 16 : 12),
        decoration: BoxDecoration(
          color: expanded ? const Color(0xFF0F172A) : const Color(0xFF0B1220),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: expanded ? const Color(0xFF3B82F6) : const Color(0xFF334155),
          ),
          boxShadow: expanded
              ? [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: expanded ? 44 : 36,
                  height: expanded ? 44 : 36,
                  decoration: BoxDecoration(
                    color: expanded
                        ? const Color(0xFF1D4ED8)
                        : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.assignment_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ordem.titulo.isEmpty
                            ? 'Artigo sem descricao'
                            : ordem.titulo,
                        maxLines: expanded ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFF8FAFC),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _DarkTag(
                            label: ordem.skuName.isEmpty
                                ? 'SKU -'
                                : 'SKU ${ordem.skuName}',
                            icon: Icons.qr_code_2_rounded,
                          ),
                          if (ordem.plant.isNotEmpty)
                            _DarkTag(
                              label: ordem.plant,
                              icon: Icons.apartment_rounded,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Ordem',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      ordem.woid.isEmpty ? '-' : ordem.woid,
                      style: const TextStyle(
                        color: Color(0xFF93C5FD),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: const Color(0xFF94A3B8),
                    ),
                  ],
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Color(0xFF1E293B)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DarkMetricPill(
                        label: 'Quantidade',
                        value: _formatarNumeroOrdens(ordem.quantity),
                        icon: Icons.straighten_rounded,
                      ),
                      _DarkMetricPill(
                        label: 'Pedido',
                        value: ordem.salesOrderId.isEmpty
                            ? '-'
                            : ordem.salesOrderId,
                        icon: Icons.receipt_long_rounded,
                      ),
                      _DarkMetricPill(
                        label: 'Familia',
                        value: ordem.productionFamily.isEmpty
                            ? '-'
                            : ordem.productionFamily,
                        icon: Icons.category_rounded,
                      ),
                      _DarkMetricPill(
                        label: 'Entrega',
                        value: _formatarDataOrdem(ordem.dueDate),
                        icon: Icons.event_rounded,
                      ),
                      _DarkMetricPill(
                        label: 'Liberacao',
                        value: _formatarDataOrdem(ordem.releaseDate),
                        icon: Icons.event_available_rounded,
                      ),
                      _DarkMetricPill(
                        label: 'Estoque',
                        value: _formatarNumeroOrdens(ordem.localStock),
                        icon: Icons.warehouse_rounded,
                      ),
                      _DarkMetricPill(
                        label: 'Alvo',
                        value: _formatarNumeroOrdens(ordem.alvo),
                        icon: Icons.flag_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          unidadeLocal.isEmpty
                              ? 'Unidade/local nao informados'
                              : unidadeLocal,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _selecionarOrdemParaCaixa(ordem),
                        icon: const Icon(Icons.qr_code_2_rounded),
                        label: const Text('Usar na Caixa'),
                      ),
                    ],
                  ),
                ],
              ),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 160),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaixaPanel() {
    final busy = _consultandoBusca || _imprimindo;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPrinterSelector(enabled: !busy),
          const SizedBox(height: 16),
          _sectionLabel('Buscar artigo'),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = _isNarrow(constraints);
              final buscaField = TextField(
                controller: _buscaController,
                enabled: !busy,
                style: const TextStyle(
                  color: Color(0xFFF8FAFC),
                  fontWeight: FontWeight.w600,
                ),
                cursorColor: const Color(0xFF60A5FA),
                onChanged: _onBuscaChanged,
                onSubmitted: (_) {
                  if (_cdObjSelecionado > 0) {
                    _buscarArtigo();
                  } else if (_buscaOpcoes.isNotEmpty) {
                    _selecionarArtigo(_buscaOpcoes.first);
                  } else {
                    final code =
                        int.tryParse(_buscaController.text.trim()) ?? 0;
                    if (code > 0) {
                      setState(() {
                        _cdObjSelecionado = code;
                        _artigoSelecionadoBusca = null;
                      });
                      _buscarArtigo();
                    }
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Artigo - nome ou c\u00f3digo *',
                  hintText: 'Digite o nome ou c\u00f3digo...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _buscandoOpcoes
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _cdObjSelecionado > 0
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF047857),
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
              );
              final buscarButton = SizedBox(
                height: 56,
                width: narrow ? double.infinity : 130,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: busy
                      ? null
                      : () {
                          if (_cdObjSelecionado > 0) {
                            _buscarArtigo();
                          } else {
                            final code =
                                int.tryParse(_buscaController.text.trim()) ?? 0;
                            if (code > 0) {
                              setState(() {
                                _cdObjSelecionado = code;
                                _artigoSelecionadoBusca = null;
                              });
                              _buscarArtigo();
                            } else {
                              _showSnackBar(
                                'Selecione um artigo da lista ou informe o c\u00f3digo.',
                                isError: true,
                              );
                            }
                          }
                        },
                  icon: _consultandoBusca
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search_rounded),
                  label: const Text(
                    'Buscar',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buscaField,
                    const SizedBox(height: 12),
                    buscarButton,
                  ],
                );
              }

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: buscaField),
                    const SizedBox(width: 12),
                    buscarButton,
                  ],
                ),
              );
            },
          ),
          if (_buscaOpcoes.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _buscaOpcoes.length,
                separatorBuilder: (_, __) =>
                    const Divider(
                      height: 1,
                      indent: 16,
                      color: Color(0xFF1E293B),
                    ),
                itemBuilder: (context, i) {
                  final artigo = _buscaOpcoes[i];
                  final cdObj = artigo['CdObj'].toString();
                  final nmObj = (artigo['NmObj'] ?? '').toString().trim();
                  return InkWell(
                    onTap: () => _selecionarArtigo(artigo),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E40AF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              cdObj,
                              style: const TextStyle(
                                color: Color(0xFFE0F2FE),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              nmObj,
                              style: const TextStyle(
                                color: Color(0xFFF8FAFC),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),
          _sectionLabel('Dados da etiqueta'),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = _isNarrow(constraints);
              final metrosField = _campo(
                controller: _metrosController,
                label: 'Metros *',
                hint: '3000',
                icon: Icons.straighten_rounded,
                numeric: true,
                enabled: !busy,
                onChanged: (_) => setState(_atualizarTipoCaixa),
                onSubmit: _consultarPadraoCaixaArtigo,
              );
              final tipoField = _buildTipoCaixaAssistidoField(busy);
              final ordemField = _campo(
                controller: _ordemController,
                label: 'N\u00ba da Ordem',
                hint: '123456',
                icon: Icons.tag_rounded,
                numeric: true,
                enabled: !busy,
              );
              final detalheField = _buildDetalheField(busy);

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    metrosField,
                    const SizedBox(height: 12),
                    tipoField,
                    const SizedBox(height: 12),
                    ordemField,
                    const SizedBox(height: 12),
                    detalheField,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: metrosField),
                  const SizedBox(width: 12),
                  Expanded(child: tipoField),
                  const SizedBox(width: 12),
                  Expanded(child: ordemField),
                  const SizedBox(width: 12),
                  Expanded(child: detalheField),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = _isNarrow(constraints);
              final loteField = _campo(
                controller: _loteController,
                label: _temPreto ? 'Lote *' : 'Lote',
                hint: 'LOTE123',
                icon: Icons.label_rounded,
                caps: true,
                enabled: !busy,
                highlight: _temPreto,
                suffix: _naoImprimeLoteLinha && _loteInline
                    ? const Tooltip(
                        message: 'Lote ao lado dos metros',
                        child: Icon(
                          Icons.info_outline_rounded,
                          color: Color(0xFF0284C7),
                          size: 18,
                        ),
                      )
                    : null,
              );
              final operadorField = DropdownButtonFormField<String>(
                initialValue: _operadorCaixaSelecionadoCodigo,
                isExpanded: true,
                dropdownColor: const Color(0xFF0F172A),
                style: _dropdownTextStyle,
                iconEnabledColor: const Color(0xFFCBD5E1),
                iconDisabledColor: const Color(0xFF64748B),
                decoration: InputDecoration(
                  labelText: 'Operador',
                  prefixIcon: const Icon(Icons.person_rounded),
                  border: const OutlineInputBorder(),
                  helperText: _carregandoOperadores
                      ? 'Carregando operadores...'
                      : _operadores.isEmpty
                          ? 'Nenhum operador encontrado.'
                          : 'Selecione o operador.',
                ),
                items: _operadores
                    .map(
                      (operador) => DropdownMenuItem<String>(
                        value: operador.codigo,
                        child: Text(
                          operador.label,
                          overflow: TextOverflow.ellipsis,
                          style: _dropdownTextStyle,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: busy || _carregandoOperadores || _operadores.isEmpty
                    ? null
                    : (value) {
                        setState(() {
                          _operadorCaixaSelecionadoCodigo = value;
                        });
                      },
              );
              final qtdeField = _campo(
                controller: _qtdeController,
                label: 'Qtde',
                hint: '1',
                icon: Icons.numbers_rounded,
                numeric: true,
                enabled: !busy,
              );
              final toggleField = SizedBox(
                height: 56,
                width: narrow ? double.infinity : null,
                child: _ToggleChip(
                  label: 'Pedido Especial',
                  value: _pedidoEspecial,
                  enabled: !busy,
                  onChanged: (v) => setState(() => _pedidoEspecial = v),
                ),
              );
              final loteChip = SizedBox(
                height: 56,
                width: narrow ? double.infinity : null,
                child: Tooltip(
                  message:
                      'Mantem as proximas caixas impressas no mesmo lote (LI).',
                  child: _ToggleChip(
                    label: 'Manter lote',
                    value: _manterLoteCaixa,
                    enabled: !busy,
                    onChanged: (v) => setState(() {
                      _manterLoteCaixa = v;
                      if (!v) _loteImpressaoCaixa = null;
                    }),
                  ),
                ),
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    loteField,
                    const SizedBox(height: 12),
                    operadorField,
                    const SizedBox(height: 12),
                    qtdeField,
                    const SizedBox(height: 12),
                    toggleField,
                    const SizedBox(height: 12),
                    loteChip,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: loteField),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: operadorField),
                  const SizedBox(width: 12),
                  SizedBox(width: 100, child: qtdeField),
                  const SizedBox(width: 12),
                  Align(alignment: Alignment.topCenter, child: toggleField),
                  const SizedBox(width: 12),
                  Align(alignment: Alignment.topCenter, child: loteChip),
                ],
              );
            },
          ),
          if (_manterLoteCaixa) ...[
            const SizedBox(height: 8),
            Text(
              _loteImpressaoCaixa == null
                  ? 'Lote: sera gerado na proxima impressao'
                  : 'Lote (LI): $_loteImpressaoCaixa - proximas caixas entram no mesmo lote',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: busy || _artigoInfo == null ? null : _imprimirCaixa,
              icon: _imprimindo
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_rounded),
              label: const Text(
                'Imprimir',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarretelPanel() {
    final busy = _consultandoCarretel || _imprimindoCarretel;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPrinterSelector(enabled: !busy),
          const SizedBox(height: 16),
          _sectionLabel('Buscar artigo'),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = _isNarrow(constraints);
              final buscaField = TextField(
                controller: _buscaCarretelController,
                enabled: !busy,
                style: const TextStyle(
                  color: Color(0xFFF8FAFC),
                  fontWeight: FontWeight.w600,
                ),
                cursorColor: const Color(0xFF60A5FA),
                onChanged: _onBuscaCarretelChanged,
                onSubmitted: (_) {
                  if (_cdObjCarretelSelecionado > 0) {
                    _buscarArtigoCarretel();
                  } else if (_buscaCarretelOpcoes.isNotEmpty) {
                    _selecionarArtigoCarretel(_buscaCarretelOpcoes.first);
                  } else {
                    final code =
                        int.tryParse(_buscaCarretelController.text.trim()) ??
                        0;
                    if (code > 0) {
                      setState(() => _cdObjCarretelSelecionado = code);
                      _buscarArtigoCarretel();
                    }
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Artigo - nome ou código *',
                  hintText: 'Digite o nome ou código...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _buscandoCarretelOpcoes
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _cdObjCarretelSelecionado > 0
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF047857),
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
              );
              final buscarButton = SizedBox(
                height: 56,
                width: narrow ? double.infinity : 130,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: busy
                      ? null
                      : () {
                          if (_cdObjCarretelSelecionado > 0) {
                            _buscarArtigoCarretel();
                          } else {
                            final code =
                                int.tryParse(
                                  _buscaCarretelController.text.trim(),
                                ) ??
                                0;
                            if (code > 0) {
                              setState(() => _cdObjCarretelSelecionado = code);
                              _buscarArtigoCarretel();
                            } else {
                              _showSnackBar(
                                'Selecione um artigo da lista ou informe o código.',
                                isError: true,
                              );
                            }
                          }
                        },
                  icon: _consultandoCarretel
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search_rounded),
                  label: const Text(
                    'Buscar',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buscaField,
                    const SizedBox(height: 12),
                    buscarButton,
                  ],
                );
              }

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: buscaField),
                    const SizedBox(width: 12),
                    buscarButton,
                  ],
                ),
              );
            },
          ),
          if (_buscaCarretelOpcoes.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _buscaCarretelOpcoes.length,
                separatorBuilder: (_, __) =>
                    const Divider(
                      height: 1,
                      indent: 16,
                      color: Color(0xFF1E293B),
                    ),
                itemBuilder: (context, i) {
                  final artigo = _buscaCarretelOpcoes[i];
                  final cdObj = artigo['CdObj'].toString();
                  final nmObj = (artigo['NmObj'] ?? '').toString().trim();
                  return InkWell(
                    onTap: () => _selecionarArtigoCarretel(artigo),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E40AF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              cdObj,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: Color(0xFFE0F2FE),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              nmObj,
                              style: const TextStyle(
                                color: Color(0xFFF8FAFC),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),
          _sectionLabel('Dados da etiqueta'),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = _isNarrow(constraints);
              final temPretoCarretel = (_carretelInfo?['NmObj'] ?? '')
                  .toString()
                  .toUpperCase()
                  .contains('PRETO');
              final loteField = _campo(
                controller: _loteCarretelController,
                label: temPretoCarretel ? 'Lote *' : 'Lote',
                hint: 'Ex: 12345',
                icon: Icons.label_outline_rounded,
                caps: true,
                enabled: !busy,
                highlight: temPretoCarretel,
              );
              final operadorField = _campo(
                controller: _operadorCarretelController,
                label: 'Operador',
                hint: 'Código do operador',
                icon: Icons.badge_outlined,
                numeric: true,
                enabled: !busy,
              );
              final qtdeField = _campo(
                controller: _qtdeCarretelController,
                label: 'Qtde',
                hint: '1',
                icon: Icons.filter_9_plus_rounded,
                numeric: true,
                enabled: !busy,
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    loteField,
                    const SizedBox(height: 12),
                    operadorField,
                    const SizedBox(height: 12),
                    qtdeField,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: loteField),
                  const SizedBox(width: 12),
                  Expanded(child: operadorField),
                  const SizedBox(width: 12),
                  Expanded(child: qtdeField),
                ],
              );
            },
          ),
          if (_carretelInfo != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (_carretelInfo!['NmObj'] ?? '').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if ((_carretelInfo!['Descricao'] ?? '')
                      .toString()
                      .isNotEmpty)
                    Text((_carretelInfo!['Descricao'] ?? '').toString()),
                  const SizedBox(height: 4),
                  Text(
                    'Metragem: ${(_carretelInfo!['Metragem'] ?? '').toString().isEmpty ? '-' : _carretelInfo!['Metragem']}'
                    '  •  EAN13: ${(_carretelInfo!['Ean13'] ?? '').toString().isEmpty ? '-' : _carretelInfo!['Ean13']}',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: busy || _cdObjCarretelSelecionado <= 0
                  ? null
                  : _imprimirCarretel,
              icon: _imprimindoCarretel
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_rounded),
              label: const Text(
                'Imprimir',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperadorPanel() {
    final busy = _imprimindoOp;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPrinterSelector(enabled: !busy),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = _isNarrow(constraints);
              final operadorField = DropdownButtonFormField<String>(
                initialValue: _operadorSelecionadoCodigo,
                isExpanded: true,
                dropdownColor: const Color(0xFF0F172A),
                style: _dropdownTextStyle,
                iconEnabledColor: const Color(0xFFCBD5E1),
                iconDisabledColor: const Color(0xFF64748B),
                decoration: InputDecoration(
                  labelText: 'Operador *',
                  prefixIcon: const Icon(Icons.badge_rounded),
                  border: const OutlineInputBorder(),
                  helperText: _carregandoOperadores
                      ? 'Carregando operadores...'
                      : _operadores.isEmpty
                      ? 'Nenhum operador encontrado.'
                      : 'Selecione o operador para imprimir o código.',
                ),
                items: _operadores
                    .map(
                      (operador) => DropdownMenuItem<String>(
                        value: operador.codigo,
                        child: Text(
                          operador.label,
                          overflow: TextOverflow.ellipsis,
                          style: _dropdownTextStyle,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: busy || _carregandoOperadores || _operadores.isEmpty
                    ? null
                    : (value) {
                        setState(() {
                          _operadorSelecionadoCodigo = value;
                        });
                      },
              );
              final qtdeField = _campo(
                controller: _opQtdeController,
                label: 'Qtde',
                hint: '1',
                icon: Icons.numbers_rounded,
                numeric: true,
                enabled: !busy,
              );
              final fonteField = _campo(
                controller: _opFonteController,
                label: 'Fonte',
                hint: '72',
                icon: Icons.format_size_rounded,
                numeric: true,
                enabled: !busy,
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    operadorField,
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: qtdeField),
                        const SizedBox(width: 12),
                        Expanded(child: fonteField),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: operadorField),
                  const SizedBox(width: 12),
                  SizedBox(width: 110, child: qtdeField),
                  const SizedBox(width: 12),
                  SizedBox(width: 120, child: fonteField),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: busy ? null : _imprimirOperador,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.print_rounded),
              label: const Text(
                'Imprimir',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperadorPreview() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE4EE)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = _previewWidth(constraints.maxWidth, 520);
          return Center(
            child: SizedBox(
              width: width,
              height: width * (143 / 520),
              child: CustomPaint(
                painter: _EtiquetaOperadorPainter(
                  operador: _opPreview,
                  fonte: _fonteOperador().toDouble(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Etiqueta Livre ──────────────────────────────────────────────

  Widget _buildLivrePanel() {
    final busy = _imprimindoLivre;
    final tipoB = _livreTipoModelo == _LivreTipoModelo.tipoB;
    final fios = _livreTipoModelo == _LivreTipoModelo.fios;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPrinterSelector(enabled: !busy),
          const SizedBox(height: 16),
          _sectionLabel('Tipo de impressao'),
          const SizedBox(height: 10),
          SegmentedButton<_LivreTipoModelo>(
            segments: const [
              ButtonSegment(
                value: _LivreTipoModelo.livre,
                icon: Icon(Icons.edit_note_rounded),
                label: Text('Livre'),
              ),
              ButtonSegment(
                value: _LivreTipoModelo.tipoB,
                icon: Icon(Icons.sell_outlined),
                label: Text('Tipo B'),
              ),
              ButtonSegment(
                value: _LivreTipoModelo.fios,
                icon: Icon(Icons.palette_outlined),
                label: Text('Fios'),
              ),
            ],
            selected: {_livreTipoModelo},
            onSelectionChanged: busy
                ? null
                : (value) => setState(() => _livreTipoModelo = value.first),
          ),
          const SizedBox(height: 20),
          _sectionLabel('Tamanho da etiqueta'),
          const SizedBox(height: 10),
          tipoB || fios
              ? _buildLivreTipoBTamanho(busy)
              : _buildLivreTamanhoLivre(busy),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),
          if (tipoB)
            _buildLivreTipoBFields(busy)
          else if (fios)
            _buildLivreFiosFields(busy)
          else ...[
            Row(
              children: [
                Expanded(child: _sectionLabel('Linhas da etiqueta')),
                TextButton.icon(
                  onPressed: busy ? null : _adicionarLinhaLivre,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Adicionar linha'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < _linhasLivre.length; i++) ...[
              _buildLinhaLivreRow(i, busy),
              const SizedBox(height: 10),
            ],
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: busy ? null : _imprimirLivre,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.print_rounded),
              label: const Text(
                'Imprimir',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivreTamanhoLivre(bool busy) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = _isNarrow(constraints);
        final larguraField = _campo(
          controller: _larguraLivreController,
          label: 'Largura (mm) *',
          hint: '80',
          icon: Icons.straighten_rounded,
          numeric: true,
          enabled: !busy,
        );
        final alturaField = _campo(
          controller: _alturaLivreController,
          label: 'Altura (mm) *',
          hint: '50',
          icon: Icons.height_rounded,
          numeric: true,
          enabled: !busy,
        );
        final qtdeField = _campo(
          controller: _qtdeLivreController,
          label: 'Qtde',
          hint: '1',
          icon: Icons.numbers_rounded,
          numeric: true,
          enabled: !busy,
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              larguraField,
              const SizedBox(height: 12),
              alturaField,
              const SizedBox(height: 12),
              qtdeField,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: larguraField),
            const SizedBox(width: 12),
            Expanded(child: alturaField),
            const SizedBox(width: 12),
            SizedBox(width: 110, child: qtdeField),
          ],
        );
      },
    );
  }

  Widget _buildLivreTipoBTamanho(bool busy) {
    final papelField = TextFormField(
      initialValue: '50 x 50',
      enabled: false,
      style: const TextStyle(
        color: Color(0xFFF8FAFC),
        fontWeight: FontWeight.w700,
      ),
      decoration: const InputDecoration(
        labelText: 'Papel (mm)',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.crop_square_rounded),
      ),
    );
    final qtdeField = _campo(
      controller: _qtdeLivreController,
      label: 'Qtde',
      hint: '1',
      icon: Icons.numbers_rounded,
      numeric: true,
      enabled: !busy,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (_isNarrow(constraints)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              papelField,
              const SizedBox(height: 12),
              qtdeField,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: papelField),
            const SizedBox(width: 12),
            SizedBox(width: 130, child: qtdeField),
          ],
        );
      },
    );
  }

  Widget _buildLivreTipoBFields(bool busy) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = _isNarrow(constraints);
        final linha1Field = _campo(
          controller: _tipoBLinha1Controller,
          label: 'Linha 1 *',
          hint: 'X NILO 16',
          icon: Icons.short_text_rounded,
          enabled: !busy,
        );
        final linha2Field = _campo(
          controller: _tipoBLinha2Controller,
          label: 'Linha 2 *',
          hint: 'PRETO 2',
          icon: Icons.short_text_rounded,
          enabled: !busy,
        );
        final codigoField = _campo(
          controller: _tipoBCodigoController,
          label: 'COD *',
          hint: '25',
          icon: Icons.tag_rounded,
          enabled: !busy,
        );
        final numeroField = _campo(
          controller: _tipoBNumeroController,
          label: 'Numero *',
          hint: '116',
          icon: Icons.pin_rounded,
          numeric: true,
          enabled: !busy,
        );
        final fonteLinha1Field = _campo(
          controller: _tipoBFonteLinha1Controller,
          label: 'Fonte linha 1',
          hint: '36',
          icon: Icons.format_size_rounded,
          numeric: true,
          enabled: !busy,
        );
        final fonteLinha2Field = _campo(
          controller: _tipoBFonteLinha2Controller,
          label: 'Fonte linha 2',
          hint: '36',
          icon: Icons.format_size_rounded,
          numeric: true,
          enabled: !busy,
        );
        final fonteCodigoField = _campo(
          controller: _tipoBFonteCodigoController,
          label: 'Fonte COD',
          hint: '32',
          icon: Icons.format_size_rounded,
          numeric: true,
          enabled: !busy,
        );
        final fonteNumeroField = _campo(
          controller: _tipoBFonteNumeroController,
          label: 'Fonte numero',
          hint: '72',
          icon: Icons.format_size_rounded,
          numeric: true,
          enabled: !busy,
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              linha1Field,
              const SizedBox(height: 12),
              fonteLinha1Field,
              const SizedBox(height: 12),
              linha2Field,
              const SizedBox(height: 12),
              fonteLinha2Field,
              const SizedBox(height: 12),
              codigoField,
              const SizedBox(height: 12),
              fonteCodigoField,
              const SizedBox(height: 12),
              numeroField,
              const SizedBox(height: 12),
              fonteNumeroField,
            ],
          );
        }

        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: linha1Field),
                const SizedBox(width: 12),
                SizedBox(width: 150, child: fonteLinha1Field),
                const SizedBox(width: 12),
                Expanded(child: linha2Field),
                const SizedBox(width: 12),
                SizedBox(width: 150, child: fonteLinha2Field),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: codigoField),
                const SizedBox(width: 12),
                SizedBox(width: 150, child: fonteCodigoField),
                const SizedBox(width: 12),
                SizedBox(width: 170, child: numeroField),
                const SizedBox(width: 12),
                SizedBox(width: 150, child: fonteNumeroField),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildLivreFiosFields(bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('Fio'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final fio in _fiosLivre)
              ChoiceChip(
                label: Text(fio.cor),
                selected: _fioLivreSelecionado.cor == fio.cor,
                showCheckmark: true,
                selectedColor: const Color(0xFF2563EB),
                backgroundColor: const Color(0xFF111827),
                disabledColor: const Color(0xFF111827),
                side: BorderSide(
                  color: _fioLivreSelecionado.cor == fio.cor
                      ? const Color(0xFF93C5FD)
                      : const Color(0xFF334155),
                ),
                labelStyle: TextStyle(
                  color: busy
                      ? const Color(0xFF64748B)
                      : _fioLivreSelecionado.cor == fio.cor
                      ? Colors.white
                      : const Color(0xFFCBD5E1),
                  fontWeight: FontWeight.w800,
                ),
                onSelected: busy ? null : (_) => _aplicarFioLivre(fio),
              ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = _isNarrow(constraints);
            final tituloField = _campo(
              controller: _fioTituloController,
              label: 'Titulo *',
              hint: 'Fio Poliester 167/48',
              icon: Icons.short_text_rounded,
              enabled: !busy,
              onChanged: (_) => setState(() {}),
            );
            final corField = _campo(
              controller: _fioCorController,
              label: 'Cor *',
              hint: 'VERDE GRAMA',
              icon: Icons.palette_outlined,
              caps: true,
              enabled: !busy,
              onChanged: (_) => setState(() {}),
            );
            final pesoField = _campo(
              controller: _fioPesoController,
              label: 'Peso liquido *',
              hint: '300g',
              icon: Icons.scale_rounded,
              enabled: !busy,
              onChanged: (_) => setState(() {}),
            );
            final loteField = _campo(
              controller: _fioLoteController,
              label: 'Lote *',
              hint: 'F4',
              icon: Icons.inventory_2_outlined,
              caps: true,
              enabled: !busy,
              onChanged: (_) => setState(() {}),
            );
            final codigoField = _campo(
              controller: _fioCodigoController,
              label: 'Codigo de barras *',
              hint: '7896714231266',
              icon: Icons.barcode_reader,
              numeric: true,
              enabled: !busy,
              onChanged: (_) => setState(() {}),
            );

            final fields = narrow
                ? Column(
                    children: [
                      tituloField,
                      const SizedBox(height: 12),
                      corField,
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: pesoField),
                          const SizedBox(width: 12),
                          Expanded(child: loteField),
                        ],
                      ),
                      const SizedBox(height: 12),
                      codigoField,
                    ],
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: tituloField),
                          const SizedBox(width: 12),
                          Expanded(child: corField),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: pesoField),
                          const SizedBox(width: 12),
                          Expanded(child: loteField),
                          const SizedBox(width: 12),
                          Expanded(child: codigoField),
                        ],
                      ),
                    ],
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                fields,
                const SizedBox(height: 16),
                _buildFioLivrePreview(),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildFioLivrePreview() {
    final codigo = _fioCodigoController.text.trim();
    return Center(
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxWidth: double.infinity),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD1D5DB)),
        ),
        child: AspectRatio(
          aspectRatio: 1.6,
          child: CustomPaint(
            painter: _FioLivrePreviewPainter(
              titulo: _fioTituloController.text,
              cor: _fioCorController.text,
              peso: _fioPesoController.text,
              lote: _fioLoteController.text,
              codigo: codigo,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLinhaLivreRow(int index, bool busy) {
    final linha = _linhasLivre[index];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1224),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = _isNarrow(constraints);
          final textoField = TextField(
            controller: linha.controller,
            enabled: !busy,
            style: const TextStyle(
              color: Color(0xFFF8FAFC),
              fontWeight: FontWeight.w600,
            ),
            cursorColor: const Color(0xFF60A5FA),
            decoration: InputDecoration(
              labelText: 'Texto da linha ${index + 1}',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          );
          final fonteField = TextField(
            controller: linha.fonteController,
            enabled: !busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              color: Color(0xFFF8FAFC),
              fontWeight: FontWeight.w600,
            ),
            cursorColor: const Color(0xFF60A5FA),
            decoration: const InputDecoration(
              labelText: 'Fonte',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          );
          final alinhamentoField =
              DropdownButtonFormField<AlinhamentoLinhaLivre>(
                initialValue: linha.alinhamento,
                dropdownColor: const Color(0xFF0F172A),
                style: _dropdownTextStyle,
                iconEnabledColor: const Color(0xFFCBD5E1),
                iconDisabledColor: const Color(0xFF64748B),
                decoration: const InputDecoration(
                  labelText: 'Alinhamento',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: AlinhamentoLinhaLivre.esquerda,
                    child: Text('Esquerda', style: _dropdownTextStyle),
                  ),
                  DropdownMenuItem(
                    value: AlinhamentoLinhaLivre.centro,
                    child: Text('Centro', style: _dropdownTextStyle),
                  ),
                  DropdownMenuItem(
                    value: AlinhamentoLinhaLivre.direita,
                    child: Text('Direita', style: _dropdownTextStyle),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => linha.alinhamento = value);
                        }
                      },
              );
          final negritoToggle = FilterChip(
            label: const Text('Negrito'),
            selected: linha.negrito,
            showCheckmark: true,
            checkmarkColor: Colors.white,
            backgroundColor: const Color(0xFF111827),
            selectedColor: const Color(0xFF2563EB),
            disabledColor: const Color(0xFF111827),
            side: BorderSide(
              color: linha.negrito
                  ? const Color(0xFF60A5FA)
                  : const Color(0xFF334155),
            ),
            labelStyle: TextStyle(
              color: busy
                  ? const Color(0xFF64748B)
                  : linha.negrito
                  ? Colors.white
                  : const Color(0xFFCBD5E1),
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            onSelected: busy
                ? null
                : (value) => setState(() => linha.negrito = value),
          );
          final removerButton = IconButton(
            onPressed: busy || _linhasLivre.length <= 1
                ? null
                : () => _removerLinhaLivre(index),
            icon: const Icon(Icons.delete_outline_rounded),
            color: const Color(0xFFB91C1C),
            tooltip: 'Remover linha',
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                textoField,
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(width: 96, child: fonteField),
                    const SizedBox(width: 8),
                    Expanded(child: alinhamentoField),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    negritoToggle,
                    const Spacer(),
                    removerButton,
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 3, child: textoField),
              const SizedBox(width: 8),
              SizedBox(width: 92, child: fonteField),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: alinhamentoField),
              const SizedBox(width: 8),
              negritoToggle,
              removerButton,
            ],
          );
        },
      ),
    );
  }
  /// Detalhe: dropdown para PRETO/personalizados, campo de texto nos demais.
  Widget _buildDetalheField(bool busy) {
    if (_usaDropdownDetalhe) return _buildDetalheSearchField(busy);

    if (_usaDropdownDetalhe) {
      if (_carregandoLotes) {
        return const SizedBox(
          height: 56,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      return DropdownButtonFormField<int>(
        initialValue: _detalheSelecionado > 0 ? _detalheSelecionado : null,
        isExpanded: true,
        dropdownColor: const Color(0xFF0F172A),
        style: _dropdownTextStyle,
        iconEnabledColor: const Color(0xFFCBD5E1),
        iconDisabledColor: const Color(0xFF64748B),
        decoration: InputDecoration(
          labelText: _temPreto ? 'Cor / Lote *' : 'Detalhe *',
          prefixIcon: const Icon(Icons.palette_rounded),
          border: const OutlineInputBorder(),
          labelStyle: const TextStyle(color: Color(0xFFB45309)),
        ),
        hint: Text(
          _lotesList.isEmpty ? 'Nenhum lote encontrado' : 'Selecione...',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        items: _lotesList.map((lot) {
          final cdLot = _toIntPadrao(lot['CdLot']);
          final nmLot = (lot['NmLot'] ?? '').toString().trim();
          return DropdownMenuItem<int>(
            value: cdLot,
            child: Text(
              nmLot.isNotEmpty ? '$cdLot — $nmLot' : cdLot.toString(),
              overflow: TextOverflow.ellipsis,
              style: _dropdownTextStyle,
            ),
          );
        }).toList(),
        onChanged: busy || _lotesList.isEmpty ? null : _selecionarDetalhe,
      );
    }

    return _campo(
      controller: _detalheController,
      label: 'Detalhe (auto)',
      hint: '',
      icon: Icons.palette_rounded,
      numeric: false,
      enabled: !busy,
    );
  }

  Widget _buildDetalheSearchField(bool busy) {
    if (_carregandoLotes) {
      return const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final selecionado = _lotesList.firstWhere(
      (lot) => _toIntPadrao(lot['CdLot']) == _detalheSelecionado,
      orElse: () => {},
    );
    final nmSelecionado = (selecionado['NmLot'] ?? '').toString().trim();
    final cdSelecionado = _toIntPadrao(selecionado['CdLot']);
    final textoSelecionado = selecionado.isEmpty
        ? ''
        : nmSelecionado.isEmpty
        ? cdSelecionado.toString()
        : '$cdSelecionado - $nmSelecionado';

    return TextField(
      controller: TextEditingController(text: textoSelecionado),
      readOnly: true,
      enabled: !busy && _lotesList.isNotEmpty,
      onTap: busy || _lotesList.isEmpty ? null : _abrirSeletorDetalhe,
      style: _dropdownTextStyle,
      decoration: InputDecoration(
        labelText: _temPreto ? 'Cor / Lote *' : 'Detalhe *',
        prefixIcon: const Icon(Icons.palette_rounded),
        suffixIcon: const Icon(Icons.search_rounded),
        hintText: _lotesList.isEmpty
            ? 'Nenhum lote encontrado'
            : 'Clique para filtrar e selecionar',
        border: const OutlineInputBorder(),
        labelStyle: const TextStyle(color: Color(0xFFB45309)),
      ),
    );
  }

  Widget _buildTipoCaixaAssistidoField(bool busy) {
    final podeUsarPadrao =
        !_tiposCaixaFixos.contains(_tipoBaseArticle) &&
        (_caixaPMetros > 0 || _caixaGMetros > 0);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_rounded, color: Color(0xFFCBD5E1)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tipo de caixa',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _tipoCaixaController.text.isEmpty
                      ? 'Selecione P/G ou informe metros'
                      : _tipoCaixaController.text,
                  overflow: TextOverflow.ellipsis,
                  style: _dropdownTextStyle,
                ),
              ],
            ),
          ),
          if (podeUsarPadrao) ...[
            const SizedBox(width: 8),
            _TipoCaixaQuickButton(
              label: 'P',
              value: _caixaPMetros,
              selected: _tipoCaixaController.text == 'P',
              enabled: !busy && _caixaPMetros > 0,
              onTap: () => _aplicarMetrosPorTipoCaixa('P'),
            ),
            const SizedBox(width: 6),
            _TipoCaixaQuickButton(
              label: 'G',
              value: _caixaGMetros,
              selected: _tipoCaixaController.text == 'G',
              enabled: !busy && _caixaGMetros > 0,
              onTap: () => _aplicarMetrosPorTipoCaixa('G'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool numeric = false,
    bool caps = false,
    bool enabled = true,
    bool highlight = false,
    ValueChanged<String>? onChanged,
    VoidCallback? onSubmit,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      style: const TextStyle(
        color: Color(0xFFF8FAFC),
        fontWeight: FontWeight.w600,
      ),
      cursorColor: const Color(0xFF60A5FA),
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))]
          : null,
      textCapitalization: caps
          ? TextCapitalization.characters
          : TextCapitalization.none,
      onChanged: onChanged,
      onSubmitted: onSubmit != null ? (_) => onSubmit() : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
        border: const OutlineInputBorder(),
        labelStyle: highlight
            ? const TextStyle(color: Color(0xFFB45309))
            : null,
      ),
    );
  }

  // ── Preview etiqueta caixa ────────────────────────────────────

  Widget _buildCaixaPreview() {
    final previewData = _etiquetaCaixa ?? _artigoInfo!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE4EE)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = _previewWidth(constraints.maxWidth, 520);
          return Center(
            child: SizedBox(
              width: width,
              height: width * (325 / 520),
              child: CustomPaint(
                painter: _EtiquetaCaixaPainter(data: previewData),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB91C1C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _erro!,
              style: const TextStyle(
                color: Color(0xFF7F1D1D),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrPreview() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE4EE)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = _previewWidth(constraints.maxWidth, 500);
          return Center(
            child: SizedBox(
              width: width,
              height: width * (350 / 500),
              child: CustomPaint(
                painter: _EtiquetaPaletePainter(data: _qrPalete!),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildItemsTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE4EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Text(
              'Conteúdo do palete',
              style: TextStyle(
                color: Color(0xFF0A2540),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Divider(height: 1),
          ..._itens.map(_buildItemRow),
        ],
      ),
    );
  }

  Widget _buildItemRow(PaleteEmbalagemItemEntry item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.descricao.isEmpty
                      ? 'SKU ${item.codSku}'
                      : item.descricao,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'SKU ${item.codSku} · Detalhe ${item.detalhe}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _Pill(
            label: 'Saldo',
            value:
                '${item.qtAlocada == item.qtAlocada.roundToDouble() ? item.qtAlocada.toStringAsFixed(0) : item.qtAlocada.toStringAsFixed(2)} m',
          ),
          const SizedBox(width: 8),
          _Pill(label: 'P', value: item.qtCaixaP.toString()),
          const SizedBox(width: 8),
          _Pill(label: 'G', value: item.qtCaixaG.toString()),
          const SizedBox(width: 8),
          _Pill(label: 'Enf.', value: item.qtEnfestado.toString()),
          const SizedBox(width: 8),
          _Pill(label: 'Enfr.', value: item.qtEnfraldado.toString()),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Toggle chip — Pedido Especial
// ──────────────────────────────────────────────────────────────

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: value ? const Color(0xFF2563EB) : const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: value ? const Color(0xFF60A5FA) : const Color(0xFF334155),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? () => onChanged(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value ? Icons.star_rounded : Icons.star_border_rounded,
                size: 17,
                color: value ? Colors.white : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: value ? Colors.white : const Color(0xFFCBD5E1),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Pill
// ──────────────────────────────────────────────────────────────

class _TipoCaixaQuickButton extends StatelessWidget {
  const _TipoCaixaQuickButton({
    required this.label,
    required this.value,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final int value;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: value > 0 ? 'Preencher $value metros' : 'Sem padrao cadastrado',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: enabled ? onTap : null,
        child: Container(
          width: 42,
          height: 36,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2563EB) : const Color(0xFF111C33),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? const Color(0xFF60A5FA)
                  : const Color(0xFF334155),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.white : const Color(0xFF64748B),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 74),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Etiqueta Palete painter
// ──────────────────────────────────────────────────────────────

class _DarkTag extends StatelessWidget {
  const _DarkTag({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF111C33),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF60A5FA), size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

}

class _DarkMetricPill extends StatelessWidget {
  const _DarkMetricPill({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 118),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF60A5FA), size: 16),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF8FAFC),
                    fontSize: 13,
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
}

class _EtiquetaPaletePainter extends CustomPainter {
  _EtiquetaPaletePainter({required this.data});

  final String data;
  final Barcode _barcode = Barcode.qrCode();

  static const double _w = 800;
  static const double _h = 560;
  static const Rect _qr = Rect.fromLTWH(190, 30, 420, 420);
  static const double _textY = 455;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / _w;
    canvas.save();
    canvas.scale(s);
    canvas.drawRect(Rect.fromLTWH(0, 0, _w, _h), Paint()..color = Colors.white);

    for (final e in _barcode.make(
      data,
      width: _qr.width,
      height: _qr.height,
      drawText: false,
    )) {
      if (e is BarcodeBar && e.black) {
        canvas.drawRect(
          Rect.fromLTWH(_qr.left + e.left, _qr.top + e.top, e.width, e.height),
          Paint()..color = Colors.black,
        );
      }
    }

    (TextPainter(
      text: TextSpan(
        text: data,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 58,
          fontWeight: FontWeight.w900,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(minWidth: _w, maxWidth: _w)).paint(canvas, Offset(0, _textY));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EtiquetaPaletePainter old) => old.data != data;
}

// ──────────────────────────────────────────────────────────────
// Etiqueta Caixa painter
// ──────────────────────────────────────────────────────────────

class _EtiquetaCaixaPainter extends CustomPainter {
  _EtiquetaCaixaPainter({required this.data});

  final Map<String, dynamic> data;
  final Barcode _barcode = Barcode.qrCode();

  static const double _w = 640;
  static const double _h = 400;
  static const double _top = 120;
  static const Rect _qr = Rect.fromLTWH(448, 210, 135, 135);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / _w;
    canvas.save();
    canvas.scale(s);
    canvas.drawRect(Rect.fromLTWH(0, 0, _w, _h), Paint()..color = Colors.white);

    final lines = _lines();
    final yy = [0.0, 52.0, 98.0, 128.0, 156.0, 184.0, 212.0];
    final fs = [52.0, 40.0, 24.0, 22.0, 22.0, 20.0, 18.0];
    final fw = [
      FontWeight.w900,
      FontWeight.w900,
      FontWeight.w800,
      FontWeight.w800,
      FontWeight.w800,
      FontWeight.w800,
      FontWeight.w700,
    ];

    final double mw = _qr.left - 18 - 12;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      var fontSize = fs[i];
      while (fontSize >= 12) {
        final tp = TextPainter(
          text: TextSpan(
            text: lines[i],
            style: TextStyle(
              color: Colors.black,
              fontSize: fontSize,
              fontWeight: fw[i],
              letterSpacing: 0,
            ),
          ),
          textAlign: TextAlign.left,
          textDirection: TextDirection.ltr,
        )..layout();
        if (tp.width <= mw) {
          tp.paint(canvas, Offset(18, _top + yy[i]));
          break;
        }
        fontSize -= 2;
      }
    }

    final qrData = _v(['QrCode', 'qr_code']);
    if (qrData.isNotEmpty) {
      for (final e in _barcode.make(
        qrData,
        width: _qr.width,
        height: _qr.height,
        drawText: false,
      )) {
        if (e is BarcodeBar && e.black) {
          canvas.drawRect(
            Rect.fromLTWH(
              _qr.left + e.left,
              _qr.top + e.top,
              e.width,
              e.height,
            ),
            Paint()..color = Colors.black,
          );
        }
      }
    }

    canvas.restore();
  }

  List<String> _lines() {
    final l230 = _v(['Linha230']);
    final l260 = _v(['Linha260']);
    final l300 = _v(['Linha300']);
    final lData = _v(['LinhaData']);

    final metros = l230.isNotEmpty ? l230 : _v(['Metros', 'metros']);
    final lote = l260.isNotEmpty ? l260 : _v(['Lote', 'lote']);
    final carretel = l300.isNotEmpty
        ? l300
        : () {
            final m = _v(['Metragem', 'metragem']);
            return m.isEmpty ? '' : 'Carretel: $m';
          }();
    final dataFab = lData.isNotEmpty
        ? lData
        : () {
            final d = _v(['DataFabricacao', 'data_fabricacao']);
            return d.isEmpty ? '' : 'Fabricação: $d';
          }();

    return [
      _v(['NmObj1', 'nm_obj1']),
      _v(['NmObj2', 'nm_obj2']),
      metros,
      lote,
      carretel,
      dataFab,
      _v(['Descricao', 'descricao']),
    ].map((l) => l.trim()).toList();
  }

  String _v(List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return '';
  }

  @override
  bool shouldRepaint(covariant _EtiquetaCaixaPainter old) => old.data != data;
}

// ──────────────────────────────────────────────────────────────
// Etiqueta Operador painter
// ──────────────────────────────────────────────────────────────

class _EtiquetaOperadorPainter extends CustomPainter {
  _EtiquetaOperadorPainter({required this.operador, required this.fonte});

  final int operador;
  final double fonte;

  static const double _w = 422;
  static const double _h = 116;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / _w;
    canvas.save();
    canvas.scale(s);
    canvas.drawRect(Rect.fromLTWH(0, 0, _w, _h), Paint()..color = Colors.white);
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
    );
    const centersX = [70.0, 211.0, 352.0];
    final text = operador.toString();

    for (final centerX in centersX) {
      var fontSize = (fonte * 0.48).clamp(18.0, 48.0);
      while (fontSize >= 14) {
        textPainter.text = TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.black,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        );
        textPainter.layout();
        if (textPainter.width <= 118) {
          break;
        }
        fontSize -= 2;
      }
      textPainter.paint(canvas, Offset(centerX - (textPainter.width / 2), 38));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EtiquetaOperadorPainter old) =>
      old.operador != operador || old.fonte != fonte;
}

class _FioLivrePreviewPainter extends CustomPainter {
  const _FioLivrePreviewPainter({
    required this.titulo,
    required this.cor,
    required this.peso,
    required this.lote,
    required this.codigo,
  });

  final String titulo;
  final String cor;
  final String peso;
  final String lote;
  final String codigo;

  @override
  void paint(Canvas canvas, Size size) {
    final digits = codigo.replaceAll(RegExp(r'\D'), '');
    final black = Paint()..color = Colors.black;
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
    );

    void drawText(String value, double y) {
      textPainter.text = TextSpan(
        text: value,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      );
      textPainter.textAlign = TextAlign.left;
      textPainter.layout(maxWidth: size.width * 0.52);
      textPainter.paint(canvas, Offset(size.width * 0.09, y));
    }

    drawText(titulo, size.height * 0.36);
    drawText('Cor: $cor', size.height * 0.47);
    drawText('Peso Liquido: $peso', size.height * 0.58);
    drawText('Lote: $lote', size.height * 0.69);

    final barcodeWidth = size.width * 0.34;
    final left = size.width * 0.55;
    final top = size.height * 0.73;
    final height = size.height * 0.2;
    final source = digits.isEmpty ? '7896714231266' : digits.padRight(13, '0');
    final unit = barcodeWidth / 95;
    var x = left;

    for (var i = 0; i < 95; i++) {
      final digit = int.parse(source[i % source.length]);
      final draw = i < 3 ||
          (i >= 45 && i < 50) ||
          i >= 92 ||
          ((digit + i) % 3 != 0);
      if (draw) {
        final barHeight = (i < 3 || (i >= 45 && i < 50) || i >= 92)
            ? height + 10
            : height;
        canvas.drawRect(
          Rect.fromLTWH(x, top, math.max(1.4, unit * 0.9), barHeight),
          black,
        );
      }
      x += unit;
    }

    textPainter.text = TextSpan(
      text: _formatarPreviewEan13(digits),
      style: const TextStyle(
        color: Colors.black,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.8,
      ),
    );
    textPainter.textAlign = TextAlign.center;
    textPainter.layout(maxWidth: size.width);
    textPainter.paint(
      canvas,
      Offset(left + ((barcodeWidth - textPainter.width) / 2), top + height + 2),
    );
  }

  static String _formatarPreviewEan13(String value) {
    if (value.length != 13) return value;
    return '${value.substring(0, 1)} ${value.substring(1, 7)} ${value.substring(7)}';
  }

  @override
  bool shouldRepaint(covariant _FioLivrePreviewPainter old) =>
      old.titulo != titulo ||
      old.cor != cor ||
      old.peso != peso ||
      old.lote != lote ||
      old.codigo != codigo;
}
