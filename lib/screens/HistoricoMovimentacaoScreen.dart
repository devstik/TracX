import 'package:flutter/material.dart';
import 'package:tracx/models/HistoricoMov.dart';
import 'package:tracx/services/movimentacao_service.dart';
import 'package:intl/intl.dart';

// =========================================================================
// 🎨 PALETA OFICIAL (PADRÃO HOME + SPLASH)
// =========================================================================
const Color _kPrimaryColor = Color(0xFF2563EB); // Azul principal (moderno)
const Color _kAccentColor = Color(0xFF60A5FA); // Azul claro premium

const Color _kBgTop = Color(0xFF050A14);
const Color _kBgBottom = Color(0xFF0B1220);

const Color _kSurface = Color(0xFF101B34);
const Color _kSurface2 = Color(0xFF0F172A);

const Color _kTextPrimary = Color(0xFFF9FAFB);
const Color _kTextSecondary = Color(0xFF9CA3AF);

// borda mais visível (antes tava apagada demais)
const Color _kBorderSoft = Color(0x33FFFFFF);

class HistoricoMovimentacaoScreen extends StatefulWidget {
  final int nrOrdem; // NrOrdem inicial. 0 busca todas.
  final String? titulo;

  const HistoricoMovimentacaoScreen({
    super.key,
    required this.nrOrdem,
    this.titulo,
  });

  @override
  State<HistoricoMovimentacaoScreen> createState() =>
      _HistoricoMovimentacaoScreenState();
}

class _HistoricoMovimentacaoScreenState
    extends State<HistoricoMovimentacaoScreen> {
  late Future<List<HistoricoMov>> _historicoFuture;

  late int _filterNrOrdem;
  final TextEditingController _nrOrdemController = TextEditingController();

  // Controle de ordenação
  bool _mostrarMaisRecentesPrimeiro = true;

  @override
  void initState() {
    super.initState();
    _filterNrOrdem = widget.nrOrdem;
    _nrOrdemController.text = _filterNrOrdem > 0
        ? _filterNrOrdem.toString()
        : '';
    _fetchHistorico(_filterNrOrdem);
  }

  void _fetchHistorico(int nrOrdem) {
    setState(() {
      _historicoFuture = MovimentacaoService.buscarHistorico(nrOrdem);
      _filterNrOrdem = nrOrdem;
    });
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: _kSurface,
          title: const Text(
            'Filtrar por Ordem de Produção',
            style: TextStyle(color: _kTextPrimary),
          ),
          content: TextField(
            controller: _nrOrdemController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: _kTextPrimary),
            decoration: InputDecoration(
              labelText: 'Número da OP',
              labelStyle: const TextStyle(color: _kTextSecondary),
              hintText: 'Digite 0 para ver todas',
              hintStyle: TextStyle(color: _kTextSecondary.withOpacity(0.7)),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: _kBorderSoft),
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: _kAccentColor, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onSubmitted: (_) => _applyFilter(context),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text(
                'Cancelar',
                style: TextStyle(color: _kTextSecondary),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Filtrar'),
              onPressed: () => _applyFilter(context),
            ),
          ],
        );
      },
    );
  }

  void _applyFilter(BuildContext context) {
    Navigator.of(context).pop();

    final nrOrdemText = _nrOrdemController.text.trim();
    int newNrOrdem = 0;

    if (nrOrdemText.isNotEmpty) {
      newNrOrdem = int.tryParse(nrOrdemText) ?? 0;
    }

    if (newNrOrdem != _filterNrOrdem) {
      _fetchHistorico(newNrOrdem);
    }
  }

  @override
  void dispose() {
    _nrOrdemController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String appBarTitle =
        widget.titulo ??
        (_filterNrOrdem > 0
            ? 'Histórico OP: $_filterNrOrdem'
            : 'Movimentação Geral');

    return Scaffold(
      backgroundColor: _kBgBottom,
      appBar: AppBar(
        centerTitle: true,
        title: Text(appBarTitle),
        elevation: 0,
        backgroundColor: _kBgBottom,
        foregroundColor: _kTextPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: "Filtrar OP",
            onPressed: _showFilterDialog,
          ),

          // BOTÃO ORDENAR
          IconButton(
            tooltip: _mostrarMaisRecentesPrimeiro
                ? "Mostrando: Mais recentes"
                : "Mostrando: Mais antigos",
            icon: Icon(
              _mostrarMaisRecentesPrimeiro
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
            ),
            onPressed: () {
              setState(() {
                _mostrarMaisRecentesPrimeiro = !_mostrarMaisRecentesPrimeiro;
              });
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_kBgTop, _kBgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: FutureBuilder<List<HistoricoMov>>(
          future: _historicoFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _kAccentColor),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Erro ao carregar histórico: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _kAccentColor),
                  ),
                ),
              );
            }

            // ORDENAÇÃO
            final historicoOrdenado = List<HistoricoMov>.from(
              snapshot.data ?? [],
            );

            historicoOrdenado.sort((a, b) {
              if (_mostrarMaisRecentesPrimeiro) {
                return b.dataMovimentacao.compareTo(a.dataMovimentacao);
              } else {
                return a.dataMovimentacao.compareTo(b.dataMovimentacao);
              }
            });

            if (historicoOrdenado.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history_toggle_off,
                        size: 70,
                        color: _kTextSecondary.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _filterNrOrdem > 0
                            ? 'Nenhuma movimentação encontrada para a OP $_filterNrOrdem.'
                            : 'Nenhuma movimentação encontrada.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _kTextSecondary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: ListView.builder(
                itemCount: historicoOrdenado.length,
                itemBuilder: (context, index) {
                  final mov = historicoOrdenado[index];

                  final isLast = index == historicoOrdenado.length - 1;
                  final isFirst = index == 0;

                  return _TimelineItem(
                    movimentacao: mov,
                    isFirst: isFirst,
                    isLast: isLast,
                    icon: Icons.swap_horiz_rounded,
                    iconColor: _kPrimaryColor,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

// =========================================================================
// ITEM DA LINHA DO TEMPO
// =========================================================================

class _TimelineItem extends StatelessWidget {
  final HistoricoMov movimentacao;
  final bool isFirst;
  final bool isLast;
  final IconData icon;
  final Color iconColor;

  const _TimelineItem({
    required this.movimentacao,
    required this.isFirst,
    required this.isLast,
    required this.icon,
    required this.iconColor,
  });

  Widget _buildInfoRow({
    required String label,
    required String value,
    bool isBold = false,
    Color? valueColor,
    IconData? icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: _kTextSecondary),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: _kTextSecondary),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                  color: valueColor ?? _kTextPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRouteText({required String origem, required String destino}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Movimentação',
          style: TextStyle(fontSize: 12, color: _kTextSecondary),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _kSurface2.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kBorderSoft, width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  origem,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _kTextPrimary,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Icon(
                  Icons.arrow_right_alt_rounded,
                  size: 26,
                  color: _kAccentColor,
                ),
              ),
              Expanded(
                child: Text(
                  destino,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _kTextPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy • HH:mm:ss');
    final formattedDate = dateFormat.format(
      movimentacao.dataMovimentacao.toLocal(),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // LINHA DO TEMPO
          SizedBox(
            width: 42,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: isFirst ? Colors.transparent : _kBorderSoft,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: iconColor.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : _kBorderSoft,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // CARD CONTEÚDO
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kSurface.withOpacity(0.92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _kBorderSoft, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // TOPO: OP
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _kPrimaryColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _kPrimaryColor.withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          "OP ${movimentacao.nrOrdem}",
                          style: const TextStyle(
                            color: _kPrimaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.local_shipping_rounded,
                        size: 18,
                        color: _kAccentColor,
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ROTA
                  _buildRouteText(
                    origem: movimentacao.localizacaoOrigem,
                    destino: movimentacao.localizacaoDestino,
                  ),

                  const SizedBox(height: 16),

                  // INFO DATA / CONFERENTE
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoRow(
                          label: 'Data/Hora',
                          value: formattedDate,
                          icon: Icons.access_time_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildInfoRow(
                          label: 'Conferente',
                          value: movimentacao.conferente,
                          icon: Icons.person_rounded,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
