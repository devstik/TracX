import 'package:flutter/material.dart';
import 'package:tracx/models/HistoricoMov.dart';
import 'package:tracx/services/movimentacao_service.dart';
import 'package:intl/intl.dart';

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

  // 1. Variáveis de Estado para o Filtro
  late int _filterNrOrdem;
  final TextEditingController _nrOrdemController = TextEditingController();

  // COR PRINCIPAL
  static const Color _primaryColor = Color(0xFFCD1818);

  @override
  void initState() {
    super.initState();
    _filterNrOrdem = widget.nrOrdem; // Inicializa com o valor recebido
    _nrOrdemController.text = _filterNrOrdem > 0
        ? _filterNrOrdem.toString()
        : '';
    _fetchHistorico(_filterNrOrdem);
  }

  // Novo método para buscar o histórico com base no filtro
  void _fetchHistorico(int nrOrdem) {
    setState(() {
      _historicoFuture = MovimentacaoService.buscarHistorico(nrOrdem);
      _filterNrOrdem = nrOrdem; // Atualiza o estado do filtro
    });
  }

  // Método para exibir o diálogo de filtro
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Filtrar por Ordem de Produção'),
          content: TextField(
            controller: _nrOrdemController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Número da OP',
              hintText: 'Digite 0 para ver todas',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _applyFilter(context),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
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

  // Método para aplicar o filtro
  void _applyFilter(BuildContext context) {
    Navigator.of(context).pop(); // Fecha o diálogo

    final nrOrdemText = _nrOrdemController.text.trim();
    int newNrOrdem = 0;
    if (nrOrdemText.isNotEmpty) {
      // Tenta converter para inteiro, se falhar, usa 0
      newNrOrdem = int.tryParse(nrOrdemText) ?? 0;
    }

    // Aplica o novo filtro se for diferente do atual
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
    // Título dinâmico que reflete o filtro atual
    final String appBarTitle =
        widget.titulo ??
        (_filterNrOrdem > 0
            ? 'Histórico OP: $_filterNrOrdem'
            : 'Movimentação Geral');

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(appBarTitle),
        elevation: 0,
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        actions: [
          // 2. Botão de Filtro
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
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
                  style: TextStyle(color: _primaryColor),
                ),
              ),
            );
          }

          final historicoOrdenado = snapshot.data ?? [];

          if (historicoOrdenado.isEmpty) {
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
                    _filterNrOrdem > 0
                        ? 'Nenhuma movimentação encontrada para a OP $_filterNrOrdem.'
                        : 'Nenhuma movimentação encontrada.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          // O restante do código do ListView.builder permanece o mesmo
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: ListView.builder(
              itemCount: historicoOrdenado.length,
              itemBuilder: (context, index) {
                final mov = historicoOrdenado[index];

                // Se a API retorna do mais novo para o mais antigo, o 'isFirst' é o index 0
                // e o 'isLast' é o último item (tamanho da lista - 1)
                final isLast = index == historicoOrdenado.length - 1;
                final isFirst = index == 0;

                const IconData fixedIcon = Icons.swap_horiz;
                final Color highlightColor = _primaryColor;

                return _TimelineItem(
                  movimentacao: mov,
                  isFirst: isFirst,
                  isLast: isLast,
                  icon: fixedIcon,
                  iconColor: highlightColor,
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
    Color? valueColor,
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
            color: valueColor ?? Colors.grey.shade800,
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
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Origem
            Flexible(
              child: Text(
                origem,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Icon(
                Icons.arrow_right_alt,
                color: Colors.black54,
                size: 22,
              ),
            ),
            // Destino
            Flexible(
              child: Text(
                destino,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
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
    final dateFormat = DateFormat('dd/MM/yyyy • HH:mm:ss');
    final formattedDate = dateFormat.format(
      movimentacao.dataMovimentacao.toLocal(),
    );

    // Pega a cor principal novamente para o destaque
    const Color primaryColor = Color(0xFFCD1818);

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
                        color: iconColor.withOpacity(0.4),
                        blurRadius: 6,
                        spreadRadius: 1,
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
          const SizedBox(width: 12),
          // 2. Conteúdo do Cartão
          Expanded(
            child: Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: iconColor.withOpacity(0.5), width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // OP (NrOrdem) - Em destaque no topo do cartão
                    _buildInfoRow(
                      label: 'Ordem de Produção (OP)',
                      value: movimentacao.nrOrdem.toString(),
                      isBold: true,
                      valueColor: primaryColor,
                    ),
                    const Divider(height: 20, color: Colors.black12),

                    // Rota (De -> Para) - Em destaque
                    _buildRouteText(
                      origem: movimentacao.localizacaoOrigem,
                      destino: movimentacao.localizacaoDestino,
                      color: Colors.grey.shade800,
                    ),
                    const Divider(height: 20, color: Colors.black12),

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
