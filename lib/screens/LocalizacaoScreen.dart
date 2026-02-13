import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tracx/models/registro.dart';
import 'package:tracx/services/movimentacao_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:tracx/models/HistoricoMov.dart';

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

  String _searchQuery = '';
  DateTime? _filterDate;

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

  Future<List<Registro>> _getFutureForTab(String tabLocation) {
    if (!_futureMap.containsKey(tabLocation)) {
      _futureMap[tabLocation] = _buscarRegistrosPorLocalizacao(tabLocation);
    }
    return _futureMap[tabLocation]!;
  }

  void _reloadAllFutures() {
    _futureMap.clear();
    setState(() {});
  }

  Color _getTabColor(String tabLocation) {
    // Mantendo cores por aba, mas puxando o padrão mais "premium"
    switch (tabLocation) {
      case 'Loc 3':
        return const Color(0xFF22C55E);
      case 'Loc 4':
        return const Color(0xFFF97316);
      case 'Loc 5':
        return const Color(0xFF38BDF8);
      case 'Loc 6':
        return const Color(0xFF3B82F6);
      case 'Loc 7':
        return const Color(0xFFA855F7);
      case 'Loc 8':
        return const Color(0xFF14B8A6);
      default:
        return _kPrimaryColor;
    }
  }

  Future<bool> _verifyPassword(String username, String password) async {
    if (!widget.isAdmin) {
      return false;
    }
    return password == _ADMIN_MOVE_PASSWORD;
  }

  Future<List<Registro>> _buscarRegistrosPorLocalizacao(
    String tabLocation,
  ) async {
    final targetLocation = _tabToFullLoc[tabLocation];
    if (targetLocation == null) return [];

    final dataFormatada = _filterDate != null
        ? DateFormat('yyyy-MM-dd').format(_filterDate!)
        : null;

    try {
      final queryParams = <String, String>{};
      queryParams['localizacao'] = targetLocation;

      if (_searchQuery.isNotEmpty) {
        queryParams['filtro'] = _searchQuery;
      }

      if (dataFormatada != null) {
        queryParams['data'] = dataFormatada;
      }

      final uri = Uri.parse(
        'http://168.190.90.2:5000/consulta/movimentacao',
      ).replace(queryParameters: queryParams);

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);

        final lista = jsonList.map((jsonItem) {
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

        // ✅ MAIS RECENTES PRIMEIRO
        lista.sort((a, b) {
          final da = a.dataMovimentacao ?? a.data;
          final db = b.dataMovimentacao ?? b.data;
          return db.compareTo(da);
        });

        return lista;
      } else {
        throw Exception(
          'Falha ao buscar registros da API: ${response.statusCode}',
        );
      }
    } catch (e) {
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
          backgroundColor: _kPrimaryColor,
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
            backgroundColor: Color(0xFFF97316),
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
          backgroundColor: const Color(0xFF14B8A6),
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
    final metrosController = TextEditingController();
    final double maxMetros = registro.metros ?? 0.0;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _kSurface,
          surfaceTintColor: _kSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Mover Parcialmente - OP ${registro.ordemProducao}',
            style: const TextStyle(color: _kTextPrimary),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Localização: ${registro.localizacao ?? 'N/A'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _kTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kSurface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBorderSoft),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.straighten,
                        size: 18,
                        color: _kAccentColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Total disponível: ${maxMetros.toStringAsFixed(3)} m',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _kTextPrimary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Destino: $nextLoc',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _kAccentColor,
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: metrosController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(color: _kTextPrimary),
                  decoration: InputDecoration(
                    labelText: 'Metros a Mover',
                    labelStyle: const TextStyle(color: _kTextSecondary),
                    hintText: 'Ex: ${(maxMetros / 2).toStringAsFixed(3)}',
                    hintStyle: TextStyle(
                      color: _kTextSecondary.withOpacity(0.7),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kBorderSoft),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kAccentColor),
                    ),
                    suffixText: 'm',
                    suffixStyle: const TextStyle(color: _kTextSecondary),
                    prefixIcon: const Icon(
                      Icons.straighten,
                      color: _kAccentColor,
                    ),
                    helperText: 'Máx: ${maxMetros.toStringAsFixed(3)} m',
                    helperStyle: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: _kTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: _kTextSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final metrosText = metrosController.text.replaceAll(',', '.');
                final metrosMovidos = double.tryParse(metrosText) ?? 0.0;

                if (metrosMovidos <= 0.0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Digite um valor válido de metros.'),
                      backgroundColor: Color(0xFFF97316),
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
                      backgroundColor: const Color(0xFFF97316),
                    ),
                  );
                  return;
                }

                Navigator.pop(context);
                _handlePartialMove(registro, nextLoc, metrosMovidos);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryColor,
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
        backgroundColor: _kSurface,
        surfaceTintColor: _kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirmar Retorno de Pedido',
          style: TextStyle(color: _kTextPrimary),
        ),
        content: Text(
          'Ao retornar o pedido ${registro.ordemProducao ?? 'N/A'}, ele será movido para $previousLoc. Deseja continuar?',
          style: const TextStyle(color: _kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: _kTextSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Retornar',
              style: TextStyle(color: Color(0xFFF97316)),
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
        backgroundColor: _kSurface,
        surfaceTintColor: _kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirmar Exclusão (Admin)',
          style: TextStyle(color: _kTextPrimary),
        ),
        content: Text(
          'Tem certeza que deseja EXCLUIR permanentemente o pedido ${registro.ordemProducao ?? 'N/A'}? Esta ação não pode ser desfeita.',
          style: const TextStyle(color: _kTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: _kTextSecondary),
            ),
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
    final passwordController = TextEditingController();
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
              backgroundColor: _kSurface,
              surfaceTintColor: _kSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Movimentação Admin',
                style: TextStyle(color: _kTextPrimary),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mover o Pedido ${registro.ordemProducao} de ${registro.localizacao ?? 'N/A'} para:',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _kTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      dropdownColor: _kSurface2,
                      decoration: InputDecoration(
                        labelText: 'Destino',
                        labelStyle: const TextStyle(color: _kTextSecondary),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kBorderSoft),
                        ),
                      ),
                      value: currentSelectedLoc,
                      hint: const Text(
                        'Selecione a Loc de destino',
                        style: TextStyle(color: _kTextSecondary),
                      ),
                      items: availableLocations.map((loc) {
                        return DropdownMenuItem(
                          value: loc,
                          child: Text(
                            loc,
                            style: const TextStyle(color: _kTextPrimary),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        dialogSetState(() {
                          currentSelectedLoc = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      style: const TextStyle(color: _kTextPrimary),
                      decoration: InputDecoration(
                        labelText: 'Sua Senha Admin',
                        labelStyle: const TextStyle(color: _kTextSecondary),
                        prefixIcon: const Icon(
                          Icons.lock,
                          color: _kAccentColor,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kBorderSoft),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kAccentColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: _kTextSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: currentSelectedLoc == null
                      ? null
                      : () async {
                          final password = passwordController.text;

                          if (password.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Por favor, digite a senha de Admin.',
                                ),
                                backgroundColor: Color(0xFFF97316),
                              ),
                            );
                            return;
                          }

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
                                backgroundColor: Color(0xFFEF4444),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Mover (Admin)'),
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

    // ✅ MAIS RECENTES PRIMEIRO
    historico.sort((a, b) => b.dataMovimentacao.compareTo(a.dataMovimentacao));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kSurface,
        surfaceTintColor: _kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Histórico - OP ${registro.ordemProducao}',
          style: const TextStyle(color: _kTextPrimary),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: historico.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 48, color: _kTextSecondary),
                      const SizedBox(height: 10),
                      const Text(
                        'Nenhuma movimentação registrada.',
                        style: TextStyle(color: _kTextSecondary),
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

                    final tipoColor = _getColorForTipo(mov.tipoMovimentacao);

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      elevation: 0,
                      color: _kSurface2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: _kBorderSoft, width: 1),
                      ),
                      child: ListTile(
                        leading: Icon(
                          _getIconForTipo(mov.tipoMovimentacao),
                          color: tipoColor,
                          size: 26,
                        ),
                        title: Text(
                          '${mov.localizacaoOrigem} → ${mov.localizacaoDestino}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: _kTextPrimary,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 12,
                                    color: _kTextSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    dataFormatada,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _kTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.person,
                                    size: 12,
                                    color: _kTextSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    mov.conferente,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _kTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: tipoColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: tipoColor.withOpacity(0.4),
                                  ),
                                ),
                                child: Text(
                                  mov.tipoMovimentacao,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: tipoColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar', style: TextStyle(color: _kAccentColor)),
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
        return const Color(0xFF22C55E);
      case 'ROLLBACK':
        return const Color(0xFFF97316);
      case 'ADMIN':
        return const Color(0xFFEF4444);
      case 'EXCLUSAO':
        return Colors.red.shade900;
      case 'PARCIAL':
        return const Color(0xFF14B8A6);
      default:
        return _kTextSecondary;
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
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 10.0),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isDestructive ? FontWeight.bold : FontWeight.w600,
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
      backgroundColor: _kSurface,
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
                    color: _kTextPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Localização Atual: ${currentLoc ?? 'N/A'} (Metros: ${(registro.metros ?? 0.0).toStringAsFixed(3)})',
                  style: const TextStyle(color: _kTextSecondary, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Divider(height: 25, color: _kBorderSoft),

                if (nextOptions.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Próximas Etapas:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _kTextSecondary,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),

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
                              style: const TextStyle(fontSize: 15),
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              _showParcialMoveDialog(registro, nextLoc);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF14B8A6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ),

                      ...nextOptions.map(
                        (nextLoc) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ElevatedButton.icon(
                            icon: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 20,
                            ),
                            label: Text(
                              'MOVER COMPLETO P/ ${nextLoc.toUpperCase()}',
                              style: const TextStyle(fontSize: 15),
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              _updateRegistroLocationCompleta(
                                registro,
                                nextLoc,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kPrimaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else if (currentLoc == 'Expedição')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text(
                        'MOVIMENTO FINALIZADO (EXPEDIDO)',
                        style: TextStyle(fontSize: 15),
                      ),
                      onPressed: null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade900.withOpacity(
                          0.15,
                        ),
                        foregroundColor: Colors.green.shade200,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                        side: BorderSide(
                          color: Colors.green.shade700,
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
                      style: TextStyle(color: _kTextSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),

                const SizedBox(height: 15),
                const Divider(height: 20, color: _kBorderSoft),

                if (canRollback || widget.isAdmin)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Ações Especiais:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _kTextSecondary,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),

                      _buildActionTile(
                        icon: Icons.history_rounded,
                        title: 'Ver Histórico de Movimentações',
                        color: _kAccentColor,
                        onPressed: () {
                          Navigator.pop(context);
                          _showHistoricoMovimentacao(registro);
                        },
                      ),

                      if (canRollback)
                        _buildActionTile(
                          icon: Icons.undo_rounded,
                          title: 'Retornar para ${previousLoc!.toUpperCase()}',
                          color: const Color(0xFFF97316),
                          onPressed: () {
                            Navigator.pop(context);
                            _handleRollback(registro, previousLoc);
                          },
                        ),

                      if (widget.isAdmin)
                        Column(
                          children: [
                            const Divider(height: 20, color: _kBorderSoft),
                            _buildActionTile(
                              icon: Icons.security_rounded,
                              title: 'MOVIMENTAÇÃO ADMIN (Direta)',
                              color: const Color(0xFFEF4444),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  void _showSearchDialog() {
    final searchController = TextEditingController(text: _searchQuery);
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
              backgroundColor: _kSurface,
              surfaceTintColor: _kSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Filtrar Pedidos',
                style: TextStyle(color: _kTextPrimary),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      keyboardType: TextInputType.text,
                      style: const TextStyle(color: _kTextPrimary),
                      decoration: InputDecoration(
                        hintText: 'Digite Nr Ordem ou Artigo...',
                        hintStyle: TextStyle(
                          color: _kTextSecondary.withOpacity(0.7),
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: _kAccentColor,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kBorderSoft),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _kAccentColor),
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: _kBorderSoft),
                      ),
                      leading: const Icon(
                        Icons.calendar_today,
                        color: _kAccentColor,
                      ),
                      title: Text(
                        tempFilterDate == null
                            ? 'Filtrar por Data'
                            : 'Data: ${DateFormat('dd/MM/yyyy').format(tempFilterDate!)}',
                        style: const TextStyle(color: _kTextPrimary),
                      ),
                      trailing: tempFilterDate != null
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear,
                                color: Color(0xFFEF4444),
                              ),
                              onPressed: () => dialogSetState(() {
                                tempFilterDate = null;
                              }),
                            )
                          : const Icon(
                              Icons.arrow_drop_down,
                              color: _kTextSecondary,
                            ),
                      onTap: () => _selectDate(dialogSetState),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: _kTextSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _searchQuery = searchController.text.trim();
                      _filterDate = tempFilterDate;
                    });

                    _reloadAllFutures();
                    Navigator.pop(context);

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
                        backgroundColor: _kPrimaryColor,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimaryColor,
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
    final currentTabIndex = _tabController.index;
    final currentTabName = _tabNames[currentTabIndex];
    final selectedTabColor = _getTabColor(currentTabName);

    final isFilterActive = _searchQuery.isNotEmpty || _filterDate != null;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_kBgTop, _kBgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            elevation: 0,
            centerTitle: true,
            backgroundColor: _kBgBottom,
            foregroundColor: _kTextPrimary,
            title: const Text(
              'Localização de Pedidos',
              style: TextStyle(
                color: _kTextPrimary,
                fontWeight: FontWeight.bold,
              ),
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
                      backgroundColor: Color(0xFF22C55E),
                    ),
                  );
                },
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: selectedTabColor,
              indicatorWeight: 4,
              isScrollable: false,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withOpacity(0.7),
              dividerColor: Colors.transparent,
              tabs: _tabNames.map((tabName) {
                return Tab(
                  child: Text(
                    tabName,
                    style: const TextStyle(
                      fontSize: 13,
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
        ),
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
          return const Center(
            child: CircularProgressIndicator(color: _kAccentColor),
          );
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
                  style: const TextStyle(fontSize: 12, color: _kTextSecondary),
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
                    color: headerColor.withOpacity(0.7),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    msg,
                    style: const TextStyle(
                      color: _kTextSecondary,
                      fontSize: 15,
                    ),
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: registros.length,
          itemBuilder: (context, index) {
            final r = registros[index];

            final dateFormat = DateFormat('dd/MM HH:mm');
            final dataEntradaFormatada = dateFormat.format(r.data.toLocal());
            final dataMovimentacaoFormatada = r.dataMovimentacao != null
                ? dateFormat.format(r.dataMovimentacao!.toLocal())
                : dataEntradaFormatada;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: [
                      _kSurface.withOpacity(0.95),
                      _kSurface2.withOpacity(0.95),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: _kBorderSoft, width: 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _showMoveAndDeleteSheet(r),
                  onLongPress: () => _showMoveAndDeleteSheet(r),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                'OP ${r.ordemProducao}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                  color: _kTextPrimary,
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
                                color: headerColor.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: headerColor.withOpacity(0.6),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                r.localizacao ?? 'N/A',
                                style: TextStyle(
                                  color: headerColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          r.artigo ?? 'N/A',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _kTextPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Cor: ${r.cor ?? 'N/A'}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _kTextSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: _kBorderSoft),
                        const SizedBox(height: 12),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildDetailChip(
                              icon: Icons.inventory_2_outlined,
                              label:
                                  'Caixa: ${r.caixa != null && r.caixa!.isNotEmpty ? r.caixa : '0'}',
                              color: const Color(0xFF14B8A6),
                            ),
                            _buildDetailChip(
                              icon: Icons.cut,
                              label: 'Corte: ${r.numCorte ?? 'N/A'}',
                              color: const Color(0xFFF97316),
                            ),
                            _buildDetailChip(
                              icon: Icons.straighten,
                              label:
                                  'Metros: ${(r.metros ?? 0.0).toStringAsFixed(3)} m',
                              color: const Color(0xFF3B82F6),
                            ),
                            _buildDetailChip(
                              icon: Icons.scale,
                              label:
                                  'Peso: ${(r.peso != null ? double.parse(r.peso.toString()) : 0.0).toStringAsFixed(3)} kg',
                              color: const Color(0xFF64748B),
                            ),
                            _buildDetailChip(
                              icon: Icons.unarchive_rounded,
                              label:
                                  'Volume: ${(r.volumeProg != null ? double.parse(r.volumeProg.toString()) : 0.0).toStringAsFixed(3)}',
                              color: const Color(0xFFA855F7),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoRow(
                                Icons.person_outline,
                                'Conf.: ${r.conferente ?? 'N/A'}',
                                color: _kTextSecondary,
                              ),
                            ),
                            Expanded(
                              child: _buildInfoRow(
                                Icons.layers_outlined,
                                'Qtd: ${r.quantidade ?? 0}',
                                color: _kTextSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoRow(
                                Icons.access_time_filled,
                                'Entrada: $dataEntradaFormatada',
                                color: const Color(0xFF22C55E),
                              ),
                            ),
                            Expanded(
                              child: _buildInfoRow(
                                Icons.update_rounded,
                                'Saída: $dataMovimentacaoFormatada',
                                color: const Color(0xFFEF4444),
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
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
