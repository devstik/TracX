import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/etiquetas_service.dart';
import '../services/mov_estoque_service.dart';

class MovEstoqueScreen extends StatefulWidget {
  const MovEstoqueScreen({super.key});

  @override
  State<MovEstoqueScreen> createState() => _MovEstoqueScreenState();
}

class _MovEstoqueScreenState extends State<MovEstoqueScreen> {
  static const _bg = Color(0xFF020617);
  static const _surface = Color(0xFF172033);
  static const _field = Color(0xFF0F172A);
  static const _border = Color(0xFF334155);
  static const _gold = Color(0xFFD8B840);
  static const _info = Color(0xFF38BDF8);
  static const _success = Color(0xFF16A34A);
  static const _error = Color(0xFFDC2626);

  final _unidadeController = TextEditingController();
  final _artigoController = TextEditingController();
  final _numero = NumberFormat.decimalPattern('pt_BR');
  final _dataApi = DateFormat('yyyy-MM-dd');

  DateTime? _dataInicial;
  DateTime? _dataFinal;
  int _cdArtigo = 0;
  bool _loading = false;
  String? _erro;
  List<MovEstoqueItem> _resultados = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dataInicial = DateTime(now.year, now.month, 1);
    _dataFinal = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _unidadeController.dispose();
    _artigoController.dispose();
    super.dispose();
  }

  Future<void> _consultar() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final data = await MovEstoqueService.consultar(
        cdUne: int.tryParse(_unidadeController.text.trim()) ?? 0,
        dataInicial: _dataInicial == null ? null : _dataApi.format(_dataInicial!),
        dataFinal: _dataFinal == null ? null : _dataApi.format(_dataFinal!),
        cdArtigo: _cdArtigo > 0
            ? _cdArtigo
            : int.tryParse(_artigoController.text.trim()) ?? 0,
      );
      if (!mounted) return;
      setState(() {
        _resultados = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _limpar() {
    setState(() {
      _unidadeController.clear();
      _artigoController.clear();
      _cdArtigo = 0;
      _resultados = const [];
      _erro = null;
      final now = DateTime.now();
      _dataInicial = DateTime(now.year, now.month, 1);
      _dataFinal = DateTime(now.year, now.month, now.day);
    });
  }

  Future<void> _selecionarData({required bool inicial}) async {
    final atual = inicial ? _dataInicial : _dataFinal;
    final selecionada = await showDatePicker(
      context: context,
      initialDate: atual ?? DateTime.now(),
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
    if (selecionada == null) return;
    setState(() {
      if (inicial) {
        _dataInicial = selecionada;
      } else {
        _dataFinal = selecionada;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final grupos = _agrupar(_resultados);
    final total = _resultados
        .where((item) => item.nivel == 1)
        .fold<double>(0, (sum, item) => sum + item.qtEntrada);
    final artigos = _resultados.where((item) => item.nivel == 2).length;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Movimentação de Estoque',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _consultar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _buildFiltros(),
            const SizedBox(height: 14),
            if (_erro != null) _buildError(_erro!),
            if (_loading)
              const _MovLoadingCard()
            else if (_resultados.isEmpty)
              const _MovEmptyCard()
            else ...[
              _buildResumo(total: total, dias: grupos.length, artigos: artigos),
              const SizedBox(height: 12),
              ...grupos.map(_buildDiaCard),
            ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: _gold),
              SizedBox(width: 8),
              Text(
                'Consultar movimentação de estoque',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 760;
              final fields = [
                _dateField('Data inicial', _dataInicial, () {
                  _selecionarData(inicial: true);
                }),
                _dateField('Data final', _dataFinal, () {
                  _selecionarData(inicial: false);
                }),
                _textField(
                  controller: _unidadeController,
                  label: 'Unidade',
                  hint: 'Opcional',
                  icon: Icons.apartment_rounded,
                  numeric: true,
                ),
                _MovArtigoAutocomplete(
                  controller: _artigoController,
                  onChanged: () => _cdArtigo = 0,
                  onSelected: (artigo) {
                    _cdArtigo = _toInt(artigo['CdObj']);
                    _artigoController.text =
                        (artigo['NmObj'] ?? '').toString().trim();
                  },
                ),
              ];

              if (narrow) {
                return Column(
                  children: [
                    for (final field in fields) ...[
                      field,
                      const SizedBox(height: 10),
                    ],
                    _filterButtons(),
                  ],
                );
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: fields[0]),
                      const SizedBox(width: 10),
                      Expanded(child: fields[1]),
                      const SizedBox(width: 10),
                      Expanded(child: fields[2]),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(flex: 3, child: fields[3]),
                      const SizedBox(width: 10),
                      Expanded(flex: 2, child: _filterButtons()),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _filterButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: _border),
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _loading ? null : _limpar,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Limpar'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _loading ? null : _consultar,
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search_rounded),
            label: Text(_loading ? 'Consultando' : 'Consultar'),
          ),
        ),
      ],
    );
  }

  Widget _buildResumo({
    required double total,
    required int dias,
    required int artigos,
  }) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _ResumoChip(icon: Icons.calendar_month, label: 'Dias', value: '$dias'),
        _ResumoChip(
          icon: Icons.category_outlined,
          label: 'Artigos',
          value: '$artigos',
        ),
        _ResumoChip(
          icon: Icons.straighten_rounded,
          label: 'Total de entrada',
          value: _numero.format(total),
        ),
      ],
    );
  }

  Widget _buildDiaCard(_MovDia dia) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          iconColor: _gold,
          collapsedIconColor: Colors.white54,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          title: Text(
            dia.data,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            '${dia.artigos.length} artigos - ${_numero.format(dia.total)} m',
            style: const TextStyle(color: Colors.white60),
          ),
          children: dia.artigos.map(_buildArtigoCard).toList(),
        ),
      ),
    );
  }

  Widget _buildArtigoCard(_MovArtigo artigo) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _info.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.category_outlined, color: _info),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artigo.nome,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Código ${artigo.codigo}',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
              Text(
                _numero.format(artigo.total),
                style: const TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          if (artigo.itens.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: _border),
            const SizedBox(height: 8),
            ...artigo.itens.map(_buildItemRow),
          ],
        ],
      ),
    );
  }

  Widget _buildItemRow(MovEstoqueItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          const Icon(Icons.subdirectory_arrow_right, color: Colors.white38, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              item.artigo,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _numero.format(item.qtEntrada),
            style: const TextStyle(
              color: _success,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _error),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: _error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _dateField(String label, DateTime? value, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: InputDecorator(
        decoration: _decoration(label, Icons.calendar_month_rounded),
        child: Text(
          value == null ? 'Sem filtro' : DateFormat('dd/MM/yyyy').format(value),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool numeric = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      decoration: _decoration(label, icon).copyWith(hintText: hint),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: _gold),
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

  List<_MovDia> _agrupar(List<MovEstoqueItem> items) {
    final dias = <_MovDia>[];
    _MovDia? diaAtual;
    _MovArtigo? artigoAtual;

    for (final item in items) {
      if (item.nivel == 1) {
        diaAtual = _MovDia(data: item.artigo, total: item.qtEntrada);
        dias.add(diaAtual);
        artigoAtual = null;
        continue;
      }

      diaAtual ??= _MovDia(data: item.ordem1, total: 0);
      if (!dias.contains(diaAtual)) dias.add(diaAtual);

      if (item.nivel == 2) {
        artigoAtual = _MovArtigo(
          codigo: item.codigo,
          nome: item.artigo,
          total: item.qtEntrada,
        );
        diaAtual.artigos.add(artigoAtual);
        continue;
      }

      if (item.nivel == 3) {
        artigoAtual ??= _MovArtigo(
          codigo: item.mae,
          nome: 'Artigo ${item.mae}',
          total: 0,
        );
        if (!diaAtual.artigos.contains(artigoAtual)) {
          diaAtual.artigos.add(artigoAtual);
        }
        artigoAtual.itens.add(item);
      }
    }
    return dias;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _MovDia {
  _MovDia({required this.data, required this.total});

  final String data;
  final double total;
  final List<_MovArtigo> artigos = [];
}

class _MovArtigo {
  _MovArtigo({
    required this.codigo,
    required this.nome,
    required this.total,
  });

  final String codigo;
  final String nome;
  final double total;
  final List<MovEstoqueItem> itens = [];
}

class _MovArtigoAutocomplete extends StatefulWidget {
  const _MovArtigoAutocomplete({
    required this.controller,
    required this.onSelected,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<Map<String, dynamic>> onSelected;
  final VoidCallback onChanged;

  @override
  State<_MovArtigoAutocomplete> createState() => _MovArtigoAutocompleteState();
}

class _MovArtigoAutocompleteState extends State<_MovArtigoAutocomplete> {
  Timer? _debounce;
  List<Map<String, dynamic>> _opcoes = [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _buscar(String value) {
    widget.onChanged();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (value.trim().length < 2) {
        if (mounted) setState(() => _opcoes = []);
        return;
      }
      setState(() => _loading = true);
      final data = await EtiquetasService.buscarArtigosPorNome(value);
      if (!mounted) return;
      setState(() {
        _opcoes = data.take(8).toList();
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
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            labelText: 'Artigo',
            hintText: 'Digite nome ou código',
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFD8B840)),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
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
            constraints: const BoxConstraints(maxHeight: 220),
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

class _ResumoChip extends StatelessWidget {
  const _ResumoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF172033),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFD8B840), size: 18),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white54),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MovLoadingCard extends StatelessWidget {
  const _MovLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _MovEmptyCard extends StatelessWidget {
  const _MovEmptyCard();

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
          Icon(Icons.inventory_2_outlined, color: Color(0xFFD8B840), size: 34),
          SizedBox(height: 10),
          Text(
            'Informe os filtros e clique em Consultar.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 6),
          Text(
            'A consulta mostra as entradas agrupadas por data, artigo e item.',
            style: TextStyle(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
