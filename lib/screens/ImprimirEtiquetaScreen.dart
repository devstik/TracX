import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart';

import 'ApontamentoProdutividadeScreen.dart' as produtividade;
import '../services/alocacao_service.dart';
import '../services/datawedge_service.dart';
import '../services/etiquetas_service.dart';
import '../services/zebra_printer_service.dart';

enum _EtiquetaModelo { palete, caixa, operador, produtividade }

const _appBg = Color(0xFF050A14);
const _appSurface = Color(0xFF0B1220);
const _appSurfaceAlt = Color(0xFF101B34);
const _appAccent = Color(0xFF4DA3FF);
const _appMint = Color(0xFF5EF7C5);
const _appBorder = Color(0x22FFFFFF);

class _OperadorEtiqueta {
  final String codigo;
  final String nome;

  const _OperadorEtiqueta({required this.codigo, required this.nome});

  factory _OperadorEtiqueta.fromJson(Map<String, dynamic> json) {
    return _OperadorEtiqueta(
      codigo: (json['CdUser'] ?? json['cdUser'] ?? json['codigo'] ?? '')
          .toString()
          .trim(),
      nome: (json['NmUser'] ?? json['nmUser'] ?? json['nome'] ?? '')
          .toString()
          .trim(),
    );
  }

  String get label => nome.isEmpty ? codigo : '$codigo - $nome';
}

class EtiquetasPage extends StatefulWidget {
  final int grupoId;

  const EtiquetasPage({super.key, required this.grupoId});

  @override
  State<EtiquetasPage> createState() => _EtiquetasPageState();
}

class _EtiquetasPageState extends State<EtiquetasPage> {
  // ── Palete ───────────────────────────────────────────────────
  final TextEditingController _paleteController = TextEditingController();

  // ── Caixa — busca por nome/código ────────────────────────────
  final TextEditingController _buscaController = TextEditingController();
  final FocusNode _buscaFocus = FocusNode();
  int _cdObjSelecionado = 0;
  List<Map<String, dynamic>> _buscaOpcoes = [];
  bool _buscandoOpcoes = false;
  bool _settingBuscaText = false;
  bool _aguardandoQrColetor = false;
  Timer? _buscaDebounce;
  Timer? _qrDigitadoDebounce;

  // ── Caixa — dropdown de detalhe/lote ────────────────────────
  List<Map<String, dynamic>> _lotesList = [];
  int _detalheSelecionado = 0;
  bool _carregandoLotes = false;
  String _filtroDetalhe = '';

  // ── Caixa — dados da etiqueta ────────────────────────────────
  final TextEditingController _metrosController = TextEditingController();
  final TextEditingController _ordemController = TextEditingController();
  final TextEditingController _detalheController = TextEditingController();
  final TextEditingController _loteController = TextEditingController();
  final TextEditingController _operadorController = TextEditingController();
  String? _operadorCaixaSelecionado;
  final TextEditingController _qtdeController =
      TextEditingController(text: '1');

  // ── Caixa — readonly ─────────────────────────────────────────
  final TextEditingController _tipoCaixaController = TextEditingController();

  // ── Caixa — tipo base do artigo (ENFE | ENFR | D | P | G | '')
  String _tipoBaseArticle = '';

  // ── Caixa — toggles ──────────────────────────────────────────
  bool _pedidoEspecial = false;
  bool _loteInline = false;

  // ── Operador ─────────────────────────────────────────────────
  final TextEditingController _etiquetaOpController = TextEditingController();
  final TextEditingController _opQtdeController =
      TextEditingController(text: '1');
  bool _imprimindoOp = false;
  int _opPreview = 0;
  String? _operadorEtiquetaSelecionado;
  List<_OperadorEtiqueta> _operadores = [];
  bool _carregandoOperadores = false;
  String _produtividadeTipo = 'A';

  final AlocacaoService _alocacaoService = AlocacaoService();
  final ZebraPrinterService _zebraPrinterService = ZebraPrinterService();
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

  @override
  void initState() {
    super.initState();
    DataWedgeService.init();
    DataWedgeService.scanData.addListener(_onQrColetor);
    _carregarImpressora();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focarBuscaArtigoCaixa(ativarColetor: true);
    });
  }

  Future<void> _carregarImpressora() async {
    final lista = await EtiquetasService.buscarImpressoras();
    if (!mounted || lista.isEmpty) return;
    final p = lista.first;
    setState(() {
      _printerIp = (p['ip'] as String?) ?? _printerIp;
      _printerPort = (p['porta'] as int?) ?? _printerPort;
    });
  }

  @override
  void dispose() {
    _buscaDebounce?.cancel();
    _qrDigitadoDebounce?.cancel();
    DataWedgeService.scanData.removeListener(_onQrColetor);
    _paleteController.dispose();
    _buscaController.dispose();
    _buscaFocus.dispose();
    _metrosController.dispose();
    _ordemController.dispose();
    _detalheController.dispose();
    _loteController.dispose();
    _operadorController.dispose();
    _qtdeController.dispose();
    _tipoCaixaController.dispose();
    _etiquetaOpController.dispose();
    _opQtdeController.dispose();
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
    final palete =
        (_paleteConsultado ?? _paleteController.text).trim().toUpperCase();
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
    _qrDigitadoDebounce?.cancel();

    final q = value.trim();
    if (_pareceQrArtigo(q)) {
      _qrDigitadoDebounce = Timer(const Duration(milliseconds: 250), () {
        if (mounted) _processarEntradaArtigo(q);
      });
      return;
    }

    // Se tinha item selecionado e o usuário editou o campo, limpa tudo
    if (_cdObjSelecionado > 0) {
      setState(() {
        _cdObjSelecionado = 0;
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
        _filtroDetalhe = '';
        _buscaOpcoes = [];
      });
    }

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

  void _limparArtigoCaixa() {
    _buscaDebounce?.cancel();
    _qrDigitadoDebounce?.cancel();
    _settingBuscaText = true;
    _buscaController.clear();
    _settingBuscaText = false;
    _ordemController.clear();
    _detalheController.clear();
    _loteController.clear();
    _tipoCaixaController.clear();
    setState(() {
      _cdObjSelecionado = 0;
      _buscaOpcoes = [];
      _artigoInfo = null;
      _etiquetaCaixa = null;
      _tipoBaseArticle = '';
      _naoImprimeLoteLinha = false;
      _detalheObrigatorio = false;
      _temPreto = false;
      _loteInline = false;
      _lotesList = [];
      _detalheSelecionado = 0;
      _filtroDetalhe = '';
      _aguardandoQrColetor = false;
      _erro = null;
    });
    _focarBuscaArtigoCaixa(ativarColetor: true);
  }

  void _selecionarArtigo(Map<String, dynamic> artigo) {
    final cdObj = artigo['CdObj'] as int;
    final nmObj = (artigo['NmObj'] ?? '').toString().trim();
    _settingBuscaText = true;
    _buscaController.text = '$cdObj — $nmObj';
    _settingBuscaText = false;
    setState(() {
      _cdObjSelecionado = cdObj;
      _buscaOpcoes = [];
    });
    _buscarArtigo();
  }

  void _onQrColetor() {
    final codigo = DataWedgeService.scanData.value;
    final podeLer =
        _modelo == _EtiquetaModelo.caixa &&
        (_aguardandoQrColetor || _buscaFocus.hasFocus);
    if (!podeLer || codigo == null || codigo.trim().isEmpty) {
      return;
    }
    setState(() => _aguardandoQrColetor = false);
    _processarQrArtigo(codigo);
  }

  Future<void> _abrirLeitorQrArtigo() async {
    final origem = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Ler QR Code do artigo',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: _appAccent),
              title: const Text(
                'Câmera do celular',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner_rounded,
                  color: _appAccent),
              title: const Text(
                'Bipe do coletor',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Ativa a próxima leitura do DataWedge',
                style: TextStyle(color: Colors.white60),
              ),
              onTap: () => Navigator.pop(ctx, 'coletor'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || origem == null) return;
    if (origem == 'camera') {
      final codigo = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => const produtividade.ScannerPage(
            modo: 'qr',
            titulo: 'Ler artigo',
            usarCameraFrontal: true,
          ),
        ),
      );
      if (codigo != null && codigo.trim().isNotEmpty) {
        await _processarQrArtigo(codigo);
      }
      return;
    }

    DataWedgeService.scanData.value = null;
    setState(() => _aguardandoQrColetor = true);
    _focarBuscaArtigoCaixa();
    _showSnackBar('Bipe o QR Code do artigo no coletor.', isError: false);
  }

  void _focarBuscaArtigoCaixa({bool ativarColetor = false}) {
    if (!mounted || _modelo != _EtiquetaModelo.caixa) return;
    if (ativarColetor) {
      setState(() => _aguardandoQrColetor = true);
    }
    _buscaFocus.requestFocus();
    Future.microtask(
      () => SystemChannels.textInput.invokeMethod('TextInput.hide'),
    );
  }

  bool _pareceQrArtigo(String value) => value.startsWith('{');

  Future<void> _processarEntradaArtigo(String value) async {
    final texto = value.trim();
    if (texto.isEmpty) return;
    if (_pareceQrArtigo(texto)) {
      await _processarQrArtigo(texto);
      return;
    }
    if (_cdObjSelecionado > 0) {
      await _buscarArtigo();
    } else if (_buscaOpcoes.isNotEmpty) {
      _selecionarArtigo(_buscaOpcoes.first);
    } else {
      final code = int.tryParse(texto) ?? 0;
      if (code > 0) {
        setState(() => _cdObjSelecionado = code);
        await _buscarArtigo();
      }
    }
  }

  Future<void> _processarQrArtigo(String codigo) async {
    try {
      final decoded = jsonDecode(codigo.trim());
      if (decoded is! Map) throw const FormatException();

      var cdObj = _asInt(decoded['CdObj'] ?? decoded['cd_obj']);
      final detalhe = _asInt(decoded['Detalhe'] ?? decoded['detalhe']);
      final ordem = (decoded['Ordem'] ?? decoded['ordem'] ?? '')
          .toString()
          .trim();
      final artigoNome = (decoded['Artigo'] ?? decoded['artigo'] ?? '')
          .toString()
          .trim();
      final cor = (decoded['Cor'] ?? decoded['cor'] ?? '').toString().trim();
      final artigoNomeCompleto = [artigoNome, cor]
          .where((parte) => parte.isNotEmpty)
          .join(' ');

      Map<String, dynamic>? artigo;
      if (cdObj <= 0 && artigoNomeCompleto.isNotEmpty) {
        artigo = await _buscarArtigoQrPorNome(artigoNomeCompleto);
        cdObj = _asInt(artigo['CdObj']);
      } else if (cdObj > 0 && artigoNomeCompleto.isNotEmpty) {
        artigo = {'CdObj': cdObj, 'NmObj': artigoNomeCompleto};
      }
      if (cdObj <= 0) throw const FormatException();

      _settingBuscaText = true;
      _buscaController.text = artigo == null
          ? cdObj.toString()
          : '$cdObj — ${(artigo['NmObj'] ?? artigoNomeCompleto).toString().trim()}';
      _settingBuscaText = false;
      setState(() {
        _cdObjSelecionado = cdObj;
        _buscaOpcoes = [];
        _detalheSelecionado = detalhe;
        _detalheController.text = detalhe > 0 ? detalhe.toString() : '';
        if (ordem.isNotEmpty) _ordemController.text = ordem;
      });

      await _buscarArtigo();
      if (!mounted) return;
      if (detalhe > 0) {
        _selecionarDetalhe(detalhe);
      }
    } on FormatException {
      _showSnackBar('QR Code sem artigo válido.', isError: true);
    } catch (e) {
      _showSnackBar(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<Map<String, dynamic>> _buscarArtigoQrPorNome(String nome) async {
    var opcoes = await EtiquetasService.buscarArtigosPorNome(nome);
    if (opcoes.isEmpty) {
      opcoes = await _buscarArtigoQrNoCatalogoCompleto(nome);
    }
    if (opcoes.isEmpty) {
      throw Exception('Artigo "$nome" não encontrado.');
    }

    final alvo = _normalizarTextoQr(nome);
    final exatas = opcoes.where((artigo) {
      final candidato = _normalizarTextoQr(_nomeArtigoResultado(artigo));
      return candidato == alvo || candidato.endsWith(' $alvo');
    }).toList();

    if (exatas.length == 1) return exatas.first;
    if (exatas.isEmpty && opcoes.length == 1) return opcoes.first;
    if (exatas.isEmpty) {
      final parciais = opcoes.where((artigo) {
        final candidato = _normalizarTextoQr(_nomeArtigoResultado(artigo));
        return candidato.contains(alvo) || alvo.contains(candidato);
      }).toList();
      if (parciais.length == 1) return parciais.first;
    }
    if (exatas.isEmpty) {
      throw Exception('Nenhuma correspondência exata para o artigo "$nome".');
    }
    throw Exception('Mais de um artigo corresponde ao nome "$nome".');
  }

  String _normalizarTextoQr(String value) {
    return _removerAcentos(value)
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _removerAcentos(String value) {
    return value
        .replaceAll(RegExp(r'[\u00C0-\u00C5\u00E0-\u00E5]'), 'A')
        .replaceAll(RegExp(r'[\u00C8-\u00CB\u00E8-\u00EB]'), 'E')
        .replaceAll(RegExp(r'[\u00CC-\u00CF\u00EC-\u00EF]'), 'I')
        .replaceAll(RegExp(r'[\u00D2-\u00D6\u00D8\u00F2-\u00F6\u00F8]'), 'O')
        .replaceAll(RegExp(r'[\u00D9-\u00DC\u00F9-\u00FC]'), 'U')
        .replaceAll(RegExp(r'[\u00C7\u00E7]'), 'C')
        .replaceAll(RegExp(r'[\u00D1\u00F1]'), 'N');
  }

  String _nomeArtigoResultado(Map<String, dynamic> artigo) {
    return (artigo['NmObj'] ??
            artigo['nmObj'] ??
            artigo['nm_obj'] ??
            artigo['Artigo'] ??
            artigo['artigo'] ??
            artigo['Objeto'] ??
            artigo['objeto'] ??
            '')
        .toString()
        .trim();
  }

  Future<List<Map<String, dynamic>>> _buscarArtigoQrNoCatalogoCompleto(
    String nome,
  ) async {
    final alvo = _normalizarTextoQr(nome);
    if (alvo.isEmpty) return [];

    final todos = await EtiquetasService.listarTodosArtigos();
    return todos.where((artigo) {
      final codigo = (artigo['CdObj'] ?? '').toString().trim();
      final candidato = _normalizarTextoQr(_nomeArtigoResultado(artigo));
      return codigo.isNotEmpty &&
          candidato.isNotEmpty &&
          (candidato == alvo ||
              candidato.endsWith(' $alvo') ||
              candidato.contains(alvo) ||
              alvo.contains(candidato));
    }).toList();
  }

  String _formatarTextoArtigo(int cdObj, Map<String, dynamic> artigo) {
    final nmObj =
        (artigo['NmObj'] ??
                artigo['nm_obj'] ??
                artigo['Artigo'] ??
                artigo['artigo'] ??
                artigo['Objeto'] ??
                artigo['objeto'] ??
                artigo['nome'] ??
                '')
            .toString()
            .trim();
    return nmObj.isEmpty ? cdObj.toString() : '$cdObj - $nmObj';
  }

  // ────────────────────────────────────────────────────────────
  // Caixa — Etapa 1: Busca do artigo (info + lotes)
  // ────────────────────────────────────────────────────────────

  Future<void> _buscarArtigo() async {
    final cdObj = _cdObjSelecionado > 0
        ? _cdObjSelecionado
        : int.tryParse(_buscaController.text.trim()) ?? 0;

    if (cdObj <= 0) {
      _showSnackBar('Selecione um artigo da lista ou informe o código.',
          isError: true);
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
      _filtroDetalhe = '';
    });
    try {
      final data = await EtiquetasService.buscarArtigoInfo(cdObj);
      if (!mounted) return;

      final temPreto = data['TemPreto'] == true;
      final detalheObrig = data['DetalheObrigatorio'] == true;

      final tipoBase = (data['TipoCaixa'] ?? '').toString().trim();
      setState(() {
        _settingBuscaText = true;
        _buscaController.text = _formatarTextoArtigo(cdObj, data);
        _settingBuscaText = false;
        _artigoInfo = data;
        _tipoBaseArticle = tipoBase;
        // Tipos fixos preenchem imediatamente; P/G dependem dos metros
        _tipoCaixaController.text =
            const ['ENFE', 'ENFR', 'D'].contains(tipoBase) ? tipoBase : '';
        _detalheObrigatorio = detalheObrig;
        _temPreto = temPreto;
        _naoImprimeLoteLinha = data['NaoImprimeLoteLinha'] == true;
        _consultandoBusca = false;
      });
      // Recalcula tipo de caixa caso metros já esteja preenchido
      _atualizarTipoCaixa();

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
    if (const ['ENFE', 'ENFR', 'D'].contains(_tipoBaseArticle)) return;
    final metros = int.tryParse(_metrosController.text.trim()) ?? 0;
    _tipoCaixaController.text =
        metros > 0 ? (metros <= 1200 ? 'P' : 'G') : '';
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _carregarLotes(int cdObj) async {
    setState(() => _carregandoLotes = true);
    try {
      final lotes = await EtiquetasService.buscarArtigoLotes(cdObj);
      if (!mounted) return;
      final normalizados = lotes
          .map((lot) => {...lot, 'CdLot': _asInt(lot['CdLot'])})
          .where((lot) => (lot['CdLot'] as int) > 0)
          .toList();
      setState(() {
        _lotesList = normalizados;
        _carregandoLotes = false;
        _filtroDetalhe = '';
        if (normalizados.length == 1) {
          _detalheSelecionado = normalizados.first['CdLot'] as int;
          if (_temPreto) {
            final nm = (normalizados.first['NmLot'] ?? '').toString().trim();
            if (nm.isNotEmpty) _loteController.text = nm;
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lotesList = [];
        _detalheSelecionado = 0;
        _filtroDetalhe = '';
        _carregandoLotes = false;
      });
    }
  }

  void _selecionarDetalhe(int? cdLot) {
    if (cdLot == null) return;
    final lot = _lotesList.firstWhere(
      (l) => l['CdLot'] == cdLot,
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

  List<Map<String, dynamic>> get _lotesFiltrados {
    final filtro = _filtroDetalhe.trim().toLowerCase();
    if (filtro.isEmpty) return _lotesList;
    return _lotesList.where((lot) {
      final cdLot = _asInt(lot['CdLot']).toString();
      final nmLot = (lot['NmLot'] ?? '').toString().trim().toLowerCase();
      return cdLot.startsWith(filtro) || nmLot.startsWith(filtro);
    }).toList();
  }

  // ────────────────────────────────────────────────────────────
  // Caixa — Etapa 2: Imprimir (valida + v2 + imprime)
  // ────────────────────────────────────────────────────────────

  Future<void> _imprimirCaixa() async {
    final cdObj = _cdObjSelecionado;
    final metros = _metrosController.text.trim();
    final nrOrdem = _ordemController.text.trim();
    final detalhe =
        _usaDropdownDetalhe ? _detalheSelecionado : (int.tryParse(_detalheController.text.trim()) ?? 0);
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
      _showSnackBar(
          'Nº da ordem não informado — será registrado como 0.',
          isError: true);
      // Não bloqueia — imprime com ordem = 0 no JSON
    }
    if (_detalheObrigatorio && detalhe <= 0) {
      _showSnackBar('Selecione o Detalhe — obrigatório para este artigo.',
          isError: true);
      return;
    }
    if (_temPreto && detalhe <= 0) {
      _showSnackBar('Artigo PRETO: selecione o Detalhe (Cor / Lote).',
          isError: true);
      return;
    }
    if (_temPreto && lote.isEmpty) {
      _showSnackBar('Artigo PRETO: preencha o campo Lote.', isError: true);
      return;
    }

    setState(() {
      _imprimindo = true;
      _erro = null;
    });
    try {
      final operadorCodigo = _codigoOperador(
        _operadorController,
        _operadorCaixaSelecionado,
      );
      final data = await EtiquetasService.buscarEtiquetaCaixaV2(
        cdObj: cdObj,
        metros: metros,
        nrOrdem: nrOrdem,
        detalhe: detalhe,
        lote: lote,
        operador: operadorCodigo,
        pedidoEspecial: _pedidoEspecial,
        qtdeImp: int.tryParse(_qtdeController.text.trim()) ?? 1,
        loteInline: _loteInline,
      );

      if (!mounted) return;

      final naoImprime = data['NaoImprimeLoteLinha'] == true;

      if (naoImprime && lote.isNotEmpty && !_loteInline) {
        final nmObj = (data['NmObj'] ?? '').toString();
        final querInline = await _perguntarLoteInline(nmObj);
        if (!mounted) return;
        if (querInline) {
          setState(() {
            _loteInline = true;
            _imprimindo = false;
          });
          await _imprimirCaixa();
          return;
        }
      }

      setState(() {
        _etiquetaCaixa = data;
        _naoImprimeLoteLinha = naoImprime;
      });

      await _zebraPrinterService.imprimirEtiquetaCaixa(
        dados: data,
        ip: _printerIp,
        port: _printerPort,
      );
      if (!mounted) return;
      setState(() => _imprimindo = false);
      _showSnackBar('Comando de impressão enviado.', isError: false);
      _resetarCaixa();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
        _imprimindo = false;
      });
    }
  }

  void _resetarCaixa() {
    _buscaDebounce?.cancel();
    _qrDigitadoDebounce?.cancel();
    _settingBuscaText = true;
    _buscaController.clear();
    _settingBuscaText = false;
    _metrosController.clear();
    _ordemController.clear();
    _detalheController.clear();
    _loteController.clear();
    _operadorController.clear();
    _qtdeController.text = '1';
    _tipoCaixaController.clear();
    setState(() {
      _cdObjSelecionado = 0;
      _buscaOpcoes = [];
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
      _filtroDetalhe = '';
      _operadorCaixaSelecionado = null;
      _erro = null;
    });
    _focarBuscaArtigoCaixa(ativarColetor: true);
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
    final op = _codigoOperador(
      _etiquetaOpController,
      _operadorEtiquetaSelecionado,
    );
    if (op <= 0) {
      _showSnackBar('Informe o número do operador.', isError: true);
      return;
    }
    final qtde = (int.tryParse(_opQtdeController.text.trim()) ?? 1).clamp(1, 99);
    setState(() {
      _imprimindoOp = true;
      _opPreview = op;
      _erro = null;
    });
    try {
      await _zebraPrinterService.imprimirEtiquetaOperador(
        operador: op,
        quantidade: qtde,
        ip: _printerIp,
        port: _printerPort,
      );
      if (!mounted) return;
      setState(() => _imprimindoOp = false);
      _showSnackBar('Comando de impressão enviado.', isError: false);
      _etiquetaOpController.clear();
      _opQtdeController.text = '1';
      setState(() {
        _operadorEtiquetaSelecionado = null;
        _opPreview = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _imprimindoOp = false;
      });
    }
  }

  void _selecionarModelo(_EtiquetaModelo modelo) {
    if (_modelo == modelo) return;
    setState(() {
      _modelo = modelo;
      _erro = null;
    });
    if (modelo == _EtiquetaModelo.caixa) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focarBuscaArtigoCaixa(ativarColetor: true);
      });
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? const Color(0xFFB91C1C) : const Color(0xFF047857),
      ),
    );
  }

  int _codigoOperador(
    TextEditingController controller,
    String? codigoSelecionado,
  ) {
    final selecionado = int.tryParse((codigoSelecionado ?? '').trim());
    if (selecionado != null && selecionado > 0) return selecionado;
    final texto = controller.text.trim();
    final match = RegExp(r'^\d+').firstMatch(texto);
    return int.tryParse(match?.group(0) ?? texto) ?? 0;
  }

  String _normalizarCodigoOperador(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final asInt = int.tryParse(trimmed);
    if (asInt != null) return asInt.toString();
    return trimmed;
  }

  String _extrairCodigoOperadorQr(String leitura) {
    final texto = leitura.trim();
    if (texto.isEmpty) return '';

    try {
      final decoded = jsonDecode(texto);
      if (decoded is Map) {
        final valor = _valorOperadorNoQr(decoded);
        final codigo = _normalizarCodigoOperador(valor?.toString() ?? '');
        if (codigo.isNotEmpty) return codigo;
      }
    } catch (_) {
      // Continua tentando extrair de leituras parciais ou texto puro.
    }

    final matchJson = RegExp(
      r'"operador"\s*:\s*"?([^",}\s]+)"?',
      caseSensitive: false,
    ).firstMatch(texto);
    if (matchJson != null) {
      return _normalizarCodigoOperador(matchJson.group(1) ?? '');
    }

    return _normalizarCodigoOperador(texto);
  }

  dynamic _valorOperadorNoQr(Map<dynamic, dynamic> decoded) {
    const chavesAceitas = {
      'operador',
      'cduser',
      'codigo',
      'id',
    };

    for (final entry in decoded.entries) {
      final chave = entry.key
          .toString()
          .trim()
          .toLowerCase()
          .replaceAll('_', '');
      if (chavesAceitas.contains(chave)) return entry.value;
    }
    return null;
  }

  _OperadorEtiqueta? _buscarOperadorPorCodigo(String codigo) {
    final alvo = _normalizarCodigoOperador(codigo);
    if (alvo.isEmpty) return null;

    for (final operador in _operadores) {
      if (_normalizarCodigoOperador(operador.codigo) == alvo) {
        return operador;
      }
    }
    return null;
  }

  List<_OperadorEtiqueta> _ordenarOperadores(List<_OperadorEtiqueta> operadores) {
    final ordenados = List<_OperadorEtiqueta>.from(operadores);
    ordenados.sort((a, b) => a.nome.toUpperCase().compareTo(b.nome.toUpperCase()));
    return ordenados;
  }

  Future<void> _carregarOperadores() async {
    if (_carregandoOperadores || _operadores.isNotEmpty) return;
    setState(() => _carregandoOperadores = true);
    try {
      final data = await EtiquetasService.buscarOperadores();
      if (!mounted) return;
      final operadores = data
          .map(_OperadorEtiqueta.fromJson)
          .where((op) => op.codigo.isNotEmpty)
          .toList();
      setState(() => _operadores = _ordenarOperadores(operadores));
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _carregandoOperadores = false);
    }
  }

  Future<void> _selecionarOperador({
    required TextEditingController controller,
    required ValueChanged<String?> onSelecionado,
  }) async {
    await _carregarOperadores();
    if (!mounted) return;
    if (_operadores.isEmpty) {
      _showSnackBar('Nenhum operador encontrado.', isError: true);
      return;
    }

    final selecionado = await showModalBottomSheet<_OperadorEtiqueta>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String filtro = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final termo = filtro.trim().toUpperCase();
            final filtrados = _operadores.where((op) {
              if (termo.isEmpty) return true;
              return op.codigo.toUpperCase().contains(termo) ||
                  op.nome.toUpperCase().contains(termo);
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
                    const Text(
                      'Selecionar operador',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        autofocus: true,
                        style: const TextStyle(color: Colors.white),
                        onChanged: (value) => setModalState(() => filtro = value),
                        decoration: _fieldDecoration(
                          label: 'Buscar operador',
                          hint: 'Digite codigo ou nome',
                          icon: Icons.search_rounded,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtrados.isEmpty
                          ? const Center(
                              child: Text(
                                'Nenhum operador encontrado',
                                style: TextStyle(color: Colors.white60),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtrados.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1, color: Colors.white12),
                              itemBuilder: (_, index) {
                                final operador = filtrados[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        _appAccent.withValues(alpha: 0.16),
                                    child: const Icon(
                                      Icons.badge_rounded,
                                      color: _appAccent,
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(
                                    operador.nome.isEmpty
                                        ? operador.codigo
                                        : operador.nome,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Codigo ${operador.codigo}',
                                    style: const TextStyle(color: Colors.white60),
                                  ),
                                  onTap: () => Navigator.of(ctx).pop(operador),
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
    setState(() {
      controller.text = selecionado.label;
      onSelecionado(selecionado.codigo);
    });
  }

  Future<void> _lerQrOperador({
    required TextEditingController controller,
    required ValueChanged<String?> onSelecionado,
  }) async {
    final leitura = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const produtividade.ScannerPage(
          modo: 'qr',
          titulo: 'Ler operador',
          usarCameraFrontal: true,
        ),
      ),
    );
    if (!mounted || leitura == null || leitura.trim().isEmpty) return;

    await _carregarOperadores();
    if (!mounted) return;

    final codigo = _extrairCodigoOperadorQr(leitura);
    if (codigo.isEmpty) {
      _showSnackBar('QR Code sem operador valido.', isError: true);
      return;
    }

    final operador = _buscarOperadorPorCodigo(codigo);
    if (operador == null) {
      _showSnackBar('Operador $codigo nao encontrado.', isError: true);
      return;
    }

    setState(() {
      controller.text = operador.label;
      onSelecionado(operador.codigo);
    });
    _showSnackBar('Operador preenchido automaticamente.', isError: false);
  }

  // ────────────────────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final horizontalPadding = size.width < 520 ? 16.0 : 28.0;

    return Scaffold(
      backgroundColor: _appBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            18,
            horizontalPadding,
            28,
          ),
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
                  if (_modelo == _EtiquetaModelo.palete)
                    _buildPaletePanel()
                  else if (_modelo == _EtiquetaModelo.caixa)
                    _buildCaixaPanel()
                  else if (_modelo == _EtiquetaModelo.operador)
                    _buildOperadorPanel(),
                  if (_modelo == _EtiquetaModelo.produtividade)
                    _buildProdutividadePanel(),
                  const SizedBox(height: 18),
                  if (_erro != null) _buildError(),
                  if (_modelo == _EtiquetaModelo.palete &&
                      _qrPalete != null) ...[
                    _buildQrPreview(),
                    const SizedBox(height: 18),
                  ],
                  if (_modelo == _EtiquetaModelo.palete && _itens.isNotEmpty)
                    _buildItemsTable(),
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
            gradient: const LinearGradient(colors: [_appAccent, _appMint]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.print_rounded, color: Colors.black, size: 28),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Text(
            'Etiquetas',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
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
        color: _appSurfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _appBorder),
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
            modelo: _EtiquetaModelo.operador,
            icon: Icons.badge_rounded,
            label: 'Operador',
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
          color: selected ? _appAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  )
                ]
              : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _selecionarModelo(modelo),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    color: selected ? Colors.black : Colors.white60),
                const SizedBox(height: 6),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                       color: selected ? Colors.black : Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Palete ────────────────────────────────────────────────────

  Widget _buildPaletePanel() {
    final busy = _consultando || _imprimindo;
    return _panel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final buttonWidth = compact
              ? (constraints.maxWidth - 12) / 2
              : (constraints.maxWidth - 24) * 0.24;
          final fieldWidth = compact
              ? constraints.maxWidth
              : constraints.maxWidth - 24 - (buttonWidth * 2);

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: fieldWidth,
                child: TextField(
                  controller: _paleteController,
                  enabled: !busy,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _consultar(),
                  decoration: _fieldDecoration(
                    label: 'Endereco do palete',
                    hint: 'PA-L1-R100-D-P1',
                    icon: Icons.qr_code_2_rounded,
                  ),
                ),
              ),
              SizedBox(
                width: buttonWidth,
                height: 56,
                child: OutlinedButton.icon(
                  style: _outlineButtonStyle(),
                  onPressed: busy ? null : _mostrarQrCode,
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('QR Code'),
                ),
              ),
              SizedBox(
                width: buttonWidth,
                height: 56,
                child: FilledButton.icon(
                  style: _primaryButtonStyle(),
                  onPressed: busy ? null : _imprimir,
                  icon: _imprimindo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.print_rounded),
                  label: const Text('Imprimir'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Caixa ─────────────────────────────────────────────────────

  Widget _buildCaixaPanel() {
    final busy = _consultandoBusca || _imprimindo;

    void buscarSelecionado() {
      if (_cdObjSelecionado > 0) {
        _buscarArtigo();
        return;
      }
      final code = int.tryParse(_buscaController.text.trim()) ?? 0;
      if (code > 0) {
        setState(() => _cdObjSelecionado = code);
        _buscarArtigo();
      } else {
        _showSnackBar(
          'Selecione um artigo da lista ou informe o codigo.',
          isError: true,
        );
      }
    }

    return _panel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final compact = maxWidth < 620;
          final half = compact ? maxWidth : (maxWidth - 12) / 2;
          final third = compact ? maxWidth : (maxWidth - 24) / 3;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionLabel('Buscar artigo'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: compact ? maxWidth : maxWidth - 174,
                    child: TextField(
                      controller: _buscaController,
                      focusNode: _buscaFocus,
                      enabled: !busy,
                      style: const TextStyle(color: Colors.white),
                      onChanged: _onBuscaChanged,
                      onSubmitted: _processarEntradaArtigo,
                      decoration: _fieldDecoration(
                        label: 'Artigo - nome ou codigo *',
                        hint: 'Digite o nome ou codigo...',
                        icon: Icons.search_rounded,
                        suffix: _buscandoOpcoes
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _appAccent,
                                  ),
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_buscaController.text.isNotEmpty)
                                    IconButton(
                                      tooltip: 'Limpar artigo',
                                      onPressed:
                                          busy ? null : _limparArtigoCaixa,
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  IconButton(
                                    tooltip: 'Ler QR Code do artigo',
                                    onPressed:
                                        busy ? null : _abrirLeitorQrArtigo,
                                    icon: Icon(
                                      _aguardandoQrColetor
                                          ? Icons.qr_code_scanner_rounded
                                          : Icons.qr_code_2_rounded,
                                      color: _aguardandoQrColetor
                                          ? _appMint
                                          : _appAccent,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: compact ? maxWidth : 162,
                    height: 56,
                    child: FilledButton.icon(
                      style: _primaryButtonStyle(),
                      onPressed: busy ? null : buscarSelecionado,
                      icon: _consultandoBusca
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.search_rounded),
                      label: const Text('Buscar'),
                    ),
                  ),
                  SizedBox(
                    width: maxWidth,
                    child: TextField(
                      controller: _tipoCaixaController,
                      readOnly: true,
                      enabled: false,
                      style: const TextStyle(color: Colors.white70),
                      decoration: _fieldDecoration(
                        label: 'Tipo de caixa',
                        hint: '',
                        icon: Icons.inventory_2_rounded,
                      ),
                    ),
                  ),
                ],
              ),
              if (_buscaOpcoes.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                    color: _appSurfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _appBorder),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _buscaOpcoes.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Colors.white12),
                    itemBuilder: (context, i) {
                      final artigo = _buscaOpcoes[i];
                      final cdObj = artigo['CdObj'].toString();
                      final nmObj = (artigo['NmObj'] ?? '').toString().trim();
                      return InkWell(
                        onTap: () => _selecionarArtigo(artigo),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
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
                                  color: _appAccent.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  cdObj,
                                  style: const TextStyle(
                                    color: _appAccent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  nmObj,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
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
              const SizedBox(height: 22),
              const Divider(height: 1, color: Colors.white12),
              const SizedBox(height: 22),
              _sectionLabel('Dados da etiqueta'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: third,
                    child: _campo(
                      controller: _metrosController,
                      label: 'Metros *',
                      hint: '3000',
                      icon: Icons.straighten_rounded,
                      numeric: true,
                      enabled: !busy,
                      onChanged: (_) => _atualizarTipoCaixa(),
                    ),
                  ),
                  SizedBox(
                    width: third,
                    child: _campo(
                      controller: _ordemController,
                      label: 'Numero da ordem',
                      hint: '123456',
                      icon: Icons.tag_rounded,
                      numeric: true,
                      enabled: !busy,
                    ),
                  ),
                  SizedBox(width: third, child: _buildDetalheField(busy)),
                  SizedBox(
                    width: half,
                    child: _campo(
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
                                color: _appAccent,
                                size: 18,
                              ),
                            )
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: compact ? maxWidth : (maxWidth - 24) * 0.32,
                    child: _operadorLookupField(
                      controller: _operadorController,
                      label: 'Operador',
                      enabled: !busy,
                      codigoSelecionado: _operadorCaixaSelecionado,
                      onSelecionado: (codigo) =>
                          _operadorCaixaSelecionado = codigo,
                    ),
                  ),
                  SizedBox(
                    width: compact ? maxWidth : 120,
                    child: _campo(
                      controller: _qtdeController,
                      label: 'Qtde',
                      hint: '1',
                      icon: Icons.numbers_rounded,
                      numeric: true,
                      enabled: !busy,
                    ),
                  ),
                  SizedBox(
                    width: compact ? maxWidth : 220,
                    height: 56,
                    child: _ToggleChip(
                      label: 'Pedido Especial',
                      value: _pedidoEspecial,
                      enabled: !busy,
                      onChanged: (v) => setState(() => _pedidoEspecial = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  style: _primaryButtonStyle(),
                  onPressed: busy || _artigoInfo == null ? null : _imprimirCaixa,
                  icon: _imprimindo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.print_rounded),
                  label: const Text('Imprimir'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
  Widget _buildOperadorPanel() {
    final busy = _imprimindoOp;
    return _panel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final fieldWidth = compact ? constraints.maxWidth : constraints.maxWidth - 144;
          final qtdeWidth = compact ? constraints.maxWidth : 132.0;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: _operadorLookupField(
                      controller: _etiquetaOpController,
                      label: 'Numero do operador *',
                      enabled: !busy,
                      codigoSelecionado: _operadorEtiquetaSelecionado,
                      onSelecionado: (codigo) =>
                          _operadorEtiquetaSelecionado = codigo,
                    ),
                  ),
                  SizedBox(
                    width: qtdeWidth,
                    child: _campo(
                      controller: _opQtdeController,
                      label: 'Qtde',
                      hint: '1',
                      icon: Icons.numbers_rounded,
                      numeric: true,
                      enabled: !busy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  style: _primaryButtonStyle(),
                  onPressed: busy ? null : _imprimirOperador,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.print_rounded),
                  label: const Text('Imprimir'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProdutividadePanel() {
    final hora = DateTime.now().hour;
    final turno = hora >= 6 && hora < 14
        ? 8
        : hora >= 14 && hora < 22
        ? 9
        : 10;
    final turnoLetra = turno == 8
        ? 'A'
        : turno == 9
        ? 'B'
        : 'C';

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.factory_rounded, color: _appAccent, size: 42),
          const SizedBox(height: 12),
          const Text(
            'Apontamento de produtividade',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Informe operador, setor, máquina, artigo, detalhe e quantidade.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'A', label: Text('Tipo A')),
              ButtonSegment(value: 'B', label: Text('Tipo B')),
            ],
            selected: {_produtividadeTipo},
            onSelectionChanged: (selecionado) {
              setState(() => _produtividadeTipo = selecionado.first);
            },
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 760,
            child: produtividade.FormularioGeral(
              key: ValueKey(_produtividadeTipo),
              tipo: _produtividadeTipo,
              turno: turno,
              turnoLetra: turnoLetra,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              style: _primaryButtonStyle(),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const produtividade.ProducaoTabsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Abrir produtividade em tela cheia'),
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
      child: Center(
        child: SizedBox(
          width: 520,
          height: 143,
          child: CustomPaint(
            painter: _EtiquetaOperadorPainter(operador: _opPreview),
          ),
        ),
      ),
    );
  }

  /// Detalhe: dropdown para PRETO/personalizados, campo de texto nos demais.
  Widget _buildDetalheField(bool busy) {
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

      final lotesFiltrados = _lotesFiltrados;
      final selecionadoVisivel = lotesFiltrados.any(
        (lot) => _asInt(lot['CdLot']) == _detalheSelecionado,
      );
      final mostrarFiltro = _temPreto || _lotesList.length > 8;

      final dropdown = DropdownButtonFormField<int>(
        initialValue: selecionadoVisivel && _detalheSelecionado > 0
            ? _detalheSelecionado
            : null,
        isExpanded: true,
        dropdownColor: _appSurfaceAlt,
        style: const TextStyle(color: Colors.white),
        decoration: _fieldDecoration(
          label: _temPreto ? 'Cor / Lote *' : 'Detalhe *',
          hint: '',
          icon: Icons.palette_rounded,
          highlight: true,
        ),
        hint: Text(
          _lotesList.isEmpty
              ? 'Nenhum lote encontrado'
              : lotesFiltrados.isEmpty
                  ? 'Nenhum detalhe para esse filtro'
                  : 'Selecione...',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54),
        ),
        items: lotesFiltrados.map((lot) {
          final cdLot = _asInt(lot['CdLot']);
          final nmLot = (lot['NmLot'] ?? '').toString().trim();
          return DropdownMenuItem<int>(
            value: cdLot,
            child: Text(
              nmLot.isNotEmpty ? '$cdLot - $nmLot' : cdLot.toString(),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
          );
        }).toList(),
        onChanged: busy || lotesFiltrados.isEmpty ? null : _selecionarDetalhe,
      );

      if (!mostrarFiltro) return dropdown;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            enabled: !busy && _lotesList.isNotEmpty,
            style: const TextStyle(color: Colors.white),
            onChanged: (value) => setState(() => _filtroDetalhe = value),
            decoration: _fieldDecoration(
              label: 'Filtrar detalhe',
              hint: 'Digite o inicio do codigo ou nome',
              icon: Icons.filter_alt_rounded,
            ),
          ),
          const SizedBox(height: 10),
          dropdown,
        ],
      );
    }

    return _campo(
      controller: _detalheController,
      label: 'Detalhe (auto)',
      hint: '',
      icon: Icons.palette_rounded,
      numeric: true,
      enabled: !busy,
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _appSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _appBorder),
      ),
      child: child,
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required IconData icon,
    bool highlight = false,
    Widget? suffix,
  }) {
    final borderColor = highlight ? _appMint : Colors.white24;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: _appSurfaceAlt,
      prefixIcon: Icon(icon, color: highlight ? _appMint : Colors.white70),
      suffixIcon: suffix,
      labelStyle: TextStyle(
        color: highlight ? _appMint : Colors.white70,
        fontWeight: FontWeight.w700,
      ),
      floatingLabelStyle: TextStyle(
        color: highlight ? _appMint : _appAccent,
        fontWeight: FontWeight.w800,
      ),
      hintStyle: const TextStyle(color: Colors.white38),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: borderColor),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _appAccent, width: 1.6),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  ButtonStyle _primaryButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: _appAccent,
      foregroundColor: Colors.black,
      disabledBackgroundColor: Colors.white10,
      disabledForegroundColor: Colors.white38,
      textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  ButtonStyle _outlineButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: _appAccent,
      side: const BorderSide(color: _appAccent),
      textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
      style: const TextStyle(color: Colors.white),
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))]
          : null,
      textCapitalization:
          caps ? TextCapitalization.characters : TextCapitalization.none,
      onChanged: onChanged,
      onSubmitted: onSubmit != null ? (_) => onSubmit() : null,
      decoration: _fieldDecoration(
        label: label,
        hint: hint,
        icon: icon,
        highlight: highlight,
        suffix: suffix,
      ),
    );
  }

  Widget _operadorLookupField({
    required TextEditingController controller,
    required String label,
    required bool enabled,
    required String? codigoSelecionado,
    required ValueChanged<String?> onSelecionado,
  }) {
    final selecionado = (codigoSelecionado ?? '').trim().isNotEmpty;
    return TextField(
      controller: controller,
      readOnly: true,
      enabled: enabled,
      style: const TextStyle(color: Colors.white),
      onTap: enabled
          ? () => _selecionarOperador(
                controller: controller,
                onSelecionado: onSelecionado,
              )
          : null,
      decoration: _fieldDecoration(
        label: label,
        hint: _carregandoOperadores
            ? 'Carregando operadores...'
            : 'Toque para selecionar',
        icon: Icons.badge_rounded,
        suffix: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Ler QR Code do operador',
              icon: const Icon(
                Icons.qr_code_scanner_rounded,
                color: _appAccent,
              ),
              onPressed: enabled
                  ? () => _lerQrOperador(
                        controller: controller,
                        onSelecionado: onSelecionado,
                      )
                  : null,
            ),
            if (selecionado)
              IconButton(
                tooltip: 'Limpar operador',
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: enabled
                    ? () => setState(() {
                          controller.clear();
                          onSelecionado(null);
                        })
                    : null,
              )
            else
              const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70),
          ],
        ),
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
      child: Center(
        child: SizedBox(
          width: 520,
          height: 325,
          child: CustomPaint(painter: _EtiquetaCaixaPainter(data: previewData)),
        ),
      ),
    );
  }

  // ── Erros, QR, tabela palete ──────────────────────────────────

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
                  color: Color(0xFF7F1D1D), fontWeight: FontWeight.w600),
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
      child: Center(
        child: SizedBox(
          width: 500,
          height: 350,
          child:
              CustomPaint(painter: _EtiquetaPaletePainter(data: _qrPalete!)),
        ),
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
                  fontWeight: FontWeight.w800),
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
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'SKU ${item.codSku} · Detalhe ${item.detalhe}',
                  style: const TextStyle(
                      color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          _Pill(
              label: 'Saldo',
              value:
                  '${item.qtAlocada == item.qtAlocada.roundToDouble() ? item.qtAlocada.toStringAsFixed(0) : item.qtAlocada.toStringAsFixed(2)} m'),
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
        color: value ? _appAccent : _appSurfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: value ? _appAccent : Colors.white24,
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
                color: value ? Colors.black : Colors.white70,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: value ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.w800,
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
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 13,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Etiqueta Palete painter
// ──────────────────────────────────────────────────────────────

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
    canvas.drawRect(
        Rect.fromLTWH(0, 0, _w, _h), Paint()..color = Colors.white);

    for (final e in _barcode.make(data,
        width: _qr.width, height: _qr.height, drawText: false)) {
      if (e is BarcodeBar && e.black) {
        canvas.drawRect(
          Rect.fromLTWH(
              _qr.left + e.left, _qr.top + e.top, e.width, e.height),
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
              fontWeight: FontWeight.w900)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(minWidth: _w, maxWidth: _w))
        .paint(canvas, Offset(0, _textY));

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
    canvas.drawRect(
        Rect.fromLTWH(0, 0, _w, _h), Paint()..color = Colors.white);

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
      FontWeight.w700
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
                  letterSpacing: 0)),
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
      for (final e in _barcode.make(qrData,
          width: _qr.width, height: _qr.height, drawText: false)) {
        if (e is BarcodeBar && e.black) {
          canvas.drawRect(
            Rect.fromLTWH(
                _qr.left + e.left, _qr.top + e.top, e.width, e.height),
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
  _EtiquetaOperadorPainter({required this.operador});

  final int operador;
  final Barcode _barcode = Barcode.qrCode();

  static const double _w = 422;
  static const double _h = 116;
  static const double _qrSide = 63;
  static const List<Offset> _offsets = [
    Offset(34, 26),
    Offset(168, 26),
    Offset(325, 21),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / _w;
    canvas.save();
    canvas.scale(s);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, _w, _h), Paint()..color = Colors.white);

    final qrData = '{"operador":$operador}';
    final black = Paint()..color = Colors.black;

    for (final offset in _offsets) {
      for (final e in _barcode.make(qrData,
          width: _qrSide, height: _qrSide, drawText: false)) {
        if (e is BarcodeBar && e.black) {
          canvas.drawRect(
            Rect.fromLTWH(
                offset.dx + e.left, offset.dy + e.top, e.width, e.height),
            black,
          );
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EtiquetaOperadorPainter old) =>
      old.operador != operador;
}
