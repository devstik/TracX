import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tracx/models/registro.dart';
import 'package:tracx/services/movimentacao_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:tracx/models/HistoricoMov.dart';

class Localizacaoscreen extends StatefulWidget {
  final String conferente;
  final bool isAdmin;

  const Localizacaoscreen({
    super.key,
    required this.conferente,
    required this.isAdmin,
  });

  @override
  _LocalizacaoscreenState createState() => _LocalizacaoscreenState();
}

class _LocalizacaoscreenState extends State<Localizacaoscreen>
    with SingleTickerProviderStateMixin {
  static const String _ADMIN_MOVE_PASSWORD = 'admin123456';

  late TabController _tabController;

  // Variáveis de estado para o filtro
  String _searchQuery = ''; // Filtro de OP ou Artigo
  DateTime? _filterDate; // Filtro de Data

  // Mapa para guardar o Future de cada aba e forçar recarregamento
  final Map<String, Future<List<Registro>>> _futureMap = {};

  static const Map<String, int> _locOrder = {
    'Mesas': 3,
    'Imatecs': 4,
    'Controle de Qualidade': 5,
    'Apontamento': 6,
    'Túnel': 7,
    'Expedição': 8,
  };

  static const Map<String, String> _tabToFullLoc = {
    'Loc 3': 'Mesas',
    'Loc 4': 'Imatecs',
    'Loc 5': 'Controle de Qualidade',
    'Loc 6': 'Apontamento',
    'Loc 7': 'Túnel',
    'Loc 8': 'Expedição',
  };

  static const List<String> _tabNames = [
    'Loc 3',
    'Loc 4',
    'Loc 5',
    'Loc 6',
    'Loc 7',
    'Loc 8',
  ];

  static const List<String> _allLocations = [
    'Mesas',
    'Imatecs',
    'Controle de Qualidade',
    'Apontamento',
    'Túnel',
    'Expedição',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabNames.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Inicializa/Recarrega o Future para a aba
  Future<List<Registro>> _getFutureForTab(String tabLocation) {
    if (!_futureMap.containsKey(tabLocation)) {
      _futureMap[tabLocation] = _buscarRegistrosPorLocalizacao(tabLocation);
    }
    return _futureMap[tabLocation]!;
  }

  // Recarrega todos os Futures quando os filtros mudam
  void _reloadAllFutures() {
    _futureMap.clear();
    setState(() {});
  }

  // Função para obter a cor com base no nome da Tab/Localização
  Color _getTabColor(String tabLocation) {
    switch (tabLocation) {
      case 'Loc 3':
        return const Color(0xFF2E7D32);
      case 'Loc 4':
        return const Color(0xFFE65100);
      case 'Loc 5':
        return const Color(0xFF42A5F5);
      case 'Loc 6':
        return const Color(0xFF1565C0);
      case 'Loc 7':
        return const Color(0xFF6A1B9A);
      case 'Loc 8':
        return const Color(0xFF00695C);
      default:
        return const Color(0xFFCD1818);
    }
  }

  Future<bool> _verifyPassword(String username, String password) async {
    if (!widget.isAdmin) {
      return false;
    }
    return password == _ADMIN_MOVE_PASSWORD;
  }

  // CORRIGIDO: Busca de registros com filtros
  Future<List<Registro>> _buscarRegistrosPorLocalizacao(
    String tabLocation,
  ) async {
    final targetLocation = _tabToFullLoc[tabLocation];
    if (targetLocation == null) return [];

    final dataFormatada = _filterDate != null
        ? DateFormat('yyyy-MM-dd').format(_filterDate!)
        : null;

    try {
      // Monta os parâmetros da query
      final queryParams = <String, String>{};

      // Sempre adiciona a localização
      queryParams['localizacao'] = targetLocation;

      // Adiciona filtro de busca se existir
      if (_searchQuery.isNotEmpty) {
        queryParams['filtro'] = _searchQuery;
      }

      // Adiciona filtro de data se existir
      if (dataFormatada != null) {
        queryParams['data'] = dataFormatada;
      }

      final uri = Uri.parse(
        'http://168.190.90.2:5000/consulta/movimentacao',
      ).replace(queryParameters: queryParams);

      print('🔍 Buscando registros: $uri'); // Debug

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);

        print(
          '📦 Registros encontrados para $targetLocation: ${jsonList.length}',
        ); // Debug

        return jsonList.map((jsonItem) {
          return Registro(
            ordemProducao: jsonItem['NrOrdem'] ?? 0,
            artigo: jsonItem['Artigo'] ?? '',
            cor: jsonItem['Cor'] ?? '',
            quantidade: jsonItem['Quantidade'] ?? 0,
            peso: jsonItem['Peso'] != null
                ? double.tryParse(jsonItem['Peso'].toString()) ?? 0.0
                : 0.0,
            conferente: jsonItem['Conferente'] ?? '',
            turno: jsonItem['Turno'] ?? '',
            metros: jsonItem['Metros'] != null
                ? double.tryParse(jsonItem['Metros'].toString()) ?? 0.0
                : 0.0,
            numCorte: jsonItem['NumCorte'] ?? '',
            volumeProg: jsonItem['VolumeProg'] != null
                ? double.tryParse(jsonItem['VolumeProg'].toString()) ?? 0.0
                : 0.0,
            data: jsonItem['DataEntrada'] != null
                ? DateTime.parse(jsonItem['DataEntrada'])
                : DateTime.now(),
            dataTingimento: jsonItem['DataTingimento'] ?? '',
            localizacao: jsonItem['Localizacao'] ?? '',
            dataMovimentacao: jsonItem['DataMovimentacao'] != null
                ? DateTime.parse(jsonItem['DataMovimentacao'])
                : null,
            caixa: jsonItem['Caixa'] ?? '',
          );
        }).toList();
      } else {
        print('❌ Erro na API: ${response.statusCode}'); // Debug
        throw Exception(
          'Falha ao buscar registros da API: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('❌ Erro ao buscar registros: $e'); // Debug
      return [];
    }
  }

  List<String> _getValidNextOptions(String? currentLocation) {
    if (currentLocation == 'Mesas') {
      return ['Apontamento'];
    } else if (currentLocation == 'Imatecs') {
      return ['Controle de Qualidade', 'Apontamento'];
    } else if (currentLocation == 'Controle de Qualidade') {
      return ['Apontamento'];
    } else if (currentLocation == 'Apontamento') {
      return ['Túnel'];
    } else if (currentLocation == 'Túnel') {
      return ['Expedição'];
    }
    return [];
  }

  String? _getValidPreviousLocation(String? currentLocation) {
    if (currentLocation == 'Expedição') {
      return 'Túnel';
    } else if (currentLocation == 'Túnel') {
      return 'Apontamento';
    } else if (currentLocation == 'Apontamento') {
      return 'Imatecs';
    } else if (currentLocation == "Controle de Qualidade") {
      return 'Imatecs';
    } else if (currentLocation == 'Imatecs') {
      return 'Mesas';
    }
    return null;
  }

  Future<void> _updateRegistroLocationCompleta(
    Registro registro,
    String newLocation,
  ) async {
    try {
      final localizacaoOrigem = registro.localizacao ?? 'N/A';
      final isRollback =
          _locOrder[newLocation]! < _locOrder[registro.localizacao]!;

      final isAdminMove =
          _locOrder[newLocation]! > _locOrder[registro.localizacao]! &&
          !_getValidNextOptions(registro.localizacao).contains(newLocation);

      String tipoMovimentacao;
      if (isRollback) {
        tipoMovimentacao = 'ROLLBACK';
      } else if (isAdminMove) {
        tipoMovimentacao = 'ADMIN';
      } else {
        tipoMovimentacao = 'NORMAL';
      }

      final dataMovimentacao = DateTime.now();

      final sucesso = await MovimentacaoService.registrarMovimentacaoCompleta(
        idPedido: registro.ordemProducao ?? 0,
        localizacaoOrigem: localizacaoOrigem,
        localizacaoDestino: newLocation,
        conferente: widget.conferente,
        dataMovimentacao: dataMovimentacao,
        tipoMovimentacao: tipoMovimentacao,
      );

      if (!sucesso) {
        throw Exception(
          'Falha ao registrar movimentação completa no servidor.',
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pedido ${registro.ordemProducao} movido COMPLETO para $newLocation!',
          ),
          backgroundColor: const Color(0xFF3A59D1),
        ),
      );

      _reloadAllFutures();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar registro (Completo): $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handlePartialMove(
    Registro registro,
    String newLocation,
    double metrosMovidos,
  ) async {
    try {
      if ((registro.metros ?? 0.0) < metrosMovidos) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro: Metros a mover maior que o total do pedido.'),
            backgroundColor: Color(0xFFE65100),
          ),
        );
        return;
      }

      final localizacaoOrigem = registro.localizacao ?? 'N/A';
      const tipoMovimentacao = 'PARCIAL';
      final dataMovimentacao = DateTime.now();

      final sucesso = await MovimentacaoService.registrarMovimentacaoParcial(
        idPedido: registro.ordemProducao ?? 0,
        localizacaoOrigem: localizacaoOrigem,
        localizacaoDestino: newLocation,
        conferente: widget.conferente,
        dataMovimentacao: dataMovimentacao,
        tipoMovimentacao: tipoMovimentacao,
        metrosMovidos: metrosMovidos,
      );

      if (!sucesso) {
        throw Exception('Falha ao registrar movimentação parcial no servidor.');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pedido ${registro.ordemProducao}: $metrosMovidos m movidos parcialmente para $newLocation!',
          ),
          backgroundColor: const Color(0xFF00695C),
        ),
      );

      _reloadAllFutures();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar registro (Parcial): $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showParcialMoveDialog(Registro registro, String nextLoc) async {
    final _metrosController = TextEditingController();
    final double maxMetros = registro.metros ?? 0.0;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Mover Parcialmente - OP ${registro.ordemProducao}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Localização: ${registro.localizacao ?? 'N/A'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.straighten,
                        size: 20,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Total disponível: ${maxMetros.toStringAsFixed(3)} m',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Destino: $nextLoc',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00695C),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _metrosController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Metros a Mover',
                    hintText: 'Ex: ${(maxMetros / 2).toStringAsFixed(3)}',
                    border: const OutlineInputBorder(),
                    suffixText: 'm',
                    prefixIcon: const Icon(Icons.straighten),
                    helperText: 'Máx: ${maxMetros.toStringAsFixed(3)} m',
                    helperStyle: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final metrosText = _metrosController.text.replaceAll(',', '.');
                final metrosMovidos = double.tryParse(metrosText) ?? 0.0;

                if (metrosMovidos <= 0.0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Digite um valor válido de metros.'),
                      backgroundColor: Color(0xFFE65100),
                    ),
                  );
                  return;
                }

                if (metrosMovidos > maxMetros) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'O valor de $metrosMovidos m excede o total disponível de ${maxMetros.toStringAsFixed(3)} m.',
                      ),
                      backgroundColor: const Color(0xFFE65100),
                    ),
                  );
                  return;
                }

                Navigator.pop(context);
                _handlePartialMove(registro, nextLoc, metrosMovidos);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00695C),
                foregroundColor: Colors.white,
              ),
              child: const Text('Mover Parcialmente'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleRollback(Registro registro, String previousLoc) async {
    final confirmAction = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Retorno de Pedido'),
        content: Text(
          'Ao retornar o pedido ${registro.ordemProducao ?? 'N/A'}, ele será movido para $previousLoc. Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Retornar',
              style: TextStyle(color: Color(0xFFE65100)),
            ),
          ),
        ],
      ),
    );

    if (confirmAction == true) {
      await _updateRegistroLocationCompleta(registro, previousLoc);
    }
  }

  Future<void> _handleDelete(Registro registro) async {
    final confirmAction = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão (Admin)'),
        content: Text(
          'Tem certeza que deseja EXCLUIR permanentemente o pedido ${registro.ordemProducao ?? 'N/A'}? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
              foregroundColor: Colors.white,
            ),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );

    if (confirmAction == true) {
      try {
        final localizacaoAtual = registro.localizacao ?? 'N/A';
        final DateTime dataMovimentacao = DateTime.now();

        final sucesso = await MovimentacaoService.registrarMovimentacaoCompleta(
          idPedido: registro.ordemProducao ?? 0,
          localizacaoOrigem: localizacaoAtual,
          localizacaoDestino: 'EXCLUÍDO',
          conferente: widget.conferente,
          dataMovimentacao: dataMovimentacao,
          tipoMovimentacao: 'EXCLUSAO',
        );

        if (!sucesso) {
          throw Exception('Falha ao registrar exclusão no servidor.');
        }

        _reloadAllFutures();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pedido ${registro.ordemProducao ?? 'N/A'} EXCLUÍDO com sucesso!',
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir registro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showAdminMoveDialog(Registro registro) async {
    final _passwordController = TextEditingController();
    String? currentSelectedLoc;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter dialogSetState) {
            final availableLocations = _allLocations
                .where((loc) => loc != registro.localizacao)
                .toList();

            return AlertDialog(
              title: const Text('Movimentação Admin'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mover o Pedido ${registro.ordemProducao} de ${registro.localizacao ?? 'N/A'} para:',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Destino',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 0,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      value: currentSelectedLoc,
                      hint: const Text('Selecione a Loc de destino'),
                      items: availableLocations.map((loc) {
                        return DropdownMenuItem(value: loc, child: Text(loc));
                      }).toList(),
                      onChanged: (value) {
                        dialogSetState(() {
                          currentSelectedLoc = value;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Sua Senha Admin',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: currentSelectedLoc == null
                      ? null
                      : () async {
                          final password = _passwordController.text;

                          if (password.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Por favor, digite a senha de Admin.',
                                ),
                                backgroundColor: Color(0xFFE65100),
                              ),
                            );
                            return;
                          }

                          if (currentSelectedLoc == null) return;

                          final isVerified = await _verifyPassword(
                            widget.conferente,
                            password,
                          );

                          if (isVerified) {
                            Navigator.pop(context);
                            await _updateRegistroLocationCompleta(
                              registro,
                              currentSelectedLoc!,
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Senha Admin inválida. Tente novamente.',
                                ),
                                backgroundColor: Color(0xFFB71C1C),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB71C1C),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'Mover (Admin)',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showHistoricoMovimentacao(Registro registro) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final historico = await MovimentacaoService.buscarHistorico(
      registro.ordemProducao,
    );

    if (!mounted) return;

    Navigator.pop(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Histórico - OP ${registro.ordemProducao}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: historico.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Nenhuma movimentação registrada.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: historico.length,
                  itemBuilder: (context, index) {
                    final mov = historico[index];

                    final dataFormatada = DateFormat(
                      'dd/MM/yy HH:mm',
                    ).format(mov.dataMovimentacao.toLocal());

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 0,
                      ),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        leading: Icon(
                          _getIconForTipo(mov.tipoMovimentacao),
                          color: _getColorForTipo(mov.tipoMovimentacao),
                          size: 24,
                        ),
                        title: Text(
                          '${mov.localizacaoOrigem} → ${mov.localizacaoDestino}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today,
                                      size: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      dataFormatada,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.person,
                                      size: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      mov.conferente,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getColorForTipo(
                                  mov.tipoMovimentacao,
                                ).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                mov.tipoMovimentacao,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _getColorForTipo(mov.tipoMovimentacao),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                        isThreeLine: false,
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  IconData _getIconForTipo(String tipo) {
    switch (tipo) {
      case 'NORMAL':
        return Icons.arrow_forward_ios_rounded;
      case 'ROLLBACK':
        return Icons.undo_rounded;
      case 'ADMIN':
        return Icons.security_rounded;
      case 'EXCLUSAO':
        return Icons.delete_forever_rounded;
      case 'PARCIAL':
        return Icons.content_cut_rounded;
      default:
        return Icons.help;
    }
  }

  Color _getColorForTipo(String tipo) {
    switch (tipo) {
      case 'NORMAL':
        return const Color(0xFF2E7D32);
      case 'ROLLBACK':
        return const Color(0xFFE65100);
      case 'ADMIN':
        return const Color(0xFFB71C1C);
      case 'EXCLUSAO':
        return Colors.red.shade900;
      case 'PARCIAL':
        return const Color(0xFF00695C);
      default:
        return Colors.grey.shade600;
    }
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onPressed,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 10.0),
        child: Row(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isDestructive ? FontWeight.bold : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoveAndDeleteSheet(Registro registro) {
    final currentLoc = registro.localizacao;
    final nextOptions = _getValidNextOptions(currentLoc);
    final previousLoc = _getValidPreviousLocation(currentLoc);
    final canRollback = previousLoc != null;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.only(
            top: 25,
            left: 20,
            right: 20,
            bottom: 30,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ações do Pedido ${registro.ordemProducao ?? 'N/A'}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  'Localização Atual: ${currentLoc ?? 'N/A'} (Metros: ${(registro.metros ?? 0.0).toStringAsFixed(3)})',
                  style: const TextStyle(color: Colors.black54, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const Divider(height: 30),

                if (nextOptions.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Próximas Etapas:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...nextOptions.map(
                        (nextLoc) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ElevatedButton.icon(
                            icon: const Icon(
                              Icons.content_cut_rounded,
                              size: 20,
                            ),
                            label: Text(
                              'MOVER PARCIAL P/ ${nextLoc.toUpperCase()}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              _showParcialMoveDialog(registro, nextLoc);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00695C),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 3,
                            ),
                          ),
                        ),
                      ),

                      ...nextOptions
                          .map(
                            (nextLoc) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: ElevatedButton.icon(
                                icon: const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 20,
                                ),
                                label: Text(
                                  'MOVER COMPLETO P/ ${nextLoc.toUpperCase()}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _updateRegistroLocationCompleta(
                                    registro,
                                    nextLoc,
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3A59D1),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 5,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ],
                  )
                else if (currentLoc == 'Expedição')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text(
                        'MOVIMENTO FINALIZADO (EXPEDIDO)',
                        style: TextStyle(fontSize: 16),
                      ),
                      onPressed: null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade50,
                        foregroundColor: Colors.green.shade800,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                        side: BorderSide(
                          color: Colors.green.shade300,
                          width: 1,
                        ),
                      ),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10.0),
                    child: Text(
                      'Nenhuma movimentação de fluxo normal disponível.',
                      style: TextStyle(color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                  ),

                const SizedBox(height: 15),
                const Divider(height: 1),

                if (canRollback || widget.isAdmin)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 15),
                      const Text(
                        'Ações Especiais:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 5),

                      _buildActionTile(
                        icon: Icons.history_rounded,
                        title: 'Ver Histórico de Movimentações',
                        color: const Color(0xFF1565C0),
                        onPressed: () {
                          Navigator.pop(context);
                          _showHistoricoMovimentacao(registro);
                        },
                      ),

                      if (canRollback)
                        _buildActionTile(
                          icon: Icons.undo_rounded,
                          title: 'Retornar para ${previousLoc!.toUpperCase()}',
                          color: const Color(0xFFE65100),
                          onPressed: () {
                            Navigator.pop(context);
                            _handleRollback(registro, previousLoc);
                          },
                        ),

                      if (widget.isAdmin)
                        Column(
                          children: [
                            const Divider(height: 1),
                            const SizedBox(height: 10),
                            _buildActionTile(
                              icon: Icons.security_rounded,
                              title: 'MOVIMENTAÇÃO ADMIN (Direta)',
                              color: Colors.red.shade700,
                              isDestructive: true,
                              onPressed: () {
                                Navigator.pop(context);
                                _showAdminMoveDialog(registro);
                              },
                            ),
                            _buildActionTile(
                              icon: Icons.delete_forever_rounded,
                              title: 'EXCLUIR PEDIDO (Admin)',
                              color: Colors.red.shade900,
                              isDestructive: true,
                              onPressed: () {
                                Navigator.pop(context);
                                _handleDelete(registro);
                              },
                            ),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // CORRIGIDO: Diálogo de Busca com melhor feedback
  void _showSearchDialog() {
    final _searchController = TextEditingController(text: _searchQuery);
    DateTime? tempFilterDate = _filterDate;

    Future<void> _selectDate(StateSetter dialogSetState) async {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: tempFilterDate ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2101),
      );
      if (picked != null && picked != tempFilterDate) {
        dialogSetState(() {
          tempFilterDate = picked;
        });
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter dialogSetState) {
            return AlertDialog(
              title: const Text('Filtrar Pedidos'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _searchController,
                      autofocus: true,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        hintText: 'Digite Nr Ordem ou Artigo...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 15),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                        side: const BorderSide(color: Colors.grey),
                      ),
                      leading: const Icon(Icons.calendar_today),
                      title: Text(
                        tempFilterDate == null
                            ? 'Filtrar por Data'
                            : 'Data: ${DateFormat('dd/MM/yyyy').format(tempFilterDate!)}',
                      ),
                      trailing: tempFilterDate != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.red),
                              onPressed: () => dialogSetState(() {
                                tempFilterDate = null;
                              }),
                            )
                          : const Icon(Icons.arrow_drop_down),
                      onTap: () => _selectDate(dialogSetState),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _searchQuery = _searchController.text.trim();
                      _filterDate = tempFilterDate;
                    });

                    // IMPORTANTE: Força o recarregamento de TODAS as abas
                    _reloadAllFutures();

                    Navigator.pop(context);

                    // Feedback visual melhorado
                    String filterMsg = 'Filtro aplicado';
                    if (_searchQuery.isNotEmpty && _filterDate != null) {
                      filterMsg =
                          'Filtros: "$_searchQuery" e ${DateFormat('dd/MM/yyyy').format(_filterDate!)}';
                    } else if (_searchQuery.isNotEmpty) {
                      filterMsg = 'Filtro: "$_searchQuery"';
                    } else if (_filterDate != null) {
                      filterMsg =
                          'Filtro: ${DateFormat('dd/MM/yyyy').format(_filterDate!)}';
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(filterMsg),
                        duration: const Duration(seconds: 2),
                        backgroundColor: const Color(0xFF3A59D1),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3A59D1),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Aplicar Filtro'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const appBarColor = Color(0xFFCD1818);
    final currentTabIndex = _tabController.index;
    final currentTabName = _tabNames[currentTabIndex];
    final selectedTabColor = _getTabColor(currentTabName);
    const unselectedLabelColor = Color(0xFFF0F0F0);
    final isFilterActive = _searchQuery.isNotEmpty || _filterDate != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: appBarColor,
        surfaceTintColor: appBarColor,
        title: const Text(
          'Localização de Pedidos',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isFilterActive ? Icons.filter_alt : Icons.search,
              color: Colors.white,
            ),
            onPressed: _showSearchDialog,
            tooltip: isFilterActive
                ? 'Filtro ativo: ${_searchQuery.isNotEmpty ? "OP/Artigo" : ""}${_searchQuery.isNotEmpty && _filterDate != null ? " + " : ""}${_filterDate != null ? "Data" : ""}'
                : 'Filtrar por OP, Artigo ou Data',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              setState(() {
                _searchQuery = '';
                _filterDate = null;
              });

              _reloadAllFutures();

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Atualizando...'),
                  duration: Duration(seconds: 1),
                  backgroundColor: Color(0xFF2E7D32),
                ),
              );
            },
            tooltip: 'Remover Filtros e Atualizar',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: selectedTabColor,
          indicatorWeight: 4,
          isScrollable: false,
          labelColor: selectedTabColor,
          unselectedLabelColor: unselectedLabelColor.withOpacity(0.8),
          dividerColor: Colors.transparent,
          padding: EdgeInsets.zero,
          tabs: _tabNames.map((tabName) {
            return Tab(
              child: Text(
                tabName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabNames
            .map((tabName) => _buildRegistroTab(tabName))
            .toList(),
      ),
    );
  }

  Widget _buildRegistroTab(String tabLocation) {
    final actualLocation = _tabToFullLoc[tabLocation];
    final headerColor = _getTabColor(tabLocation);
    final isFilterActive = _searchQuery.isNotEmpty || _filterDate != null;

    return FutureBuilder<List<Registro>>(
      future: _getFutureForTab(tabLocation),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 60, color: Colors.red.shade300),
                const SizedBox(height: 10),
                Text(
                  'Erro ao carregar dados',
                  style: TextStyle(fontSize: 18, color: Colors.red.shade700),
                ),
                const SizedBox(height: 5),
                Text(
                  '${snapshot.error}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final registros = snapshot.data ?? [];

        if (registros.isEmpty) {
          String msg = isFilterActive
              ? 'Nenhum pedido encontrado com o filtro aplicado em ${actualLocation?.toUpperCase() ?? tabLocation}'
              : 'Nenhum registro encontrado para ${actualLocation?.toUpperCase() ?? tabLocation}';

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isFilterActive ? Icons.search_off : Icons.layers_clear,
                    size: 60,
                    color: headerColor.withOpacity(0.5),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    msg,
                    style: TextStyle(color: headerColor, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  if (isFilterActive) ...[
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Limpar Filtros'),
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                          _filterDate = null;
                        });
                        _reloadAllFutures();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: headerColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: registros.length,
          itemBuilder: (context, index) {
            final r = registros[index];
            final dateFormat = DateFormat('dd/MM HH:mm');
            final dataEntradaFormatada = dateFormat.format(r.data.toLocal());
            final dataMovimentacaoFormatada = r.dataMovimentacao != null
                ? dateFormat.format(r.dataMovimentacao!.toLocal())
                : dataEntradaFormatada;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _showMoveAndDeleteSheet(r),
                  onLongPress: () => _showMoveAndDeleteSheet(r),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                'OP ${r.ordemProducao}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                  color: headerColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: headerColor,
                                borderRadius: BorderRadius.circular(15),
                                boxShadow: [
                                  BoxShadow(
                                    color: headerColor.withOpacity(0.5),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Text(
                                r.localizacao ?? 'N/A',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          r.artigo ?? 'N/A',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Cor: ${r.cor ?? 'N/A'}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            // 🔥 NOVO CHIP: Caixa (Adicionado no início)
                            _buildDetailChip(
                              icon: Icons.inventory_2_outlined,
                              label: 'Caixa: ${r.caixa ?? 'N/A'}',
                              color: Colors.teal.shade700,
                            ),
                            _buildDetailChip(
                              icon: Icons.cut,
                              label: 'Corte: ${r.numCorte ?? 'N/A'}',
                              color: Colors.deepOrange,
                            ),
                            _buildDetailChip(
                              icon: Icons.straighten,
                              label:
                                  'Metros: ${(r.metros ?? 0.0).toStringAsFixed(3)} m',
                              color: Colors.indigo.shade600,
                            ),
                            _buildDetailChip(
                              icon: Icons.scale,
                              label:
                                  'Peso: ${(r.peso != null ? double.parse(r.peso.toString()) : 0.0).toStringAsFixed(3)} kg',
                              color: Colors.blueGrey.shade600,
                            ),
                            _buildDetailChip(
                              icon: Icons.unarchive_rounded,
                              label:
                                  'Volume: ${(r.volumeProg != null ? double.parse(r.volumeProg.toString()) : 0.0).toStringAsFixed(3)}',
                              color: Colors
                                  .purple
                                  .shade600, // Alterei a cor para diferenciar de Peso
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: _buildInfoRow(
                                Icons.person_outline,
                                'Conf.: ${r.conferente ?? 'N/A'}',
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: _buildInfoRow(
                                Icons.layers_outlined,
                                'Qtd: ${r.quantidade ?? 0}',
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: _buildInfoRow(
                                Icons.access_time_filled,
                                'Entrada: $dataEntradaFormatada',
                                color: Colors.green.shade700,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: _buildInfoRow(
                                Icons.update_rounded,
                                'Saída.: $dataMovimentacaoFormatada',
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, {required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
