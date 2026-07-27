import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/checkin_tambores.dart';
import '../services/checkin_tambores_service.dart';
import 'qr_scanner_screen.dart';

class _TamborCheckinItem {
  const _TamborCheckinItem({
    this.id,
    required this.codigo,
    required this.ordem,
    required this.artigo,
    required this.volume,
    required this.lidoEm,
    this.quantidade = 1,
  });

  final String? id;
  final String codigo;
  final String ordem;
  final String artigo;
  final double volume;
  final DateTime lidoEm;
  final int quantidade;

  String get chaveGrupo => '$ordem|$artigo';

  _TamborCheckinItem somar(_TamborCheckinItem item) {
    return _TamborCheckinItem(
      id: id,
      codigo: codigo,
      ordem: ordem,
      artigo: artigo,
      volume: volume,
      lidoEm: item.lidoEm,
      quantidade: quantidade + item.quantidade,
    );
  }

  _TamborCheckinItem decrementar() {
    return _TamborCheckinItem(
      id: id,
      codigo: codigo,
      ordem: ordem,
      artigo: artigo,
      volume: volume,
      lidoEm: lidoEm,
      quantidade: quantidade > 1 ? quantidade - 1 : 0,
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      'codigo_tambor': codigo,
      'ordem_producao': ordem,
      'artigo': artigo,
      'volume': volume,
      'quantidade_tambores': quantidade,
    };
  }

  factory _TamborCheckinItem.fromApi(CheckinTamboresItem item) {
    return _TamborCheckinItem(
      id: item.id,
      codigo: item.codigoTambor,
      ordem: item.ordemProducao,
      artigo: item.artigo,
      volume: item.volume,
      lidoEm: item.bipadoEm,
      quantidade: item.quantidadeTambores,
    );
  }
}

class CheckinTamboresScreen extends StatefulWidget {
  const CheckinTamboresScreen({super.key});

  @override
  State<CheckinTamboresScreen> createState() => _CheckinTamboresScreenState();
}

class _CheckinTamboresScreenState extends State<CheckinTamboresScreen> {
  final _service = CheckinTamboresService();
  final _quantidadeController = TextEditingController();
  final _volumeController = TextEditingController();
  final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  final _timeFormat = DateFormat('HH:mm:ss');

  CheckinTambores? _registroAtual;
  final List<_TamborCheckinItem> _tamboresLidos = [];
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _atualizarTotaisLidos();
    _carregarDados();
  }

  @override
  void dispose() {
    _quantidadeController.dispose();
    _volumeController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    try {
      final aberto = await _service.buscarAberto();
      var itens = <CheckinTamboresItem>[];
      Object? erroItens;

      if (aberto != null) {
        try {
          itens = await _service.listarItens(aberto.id);
        } catch (e) {
          erroItens = e;
        }
      }

      if (!mounted) return;
      setState(() {
        _registroAtual = aberto;
        _tamboresLidos
          ..clear()
          ..addAll(itens.map(_TamborCheckinItem.fromApi));
        _atualizarTotaisLidos();
        _carregando = false;
      });
      _preencherCampos(aberto);
      if (erroItens != null) {
        _mostrarMensagem(_mensagemErro(erroItens), erro: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      _mostrarMensagem(_mensagemErro(e), erro: true);
    }
  }

  void _preencherCampos(CheckinTambores? registro) {
    if (registro == null) return;
    _quantidadeController.text = registro.quantidadeTambores.toString();
    _volumeController.text = _formatarVolume(registro.volumeTotal);
  }

  Future<void> _registrarInicial() async {
    final quantidade = _quantidadeTotalLida;
    final volume = _volumeTotalLido;

    if (quantidade <= 0) {
      _mostrarMensagem('Bipe pelo menos um tambor antes do check-in.', erro: true);
      return;
    }

    setState(() => _salvando = true);
    try {
      final registro = await _service.registrarInicial(
        quantidadeTambores: quantidade,
        volumeTotal: volume,
        itens: _tamboresLidos.map((item) => item.toApiJson()).toList(),
      );
      if (!mounted) return;
      setState(() {
        _registroAtual = registro;
        _salvando = false;
      });
      _mostrarMensagem('Check-in inicial registrado.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      _mostrarMensagem(_mensagemErro(e), erro: true);
    }
  }

  Future<void> _registrarFinal() async {
    final atual = _registroAtual;
    if (atual == null) {
      _mostrarMensagem('Faca o check-in inicial primeiro.', erro: true);
      return;
    }

    setState(() => _salvando = true);
    try {
      await _service.registrarFinal(atual);
      if (!mounted) return;
      setState(() {
        _registroAtual = null;
        _tamboresLidos.clear();
        _atualizarTotaisLidos();
        _salvando = false;
      });
      _mostrarMensagem('Check-in final registrado.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      _mostrarMensagem(_mensagemErro(e), erro: true);
    }
  }

  void _novoCheckin() {
    setState(() {
      _registroAtual = null;
      _tamboresLidos.clear();
      _atualizarTotaisLidos();
    });
  }

  double get _volumeTotalLido {
    return _tamboresLidos.fold<double>(
      0,
      (total, item) => total + item.volume,
    );
  }

  int get _quantidadeTotalLida {
    return _tamboresLidos.fold<int>(
      0,
      (total, item) => total + item.quantidade,
    );
  }

  void _atualizarTotaisLidos() {
    _quantidadeController.text = _quantidadeTotalLida.toString();
    _volumeController.text = _formatarVolume(_volumeTotalLido);
  }

  Future<void> _lerQrTambor() async {
    if (_registroAtual != null || _salvando) return;

    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (raw == null || raw.trim().isEmpty) return;

    _processarQrTambor(raw);
  }

  void _processarQrTambor(String rawQr) {
    final item = _parseTamborQr(rawQr);
    if (item == null) {
      _mostrarMensagem('QR Code do tambor invalido ou incompleto.', erro: true);
      return;
    }

    setState(() {
      final index = _tamboresLidos.indexWhere(
        (tambor) => tambor.chaveGrupo == item.chaveGrupo,
      );
      if (index >= 0) {
        _tamboresLidos[index] = _tamboresLidos[index].somar(item);
      } else {
        _tamboresLidos.add(item);
      }
      _atualizarTotaisLidos();
    });
    _mostrarMensagem('Tambor bipado: ${item.artigo}');
  }

  Future<void> _removerTambor(int index) async {
    if (_salvando || index < 0 || index >= _tamboresLidos.length) return;

    final registro = _registroAtual;
    final item = _tamboresLidos[index];

    if (registro == null) {
      setState(() {
        final atualizado = item.decrementar();
        if (atualizado.quantidade <= 0) {
          _tamboresLidos.removeAt(index);
        } else {
          _tamboresLidos[index] = atualizado;
        }
        _atualizarTotaisLidos();
      });
      _mostrarMensagem('Tambor removido da leitura.');
      return;
    }

    final idItem = item.id;
    if (idItem == null || idItem.isEmpty) {
      _mostrarMensagem('Item sem ID para remover no banco.', erro: true);
      return;
    }

    setState(() => _salvando = true);
    try {
      final atualizado = await _service.removerItem(
        idCheckin: registro.id,
        idItem: idItem,
      );
      if (!mounted) return;
      setState(() {
        _registroAtual = atualizado;
        _tamboresLidos.removeAt(index);
        _atualizarTotaisLidos();
        _salvando = false;
      });
      _mostrarMensagem('Tambor removido do check-in.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      _mostrarMensagem(_mensagemErro(e), erro: true);
    }
  }

  _TamborCheckinItem? _parseTamborQr(String rawQr) {
    try {
      final cleanedQr = _normalizarQrJson(rawQr);
      final decoded = jsonDecode(cleanedQr);
      if (decoded is! Map) return null;
      final data = Map<String, dynamic>.from(decoded);

      final ordem = _qrValue(data, const ['Ordem', 'NrOrdem', 'ordem']);
      final artigo = _qrValue(data, const ['Artigo', 'artigo']);
      final cor = _qrValue(data, const ['Cor', 'cor']);
      final volume = _volumeProgQr(data);

      if (ordem.isEmpty || artigo.isEmpty) return null;

      final artigoCompleto = cor.isEmpty ? artigo : '$artigo $cor';
      final codigo = _codigoTambor(ordem: ordem, artigo: artigoCompleto);

      return _TamborCheckinItem(
        codigo: codigo,
        ordem: ordem,
        artigo: artigoCompleto,
        volume: volume,
        lidoEm: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  String _normalizarQrJson(String rawQr) {
    var text = rawQr
        .replaceAll('\uFEFF', '')
        .replaceAll('\u0000', '')
        .replaceAll('\r', '')
        .trim();

    final firstBrace = text.indexOf('{');
    final lastBrace = text.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      text = text.substring(firstBrace, lastBrace + 1);
    }
    return text.trim();
  }

  String _qrValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  double _toDoubleQr(dynamic value) {
    if (value is num) return value.toDouble();
    var text = (value ?? '').toString().trim();
    if (text.isEmpty) return 0;

    text = text.replaceAll(RegExp(r'\s+'), '');
    final hasComma = text.contains(',');
    final hasDot = text.contains('.');

    if (hasComma && hasDot) {
      final lastComma = text.lastIndexOf(',');
      final lastDot = text.lastIndexOf('.');
      if (lastComma > lastDot) {
        text = text.replaceAll('.', '').replaceAll(',', '.');
      } else {
        text = text.replaceAll(',', '');
      }
    } else if (hasComma) {
      text = text.replaceAll(',', '.');
    }

    return double.tryParse(text) ?? 0;
  }

  double _volumeProgQr(Map<String, dynamic> data) {
    final rawVolume = data['VolumeProg'] ?? data['volumeProg'];
    final text = (rawVolume ?? '').toString().trim();

    if (RegExp(r'^\d{1,2}\.\d{3}$').hasMatch(text)) {
      return double.tryParse(text.replaceAll('.', '')) ?? 0;
    }

    return _toDoubleQr(rawVolume);
  }

  String _codigoTambor({
    required String ordem,
    required String artigo,
  }) {
    return 'OP:$ordem|ARTIGO:$artigo';
  }

  void _mostrarMensagem(String mensagem, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro
            ? const Color(0xFFB91C1C)
            : const Color(0xFF047857),
      ),
    );
  }

  String _mensagemErro(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  String _formatarData(DateTime? data) {
    if (data == null) return 'Pendente';
    return _dateFormat.format(data);
  }

  String _formatarVolume(double value) {
    final fixed = value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
    return fixed.replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final registro = _registroAtual;
    final bloqueado = registro != null || _salvando;

    return Scaffold(
      backgroundColor: const Color(0xFF050A14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050A14),
        foregroundColor: Colors.white,
        title: const Text('Check-in de Tambores'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StatusCard(registro: registro, formatarData: _formatarData),
                      const SizedBox(height: 16),
                      _FormularioCard(
                        quantidadeController: _quantidadeController,
                        volumeController: _volumeController,
                        bloqueado: bloqueado,
                        salvando: _salvando,
                        temRegistroAberto: registro != null,
                        tamboresLidos: _tamboresLidos,
                        formatarVolume: _formatarVolume,
                        formatarHora: (data) => _timeFormat.format(data),
                        onLerQr: _lerQrTambor,
                        onRemoverTambor: _removerTambor,
                        onInicial: _registrarInicial,
                        onFinal: _registrarFinal,
                        onNovo: _novoCheckin,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.registro,
    required this.formatarData,
  });

  final CheckinTambores? registro;
  final String Function(DateTime?) formatarData;

  @override
  Widget build(BuildContext context) {
    final aberto = registro != null;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                aberto ? Icons.local_shipping_rounded : Icons.inventory_2,
                color: aberto
                    ? const Color(0xFF5EF7C5)
                    : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  aberto ? 'Em andamento' : 'Nenhum check-in aberto',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (registro == null)
            const Text(
              'Bipe os tambores para registrar a retirada.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            )
          else ...[
            _ResumoLinha(label: 'Quantidade', value: '${registro!.quantidadeTambores} tambores'),
            _ResumoLinha(label: 'Volume total', value: registro!.volumeTotal.toString().replaceAll('.', ',')),
            _ResumoLinha(label: 'Check-in inicial', value: formatarData(registro!.checkinInicialEm)),
            _ResumoLinha(label: 'Check-in final', value: formatarData(registro!.checkinFinalEm)),
          ],
        ],
      ),
    );
  }
}

class _FormularioCard extends StatelessWidget {
  const _FormularioCard({
    required this.quantidadeController,
    required this.volumeController,
    required this.bloqueado,
    required this.salvando,
    required this.temRegistroAberto,
    required this.tamboresLidos,
    required this.formatarVolume,
    required this.formatarHora,
    required this.onLerQr,
    required this.onRemoverTambor,
    required this.onInicial,
    required this.onFinal,
    required this.onNovo,
  });

  final TextEditingController quantidadeController;
  final TextEditingController volumeController;
  final bool bloqueado;
  final bool salvando;
  final bool temRegistroAberto;
  final List<_TamborCheckinItem> tamboresLidos;
  final String Function(double) formatarVolume;
  final String Function(DateTime) formatarHora;
  final VoidCallback onLerQr;
  final ValueChanged<int> onRemoverTambor;
  final VoidCallback onInicial;
  final VoidCallback onFinal;
  final VoidCallback onNovo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: quantidadeController,
            enabled: false,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              label: 'Quantidade de tambores bipados',
              icon: Icons.numbers_rounded,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: volumeController,
            enabled: false,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              label: 'Volume total',
              icon: Icons.scale_rounded,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: bloqueado ? null : onLerQr,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Ler QR Code do tambor'),
          ),
          const SizedBox(height: 12),
          _TamboresBipadosList(
            tambores: tamboresLidos,
            formatarVolume: formatarVolume,
            formatarHora: formatarHora,
            podeRemover: !salvando,
            onRemover: onRemoverTambor,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: salvando || temRegistroAberto ? null : onInicial,
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Check-in inicial'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: salvando || !temRegistroAberto ? null : onFinal,
                  icon: const Icon(Icons.done_all_rounded),
                  label: const Text('Check-in final'),
                ),
              ),
            ],
          ),
          if (!temRegistroAberto && quantidadeController.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: salvando ? null : onNovo,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Novo check-in'),
            ),
          ],
        ],
      ),
    );
  }
}

class _TamboresBipadosList extends StatelessWidget {
  const _TamboresBipadosList({
    required this.tambores,
    required this.formatarVolume,
    required this.formatarHora,
    required this.podeRemover,
    required this.onRemover,
  });

  final List<_TamborCheckinItem> tambores;
  final String Function(double) formatarVolume;
  final String Function(DateTime) formatarHora;
  final bool podeRemover;
  final ValueChanged<int> onRemover;

  @override
  Widget build(BuildContext context) {
    if (tambores.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: const Text(
          'Nenhum tambor bipado ainda.',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.all(10),
        itemCount: tambores.length,
        separatorBuilder: (_, __) => const Divider(color: Colors.white10),
        itemBuilder: (context, index) {
          final tambor = tambores[index];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF1D4ED8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tambor.artigo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'OP ${tambor.ordem}  |  ${tambor.quantidade} tambor(es)  |  Volume ${formatarVolume(tambor.volume)}  |  ${formatarHora(tambor.lidoEm)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: podeRemover ? () => onRemover(index) : null,
                tooltip: 'Remover tambor',
                icon: const Icon(Icons.delete_outline_rounded),
                color: const Color(0xFFF87171),
                disabledColor: Colors.white24,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ResumoLinha extends StatelessWidget {
  const _ResumoLinha({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white60)),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: const Color(0xFF0B1220),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: Colors.white10),
  );
}

InputDecoration _inputDecoration({
  required String label,
  required IconData icon,
}) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFFCBD5E1)),
    prefixIcon: Icon(icon, color: const Color(0xFFCBD5E1)),
    filled: true,
    fillColor: const Color(0xFF0F172A),
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
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  );
}
