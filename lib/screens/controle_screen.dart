import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/controle_db_service.dart';
import '../services/etiquetas_service.dart';

class ControleScreen extends StatefulWidget {
  const ControleScreen({super.key});

  @override
  State<ControleScreen> createState() => _ControleScreenState();
}

class _ControleScreenState extends State<ControleScreen> {
  static const _bg = Color(0xFF020617);
  static const _surface = Color(0xFF172033);
  static const _field = Color(0xFF0F172A);
  static const _border = Color(0xFF334155);
  static const _gold = Color(0xFFD8B840);
  static const _success = Color(0xFF16A34A);
  static const _danger = Color(0xFFDC2626);

  final _db = ControleDbService.instance;
  final _filtroController = TextEditingController();
  final _mesFormat = DateFormat('yyyy-MM');
  final _dataBr = DateFormat('dd/MMM', 'pt_BR');
  final _numero = NumberFormat.decimalPattern('pt_BR');

  DateTime _mesSelecionado = DateTime(DateTime.now().year, DateTime.now().month);
  List<ControleGrupo> _grupos = [];
  Map<int, List<ControleLinha>> _linhasPorGrupo = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _filtroController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final mes = _mesFormat.format(_mesSelecionado);
    final grupos = await _db.listarGrupos(
      mesReferencia: mes,
      filtro: _filtroController.text,
    );
    final linhas = <int, List<ControleLinha>>{};
    for (final grupo in grupos) {
      final id = grupo.id;
      if (id != null) linhas[id] = await _db.listarLinhas(id);
    }
    if (!mounted) return;
    setState(() {
      _grupos = grupos;
      _linhasPorGrupo = linhas;
      _loading = false;
    });
  }

  Future<void> _selecionarMes() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _mesSelecionado,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
      locale: const Locale('pt', 'BR'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _gold,
            surface: _surface,
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (data == null) return;
    setState(() => _mesSelecionado = DateTime(data.year, data.month));
    await _carregar();
  }

  Future<void> _abrirGrupoDialog({ControleGrupo? grupo}) async {
    final tituloController = TextEditingController(text: grupo?.titulo ?? '');
    final valorController = TextEditingController(
      text: grupo == null || grupo.valorBase <= 0
          ? ''
          : _numero.format(grupo.valorBase),
    );

    final salvou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: _border),
        ),
        title: Text(
          grupo == null ? 'Novo controle' : 'Editar controle',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogField(
              controller: tituloController,
              label: 'Material / nome do controle',
              hint: 'Ex: ARTIGO - MAR 07',
            ),
            const SizedBox(height: 12),
            _dialogField(
              controller: valorController,
              label: 'Valor da coluna',
              hint: 'Ex: 150.000',
              numeric: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              final titulo = tituloController.text.trim();
              if (titulo.isEmpty) return;
              final now = DateTime.now().toIso8601String();
              await _db.salvarGrupo(
                ControleGrupo(
                  id: grupo?.id,
                  titulo: titulo,
                  valorBase: _parseNumero(valorController.text),
                  mesReferencia: _mesFormat.format(_mesSelecionado),
                  createdAt: grupo?.createdAt ?? now,
                  updatedAt: now,
                ),
              );
              if (context.mounted) Navigator.pop(context, true);
            },
            icon: const Icon(Icons.save_rounded),
            label: const Text('Salvar'),
          ),
        ],
      ),
    );

    tituloController.dispose();
    valorController.dispose();
    if (salvou == true) await _carregar();
  }

  Future<void> _abrirLinhaDialog(ControleGrupo grupo, {ControleLinha? linha}) async {
    final id = grupo.id;
    if (id == null) return;

    DateTime data = DateTime.tryParse(linha?.data ?? '') ?? _mesSelecionado;
    final artigoController = TextEditingController(text: linha?.artigo ?? '');
    final metrosController = TextEditingController(
      text: linha == null || linha.metrosEnviado <= 0
          ? ''
          : _numero.format(linha.metrosEnviado),
    );
    var cdObj = linha?.cdObj;
    var conferencia = linha?.conferencia ?? 'Não enviado ainda';

    final salvou = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _border),
          ),
          title: Text(
            linha == null ? 'Adicionar linha' : 'Editar linha',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: _border),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () async {
                    final selecionada = await showDatePicker(
                      context: context,
                      initialDate: data,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035, 12, 31),
                      locale: const Locale('pt', 'BR'),
                    );
                    if (selecionada != null) {
                      setDialogState(() => data = selecionada);
                    }
                  },
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(_dataBr.format(data)),
                ),
                const SizedBox(height: 12),
                _ControleArtigoAutocomplete(
                  controller: artigoController,
                  onSelected: (artigo) {
                    cdObj = _toInt(artigo['CdObj']);
                    artigoController.text =
                        (artigo['NmObj'] ?? artigo['nome'] ?? '').toString();
                  },
                ),
                const SizedBox(height: 12),
                _dialogField(
                  controller: metrosController,
                  label: 'Metros enviado',
                  hint: 'Ex: 10.000',
                  numeric: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: conferencia,
                  dropdownColor: _field,
                  decoration: _inputDecoration('Conferência'),
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 'OK', child: Text('OK')),
                    DropdownMenuItem(
                      value: 'Não enviado ainda',
                      child: Text('Não enviado ainda'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => conferencia = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
              ),
              onPressed: () async {
                final artigo = artigoController.text.trim();
                if (artigo.isEmpty) return;
                await _db.salvarLinha(
                  ControleLinha(
                    id: linha?.id,
                    grupoId: id,
                    data: DateTime(data.year, data.month, data.day)
                        .toIso8601String(),
                    artigo: artigo,
                    cdObj: cdObj,
                    metrosEnviado: _parseNumero(metrosController.text),
                    conferencia: conferencia,
                    createdAt: linha?.createdAt ?? DateTime.now().toIso8601String(),
                  ),
                );
                if (context.mounted) Navigator.pop(context, true);
              },
              icon: const Icon(Icons.save_rounded),
              label: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    artigoController.dispose();
    metrosController.dispose();
    if (salvou == true) await _carregar();
  }

  Future<void> _excluirGrupo(ControleGrupo grupo) async {
    final id = grupo.id;
    if (id == null) return;
    final confirmar = await _confirmar(
      'Excluir controle?',
      'Todas as linhas deste controle serão removidas.',
    );
    if (!confirmar) return;
    await _db.excluirGrupo(id);
    await _carregar();
  }

  Future<void> _excluirLinha(ControleLinha linha) async {
    final id = linha.id;
    if (id == null) return;
    final confirmar = await _confirmar('Excluir linha?', linha.artigo);
    if (!confirmar) return;
    await _db.excluirLinha(id, linha.grupoId);
    await _carregar();
  }

  Future<bool> _confirmar(String titulo, String conteudo) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: _surface,
            title: Text(titulo, style: const TextStyle(color: Colors.white)),
            content: Text(conteudo, style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _danger),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _exportarPdf() async {
    if (_grupos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum controle para exportar.')),
      );
      return;
    }

    final pdf = pw.Document();
    final mes = DateFormat('MMMM/yyyy', 'pt_BR').format(_mesSelecionado);
    final totalBase = _grupos.fold<double>(0, (sum, item) => sum + item.valorBase);
    final totalEnviado = _grupos.fold<double>(0, (sum, grupo) {
      final linhas = _linhasPorGrupo[grupo.id] ?? const <ControleLinha>[];
      return sum + linhas.fold<double>(0, (lineSum, item) => lineSum + item.metrosEnviado);
    });
    final saldoGeral = totalBase - totalEnviado;

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(22),
        ),
        header: (context) => _pdfHeader(mes),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          _pdfResumo(totalBase, totalEnviado, saldoGeral),
          pw.SizedBox(height: 14),
          for (final grupo in _grupos) ...[
            _pdfGrupo(grupo),
            pw.SizedBox(height: 16),
          ],
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'controle_${_mesFormat.format(_mesSelecionado)}.pdf',
    );
  }

  pw.Widget _pdfHeader(String mes) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.8),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Controle de Envio',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blueGrey900,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Referência: $mes',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ],
          ),
          pw.Text(
            DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfResumo(double totalBase, double totalEnviado, double saldoGeral) {
    pw.Widget card(String label, String value, PdfColor color) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label,
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.white),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return pw.Row(
      children: [
        card('Valor base', _numero.format(totalBase), PdfColors.blueGrey700),
        pw.SizedBox(width: 8),
        card('Metros enviados', _numero.format(totalEnviado), PdfColors.green700),
        pw.SizedBox(width: 8),
        card(
          'Saldo',
          _numero.format(saldoGeral),
          saldoGeral < 0 ? PdfColors.red700 : PdfColors.amber800,
        ),
      ],
    );
  }

  pw.Widget _pdfGrupo(ControleGrupo grupo) {
    final linhas = _linhasPorGrupo[grupo.id] ?? const <ControleLinha>[];
    final totalEnviado =
        linhas.fold<double>(0, (sum, item) => sum + item.metrosEnviado);
    final saldo = grupo.valorBase - totalEnviado;

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.black),
        children: [
          _pdfCell('DATA', header: true),
          _pdfCell(
            grupo.valorBase <= 0 ? '-' : _numero.format(grupo.valorBase),
            header: true,
          ),
          _pdfCell('METROS / ENVIADO', header: true),
          _pdfCell('CONFERÊNCIA', header: true),
        ],
      ),
      for (final linha in linhas)
        pw.TableRow(
          children: [
            _pdfCell(_formatarDataPdf(linha.data)),
            _pdfCell(linha.artigo),
            _pdfCell(_numero.format(linha.metrosEnviado), alignRight: true),
            _pdfCell(linha.conferencia),
          ],
        ),
      if (linhas.isEmpty)
        pw.TableRow(
          children: [
            _pdfCell('-'),
            _pdfCell('Sem linhas cadastradas'),
            _pdfCell('-'),
            _pdfCell('-'),
          ],
        ),
    ];

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.8),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey900,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(6),
                topRight: pw.Radius.circular(6),
              ),
            ),
            child: pw.Text(
              grupo.titulo,
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.2),
              1: pw.FlexColumnWidth(2.6),
              2: pw.FlexColumnWidth(1.8),
              3: pw.FlexColumnWidth(1.5),
            },
            children: rows,
          ),
          pw.Row(
            children: [
              pw.Expanded(flex: 1, child: pw.SizedBox()),
              pw.Expanded(
                flex: 3,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  alignment: pw.Alignment.center,
                  color: PdfColors.yellow,
                  child: pw.Text(
                    'TOTAL',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  alignment: pw.Alignment.centerRight,
                  color: saldo < 0 ? PdfColors.red300 : PdfColors.green400,
                  child: pw.Text(
                    _numero.format(saldo),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ),
              pw.Expanded(flex: 1, child: pw.SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfCell(
    String value, {
    bool header = false,
    bool alignRight = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: alignRight ? pw.Alignment.centerRight : pw.Alignment.center,
      child: pw.Text(
        value,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: header ? 8 : 9,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: header ? PdfColors.white : PdfColors.black,
        ),
      ),
    );
  }

  String _formatarDataPdf(String data) {
    final parsed = DateTime.tryParse(data);
    if (parsed == null) return data;
    return _dataBr.format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Controle',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Enviar PDF',
            onPressed: _loading || _grupos.isEmpty ? null : _exportarPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _gold,
        foregroundColor: Colors.black,
        onPressed: () => _abrirGrupoDialog(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo controle'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 90),
          children: [
            _buildFiltros(),
            const SizedBox(height: 14),
            if (_loading)
              const _ControleLoading()
            else if (_grupos.isEmpty)
              const _ControleEmpty()
            else
              ..._grupos.map(_buildGrupoCard),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltros() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 620;
          final filtro = _dialogField(
            controller: _filtroController,
            label: 'Filtrar controle',
            hint: 'Nome da coluna ou artigo',
            onChanged: (_) => _carregar(),
          );
          final mes = OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: _border),
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _selecionarMes,
            icon: const Icon(Icons.calendar_month_rounded, color: _gold),
            label: Text(DateFormat('MMMM/yyyy', 'pt_BR').format(_mesSelecionado)),
          );
          if (narrow) {
            return Column(children: [mes, const SizedBox(height: 10), filtro]);
          }
          return Row(
            children: [
              SizedBox(width: 220, child: mes),
              const SizedBox(width: 10),
              Expanded(child: filtro),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGrupoCard(ControleGrupo grupo) {
    final linhas = _linhasPorGrupo[grupo.id] ?? const <ControleLinha>[];
    final totalEnviado =
        linhas.fold<double>(0, (sum, item) => sum + item.metrosEnviado);
    final saldo = grupo.valorBase - totalEnviado;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    grupo.titulo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Adicionar linha',
                  onPressed: () => _abrirLinhaDialog(grupo),
                  icon: const Icon(Icons.add_circle_outline, color: _gold),
                ),
                IconButton(
                  tooltip: 'Editar controle',
                  onPressed: () => _abrirGrupoDialog(grupo: grupo),
                  icon: const Icon(Icons.edit_outlined, color: Colors.white70),
                ),
                IconButton(
                  tooltip: 'Excluir controle',
                  onPressed: () => _excluirGrupo(grupo),
                  icon: const Icon(Icons.delete_outline, color: _danger),
                ),
              ],
            ),
          ),
          _buildTabelaPlanilha(grupo, linhas, totalEnviado, saldo),
        ],
      ),
    );
  }

  Widget _buildTabelaPlanilha(
    ControleGrupo grupo,
    List<ControleLinha> linhas,
    double totalEnviado,
    double saldo,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth < 620 ? 620.0 : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                _buildTabelaHeader(grupo),
                if (linhas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(22),
                    child: Text(
                      'Nenhuma linha adicionada.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                else
                  ...linhas.map((linha) => _buildLinha(grupo, linha)),
                _buildTotalRow(totalEnviado, saldo),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabelaHeader(ControleGrupo grupo) {
    return Container(
      color: Colors.black,
      child: Row(
        children: [
          _cell('DATA', flex: 2, header: true),
          _cell(
            grupo.valorBase <= 0 ? '-' : _numero.format(grupo.valorBase),
            flex: 4,
            header: true,
          ),
          _cell('METROS / ENVIADO', flex: 3, header: true),
          _cell('CONFERÊNCIA', flex: 3, header: true),
        ],
      ),
    );
  }

  Widget _buildLinha(ControleGrupo grupo, ControleLinha linha) {
    final ok = linha.conferencia.toLowerCase() == 'ok';
    return InkWell(
      onTap: () => _abrirLinhaDialog(grupo, linha: linha),
      child: Row(
        children: [
          _cell(_dataBr.format(DateTime.parse(linha.data)), flex: 2),
          _cell(linha.artigo, flex: 4),
          _cell(_numero.format(linha.metrosEnviado), flex: 3, alignRight: true),
          Expanded(
            flex: 3,
            child: Container(
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black54, width: 0.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    ok ? Icons.check_circle_rounded : Icons.schedule_rounded,
                    size: 16,
                    color: ok ? _success : _gold,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      linha.conferencia,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Excluir linha',
                    onPressed: () => _excluirLinha(linha),
                    icon: const Icon(Icons.close_rounded, size: 16, color: _danger),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(double totalEnviado, double saldo) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 12),
      child: Row(
        children: [
          const Spacer(flex: 2),
          Expanded(
            flex: 4,
            child: Container(
              height: 40,
              alignment: Alignment.center,
              color: Colors.yellow,
              child: const Text(
                'TOTAL',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.centerRight,
              color: saldo < 0 ? _danger : const Color(0xFF00B050),
              child: Text(
                _numero.format(saldo),
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const Spacer(flex: 3),
        ],
      ),
    );
  }

  Widget _cell(
    String value, {
    required int flex,
    bool header = false,
    bool alignRight = false,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        height: header ? 34 : 38,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: alignRight ? Alignment.centerRight : Alignment.center,
        decoration: BoxDecoration(
          color: header ? Colors.black : Colors.white.withValues(alpha: 0.02),
          border: Border.all(color: Colors.black54, width: 0.5),
        ),
        child: Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: header ? Colors.white : Colors.white,
            fontWeight: header ? FontWeight.w900 : FontWeight.w700,
            fontSize: header ? 12 : 13,
          ),
        ),
      ),
    );
  }

  Widget _dialogField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool numeric = false,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      decoration: _inputDecoration(label).copyWith(hintText: hint),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60),
      hintStyle: const TextStyle(color: Colors.white30),
      filled: true,
      fillColor: _field,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _gold, width: 1.5),
      ),
    );
  }

  double _parseNumero(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return 0;
    final normalized = raw.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}

class _ControleArtigoAutocomplete extends StatefulWidget {
  const _ControleArtigoAutocomplete({
    required this.controller,
    required this.onSelected,
  });

  final TextEditingController controller;
  final ValueChanged<Map<String, dynamic>> onSelected;

  @override
  State<_ControleArtigoAutocomplete> createState() =>
      _ControleArtigoAutocompleteState();
}

class _ControleArtigoAutocompleteState
    extends State<_ControleArtigoAutocomplete> {
  Timer? _debounce;
  List<Map<String, dynamic>> _opcoes = [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _buscar(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (value.trim().length < 2) {
        if (mounted) setState(() => _opcoes = []);
        return;
      }
      setState(() => _loading = true);
      final opcoes = await EtiquetasService.buscarArtigosPorNome(value);
      if (!mounted) return;
      setState(() {
        _opcoes = opcoes.take(8).toList();
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: widget.controller,
          onChanged: _buscar,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            labelText: 'Artigo',
            hintText: 'Digite o artigo',
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.search_rounded, color: Colors.white54),
            labelStyle: const TextStyle(color: Colors.white60),
            hintStyle: const TextStyle(color: Colors.white30),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF334155)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD8B840)),
            ),
          ),
        ),
        if (_opcoes.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 210),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _opcoes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _opcoes[index];
                final cdObj = item['CdObj']?.toString() ?? '';
                final nmObj = (item['NmObj'] ?? '').toString();
                return ListTile(
                  dense: true,
                  title: Text(
                    nmObj,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    'Código $cdObj',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  onTap: () {
                    widget.controller.text = nmObj;
                    widget.onSelected(item);
                    setState(() => _opcoes = []);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ControleLoading extends StatelessWidget {
  const _ControleLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(30),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ControleEmpty extends StatelessWidget {
  const _ControleEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF172033),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: const Column(
        children: [
          Icon(Icons.table_chart_outlined, color: Color(0xFFD8B840), size: 34),
          SizedBox(height: 10),
          Text(
            'Nenhum controle neste mês.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 6),
          Text(
            'Clique em Novo controle para iniciar uma planilha vazia.',
            style: TextStyle(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
