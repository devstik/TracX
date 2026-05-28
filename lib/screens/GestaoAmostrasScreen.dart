import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color _kAmostraBg = Color(0xFF050A14);
const Color _kAmostraSurface = Color(0xFF101B34);
const Color _kAmostraSurface2 = Color(0xFF0F172A);
const Color _kAmostraPrimary = Color(0xFF2563EB);
const Color _kAmostraAccent = Color(0xFF60A5FA);
const Color _kAmostraText = Color(0xFFF9FAFB);
const Color _kAmostraMuted = Color(0xFF9CA3AF);
const Color _kAmostraBorder = Color(0x33FFFFFF);

enum _AmostraEtapa {
  solicitacaoTriagem,
  planejamentoFila,
  execucaoDesenvolvimento,
  entregaFeedback,
}

enum _AmostraPrioridade { alta, media, baixa }

enum _PcpParecer { pendente, aprovado, reprovado }

enum _FeedbackCliente { pendente, aprovado, reprovado }

class _TentativaAmostra {
  final String id;
  final String descricao;
  final String ajuste;
  final bool sucesso;
  final String dataIso;

  const _TentativaAmostra({
    required this.id,
    required this.descricao,
    required this.ajuste,
    required this.sucesso,
    required this.dataIso,
  });

  factory _TentativaAmostra.fromJson(Map<String, dynamic> json) {
    return _TentativaAmostra(
      id: (json['id'] ?? '').toString(),
      descricao: (json['descricao'] ?? '').toString(),
      ajuste: (json['ajuste'] ?? '').toString(),
      sucesso: json['sucesso'] == true,
      dataIso: (json['dataIso'] ?? DateTime.now().toIso8601String()).toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'descricao': descricao,
      'ajuste': ajuste,
      'sucesso': sucesso,
      'dataIso': dataIso,
    };
  }
}

class _AmostraSolicitacao {
  final String id;
  final String protocolo;
  final String? vinculoOrigemId;
  final String cliente;
  final String produto;
  final String prazoIso;
  final _AmostraPrioridade prioridade;
  final String solicitadoPor;
  final String codigoArte;
  final String observacoesComercial;
  final bool tecidoLiberadoRetirada;
  final bool amostraCor;
  final String nomenclaturaSugerida;
  final bool comercialValidado;
  final String aprovadorComercial;
  final String codigoIndustrial;
  final _AmostraEtapa etapa;
  final String etapaAtualizadaEmIso;
  final _PcpParecer parecerPcp;
  final String justificativaPcp;
  final String gargalosPcp;
  final String observacoesPcp;
  final bool comercialLiberouComGargalo;
  final int? ordemFila;
  final List<_TentativaAmostra> tentativas;
  final bool amostraPronta;
  final String? dataSucessoIso;
  final String fichaTecnicaAnexo;
  final bool qualidadeValidada;
  final bool artigoCadastrado;
  final bool amostraEnviada;
  final bool fichaCustoConcluida;
  final String fotoArtigoAnexo;
  final _FeedbackCliente feedbackCliente;
  final bool pedidoVendaGerado;
  final bool engenhariaValidou;
  final String anexoTecelagem;
  final String anexoQualidade;
  final String anexoEmbalagem;
  final String observacoesEntrega;
  final String criadoEmIso;
  final String atualizadoEmIso;

  const _AmostraSolicitacao({
    required this.id,
    required this.protocolo,
    required this.vinculoOrigemId,
    required this.cliente,
    required this.produto,
    required this.prazoIso,
    required this.prioridade,
    required this.solicitadoPor,
    required this.codigoArte,
    required this.observacoesComercial,
    required this.tecidoLiberadoRetirada,
    required this.amostraCor,
    required this.nomenclaturaSugerida,
    required this.comercialValidado,
    required this.aprovadorComercial,
    required this.codigoIndustrial,
    required this.etapa,
    required this.etapaAtualizadaEmIso,
    required this.parecerPcp,
    required this.justificativaPcp,
    required this.gargalosPcp,
    required this.observacoesPcp,
    required this.comercialLiberouComGargalo,
    required this.ordemFila,
    required this.tentativas,
    required this.amostraPronta,
    required this.dataSucessoIso,
    required this.fichaTecnicaAnexo,
    required this.qualidadeValidada,
    required this.artigoCadastrado,
    required this.amostraEnviada,
    required this.fichaCustoConcluida,
    required this.fotoArtigoAnexo,
    required this.feedbackCliente,
    required this.pedidoVendaGerado,
    required this.engenhariaValidou,
    required this.anexoTecelagem,
    required this.anexoQualidade,
    required this.anexoEmbalagem,
    required this.observacoesEntrega,
    required this.criadoEmIso,
    required this.atualizadoEmIso,
  });

  factory _AmostraSolicitacao.fromJson(Map<String, dynamic> json) {
    return _AmostraSolicitacao(
      id: (json['id'] ?? '').toString(),
      protocolo: (json['protocolo'] ?? '').toString(),
      vinculoOrigemId: json['vinculoOrigemId']?.toString(),
      cliente: (json['cliente'] ?? '').toString(),
      produto: (json['produto'] ?? '').toString(),
      prazoIso: (json['prazoIso'] ?? DateTime.now().toIso8601String()).toString(),
      prioridade: _prioridadeFromString(json['prioridade']),
      solicitadoPor: (json['solicitadoPor'] ?? '').toString(),
      codigoArte: (json['codigoArte'] ?? '').toString(),
      observacoesComercial: (json['observacoesComercial'] ?? '').toString(),
      tecidoLiberadoRetirada: json['tecidoLiberadoRetirada'] == true,
      amostraCor: json['amostraCor'] == true,
      nomenclaturaSugerida: (json['nomenclaturaSugerida'] ?? '').toString(),
      comercialValidado: json['comercialValidado'] == true,
      aprovadorComercial: (json['aprovadorComercial'] ?? '').toString(),
      codigoIndustrial: (json['codigoIndustrial'] ?? '').toString(),
      etapa: _etapaFromString(json['etapa']),
      etapaAtualizadaEmIso: (json['etapaAtualizadaEmIso'] ??
              DateTime.now().toIso8601String())
          .toString(),
      parecerPcp: _parecerFromString(json['parecerPcp']),
      justificativaPcp: (json['justificativaPcp'] ?? '').toString(),
      gargalosPcp: (json['gargalosPcp'] ?? '').toString(),
      observacoesPcp: (json['observacoesPcp'] ?? '').toString(),
      comercialLiberouComGargalo:
          json['comercialLiberouComGargalo'] == true,
      ordemFila: json['ordemFila'] is int
          ? json['ordemFila'] as int
          : int.tryParse((json['ordemFila'] ?? '').toString()),
      tentativas: (json['tentativas'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => _TentativaAmostra.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      amostraPronta: json['amostraPronta'] == true,
      dataSucessoIso: json['dataSucessoIso']?.toString(),
      fichaTecnicaAnexo: (json['fichaTecnicaAnexo'] ?? '').toString(),
      qualidadeValidada: json['qualidadeValidada'] == true,
      artigoCadastrado: json['artigoCadastrado'] == true,
      amostraEnviada: json['amostraEnviada'] == true,
      fichaCustoConcluida: json['fichaCustoConcluida'] == true,
      fotoArtigoAnexo: (json['fotoArtigoAnexo'] ?? '').toString(),
      feedbackCliente: _feedbackFromString(json['feedbackCliente']),
      pedidoVendaGerado: json['pedidoVendaGerado'] == true,
      engenhariaValidou: json['engenhariaValidou'] == true,
      anexoTecelagem: (json['anexoTecelagem'] ?? '').toString(),
      anexoQualidade: (json['anexoQualidade'] ?? '').toString(),
      anexoEmbalagem: (json['anexoEmbalagem'] ?? '').toString(),
      observacoesEntrega: (json['observacoesEntrega'] ?? '').toString(),
      criadoEmIso: (json['criadoEmIso'] ?? DateTime.now().toIso8601String())
          .toString(),
      atualizadoEmIso: (json['atualizadoEmIso'] ??
              DateTime.now().toIso8601String())
          .toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'protocolo': protocolo,
      'vinculoOrigemId': vinculoOrigemId,
      'cliente': cliente,
      'produto': produto,
      'prazoIso': prazoIso,
      'prioridade': prioridade.name,
      'solicitadoPor': solicitadoPor,
      'codigoArte': codigoArte,
      'observacoesComercial': observacoesComercial,
      'tecidoLiberadoRetirada': tecidoLiberadoRetirada,
      'amostraCor': amostraCor,
      'nomenclaturaSugerida': nomenclaturaSugerida,
      'comercialValidado': comercialValidado,
      'aprovadorComercial': aprovadorComercial,
      'codigoIndustrial': codigoIndustrial,
      'etapa': etapa.name,
      'etapaAtualizadaEmIso': etapaAtualizadaEmIso,
      'parecerPcp': parecerPcp.name,
      'justificativaPcp': justificativaPcp,
      'gargalosPcp': gargalosPcp,
      'observacoesPcp': observacoesPcp,
      'comercialLiberouComGargalo': comercialLiberouComGargalo,
      'ordemFila': ordemFila,
      'tentativas': tentativas.map((item) => item.toJson()).toList(),
      'amostraPronta': amostraPronta,
      'dataSucessoIso': dataSucessoIso,
      'fichaTecnicaAnexo': fichaTecnicaAnexo,
      'qualidadeValidada': qualidadeValidada,
      'artigoCadastrado': artigoCadastrado,
      'amostraEnviada': amostraEnviada,
      'fichaCustoConcluida': fichaCustoConcluida,
      'fotoArtigoAnexo': fotoArtigoAnexo,
      'feedbackCliente': feedbackCliente.name,
      'pedidoVendaGerado': pedidoVendaGerado,
      'engenhariaValidou': engenhariaValidou,
      'anexoTecelagem': anexoTecelagem,
      'anexoQualidade': anexoQualidade,
      'anexoEmbalagem': anexoEmbalagem,
      'observacoesEntrega': observacoesEntrega,
      'criadoEmIso': criadoEmIso,
      'atualizadoEmIso': atualizadoEmIso,
    };
  }
}

class _AmostraStorage {
  static const String _storageKey = 'gestao_amostras_workflow_v1';

  static Future<List<_AmostraSolicitacao>> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => _AmostraSolicitacao.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> salvar(List<_AmostraSolicitacao> itens) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(itens.map((item) => item.toJson()).toList());
    await prefs.setString(_storageKey, payload);
  }
}

class GestaoAmostrasScreen extends StatefulWidget {
  final String usuario;

  const GestaoAmostrasScreen({super.key, required this.usuario});

  @override
  State<GestaoAmostrasScreen> createState() => _GestaoAmostrasScreenState();
}

class _GestaoAmostrasScreenState extends State<GestaoAmostrasScreen> {
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  bool _loading = true;
  List<_AmostraSolicitacao> _itens = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final itens = await _AmostraStorage.carregar();
    if (!mounted) return;
    setState(() {
      _itens = _ordenarERecalcularFila(itens);
      _loading = false;
    });
  }

  Future<void> _salvarTudo(List<_AmostraSolicitacao> itens) async {
    final lista = _ordenarERecalcularFila(itens);
    await _AmostraStorage.salvar(lista);
    if (!mounted) return;
    setState(() => _itens = lista);
  }

  List<_AmostraSolicitacao> _ordenarERecalcularFila(
    List<_AmostraSolicitacao> itens,
  ) {
    final lista = [...itens];
    final emFila = lista
        .where(
          (item) =>
              item.etapa == _AmostraEtapa.planejamentoFila &&
              (item.parecerPcp == _PcpParecer.aprovado ||
                  item.comercialLiberouComGargalo),
        )
        .toList()
      ..sort((a, b) {
        final prioridade = _pesoPrioridade(a.prioridade)
            .compareTo(_pesoPrioridade(b.prioridade));
        if (prioridade != 0) return prioridade;
        return a.criadoEmIso.compareTo(b.criadoEmIso);
      });

    final mapaFila = <String, int>{};
    for (var i = 0; i < emFila.length; i++) {
      mapaFila[emFila[i].id] = i + 1;
    }

    final atualizados = lista
        .map((item) {
          final json = item.toJson();
          json['ordemFila'] = mapaFila[item.id];
          return _AmostraSolicitacao.fromJson(json);
        })
        .toList()
      ..sort((a, b) => b.atualizadoEmIso.compareTo(a.atualizadoEmIso));

    return atualizados;
  }

  int _pesoPrioridade(_AmostraPrioridade prioridade) {
    switch (prioridade) {
      case _AmostraPrioridade.alta:
        return 0;
      case _AmostraPrioridade.media:
        return 1;
      case _AmostraPrioridade.baixa:
        return 2;
    }
  }

  Future<void> _abrirEditor({_AmostraSolicitacao? item}) async {
    final bool isNovo = item == null;
    final DateTime agora = DateTime.now();
    final String protocolo = item?.protocolo ?? _gerarProtocolo(agora);
    final String codigoIndustrial =
        item?.codigoIndustrial ?? _gerarCodigoIndustrial(protocolo);

    final result = await Navigator.of(context).push<_EditorAmostraResult>(
      MaterialPageRoute(
        builder: (_) => _EditorAmostraScreen(
          usuarioAtual: widget.usuario,
          isNovo: isNovo,
          amostraInicial: item,
          protocoloSugerido: protocolo,
          codigoIndustrialSugerido: codigoIndustrial,
        ),
      ),
    );

    if (result == null) return;

    final novosItens = [..._itens];
    final int index =
        novosItens.indexWhere((existing) => existing.id == result.item.id);
    if (index >= 0) {
      novosItens[index] = result.item;
    } else {
      novosItens.add(result.item);
    }

    if (result.criarNovoDesenvolvimento) {
      novosItens.add(_criarNovaVersao(result.item));
    }

    await _salvarTudo(novosItens);
  }

  _AmostraSolicitacao _criarNovaVersao(_AmostraSolicitacao origem) {
    final agora = DateTime.now();
    final protocolo = _gerarProtocolo(agora);
    return _AmostraSolicitacao(
      id: 'amostra_${agora.microsecondsSinceEpoch}',
      protocolo: protocolo,
      vinculoOrigemId: origem.id,
      cliente: origem.cliente,
      produto: origem.produto,
      prazoIso: agora.add(const Duration(days: 7)).toIso8601String(),
      prioridade: origem.prioridade,
      solicitadoPor: widget.usuario,
      codigoArte: origem.codigoArte,
      observacoesComercial:
          'Novo desenvolvimento gerado a partir do protocolo ${origem.protocolo}.',
      tecidoLiberadoRetirada: origem.tecidoLiberadoRetirada,
      amostraCor: origem.amostraCor,
      nomenclaturaSugerida: origem.nomenclaturaSugerida,
      comercialValidado: false,
      aprovadorComercial: '',
      codigoIndustrial: _gerarCodigoIndustrial(protocolo),
      etapa: _AmostraEtapa.solicitacaoTriagem,
      etapaAtualizadaEmIso: agora.toIso8601String(),
      parecerPcp: _PcpParecer.pendente,
      justificativaPcp: '',
      gargalosPcp: '',
      observacoesPcp: '',
      comercialLiberouComGargalo: false,
      ordemFila: null,
      tentativas: const [],
      amostraPronta: false,
      dataSucessoIso: null,
      fichaTecnicaAnexo: '',
      qualidadeValidada: false,
      artigoCadastrado: false,
      amostraEnviada: false,
      fichaCustoConcluida: false,
      fotoArtigoAnexo: '',
      feedbackCliente: _FeedbackCliente.pendente,
      pedidoVendaGerado: false,
      engenhariaValidou: false,
      anexoTecelagem: '',
      anexoQualidade: '',
      anexoEmbalagem: '',
      observacoesEntrega: '',
      criadoEmIso: agora.toIso8601String(),
      atualizadoEmIso: agora.toIso8601String(),
    );
  }

  String _gerarProtocolo(DateTime data) {
    final sequencial = (_itens.length + 1).toString().padLeft(4, '0');
    return 'SOL-${DateFormat('yyyyMMdd').format(data)}-$sequencial';
  }

  String _gerarCodigoIndustrial(String protocolo) {
    final sufixo = protocolo.replaceAll('SOL-', '');
    return 'DEV-$sufixo';
  }

  List<_AmostraSolicitacao> _itensDaEtapa(_AmostraEtapa etapa) {
    final itens = _itens.where((item) => item.etapa == etapa).toList();
    switch (etapa) {
      case _AmostraEtapa.solicitacaoTriagem:
        itens.sort((a, b) => b.criadoEmIso.compareTo(a.criadoEmIso));
        break;
      case _AmostraEtapa.planejamentoFila:
        itens.sort((a, b) {
          final filaA = a.ordemFila ?? 9999;
          final filaB = b.ordemFila ?? 9999;
          if (filaA != filaB) return filaA.compareTo(filaB);
          return _pesoPrioridade(a.prioridade).compareTo(
            _pesoPrioridade(b.prioridade),
          );
        });
        break;
      case _AmostraEtapa.execucaoDesenvolvimento:
        itens.sort(
          (a, b) => a.etapaAtualizadaEmIso.compareTo(b.etapaAtualizadaEmIso),
        );
        break;
      case _AmostraEtapa.entregaFeedback:
        itens.sort((a, b) => b.atualizadoEmIso.compareTo(a.atualizadoEmIso));
        break;
    }
    return itens;
  }

  String _tituloEtapa(_AmostraEtapa etapa) {
    switch (etapa) {
      case _AmostraEtapa.solicitacaoTriagem:
        return 'Solicitacao & Triagem';
      case _AmostraEtapa.planejamentoFila:
        return 'Planejamento & Fila';
      case _AmostraEtapa.execucaoDesenvolvimento:
        return 'Execucao & Desenvolvimento';
      case _AmostraEtapa.entregaFeedback:
        return 'Entrega & Feedback';
    }
  }

  String _subtituloEtapa(_AmostraEtapa etapa) {
    switch (etapa) {
      case _AmostraEtapa.solicitacaoTriagem:
        return 'Comercial, aprovacao e triagem inicial';
      case _AmostraEtapa.planejamentoFila:
        return 'PCP, gargalos e organizacao da fila';
      case _AmostraEtapa.execucaoDesenvolvimento:
        return 'Tentativas, ficha tecnica e validacao';
      case _AmostraEtapa.entregaFeedback:
        return 'Entrega, custo, cliente e engenharia';
    }
  }

  Color _corPrioridade(_AmostraPrioridade prioridade) {
    switch (prioridade) {
      case _AmostraPrioridade.alta:
        return const Color(0xFFEF4444);
      case _AmostraPrioridade.media:
        return const Color(0xFFF59E0B);
      case _AmostraPrioridade.baixa:
        return const Color(0xFF10B981);
    }
  }

  String _labelPrioridade(_AmostraPrioridade prioridade) {
    switch (prioridade) {
      case _AmostraPrioridade.alta:
        return 'Alta';
      case _AmostraPrioridade.media:
        return 'Media';
      case _AmostraPrioridade.baixa:
        return 'Baixa';
    }
  }

  Widget _buildIndicadores() {
    final int total = _itens.length;
    final int pendentesGerencia =
        _itens.where((item) => !item.comercialValidado).length;
    final int comPedido = _itens.where((item) => item.pedidoVendaGerado).length;
    final double eficiencia = total == 0 ? 0 : (comPedido / total) * 100;

    final Map<_AmostraEtapa, double> mediasPorEtapa = {
      for (final etapa in _AmostraEtapa.values) etapa: 0,
    };
    for (final etapa in _AmostraEtapa.values) {
      final itens = _itensDaEtapa(etapa);
      if (itens.isEmpty) continue;
      final totalDias = itens.fold<double>(0, (acc, item) {
        final data = DateTime.tryParse(item.etapaAtualizadaEmIso) ?? DateTime.now();
        return acc + DateTime.now().difference(data).inHours / 24;
      });
      mediasPorEtapa[etapa] = totalDias / itens.length;
    }

    final etapaGargalo = mediasPorEtapa.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );

    final Map<String, int> tentativasPorProduto = {};
    for (final item in _itens) {
      tentativasPorProduto[item.produto] =
          (tentativasPorProduto[item.produto] ?? 0) + item.tentativas.length;
    }
    String historicoTop = '-';
    if (tentativasPorProduto.isNotEmpty) {
      final top = tentativasPorProduto.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      historicoTop = '${top.key} (${top.value} tentativas)';
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _IndicadorCard(
          titulo: 'Volume total',
          valor: '$total amostras',
          descricao: 'Acompanhamento em tempo real do funil',
          icon: Icons.layers_outlined,
          accent: _kAmostraAccent,
        ),
        _IndicadorCard(
          titulo: 'Gargalo atual',
          valor: _tituloEtapa(etapaGargalo.key),
          descricao:
              '${etapaGargalo.value.toStringAsFixed(1)} dias em media na etapa',
          icon: Icons.speed_outlined,
          accent: const Color(0xFFF59E0B),
        ),
        _IndicadorCard(
          titulo: 'Eficiencia',
          valor: '${eficiencia.toStringAsFixed(0)}%',
          descricao: '$comPedido de $total amostras viraram pedido',
          icon: Icons.insights_outlined,
          accent: const Color(0xFF10B981),
        ),
        _IndicadorCard(
          titulo: 'Historico tecnico',
          valor: historicoTop,
          descricao: '$pendentesGerencia aguardando aprovacao comercial',
          icon: Icons.history_edu_outlined,
          accent: const Color(0xFF8B5CF6),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kAmostraBg,
      appBar: AppBar(
        backgroundColor: _kAmostraBg,
        foregroundColor: _kAmostraText,
        title: const Text('Gestao de Amostras'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _abrirEditor(),
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Nova solicitacao',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _abrirEditor(),
        backgroundColor: _kAmostraPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nova solicitacao'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAmostraAccent))
          : RefreshIndicator(
              color: _kAmostraAccent,
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _kAmostraSurface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _kAmostraBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Fluxo de desenvolvimento de produto',
                          style: TextStyle(
                            color: _kAmostraText,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Acompanhamento do inicio da solicitacao ate a entrega da amostra, com aprovador comercial, triagem PCP, execucao, feedback e engenharia.',
                          style: TextStyle(color: _kAmostraMuted, height: 1.4),
                        ),
                        const SizedBox(height: 18),
                        _buildIndicadores(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _AmostraEtapa.values.map((etapa) {
                        final itens = _itensDaEtapa(etapa);
                        return Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: SizedBox(
                            width: 320,
                            child: _StageColumn(
                              titulo: _tituloEtapa(etapa),
                              subtitulo: _subtituloEtapa(etapa),
                              total: itens.length,
                              child: itens.isEmpty
                                  ? const _ColunaVazia()
                                  : Column(
                                      children: itens.map((item) {
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 12),
                                          child: _AmostraCard(
                                            item: item,
                                            dateFormat: _dateFormat,
                                            prioridadeLabel: _labelPrioridade(
                                              item.prioridade,
                                            ),
                                            prioridadeColor: _corPrioridade(
                                              item.prioridade,
                                            ),
                                            onTap: () => _abrirEditor(item: item),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _EditorAmostraResult {
  final _AmostraSolicitacao item;
  final bool criarNovoDesenvolvimento;

  const _EditorAmostraResult({
    required this.item,
    required this.criarNovoDesenvolvimento,
  });
}

class _EditorAmostraScreen extends StatefulWidget {
  final String usuarioAtual;
  final bool isNovo;
  final _AmostraSolicitacao? amostraInicial;
  final String protocoloSugerido;
  final String codigoIndustrialSugerido;

  const _EditorAmostraScreen({
    required this.usuarioAtual,
    required this.isNovo,
    required this.amostraInicial,
    required this.protocoloSugerido,
    required this.codigoIndustrialSugerido,
  });

  @override
  State<_EditorAmostraScreen> createState() => _EditorAmostraScreenState();
}

class _EditorAmostraScreenState extends State<_EditorAmostraScreen> {
  final _formKey = GlobalKey<FormState>();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

  late final TextEditingController _clienteController;
  late final TextEditingController _produtoController;
  late final TextEditingController _codigoArteController;
  late final TextEditingController _observacoesComercialController;
  late final TextEditingController _nomenclaturaController;
  late final TextEditingController _aprovadorController;
  late final TextEditingController _justificativaPcpController;
  late final TextEditingController _gargalosPcpController;
  late final TextEditingController _observacoesPcpController;
  late final TextEditingController _fichaTecnicaController;
  late final TextEditingController _fotoArtigoController;
  late final TextEditingController _anexoTecelagemController;
  late final TextEditingController _anexoQualidadeController;
  late final TextEditingController _anexoEmbalagemController;
  late final TextEditingController _observacoesEntregaController;

  late _AmostraPrioridade _prioridade;
  late _AmostraEtapa _etapa;
  late _PcpParecer _parecerPcp;
  late _FeedbackCliente _feedbackCliente;
  late bool _tecidoLiberadoRetirada;
  late bool _amostraCor;
  late bool _comercialValidado;
  late bool _comercialLiberouComGargalo;
  late bool _artigoCadastrado;
  late bool _qualidadeValidada;
  late bool _amostraPronta;
  late bool _amostraEnviada;
  late bool _fichaCustoConcluida;
  late bool _pedidoVendaGerado;
  late bool _engenhariaValidou;
  late DateTime _prazo;
  late List<_TentativaAmostra> _tentativas;
  late String _protocolo;
  late String _codigoIndustrial;
  String? _dataSucessoIso;
  bool _criarNovoDesenvolvimento = false;

  @override
  void initState() {
    super.initState();
    final item = widget.amostraInicial;
    _protocolo = item?.protocolo ?? widget.protocoloSugerido;
    _codigoIndustrial = item?.codigoIndustrial.isNotEmpty == true
        ? item!.codigoIndustrial
        : widget.codigoIndustrialSugerido;
    _prazo = DateTime.tryParse(item?.prazoIso ?? '') ??
        DateTime.now().add(const Duration(days: 7));
    _prioridade = item?.prioridade ?? _AmostraPrioridade.media;
    _etapa = item?.etapa ?? _AmostraEtapa.solicitacaoTriagem;
    _parecerPcp = item?.parecerPcp ?? _PcpParecer.pendente;
    _feedbackCliente = item?.feedbackCliente ?? _FeedbackCliente.pendente;
    _tecidoLiberadoRetirada = item?.tecidoLiberadoRetirada ?? false;
    _amostraCor = item?.amostraCor ?? false;
    _comercialValidado = item?.comercialValidado ?? false;
    _comercialLiberouComGargalo = item?.comercialLiberouComGargalo ?? false;
    _artigoCadastrado = item?.artigoCadastrado ?? false;
    _qualidadeValidada = item?.qualidadeValidada ?? false;
    _amostraPronta = item?.amostraPronta ?? false;
    _amostraEnviada = item?.amostraEnviada ?? false;
    _fichaCustoConcluida = item?.fichaCustoConcluida ?? false;
    _pedidoVendaGerado = item?.pedidoVendaGerado ?? false;
    _engenhariaValidou = item?.engenhariaValidou ?? false;
    _tentativas = [...(item?.tentativas ?? const [])];
    _dataSucessoIso = item?.dataSucessoIso;

    _clienteController = TextEditingController(text: item?.cliente ?? '');
    _produtoController = TextEditingController(text: item?.produto ?? '');
    _codigoArteController = TextEditingController(text: item?.codigoArte ?? '');
    _observacoesComercialController = TextEditingController(
      text: item?.observacoesComercial ?? '',
    );
    _nomenclaturaController = TextEditingController(
      text: item?.nomenclaturaSugerida ?? '',
    );
    _aprovadorController = TextEditingController(
      text: item?.aprovadorComercial ?? '',
    );
    _justificativaPcpController = TextEditingController(
      text: item?.justificativaPcp ?? '',
    );
    _gargalosPcpController = TextEditingController(
      text: item?.gargalosPcp ?? '',
    );
    _observacoesPcpController = TextEditingController(
      text: item?.observacoesPcp ?? '',
    );
    _fichaTecnicaController = TextEditingController(
      text: item?.fichaTecnicaAnexo ?? '',
    );
    _fotoArtigoController = TextEditingController(
      text: item?.fotoArtigoAnexo ?? '',
    );
    _anexoTecelagemController = TextEditingController(
      text: item?.anexoTecelagem ?? '',
    );
    _anexoQualidadeController = TextEditingController(
      text: item?.anexoQualidade ?? '',
    );
    _anexoEmbalagemController = TextEditingController(
      text: item?.anexoEmbalagem ?? '',
    );
    _observacoesEntregaController = TextEditingController(
      text: item?.observacoesEntrega ?? '',
    );
  }

  @override
  void dispose() {
    _clienteController.dispose();
    _produtoController.dispose();
    _codigoArteController.dispose();
    _observacoesComercialController.dispose();
    _nomenclaturaController.dispose();
    _aprovadorController.dispose();
    _justificativaPcpController.dispose();
    _gargalosPcpController.dispose();
    _observacoesPcpController.dispose();
    _fichaTecnicaController.dispose();
    _fotoArtigoController.dispose();
    _anexoTecelagemController.dispose();
    _anexoQualidadeController.dispose();
    _anexoEmbalagemController.dispose();
    _observacoesEntregaController.dispose();
    super.dispose();
  }

  Future<void> _selecionarPrazo() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _prazo,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _kAmostraPrimary,
              surface: _kAmostraSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (selected == null) return;
    setState(() => _prazo = selected);
  }

  Future<void> _registrarTentativa() async {
    final descricaoController = TextEditingController();
    final ajusteController = TextEditingController();
    bool sucesso = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _kAmostraSurface,
          title: const Text(
            'Registrar tentativa',
            style: TextStyle(color: _kAmostraText),
          ),
          content: StatefulBuilder(
            builder: (context, setModalState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildInput(
                      controller: descricaoController,
                      label: 'O que aconteceu',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    _buildInput(
                      controller: ajusteController,
                      label: 'Ajuste realizado',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      value: sucesso,
                      onChanged: (value) => setModalState(() => sucesso = value),
                      title: const Text(
                        'Essa tentativa resolveu?',
                        style: TextStyle(color: _kAmostraText),
                      ),
                      activeColor: _kAmostraAccent,
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Adicionar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    if (descricaoController.text.trim().isEmpty &&
        ajusteController.text.trim().isEmpty) {
      return;
    }

    setState(() {
      _tentativas = [
        ..._tentativas,
        _TentativaAmostra(
          id: 'tentativa_${DateTime.now().microsecondsSinceEpoch}',
          descricao: descricaoController.text.trim(),
          ajuste: ajusteController.text.trim(),
          sucesso: sucesso,
          dataIso: DateTime.now().toIso8601String(),
        ),
      ];
      if (sucesso) {
        _amostraPronta = true;
        _dataSucessoIso = DateTime.now().toIso8601String();
      }
    });
  }

  void _enviarParaPlanejamento() {
    if (!_validarSolicitacaoBase()) return;
    if (!_comercialValidado || _aprovadorController.text.trim().isEmpty) {
      _showSnack(
        'Valide a solicitacao pela gerencia/coordenacao comercial antes de enviar.',
      );
      return;
    }
    setState(() {
      _etapa = _AmostraEtapa.planejamentoFila;
      if (_codigoIndustrial.trim().isEmpty) {
        _codigoIndustrial = widget.codigoIndustrialSugerido;
      }
    });
  }

  void _iniciarExecucao() {
    if (_parecerPcp != _PcpParecer.aprovado &&
        !_comercialLiberouComGargalo) {
      _showSnack(
        'A etapa 2 precisa estar aprovada pelo PCP ou liberada pelo comercial com gargalo.',
      );
      return;
    }
    setState(() => _etapa = _AmostraEtapa.execucaoDesenvolvimento);
  }

  void _liberarParaEntrega() {
    if (!_amostraPronta) {
      _showSnack('Marque a amostra como pronta antes de seguir.');
      return;
    }
    if (_fichaTecnicaController.text.trim().isEmpty) {
      _showSnack('A ficha tecnica e obrigatoria para seguir no fluxo.');
      return;
    }
    if (!_artigoCadastrado) {
      _showSnack('Cadastre o artigo antes de liberar a entrega.');
      return;
    }
    if (!_qualidadeValidada) {
      _showSnack('A qualidade precisa validar antes da etapa 4.');
      return;
    }
    setState(() => _etapa = _AmostraEtapa.entregaFeedback);
  }

  bool _validarSolicitacaoBase() {
    return _formKey.currentState?.validate() ?? false;
  }

  Future<void> _gerarGuiaPdf() async {
    final bytes = await _montarGuiaPdf(_construirItem());
    if (!mounted) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<Uint8List> _montarGuiaPdf(_AmostraSolicitacao item) async {
    final pdf = pw.Document();
    final prazo = _dateFormat.format(
      DateTime.tryParse(item.prazoIso) ?? DateTime.now(),
    );
    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(24),
        ),
        build: (context) {
          return [
            pw.Text(
              'Guia de envio da amostra',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 18),
            _pdfLinha('Protocolo', item.protocolo),
            _pdfLinha('Codigo industrial', item.codigoIndustrial),
            _pdfLinha('Cliente', item.cliente),
            _pdfLinha('Produto', item.produto),
            _pdfLinha('Prioridade', _labelPrioridade(item.prioridade)),
            _pdfLinha('Prazo', prazo),
            _pdfLinha('Codigo da arte', item.codigoArte),
            _pdfLinha('Nomenclatura sugerida', item.nomenclaturaSugerida),
            _pdfLinha(
              'Amostra de cor liberada para retirada',
              item.tecidoLiberadoRetirada ? 'Sim' : 'Nao',
            ),
            _pdfLinha('Observacoes comerciais', item.observacoesComercial),
            _pdfLinha('Observacoes PCP', item.observacoesPcp),
            _pdfLinha('Gargalos', item.gargalosPcp),
            _pdfLinha(
              'Ficha tecnica',
              item.fichaTecnicaAnexo.isEmpty ? '-' : item.fichaTecnicaAnexo,
            ),
          ];
        },
      ),
    );
    return pdf.save();
  }

  pw.Widget _pdfLinha(String label, String valor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label: ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.TextSpan(text: valor.isEmpty ? '-' : valor),
          ],
        ),
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  _AmostraSolicitacao _construirItem() {
    final agora = DateTime.now();
    final inicial = widget.amostraInicial;
    final etapaAnterior = inicial?.etapa;
    final etapaMudou = etapaAnterior != null && etapaAnterior != _etapa;
    return _AmostraSolicitacao(
      id: inicial?.id ?? 'amostra_${agora.microsecondsSinceEpoch}',
      protocolo: _protocolo,
      vinculoOrigemId: inicial?.vinculoOrigemId,
      cliente: _clienteController.text.trim(),
      produto: _produtoController.text.trim(),
      prazoIso: DateTime(_prazo.year, _prazo.month, _prazo.day).toIso8601String(),
      prioridade: _prioridade,
      solicitadoPor: inicial?.solicitadoPor ?? widget.usuarioAtual,
      codigoArte: _codigoArteController.text.trim(),
      observacoesComercial: _observacoesComercialController.text.trim(),
      tecidoLiberadoRetirada: _tecidoLiberadoRetirada,
      amostraCor: _amostraCor,
      nomenclaturaSugerida: _nomenclaturaController.text.trim(),
      comercialValidado: _comercialValidado,
      aprovadorComercial: _aprovadorController.text.trim(),
      codigoIndustrial: _codigoIndustrial.trim(),
      etapa: _etapa,
      etapaAtualizadaEmIso: etapaMudou
          ? agora.toIso8601String()
          : (inicial?.etapaAtualizadaEmIso ?? agora.toIso8601String()),
      parecerPcp: _parecerPcp,
      justificativaPcp: _justificativaPcpController.text.trim(),
      gargalosPcp: _gargalosPcpController.text.trim(),
      observacoesPcp: _observacoesPcpController.text.trim(),
      comercialLiberouComGargalo: _comercialLiberouComGargalo,
      ordemFila: inicial?.ordemFila,
      tentativas: _tentativas,
      amostraPronta: _amostraPronta,
      dataSucessoIso: _dataSucessoIso,
      fichaTecnicaAnexo: _fichaTecnicaController.text.trim(),
      qualidadeValidada: _qualidadeValidada,
      artigoCadastrado: _artigoCadastrado,
      amostraEnviada: _amostraEnviada,
      fichaCustoConcluida: _fichaCustoConcluida,
      fotoArtigoAnexo: _fotoArtigoController.text.trim(),
      feedbackCliente: _feedbackCliente,
      pedidoVendaGerado: _pedidoVendaGerado,
      engenhariaValidou: _engenhariaValidou,
      anexoTecelagem: _anexoTecelagemController.text.trim(),
      anexoQualidade: _anexoQualidadeController.text.trim(),
      anexoEmbalagem: _anexoEmbalagemController.text.trim(),
      observacoesEntrega: _observacoesEntregaController.text.trim(),
      criadoEmIso: inicial?.criadoEmIso ?? agora.toIso8601String(),
      atualizadoEmIso: agora.toIso8601String(),
    );
  }

  void _salvar() {
    if (!_validarSolicitacaoBase()) return;
    final item = _construirItem();
    Navigator.of(context).pop(
      _EditorAmostraResult(
        item: item,
        criarNovoDesenvolvimento: _criarNovoDesenvolvimento,
      ),
    );
  }

  String _textoEtapaAtual() {
    switch (_etapa) {
      case _AmostraEtapa.solicitacaoTriagem:
        return 'Solicitacao & Triagem';
      case _AmostraEtapa.planejamentoFila:
        return 'Planejamento & Fila';
      case _AmostraEtapa.execucaoDesenvolvimento:
        return 'Execucao & Desenvolvimento';
      case _AmostraEtapa.entregaFeedback:
        return 'Entrega & Feedback';
    }
  }

  String _labelPrioridade(_AmostraPrioridade prioridade) {
    switch (prioridade) {
      case _AmostraPrioridade.alta:
        return 'Alta';
      case _AmostraPrioridade.media:
        return 'Media';
      case _AmostraPrioridade.baixa:
        return 'Baixa';
    }
  }

  String _labelParecer(_PcpParecer parecer) {
    switch (parecer) {
      case _PcpParecer.pendente:
        return 'Pendente';
      case _PcpParecer.aprovado:
        return 'Aprovado';
      case _PcpParecer.reprovado:
        return 'Reprovado';
    }
  }

  String _labelFeedback(_FeedbackCliente feedback) {
    switch (feedback) {
      case _FeedbackCliente.pendente:
        return 'Pendente';
      case _FeedbackCliente.aprovado:
        return 'Aprovado';
      case _FeedbackCliente.reprovado:
        return 'Reprovado';
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataSucesso = _dataSucessoIso == null
        ? '-'
        : _dateFormat.format(DateTime.parse(_dataSucessoIso!));

    return Scaffold(
      backgroundColor: _kAmostraBg,
      appBar: AppBar(
        backgroundColor: _kAmostraBg,
        foregroundColor: _kAmostraText,
        title: Text(widget.isNovo ? 'Nova solicitacao' : 'Editar amostra'),
        actions: [
          IconButton(
            onPressed: _salvar,
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Salvar',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _kAmostraSurface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _kAmostraBorder),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ResumoChip(
                    titulo: 'Protocolo',
                    valor: _protocolo,
                    icon: Icons.confirmation_number_outlined,
                  ),
                  _ResumoChip(
                    titulo: 'Etapa atual',
                    valor: _textoEtapaAtual(),
                    icon: Icons.flag_outlined,
                  ),
                  _ResumoChip(
                    titulo: 'Codigo industrial',
                    valor: _codigoIndustrial,
                    icon: Icons.qr_code_2_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              titulo: '1. Solicitacao & Triagem',
              subtitulo:
                  'Formulario do comercial, dados iniciais, protocolo, arte, observacoes e aprovacao gerencial.',
              child: Column(
                children: [
                  _buildInput(
                    controller: _clienteController,
                    label: 'Cliente',
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? 'Informe o cliente' : null,
                  ),
                  const SizedBox(height: 12),
                  _buildInput(
                    controller: _produtoController,
                    label: 'Produto',
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? 'Informe o produto' : null,
                  ),
                  const SizedBox(height: 12),
                  _buildDateField(),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<_AmostraPrioridade>(
                    value: _prioridade,
                    dropdownColor: _kAmostraSurface2,
                    decoration: _inputDecoration('Prioridade'),
                    items: _AmostraPrioridade.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(_labelPrioridade(item)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _prioridade = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildInput(
                    controller: _codigoArteController,
                    label: 'Codigo da arte',
                  ),
                  const SizedBox(height: 12),
                  _buildInput(
                    controller: _nomenclaturaController,
                    label: 'Nomenclatura sugerida pelo comercial',
                  ),
                  const SizedBox(height: 12),
                  _buildInput(
                    controller: _observacoesComercialController,
                    label: 'Observacoes comerciais',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    value: _amostraCor,
                    onChanged: (value) => setState(() => _amostraCor = value),
                    title: const Text(
                      'A solicitacao eh de amostra de cor?',
                      style: TextStyle(color: _kAmostraText),
                    ),
                    activeColor: _kAmostraAccent,
                  ),
                  SwitchListTile.adaptive(
                    value: _tecidoLiberadoRetirada,
                    onChanged: (value) =>
                        setState(() => _tecidoLiberadoRetirada = value),
                    title: const Text(
                      'Amostra de tecido liberada para retirada',
                      style: TextStyle(color: _kAmostraText),
                    ),
                    activeColor: _kAmostraAccent,
                  ),
                  const SizedBox(height: 8),
                  _buildInput(
                    controller: _aprovadorController,
                    label: 'Aprovador comercial (gerencia/coordenacao)',
                  ),
                  SwitchListTile.adaptive(
                    value: _comercialValidado,
                    onChanged: (value) =>
                        setState(() => _comercialValidado = value),
                    title: const Text(
                      'Solicitacao validada pela gerencia/coordenacao comercial',
                      style: TextStyle(color: _kAmostraText),
                    ),
                    activeColor: _kAmostraAccent,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: _enviarParaPlanejamento,
                      icon: const Icon(Icons.forward_outlined),
                      label: const Text('Enviar para planejamento'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              titulo: '2. Planejamento & Fila',
              subtitulo:
                  'Analise PCP, gargalos, justificativa, liberacao comercial e posicionamento na fila.',
              child: Column(
                children: [
                  DropdownButtonFormField<_PcpParecer>(
                    value: _parecerPcp,
                    dropdownColor: _kAmostraSurface2,
                    decoration: _inputDecoration('Parecer PCP'),
                    items: _PcpParecer.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(_labelParecer(item)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _parecerPcp = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildInput(
                    controller: _gargalosPcpController,
                    label: 'Gargalos identificados',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  _buildInput(
                    controller: _observacoesPcpController,
                    label: 'Observacoes do PCP para o comercial',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  _buildInput(
                    controller: _justificativaPcpController,
                    label: 'Justificativa em caso de reprova',
                    maxLines: 3,
                  ),
                  SwitchListTile.adaptive(
                    value: _comercialLiberouComGargalo,
                    onChanged: (value) =>
                        setState(() => _comercialLiberouComGargalo = value),
                    title: const Text(
                      'Comercial liberou seguir mesmo com gargalos',
                      style: TextStyle(color: _kAmostraText),
                    ),
                    activeColor: _kAmostraAccent,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _etapa.index >=
                                  _AmostraEtapa.planejamentoFila.index
                              ? _iniciarExecucao
                              : null,
                          icon: const Icon(Icons.play_circle_outline),
                          label: const Text('Iniciar execucao'),
                        ),
                        if (_parecerPcp == _PcpParecer.aprovado ||
                            _comercialLiberouComGargalo)
                          Chip(
                            backgroundColor: _kAmostraPrimary.withOpacity(0.18),
                            label: const Text(
                              'Fila pronta para producao',
                              style: TextStyle(color: _kAmostraText),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              titulo: '3. Execucao & Desenvolvimento',
              subtitulo:
                  'Registro de tentativas, ficha tecnica obrigatoria, cadastro do artigo e validacao da qualidade.',
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: _registrarTentativa,
                      icon: const Icon(Icons.add_task_outlined),
                      label: const Text('Registrar tentativa'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_tentativas.isEmpty)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Nenhuma tentativa registrada ainda.',
                        style: TextStyle(color: _kAmostraMuted),
                      ),
                    )
                  else
                    Column(
                      children: _tentativas.map((tentativa) {
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _kAmostraSurface2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _kAmostraBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    tentativa.sucesso
                                        ? Icons.check_circle_outline
                                        : Icons.build_circle_outlined,
                                    color: tentativa.sucesso
                                        ? const Color(0xFF10B981)
                                        : _kAmostraAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tentativa.descricao.isEmpty
                                          ? 'Tentativa sem descricao'
                                          : tentativa.descricao,
                                      style: const TextStyle(
                                        color: _kAmostraText,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                tentativa.ajuste,
                                style: const TextStyle(color: _kAmostraMuted),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 12),
                  _buildInput(
                    controller: _fichaTecnicaController,
                    label: 'Anexo da ficha tecnica (caminho ou URL)',
                    validator: (value) {
                      if (_etapa.index >=
                              _AmostraEtapa.execucaoDesenvolvimento.index &&
                          _amostraPronta &&
                          (value ?? '').trim().isEmpty) {
                        return 'Informe a ficha tecnica para seguir';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    value: _artigoCadastrado,
                    onChanged: (value) =>
                        setState(() => _artigoCadastrado = value),
                    title: const Text(
                      'Cadastro do artigo concluido pelo PCP',
                      style: TextStyle(color: _kAmostraText),
                    ),
                    activeColor: _kAmostraAccent,
                  ),
                  SwitchListTile.adaptive(
                    value: _qualidadeValidada,
                    onChanged: (value) =>
                        setState(() => _qualidadeValidada = value),
                    title: const Text(
                      'Qualidade validou a ficha tecnica e liberou a etapa 4',
                      style: TextStyle(color: _kAmostraText),
                    ),
                    activeColor: _kAmostraAccent,
                  ),
                  SwitchListTile.adaptive(
                    value: _amostraPronta,
                    onChanged: (value) {
                      setState(() {
                        _amostraPronta = value;
                        _dataSucessoIso =
                            value ? DateTime.now().toIso8601String() : null;
                      });
                    },
                    title: Text(
                      'Amostra pronta com sucesso ($dataSucesso)',
                      style: const TextStyle(color: _kAmostraText),
                    ),
                    activeColor: _kAmostraAccent,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: _liberarParaEntrega,
                      icon: const Icon(Icons.forward_to_inbox_outlined),
                      label: const Text('Liberar para entrega'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              titulo: '4. Entrega & Feedback',
              subtitulo:
                  'Envio da amostra, ficha de custo em paralelo, feedback do cliente e validacao de engenharia.',
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _gerarGuiaPdf,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Gerar guia de envio'),
                        ),
                        if (_feedbackCliente == _FeedbackCliente.reprovado)
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() => _criarNovoDesenvolvimento = true);
                              _showSnack(
                                'Ao salvar, sera criado um novo desenvolvimento vinculado.',
                              );
                            },
                            icon: const Icon(Icons.restart_alt_outlined),
                            label: const Text('Gerar novo desenvolvimento'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    value: _amostraEnviada,
                    onChanged: (value) =>
                        setState(() => _amostraEnviada = value),
                    title: const Text(
                      'Amostra enviada ao comercial/cliente',
                      style: TextStyle(color: _kAmostraText),
                    ),
                    activeColor: _kAmostraAccent,
                  ),
                  SwitchListTile.adaptive(
                    value: _fichaCustoConcluida,
                    onChanged: (value) =>
                        setState(() => _fichaCustoConcluida = value),
                    title: const Text(
                      'Ficha de custo concluida pela controladoria',
                      style: TextStyle(color: _kAmostraText),
                    ),
                    activeColor: _kAmostraAccent,
                  ),
                  const SizedBox(height: 12),
                  _buildInput(
                    controller: _fotoArtigoController,
                    label: 'Foto do artigo (caminho ou URL)',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<_FeedbackCliente>(
                    value: _feedbackCliente,
                    dropdownColor: _kAmostraSurface2,
                    decoration: _inputDecoration('Feedback do cliente'),
                    items: _FeedbackCliente.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(_labelFeedback(item)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _feedbackCliente = value;
                          if (value != _FeedbackCliente.reprovado) {
                            _criarNovoDesenvolvimento = false;
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    value: _pedidoVendaGerado,
                    onChanged: (value) =>
                        setState(() => _pedidoVendaGerado = value),
                    title: const Text(
                      'Gerou pedido de venda',
                      style: TextStyle(color: _kAmostraText),
                    ),
                    activeColor: _kAmostraAccent,
                  ),
                  const SizedBox(height: 12),
                  _buildInput(
                    controller: _anexoTecelagemController,
                    label: 'Informacoes tecnicas de tecelagem',
                  ),
                  const SizedBox(height: 12),
                  _buildInput(
                    controller: _anexoQualidadeController,
                    label: 'Informacoes tecnicas de qualidade',
                  ),
                  const SizedBox(height: 12),
                  _buildInput(
                    controller: _anexoEmbalagemController,
                    label: 'Informacoes tecnicas de embalagem',
                  ),
                  const SizedBox(height: 12),
                  _buildInput(
                    controller: _observacoesEntregaController,
                    label: 'Observacoes de entrega e retorno',
                    maxLines: 3,
                  ),
                  SwitchListTile.adaptive(
                    value: _engenhariaValidou,
                    onChanged: (value) =>
                        setState(() => _engenhariaValidou = value),
                    title: const Text(
                      'Engenharia de processos validou a producao',
                      style: TextStyle(color: _kAmostraText),
                    ),
                    activeColor: _kAmostraAccent,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _salvar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAmostraPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar solicitacao'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField() {
    return InkWell(
      onTap: _selecionarPrazo,
      child: InputDecorator(
        decoration: _inputDecoration('Prazo solicitado'),
        child: Row(
          children: [
            const Icon(Icons.event_outlined, color: _kAmostraAccent),
            const SizedBox(width: 10),
            Text(
              _dateFormat.format(_prazo),
              style: const TextStyle(color: _kAmostraText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: _kAmostraText),
      maxLines: maxLines,
      validator: validator,
      decoration: _inputDecoration(label),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _kAmostraMuted),
      filled: true,
      fillColor: _kAmostraSurface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kAmostraBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kAmostraAccent),
      ),
    );
  }
}

class _IndicadorCard extends StatelessWidget {
  final String titulo;
  final String valor;
  final String descricao;
  final IconData icon;
  final Color accent;

  const _IndicadorCard({
    required this.titulo,
    required this.valor,
    required this.descricao,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kAmostraSurface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kAmostraBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(height: 12),
          Text(
            titulo,
            style: const TextStyle(
              color: _kAmostraMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: const TextStyle(
              color: _kAmostraText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            descricao,
            style: const TextStyle(color: _kAmostraMuted, height: 1.3),
          ),
        ],
      ),
    );
  }
}

class _StageColumn extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final int total;
  final Widget child;

  const _StageColumn({
    required this.titulo,
    required this.subtitulo,
    required this.total,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kAmostraSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kAmostraBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: _kAmostraText,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              CircleAvatar(
                radius: 14,
                backgroundColor: _kAmostraPrimary.withOpacity(0.18),
                child: Text(
                  '$total',
                  style: const TextStyle(
                    color: _kAmostraText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitulo,
            style: const TextStyle(color: _kAmostraMuted, height: 1.35),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ColunaVazia extends StatelessWidget {
  const _ColunaVazia();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kAmostraSurface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kAmostraBorder),
      ),
      child: const Text(
        'Nenhuma amostra nesta etapa.',
        style: TextStyle(color: _kAmostraMuted),
      ),
    );
  }
}

class _AmostraCard extends StatelessWidget {
  final _AmostraSolicitacao item;
  final DateFormat dateFormat;
  final String prioridadeLabel;
  final Color prioridadeColor;
  final VoidCallback onTap;

  const _AmostraCard({
    required this.item,
    required this.dateFormat,
    required this.prioridadeLabel,
    required this.prioridadeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final prazo = dateFormat.format(
      DateTime.tryParse(item.prazoIso) ?? DateTime.now(),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kAmostraSurface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kAmostraBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.produto.isEmpty ? 'Sem produto' : item.produto,
                    style: const TextStyle(
                      color: _kAmostraText,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: prioridadeColor.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    prioridadeLabel,
                    style: TextStyle(
                      color: prioridadeColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.cliente,
              style: const TextStyle(color: _kAmostraMuted),
            ),
            const SizedBox(height: 12),
            _MiniInfo(label: 'Protocolo', valor: item.protocolo),
            _MiniInfo(label: 'Prazo', valor: prazo),
            if (item.codigoIndustrial.isNotEmpty)
              _MiniInfo(label: 'Codigo', valor: item.codigoIndustrial),
            if (item.ordemFila != null)
              _MiniInfo(label: 'Fila', valor: '#${item.ordemFila}'),
            if (item.gargalosPcp.isNotEmpty)
              _MiniInfo(label: 'Gargalo', valor: item.gargalosPcp),
            if (item.tentativas.isNotEmpty)
              _MiniInfo(
                label: 'Tentativas',
                valor: '${item.tentativas.length} registradas',
              ),
            if (item.feedbackCliente != _FeedbackCliente.pendente)
              _MiniInfo(
                label: 'Feedback',
                valor: item.feedbackCliente == _FeedbackCliente.aprovado
                    ? 'Aprovado'
                    : 'Reprovado',
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final String label;
  final String valor;

  const _MiniInfo({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: _kAmostraMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: valor,
              style: const TextStyle(color: _kAmostraText),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumoChip extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icon;

  const _ResumoChip({
    required this.titulo,
    required this.valor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kAmostraSurface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kAmostraBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _kAmostraAccent, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  color: _kAmostraMuted,
                  fontSize: 12,
                ),
              ),
              Text(
                valor,
                style: const TextStyle(
                  color: _kAmostraText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final Widget child;

  const _SectionCard({
    required this.titulo,
    required this.subtitulo,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kAmostraSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kAmostraBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              color: _kAmostraText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitulo,
            style: const TextStyle(color: _kAmostraMuted, height: 1.35),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

_AmostraPrioridade _prioridadeFromString(dynamic raw) {
  final texto = (raw ?? '').toString().trim().toLowerCase();
  switch (texto) {
    case 'alta':
      return _AmostraPrioridade.alta;
    case 'baixa':
      return _AmostraPrioridade.baixa;
    default:
      return _AmostraPrioridade.media;
  }
}

_AmostraEtapa _etapaFromString(dynamic raw) {
  final texto = (raw ?? '').toString().trim();
  return _AmostraEtapa.values.firstWhere(
    (item) => item.name == texto,
    orElse: () => _AmostraEtapa.solicitacaoTriagem,
  );
}

_PcpParecer _parecerFromString(dynamic raw) {
  final texto = (raw ?? '').toString().trim();
  return _PcpParecer.values.firstWhere(
    (item) => item.name == texto,
    orElse: () => _PcpParecer.pendente,
  );
}

_FeedbackCliente _feedbackFromString(dynamic raw) {
  final texto = (raw ?? '').toString().trim();
  return _FeedbackCliente.values.firstWhere(
    (item) => item.name == texto,
    orElse: () => _FeedbackCliente.pendente,
  );
}
