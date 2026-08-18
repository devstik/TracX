import 'dart:async';

import 'package:flutter/material.dart';

import '../services/etiquetas_service.dart';
import '../services/zebra_printer_service.dart';

class StatusImpressorasScreen extends StatefulWidget {
  const StatusImpressorasScreen({super.key});

  @override
  State<StatusImpressorasScreen> createState() =>
      _StatusImpressorasScreenState();
}

class _PrinterStatus {
  const _PrinterStatus({
    required this.nome,
    required this.setor,
    required this.ip,
    required this.porta,
    required this.servidorOnline,
    required this.usbConectado,
    required this.tempoMs,
    required this.verificadoEm,
    this.statusUsb,
    this.portaUsb,
    this.erro,
  });

  final String nome;
  final String setor;
  final String ip;
  final int porta;
  final bool servidorOnline;
  final bool? usbConectado;
  final int? tempoMs;
  final DateTime verificadoEm;
  final String? statusUsb;
  final String? portaUsb;
  final String? erro;

  String get destino => '$ip:$porta';
  bool get usbInformado =>
      usbConectado != null ||
      (statusUsb?.trim().isNotEmpty ?? false) ||
      (portaUsb?.trim().isNotEmpty ?? false);
  bool get operacional => servidorOnline && usbConectado != false;
  bool get precisaValidarUsb => servidorOnline && !usbInformado;
  bool get usbDesconectado => servidorOnline && usbConectado == false;
}

class _StatusImpressorasScreenState extends State<StatusImpressorasScreen> {
  bool _carregando = true;
  String? _erro;
  DateTime? _ultimaVerificacao;
  List<_PrinterStatus> _status = const [];
  final Set<String> _testandoImpressoras = <String>{};

  @override
  void initState() {
    super.initState();
    _verificarImpressoras();
  }

  Future<void> _verificarImpressoras() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final impressoras = await EtiquetasService.buscarImpressoras();
      var nextZebraNumber = 3;
      final normalizadas = impressoras
          .map(
            (printer) => _normalizarImpressora(
              printer,
              nextZebraNumber: () => nextZebraNumber++,
            ),
          )
          .where((item) => item != null)
          .cast<Map<String, dynamic>>()
          .toList();

      final resultados = await Future.wait(
        normalizadas.map(_testarImpressora),
      );

      if (!mounted) return;
      setState(() {
        _status = resultados..sort(_compararStatus);
        _ultimaVerificacao = DateTime.now();
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
        _status = const [];
        _ultimaVerificacao = DateTime.now();
        _carregando = false;
      });
    }
  }

  Map<String, dynamic>? _normalizarImpressora(
    Map<String, dynamic> printer, {
    required int Function() nextZebraNumber,
  }) {
    final ipOriginal = (printer['ip'] ?? '').toString().trim();
    final ip = ipOriginal.split(':').first.trim();
    if (ip.isEmpty) return null;

    final portaOriginal = printer['porta'];
    final porta = portaOriginal is int
        ? portaOriginal
        : int.tryParse(portaOriginal?.toString() ?? '') ??
              int.tryParse(ipOriginal.split(':').skip(1).firstOrNull ?? '') ??
              ZebraPrinterService.defaultPort;

    final impressoraNomeSetor = _nomeSetorImpressora(
      ip,
      nextZebraNumber: nextZebraNumber,
    );
    return {
      'nome': impressoraNomeSetor.nome,
      'setor': impressoraNomeSetor.setor,
      'ip': ip,
      'porta': porta,
      'usbConectado': _extrairStatusUsb(printer),
      'statusUsb': _primeiroValor(printer, const [
        'status_usb',
        'usb_status',
        'statusUsb',
        'usbStatus',
        'printer_status',
        'printerStatus',
        'status',
      ]),
      'portaUsb': _primeiroValor(printer, const [
        'porta_usb',
        'usb_port',
        'portaUsb',
        'usbPort',
        'portaFisica',
        'port_name',
        'portName',
      ]),
    };
  }

  ({String nome, String setor}) _nomeSetorImpressora(
    String ip, {
    required int Function() nextZebraNumber,
  }) {
    return switch (ip) {
      '168.190.30.206' => (
        nome: 'EtqCaixa/Carretel 2',
        setor: 'Embalagem',
      ),
      '168.190.30.181' => (
        nome: 'EtqCaixa/Carretel',
        setor: 'Embalagem',
      ),
      '168.190.30.74' => (nome: 'Zebra 1', setor: 'Embalagem'),
      '168.190.30.172' || '168.190.31.22' => (
        nome: 'EtqManual',
        setor: 'Embalagem',
      ),
      _ => (
        nome: 'Zebra ${nextZebraNumber()}',
        setor: 'Expedicao/Semi-Acabado',
      ),
    };
  }

  bool? _extrairStatusUsb(Map<String, dynamic> printer) {
    for (final key in const [
      'usb_conectado',
      'usbConectado',
      'usb_connected',
      'usbConnected',
      'usb_online',
      'usbOnline',
      'impressora_conectada',
      'impressoraConectada',
      'printer_connected',
      'printerConnected',
      'conectada_usb',
      'conectadaUsb',
    ]) {
      final value = _boolFlexivel(printer[key]);
      if (value != null) return value;
    }

    for (final key in const [
      'status_usb',
      'usb_status',
      'statusUsb',
      'usbStatus',
      'printer_status',
      'printerStatus',
    ]) {
      final value = _boolFlexivel(printer[key]);
      if (value != null) return value;
    }

    return null;
  }

  String? _primeiroValor(Map<String, dynamic> printer, List<String> keys) {
    for (final key in keys) {
      final value = printer[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }
    return null;
  }

  bool? _boolFlexivel(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) {
      if (value == 1) return true;
      if (value == 0) return false;
    }

    final text = value
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('ã', 'a')
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');

    if (const {
      '1',
      'true',
      'sim',
      's',
      'yes',
      'y',
      'ok',
      'online',
      'conectado',
      'conectada',
      'connected',
      'ready',
      'pronta',
    }.contains(text)) {
      return true;
    }

    if (const {
      '0',
      'false',
      'nao',
      'n',
      'no',
      'offline',
      'desconectado',
      'desconectada',
      'disconnected',
      'erro',
      'error',
      'falha',
      'indisponivel',
    }.contains(text)) {
      return false;
    }

    return null;
  }

  Future<_PrinterStatus> _testarImpressora(Map<String, dynamic> printer) async {
    final nome = printer['nome'] as String;
    final setor = printer['setor'] as String;
    final ip = printer['ip'] as String;
    final porta = printer['porta'] as int;
    final usbInformadoEndpoint = printer['usbConectado'] as bool?;
    final statusEndpoint = printer['statusUsb'] as String?;
    final portaUsb = printer['portaUsb'] as String?;
    final zebraStatus = await ZebraPrinterService().consultarStatusRede(
      ip: ip,
      port: porta,
    );

    if (zebraStatus.servidorOnline) {
      final usbConectado = zebraStatus.usbConectado ?? usbInformadoEndpoint;
      final statusUsb =
          statusEndpoint ??
          zebraStatus.statusRaw ??
          (zebraStatus.impressoraRespondeu ? 'Impressora respondeu' : null);
      return _PrinterStatus(
        nome: nome,
        setor: setor,
        ip: ip,
        porta: porta,
        servidorOnline: zebraStatus.servidorOnline,
        usbConectado: usbConectado,
        statusUsb: statusUsb,
        portaUsb: portaUsb,
        tempoMs: zebraStatus.tempoMs,
        verificadoEm: DateTime.now(),
        erro: zebraStatus.usbConectado == false
            ? zebraStatus.erro
            : zebraStatus.usbConectado == null
            ? zebraStatus.erro
            : null,
      );
    }

    return _PrinterStatus(
      nome: nome,
      setor: setor,
      ip: ip,
      porta: porta,
      servidorOnline: false,
      usbConectado: usbInformadoEndpoint,
      statusUsb: statusEndpoint,
      portaUsb: portaUsb,
      tempoMs: null,
      verificadoEm: DateTime.now(),
      erro: zebraStatus.erro,
    );
  }

  int _compararStatus(_PrinterStatus a, _PrinterStatus b) {
    final setorCompare = a.setor.toLowerCase().compareTo(
      b.setor.toLowerCase(),
    );
    if (setorCompare != 0) return setorCompare;
    final criticidadeA = _criticidadeStatus(a);
    final criticidadeB = _criticidadeStatus(b);
    if (criticidadeA != criticidadeB) return criticidadeA - criticidadeB;
    return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
  }

  List<Widget> _buildStatusPorSetor() {
    final widgets = <Widget>[];
    String? setorAtual;

    for (final item in _status) {
      if (item.setor != setorAtual) {
        setorAtual = item.setor;
        widgets.add(_SetorHeader(setor: setorAtual));
      }
      widgets.add(
        _PrinterStatusCard(
          item,
          testando: _testandoImpressoras.contains(item.destino),
          onTestarImpressao: () => _enviarTesteImpressao(item),
        ),
      );
    }

    return widgets;
  }

  Future<void> _enviarTesteImpressao(_PrinterStatus status) async {
    final key = status.destino;
    if (_testandoImpressoras.contains(key)) return;

    setState(() => _testandoImpressoras.add(key));
    try {
      await ZebraPrinterService().imprimirTesteConexao(
        ip: status.ip,
        port: status.porta,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Teste enviado para ${status.nome}. Confirme se a etiqueta saiu.',
          ),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Falha no teste de ${status.nome}: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _testandoImpressoras.remove(key));
      }
    }
  }

  int _criticidadeStatus(_PrinterStatus status) {
    if (status.usbDesconectado) return 0;
    if (!status.servidorOnline) return 1;
    if (status.precisaValidarUsb) return 2;
    return 3;
  }

  String _formatarHora(DateTime? data) {
    if (data == null) return '-';
    final h = data.hour.toString().padLeft(2, '0');
    final m = data.minute.toString().padLeft(2, '0');
    final s = data.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final servidorOnline = _status.where((item) => item.servidorOnline).length;
    final usbOk = _status.where((item) => item.usbConectado == true).length;
    final alertas = _status
        .where((item) => item.usbDesconectado || item.precisaValidarUsb)
        .length;
    final offline = _status.length - servidorOnline;

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: const Color(0xFF020617),
        foregroundColor: Colors.white,
        title: const Text('Print Server'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregando ? null : _verificarImpressoras,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _verificarImpressoras,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            _ResumoStatus(
              total: _status.length,
              servidorOnline: servidorOnline,
              usbOk: usbOk,
              alertas: alertas,
              offline: offline,
              atualizando: _carregando,
              ultimaVerificacao: _formatarHora(_ultimaVerificacao),
            ),
            const SizedBox(height: 14),
            if (_carregando && _status.isEmpty)
              const _LoadingPanel()
            else if (_erro != null)
              _InfoPanel(
                icon: Icons.error_outline_rounded,
                text: 'Nao foi possivel carregar a lista de impressoras. $_erro',
                color: Color(0xFFF87171),
              )
            else if (_status.isEmpty)
              const _InfoPanel(
                icon: Icons.print_disabled_rounded,
                text: 'Nenhuma impressora cadastrada para teste.',
                color: Color(0xFFD8B840),
              )
            else
              ..._buildStatusPorSetor(),
          ],
        ),
      ),
    );
  }
}

class _ResumoStatus extends StatelessWidget {
  const _ResumoStatus({
    required this.total,
    required this.servidorOnline,
    required this.usbOk,
    required this.alertas,
    required this.offline,
    required this.atualizando,
    required this.ultimaVerificacao,
  });

  final int total;
  final int servidorOnline;
  final int usbOk;
  final int alertas;
  final int offline;
  final bool atualizando;
  final String ultimaVerificacao;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.print_rounded, color: Color(0xFFD8B840)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Status do Print Server',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (atualizando)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ultima verificacao: $ultimaVerificacao',
            style: const TextStyle(color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Valida a rede do servidor e, quando o endpoint informar, tambem mostra se a impressora USB foi removida.',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'Total', value: '$total'),
              _MetricChip(
                label: 'Servidor online',
                value: '$servidorOnline',
                status: _MetricStatus.ok,
              ),
              _MetricChip(
                label: 'USB ok',
                value: '$usbOk',
                status: _MetricStatus.ok,
              ),
              _MetricChip(
                label: 'Alertas',
                value: '$alertas',
                status: _MetricStatus.warning,
              ),
              _MetricChip(
                label: 'Offline',
                value: '$offline',
                status: _MetricStatus.error,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetorHeader extends StatelessWidget {
  const _SetorHeader({required this.setor});

  final String setor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFD8B840).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFD8B840).withValues(alpha: 0.38),
              ),
            ),
            child: const Icon(
              Icons.business_rounded,
              color: Color(0xFFD8B840),
              size: 17,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              setor,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrinterStatusCard extends StatelessWidget {
  const _PrinterStatusCard(
    this.status, {
    required this.testando,
    required this.onTestarImpressao,
  });

  final _PrinterStatus status;
  final bool testando;
  final VoidCallback onTestarImpressao;

  @override
  Widget build(BuildContext context) {
    final color = status.usbDesconectado || !status.servidorOnline
        ? const Color(0xFFF87171)
        : status.precisaValidarUsb
        ? const Color(0xFFD8B840)
        : const Color(0xFF22C55E);
    final icon = status.usbDesconectado
        ? Icons.usb_off_rounded
        : status.servidorOnline
        ? Icons.check_circle_rounded
        : Icons.cancel_rounded;
    final tituloStatus = !status.servidorOnline
        ? 'SERVIDOR OFFLINE'
        : status.usbDesconectado
        ? 'USB DESCONECTADO'
        : status.precisaValidarUsb
        ? 'USB NAO INFORMADO'
        : 'OPERACIONAL';
    final descricaoStatus = !status.servidorOnline
        ? 'Sem resposta no IP/porta do print server.'
        : status.usbDesconectado
        ? 'Print server respondeu, mas a impressora USB nao foi detectada.'
        : status.precisaValidarUsb
        ? 'O print server nao disponibilizou status USB por ZPL ou SNMP.'
        : 'Print server online e USB validado.';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _boxDecoration(borderColor: color.withValues(alpha: 0.45)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  status.destino,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  descricaoStatus,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (status.statusUsb?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 6),
                  _InlineDetail(
                    icon: Icons.info_outline_rounded,
                    text: 'Status USB: ${status.statusUsb}',
                  ),
                ],
                if (status.portaUsb?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 6),
                  _InlineDetail(
                    icon: Icons.usb_rounded,
                    text: 'Porta fisica: ${status.portaUsb}',
                  ),
                ],
                if ((!status.servidorOnline || status.usbDesconectado) &&
                    status.erro != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    status.erro!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tituloStatus,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                status.servidorOnline
                    ? '${status.tempoMs} ms'
                    : 'sem conexao',
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: OutlinedButton.icon(
                  onPressed: testando ? null : onTestarImpressao,
                  icon: testando
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_rounded, size: 17),
                  label: Text(testando ? 'Enviando' : 'Teste'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFD8B840),
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    side: BorderSide(
                      color: const Color(0xFFD8B840).withValues(alpha: 0.65),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineDetail extends StatelessWidget {
  const _InlineDetail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFCBD5E1), size: 15),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

enum _MetricStatus { neutral, ok, warning, error }

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    this.status = _MetricStatus.neutral,
  });

  final String label;
  final String value;
  final _MetricStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      _MetricStatus.ok => const Color(0xFF22C55E),
      _MetricStatus.warning => const Color(0xFFD8B840),
      _MetricStatus.error => const Color(0xFFF87171),
      _MetricStatus.neutral => const Color(0xFFCBD5E1),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _boxDecoration(),
      child: const Row(
        children: [
          CircularProgressIndicator(strokeWidth: 2),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Testando conexao com o print server...',
              style: TextStyle(
                color: Color(0xFFE2E8F0),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDecoration(borderColor: color.withValues(alpha: 0.5)),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFE2E8F0),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _boxDecoration({Color borderColor = const Color(0xFF334155)}) {
  return BoxDecoration(
    color: const Color(0xFF0F172A),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: borderColor),
  );
}
