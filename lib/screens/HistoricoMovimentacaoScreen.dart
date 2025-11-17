import 'package:flutter/material.dart';
import 'package:tracx/models/HistoricoMov.dart';
import 'package:tracx/services/movimentacao_service.dart';
import 'package:intl/intl.dart';


class HistoricoMovimentacaoScreen extends StatefulWidget {
  final int nrOrdem; // NrOrdem = 0 busca todas
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

  // COR FIXA: Uma cor única para todos os itens, sem depender do tipo de movimentação.
  final Color _defaultIconColor = Colors.blue.shade700;

  @override
  void initState() {
    super.initState();
    // Busca o histórico, passando o nrOrdem (pode ser 0 para buscar todos)
    _historicoFuture = MovimentacaoService.buscarHistorico(widget.nrOrdem);
  }

  // REMOVIDO: O método _getMovimentacaoStyle não é mais necessário.

  @override
  Widget build(BuildContext context) {
    // Ajuste o título para exibir "Movimentação Geral" se NrOrdem for 0
    final String appBarTitle =
        widget.titulo ??
        (widget.nrOrdem > 0
            ? 'Histórico OP: ${widget.nrOrdem}'
            : 'Movimentação Geral');

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(appBarTitle),
        elevation: 0,
        backgroundColor: const Color(0xFFCD1818),
        foregroundColor: Colors.white // Cor do AppBar (opcional)
      ),
      body: FutureBuilder<List<HistoricoMov>>(
        future: _historicoFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Erro ao carregar histórico: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            );
          }

          final historico = snapshot.data ?? [];

          if (historico.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_toggle_off,
                    size: 60,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma movimentação encontrada.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          // A API retorna do mais novo para o mais antigo, revertemos para a Timeline.
          final historicoReverso = historico.reversed.toList();

          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: ListView.builder(
              itemCount: historicoReverso.length,
              itemBuilder: (context, index) {
                final mov = historicoReverso[index];
                final isLast = index == historicoReverso.length - 1;
                final isFirst = index == 0;
                // Ícone e cor agora são fixos.
                const IconData fixedIcon = Icons.swap_horiz;
                final Color fixedColor = _defaultIconColor;

                return _TimelineItem(
                  movimentacao: mov,
                  isFirst: isFirst,
                  isLast: isLast,
                  icon: fixedIcon,
                  iconColor: fixedColor,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// =========================================================================
// WIDGET DO ITEM DA LINHA DO TEMPO (TimelineItem APRIMORADO)
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

  // Função auxiliar para construir uma linha de informação (Título + Valor)
  Widget _buildInfoRow({
    required String label,
    required String value,
    bool isBold = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }

  // Função auxiliar para construir a Rota "De -> Para"
  Widget _buildRouteText({
    required String origem,
    required String destino,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rota de Movimentação:',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                origem,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            Icon(Icons.arrow_right_alt, color: color, size: 20),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Text(
                  destino,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
    final formattedDate = dateFormat.format(
      movimentacao.dataMovimentacao.toLocal(),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Linha do Tempo Visual
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // Linha Acima (invisível no primeiro item)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isFirst ? Colors.transparent : Colors.grey.shade300,
                  ),
                ),
                // Círculo do Evento
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: iconColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: iconColor.withOpacity(0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                // Linha Abaixo (invisível no último item)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : Colors.grey.shade300,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 2. Conteúdo do Cartão
          Expanded(
            child: Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: iconColor.withOpacity(0.4), width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // REMOVIDO: Título (Tipo de Movimentação)

                    // OP (NrOrdem)
                    _buildInfoRow(
                      label: 'Ordem de Produção (OP)',
                      value: movimentacao.nrOrdem.toString(),
                      isBold: true,
                    ),
                    const Divider(height: 24, color: Colors.black12),

                    // Rota (De -> Para)
                    _buildRouteText(
                      origem: movimentacao.localizacaoOrigem,
                      destino: movimentacao.localizacaoDestino,
                      color: Colors.grey.shade700,
                    ),
                    const Divider(height: 24, color: Colors.black12),

                    // Data, Hora e Conferente
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Data/Hora
                        _buildInfoRow(label: 'Data/Hora', value: formattedDate),
                        // Conferente
                        _buildInfoRow(
                          label: 'Conferente',
                          value: movimentacao.conferente,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
