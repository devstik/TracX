import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
// IMPORTS NECESSÁRIOS PARA PDF
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/registro.dart';
import '../models/registro_tinturaria.dart';

// =========================================================================
// CORES E ESTILOS GLOBAIS
// =========================================================================

// Cores Primárias
const Color _kPrimaryColorEmbalagem = Color(
  0xFFCD1818,
); // Vermelho da Embalagem
const Color _kPrimaryColorTinturaria = Color(
  0xFF090057,
); // Azul Escuro da Tinturaria

// Estilo constante para o cabeçalho das tabelas
const TextStyle _kHeaderStyle = TextStyle(
  fontWeight: FontWeight.bold,
  fontSize: 10, // Um pouco menor para caber mais info
  color: Colors.black54,
);

class ListaRegistrosScreen extends StatefulWidget {
  const ListaRegistrosScreen({super.key});

  @override
  _ListaRegistrosScreenState createState() => _ListaRegistrosScreenState();
}

class _ListaRegistrosScreenState extends State<ListaRegistrosScreen>
    with SingleTickerProviderStateMixin {
  // Controladores de Filtro
  final _searchOrdemProducaoController = TextEditingController();
  final _searchArtigoController = TextEditingController();
  final _searchCorController = TextEditingController();
  final _searchConferenteController = TextEditingController();

  // Variáveis de Estado do Filtro
  String _searchOrdemProducao = '';
  String _searchArtigo = '';
  String _searchCor = '';
  String _searchConferente = '';
  DateTime? _selectedDate;

  // NOVO: Conjunto para rastrear os registros de Embalagem selecionados
  Set<String> _selectedEmbalagemKeys = {};

  late TabController _tabController;
  // Future para evitar refazer a requisição a cada setState (melhora performance percebida)
  late Future<Map<String, List<Registro>>> _embalagemFuture;
  late Future<List<RegistroTinturaria>> _tinturariaFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Inicializa os Futures para que a busca comece imediatamente
    _embalagemFuture = _buscarTodos();
    _tinturariaFuture = _buscarRegistrosTinturaria();
  }

  @override
  void dispose() {
    _searchOrdemProducaoController.dispose();
    _searchArtigoController.dispose();
    _searchCorController.dispose();
    _searchConferenteController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // NOVO: Gera uma chave única para um registro de Embalagem
  String _getRegistroKey(Registro r) {
    // Usamos Data e Turno para garantir unicidade, já que a OP pode se repetir.
    return '${r.ordemProducao}|${r.data.toIso8601String()}|${r.turno}';
  }

  // NOVO: Alterna o estado de seleção
  void _toggleEmbalagemSelection(Registro registro) {
    final key = _getRegistroKey(registro);
    setState(() {
      if (_selectedEmbalagemKeys.contains(key)) {
        _selectedEmbalagemKeys.remove(key);
      } else {
        _selectedEmbalagemKeys.add(key);
      }
    });
  }

  // NOVO: Seleciona/Desseleciona todos os registros visíveis em um grupo
  void _toggleGroupSelection(List<Registro> registros) {
    // Verifica se todos os registros do grupo estão atualmente selecionados
    final allSelected = registros.every(
      (r) => _selectedEmbalagemKeys.contains(_getRegistroKey(r)),
    );

    setState(() {
      if (allSelected) {
        // Se todos estiverem selecionados, remove todos.
        for (var r in registros) {
          _selectedEmbalagemKeys.remove(_getRegistroKey(r));
        }
      } else {
        // Caso contrário, adiciona todos.
        for (var r in registros) {
          _selectedEmbalagemKeys.add(_getRegistroKey(r));
        }
      }
    });
  }

  String _formatarData(DateTime data) {
    return DateFormat('dd/MM/yy').format(data);
  }

  // Manteve as funções de compartilhamento de texto e PDF (fora do escopo de refatoração de UI)
  String _gerarTextoCompartilhamento(Map<String, List<Registro>> agrupados) {
    final buffer = StringBuffer();
    final formatter = NumberFormat('0.00');

    // ... (código original)
    agrupados.forEach((chave, registros) {
      final totalPeso = registros.fold<double>(0, (s, r) => s + r.peso);
      final totalQuantidade = registros.fold<int>(
        0,
        (s, r) => s + r.quantidade,
      );

      buffer.writeln(
        'Data: $chave | Peso: ${formatter.format(totalPeso)} Kg | Tambores: $totalQuantidade',
      );

      buffer.writeln(
        '----------------------------------------------------------------------------------',
      );
      buffer.writeln(
        'OP      Artigo           Cor                     Qtde   Peso     Conf        Ting.    Corte',
      );
      buffer.writeln(
        '----------------------------------------------------------------------------------',
      );

      for (var r in registros) {
        final dataTingimento =
            (r.dataTingimento != null && r.dataTingimento!.isNotEmpty)
            ? _formatarData(DateTime.parse(r.dataTingimento!))
            : '-';
        final numCorte = r.numCorte ?? '-';

        buffer.writeln(
          '${r.ordemProducao.toString().padRight(8)}'
          '${r.artigo.padRight(16)}'
          '${r.cor.padRight(22)}'
          '${r.quantidade.toString().padRight(7)}'
          '${formatter.format(r.peso).padLeft(7)}  '
          '${r.conferente.padRight(11)}'
          '${dataTingimento.padRight(10)}'
          '${numCorte.padRight(8)}',
        );
      }
      buffer.writeln();
    });

    return buffer.toString().trim();
  }

  // Manteve a função de geração de PDF para Embalagem (fora do escopo de refatoração de UI)
  Future<void> _generateEmbalagemPdf(
    Map<String, List<Registro>> agrupados,
  ) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.openSansRegular();
    final boldFont = await PdfGoogleFonts.openSansBold();
    final formatter = NumberFormat('0.00');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(30),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Relatório de Registros - Embalagem',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  font: boldFont,
                  color: PdfColor.fromInt(_kPrimaryColorEmbalagem.value),
                ),
              ),
              // ... (resto do cabeçalho)
              pw.SizedBox(height: 5),
              pw.Text(
                'Data de Geração: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                style: pw.TextStyle(
                  fontSize: 10,
                  font: font,
                  color: PdfColors.grey700,
                ),
              ),
              pw.Divider(height: 10, thickness: 1),
            ],
          );
        },
        build: (pw.Context context) {
          return agrupados.entries.expand((grupo) {
            final totalPeso = grupo.value.fold<double>(0, (s, r) => s + r.peso);
            final totalQuantidade = grupo.value.fold<int>(
              0,
              (s, r) => s + r.quantidade,
            );

            // Cabeçalho do Grupo
            final grupoHeader = pw.Container(
              color: PdfColor.fromInt(_kPrimaryColorEmbalagem.value),
              padding: const pw.EdgeInsets.all(8),
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Text(
                '${grupo.key} | Peso Total: ${formatter.format(totalPeso)} Kg | Tambores: $totalQuantidade',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  font: boldFont,
                  color: PdfColors.white,
                ),
              ),
            );

            // Dados da Tabela
            final tableHeaders = [
              'OP',
              'Artigo',
              'Cor',
              'Qtd',
              'Peso (Kg)',
              'Conf.',
              'Ting.',
              'Corte',
              'Vol. Prog.', // Cabeçalho do campo volumeProg
              'Metros',
            ];

            final tableData = grupo.value.map((r) {
              final dataTingimento =
                  (r.dataTingimento != null && r.dataTingimento!.isNotEmpty)
                  ? _formatarData(DateTime.parse(r.dataTingimento!))
                  : '-';

              // ALTERADO: Usando o valor real de r.volumeProg (o campo que você adicionou)
              final volumeProgStr = (r.volumeProg != null && r.volumeProg! > 0)
                  ? formatter.format(r.volumeProg!)
                  : '-';

              // CORRIGIDO: Usando o campo 'metros' que JÁ EXISTE no seu modelo 'Registro'.
              final metrosStr = (r.metros != null && r.metros! > 0)
                  ? formatter.format(r.metros!)
                  : '-';

              return [
                r.ordemProducao.toString(),
                r.artigo,
                r.cor,
                r.quantidade.toString(),
                formatter.format(r.peso),
                r.conferente,
                dataTingimento,
                r.numCorte ?? '-',
                volumeProgStr, // Valor de Vol. Prog. (REAL)
                metrosStr, // Valor de Metros (Corrigido)
              ];
            }).toList();

            // Retorna a lista plana de widgets
            return [
              grupoHeader,
              pw.Table.fromTextArray(
                headers: tableHeaders,
                data: tableData,
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize:
                      7, // Reduzido o tamanho da fonte para caber mais colunas
                  font: boldFont,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey700,
                ),
                cellStyle: pw.TextStyle(fontSize: 7, font: font),
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                columnWidths: {
                  0: const pw.FixedColumnWidth(35), // OP
                  1: const pw.FlexColumnWidth(2), // Artigo
                  2: const pw.FlexColumnWidth(2), // Cor
                  3: const pw.FixedColumnWidth(25), // Qtd
                  4: const pw.FixedColumnWidth(35), // Peso
                  5: const pw.FlexColumnWidth(1.5), // Conf
                  6: const pw.FixedColumnWidth(35), // Ting
                  7: const pw.FixedColumnWidth(35), // Corte
                  8: const pw.FixedColumnWidth(35), // Vol. Prog (NOVO)
                  9: const pw.FixedColumnWidth(35), // Metros
                },
              ),
              pw.SizedBox(height: 10),
            ];
          }).toList();
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename:
          'Registros_Embalagem_${DateFormat('ddMMyy').format(DateTime.now())}.pdf',
    );
  }

  // Manteve a função de geração de PDF para Tinturaria (fora do escopo de refatoração de UI)
  Future<void> _generateTinturariaPdf(
    List<RegistroTinturaria> registros,
  ) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.openSansRegular();
    final boldFont = await PdfGoogleFonts.openSansBold();

    final agrupados = <String, List<RegistroTinturaria>>{};
    for (var r in registros) {
      final chave = '${r.dataCorte} - ${r.turno}';
      agrupados.putIfAbsent(chave, () => []).add(r);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(30),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Relatório de Registros - Raschelina',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  font: boldFont,
                  color: PdfColor.fromInt(_kPrimaryColorTinturaria.value),
                ),
              ),
              // ... (resto do cabeçalho)
              pw.SizedBox(height: 5),
              pw.Text(
                'Data de Geração: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                style: pw.TextStyle(
                  fontSize: 10,
                  font: font,
                  color: PdfColors.grey700,
                ),
              ),
              pw.Divider(height: 10, thickness: 1),
            ],
          );
        },
        build: (pw.Context context) {
          return agrupados.entries.expand((grupo) {
            // Cabeçalho do Grupo
            final grupoHeader = pw.Container(
              color: PdfColor.fromInt(_kPrimaryColorTinturaria.value),
              padding: const pw.EdgeInsets.all(8),
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Text(
                '${grupo.key} | Registros: ${grupo.value.length}',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  font: boldFont,
                  color: PdfColors.white,
                ),
              ),
            );

            // Dados da Tabela
            final tableHeaders = [
              'Material',
              'Larg. Crua',
              'Elast. Crua',
              'Nº Máquina',
              'Data Corte',
              'Lote Elástico',
              'Conf.',
              'Turno',
            ];

            final tableData = grupo.value.map((r) {
              return [
                r.nomeMaterial,
                r.larguraCrua,
                r.elasticidadeCrua,
                r.nMaquina,
                r.dataCorte,
                r.loteElastico,
                r.conferente,
                r.turno,
              ];
            }).toList();

            // Retorna a lista plana de widgets
            return [
              grupoHeader,
              pw.Table.fromTextArray(
                headers: tableHeaders,
                data: tableData,
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                  font: boldFont,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey700,
                ),
                cellStyle: pw.TextStyle(fontSize: 7, font: font),
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2), // Material
                  1: const pw.FixedColumnWidth(40), // Larg. Crua
                  2: const pw.FixedColumnWidth(40), // Elast. Crua
                  3: const pw.FixedColumnWidth(40), // Nº Máquina
                  4: const pw.FixedColumnWidth(40), // Data Corte
                  5: const pw.FlexColumnWidth(1.5), // Lote Elástico
                  6: const pw.FlexColumnWidth(1.5), // Conf.
                  7: const pw.FixedColumnWidth(30), // Turno
                },
              ),
              pw.SizedBox(height: 10),
            ];
          }).toList();
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename:
          'Registros_Tinturaria_${DateFormat('ddMMyy').format(DateTime.now())}.pdf',
    );
  }

  // Manteve a função de busca de dados (fora do escopo de refatoração de UI)
  Future<List<RegistroTinturaria>> _buscarRegistrosTinturaria() async {
    final url = Uri.parse('http://168.190.90.2:5000/consulta/tinturaria');
    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception(
        'Erro ao buscar dados da tinturaria: ${response.statusCode}',
      );
    }

    final List<dynamic> dados = jsonDecode(response.body);
    return dados.map((item) {
      return RegistroTinturaria(
        nomeMaterial: item['nomeMaterial'] ?? '',
        larguraCrua: item['larguraCrua'] ?? '',
        elasticidadeCrua: item['elasticidadeCrua'] ?? '',
        nMaquina: item['nMaquina'] ?? '',
        dataCorte: item['dataCorte'] ?? '',
        loteElastico: item['loteElastico'] ?? '',
        conferente:
            item['Conferente'] ??
            '', // CORRIGIDO: Assumindo que a chave era "Conferente"
        turno:
            item['Turno'] ?? '', // CORRIGIDO: Assumindo que a chave era "Turno"
      );
    }).toList();
  }

  // Manteve a função de busca de dados (fora do escopo de refatoração de UI)
  Future<Map<String, List<Registro>>> _buscarTodos() async {
    final embalagem = await _buscarRegistros('embalagem');
    return {'Embalagem': embalagem};
  }

  // Manteve a função de busca de dados (fora do escopo de refatoração de UI)
  Future<List<Registro>> _buscarRegistros(String modulo) async {
    final url = Uri.parse('http://168.190.90.2:5000/consulta/$modulo');
    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception('Erro [$modulo]: ${response.statusCode}');
    }

    final List<dynamic> dados = jsonDecode(response.body);
    double pDouble(d) =>
        double.tryParse(d?.toString().replaceAll(',', '.') ?? '') ?? 0;

    return dados.map((item) {
      return Registro(
        data: DateTime.parse(item['Data']),
        ordemProducao: item['NrOrdem'] ?? 0,
        quantidade: pDouble(item['Quantidade']).toInt(),
        artigo: item['Artigo'] ?? '',
        cor: item['Cor'] ?? '',
        peso: pDouble(item['Peso']),
        conferente: item['Conferente'] ?? '',
        turno: item['Turno'] ?? '',
        metros: pDouble(item['Metros']),
        dataTingimento: item['DataTingimento'] ?? '',
        numCorte: item['NumCorte'] ?? '',
        volumeProg: pDouble(item['VolumeProg']),
      );
    }).toList();
  }

  // Manteve a função de filtro (fora do escopo de refatoração de UI)
  List<Registro> _filtrarRegistros(List<Registro> registros) {
    if (_searchOrdemProducao.isEmpty &&
        _searchArtigo.isEmpty &&
        _searchCor.isEmpty &&
        _searchConferente.isEmpty &&
        _selectedDate == null) {
      return registros;
    }

    return registros.where((r) {
      final matchesOrdemProducao =
          _searchOrdemProducao.isEmpty ||
          r.ordemProducao.toString().contains(_searchOrdemProducao);

      final matchesArtigo =
          _searchArtigo.isEmpty ||
          r.artigo.toLowerCase().contains(_searchArtigo.toLowerCase());

      final matchesCor =
          _searchCor.isEmpty ||
          r.cor.toLowerCase().contains(_searchCor.toLowerCase());

      final matchesConferente =
          _searchConferente.isEmpty ||
          r.conferente.toLowerCase().contains(_searchConferente.toLowerCase());

      final matchesData =
          _selectedDate == null ||
          (r.data.toLocal().year == _selectedDate!.year &&
              r.data.toLocal().month == _selectedDate!.month &&
              r.data.toLocal().day == _selectedDate!.day);

      return matchesOrdemProducao &&
          matchesArtigo &&
          matchesCor &&
          matchesConferente &&
          matchesData;
    }).toList();
  }

  // NOVO: Refatorado para Widget de Diálogo de Busca Mais Elegante
  Future<void> _showSearchDialog() {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                'Filtrar Registros',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Campo Ordem de Produção
                    TextField(
                      controller: _searchOrdemProducaoController,
                      decoration: const InputDecoration(
                        labelText: 'Ordem de Produção (OP)',
                        prefixIcon: Icon(Icons.pin),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    // Campo Artigo
                    TextField(
                      controller: _searchArtigoController,
                      decoration: const InputDecoration(
                        labelText: 'Artigo',
                        prefixIcon: Icon(Icons.category_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Campo Cor
                    TextField(
                      controller: _searchCorController,
                      decoration: const InputDecoration(
                        labelText: 'Cor',
                        prefixIcon: Icon(Icons.color_lens_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Campo Conferente
                    TextField(
                      controller: _searchConferenteController,
                      decoration: const InputDecoration(
                        labelText: 'Conferente',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Campo de Data com DatePicker (Elegante)
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Colors.grey.shade400),
                      ),
                      leading: const Icon(Icons.calendar_today),
                      title: Text(
                        _selectedDate == null
                            ? 'Data de Registro'
                            : DateFormat('dd/MM/yyyy').format(_selectedDate!),
                        style: TextStyle(
                          color: _selectedDate == null
                              ? Colors.grey.shade600
                              : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          _selectedDate == null ? Icons.add : Icons.close,
                        ),
                        onPressed: () {
                          if (_selectedDate != null) {
                            // Limpar Data
                            setState(() {
                              _selectedDate = null;
                            });
                          } else {
                            // Mostrar Date Picker
                            showDatePicker(
                              context: context,
                              initialDate: _selectedDate ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                            ).then((pickedDate) {
                              if (pickedDate != null) {
                                setState(() {
                                  _selectedDate = pickedDate;
                                });
                              }
                            });
                          }
                        },
                      ),
                      onTap: () {
                        // Tocar para mostrar o Date Picker
                        if (_selectedDate == null) {
                          showDatePicker(
                            context: context,
                            initialDate: _selectedDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          ).then((pickedDate) {
                            if (pickedDate != null) {
                              setState(() {
                                _selectedDate = pickedDate;
                              });
                            }
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // Limpar e aplicar o filtro vazio
                    _searchOrdemProducaoController.clear();
                    _searchArtigoController.clear();
                    _searchCorController.clear();
                    _searchConferenteController.clear();
                    this.setState(() {
                      // Força a reconstrução do widget principal após fechar o diálogo
                      _selectedDate = null;
                      _searchOrdemProducao = '';
                      _searchArtigo = '';
                      _searchCor = '';
                      _searchConferente = '';
                      _selectedEmbalagemKeys.clear();
                      // Recarrega os dados (opcional, mas bom para garantir)
                      _embalagemFuture = _buscarTodos();
                    });
                    Navigator.pop(dialogContext);
                  },
                  child: const Text(
                    'LIMPAR',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimaryColorEmbalagem,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    // Atualiza o estado principal com os valores dos controladores
                    this.setState(() {
                      _searchOrdemProducao = _searchOrdemProducaoController.text
                          .trim();
                      _searchArtigo = _searchArtigoController.text.trim();
                      _searchCor = _searchCorController.text.trim();
                      _searchConferente = _searchConferenteController.text
                          .trim();
                      // Recarrega os dados (opcional, mas bom para garantir)
                      _embalagemFuture = _buscarTodos();
                    });
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('APLICAR FILTRO'),
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _kPrimaryColorEmbalagem,
        title: const Text(
          'Registros de Produção',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Ícone de Filtro que muda se houver filtro aplicado
          IconButton(
            icon: Icon(
              (_searchOrdemProducao.isNotEmpty ||
                      _searchArtigo.isNotEmpty ||
                      _searchCor.isNotEmpty ||
                      _searchConferente.isNotEmpty ||
                      _selectedDate != null)
                  ? Icons.filter_alt
                  : Icons.filter_alt_outlined,
              color: Colors.white,
            ),
            onPressed: () async {
              // Só mostra o filtro para a aba de Embalagem, onde ele é aplicado
              if (_tabController.index == 0) {
                await _showSearchDialog();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Filtro de busca disponível apenas na aba EMBALAGEM.',
                    ),
                  ),
                );
              }
            },
          ),
          // Botão de Compartilhar
          IconButton(
            icon: Icon(
              Icons.share,
              color: _selectedEmbalagemKeys.isNotEmpty
                  ? Colors.yellowAccent
                  : Colors.white,
            ),
            onPressed: () {
              final selectedCount = _selectedEmbalagemKeys.length;

              showDialog(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Compartilhar Relatório'),
                  content: Text(
                    selectedCount > 0
                        ? 'Deseja exportar $selectedCount registros selecionados de Embalagem, ou o relatório completo de Tinturaria?'
                        : 'Deseja exportar todos os registros visíveis de Embalagem, ou o relatório de Tinturaria?',
                  ),
                  actions: [
                    // AÇÕES DE EMBALAGEM
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        // Lógica de exportação de Embalagem (PDF)
                        await _handleEmbalagemExport(
                          isPdf: true,
                          selectedCount: selectedCount,
                        );
                      },
                      child: Text(
                        'Embalagem (PDF) ${selectedCount > 0 ? '($selectedCount)' : ''}',
                        style: const TextStyle(color: _kPrimaryColorEmbalagem),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        // Lógica de exportação de Embalagem (Texto Simples)
                        await _handleEmbalagemExport(
                          isPdf: false,
                          selectedCount: selectedCount,
                        );
                      },
                      child: Text(
                        'Embalagem (Texto) ${selectedCount > 0 ? '($selectedCount)' : ''}',
                        style: const TextStyle(color: _kPrimaryColorEmbalagem),
                      ),
                    ),
                    // AÇÃO DE TINTURARIA
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        // Lógica de exportação de Tinturaria (PDF)
                        await _handleTinturariaExport();
                      },
                      child: const Text(
                        'Raschelina (PDF)',
                        style: TextStyle(color: _kPrimaryColorTinturaria),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'EMBALAGEM', icon: Icon(Icons.inventory_2_outlined)),
            Tab(text: 'RASCHELINA', icon: Icon(Icons.color_lens_outlined)),
            Tab(text: 'CONFRONTO', icon: Icon(Icons.compare_arrows)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEmbalagemTab(),
          _buildTinturariaTab(),
          _buildConfrontoTab(),
        ],
      ),
    );
  }

  // NOVO: Função para consolidar a lógica de exportação de Embalagem
  Future<void> _handleEmbalagemExport({
    required bool isPdf,
    required int selectedCount,
  }) async {
    if (!mounted) return;

    try {
      // Usa o future já carregado para evitar nova requisição, se possível
      final allEmbalagem = (await _embalagemFuture)['Embalagem']!;
      List<Registro> filteredEmbalagem = _filtrarRegistros(allEmbalagem);

      final List<Registro> registrosToExport = selectedCount > 0
          ? filteredEmbalagem
                .where(
                  (r) => _selectedEmbalagemKeys.contains(_getRegistroKey(r)),
                )
                .toList()
          : filteredEmbalagem;

      if (registrosToExport.isEmpty) {
        throw Exception(
          "Nenhum registro para exportar. Aplique filtros ou faça uma seleção.",
        );
      }

      final agrupadosEmbalagem = <String, List<Registro>>{};
      for (var r in registrosToExport) {
        final dataStr = _formatarData(r.data);
        final chave = '$dataStr - ${r.turno}';
        agrupadosEmbalagem.putIfAbsent(chave, () => []).add(r);
      }

      if (isPdf) {
        await _generateEmbalagemPdf(agrupadosEmbalagem);
      } else {
        final texto = _gerarTextoCompartilhamento(agrupadosEmbalagem);
        if (texto.isNotEmpty) Share.share(texto);
      }

      // Desseleciona após a exportação (limpa o estado do widget)
      if (selectedCount > 0 && mounted)
        setState(() => _selectedEmbalagemKeys.clear());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao compartilhar: ${e.toString()}')),
      );
    }
  }

  // NOVO: Função para consolidar a lógica de exportação de Tinturaria
  Future<void> _handleTinturariaExport() async {
    if (!mounted) return;
    try {
      // Usa o future já carregado
      final tinturaria = await _tinturariaFuture;
      if (tinturaria.isEmpty) {
        throw Exception("Nenhum pedido para exportar.");
      }
      await _generateTinturariaPdf(tinturaria);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao compartilhar: ${e.toString()}')),
      );
    }
  }

  // =========================================================================
  // ABA EMABALAGEM (Mais Bonita e Organizada)
  // =========================================================================

  Widget _buildEmbalagemTab() {
    return FutureBuilder<Map<String, List<Registro>>>(
      future: _embalagemFuture, // Usa o future pré-carregado
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(
            child: Text(
              'Erro ao carregar registros: ${snapshot.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          );
        } else if (!snapshot.hasData || snapshot.data!['Embalagem']!.isEmpty) {
          return const Center(
            child: Text('Nenhum registro de embalagem encontrado.'),
          );
        }

        final allRegistros = snapshot.data!['Embalagem']!;
        final registros = _filtrarRegistros(allRegistros);

        if (registros.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Nenhum resultado encontrado com os filtros aplicados.',
              ),
            ),
          );
        }

        // Agrupa por "Data - Turno"
        final agrupados = <String, List<Registro>>{};
        for (var r in registros) {
          final dataStr = _formatarData(r.data);
          final chave = '$dataStr - ${r.turno}';
          agrupados.putIfAbsent(chave, () => []).add(r);
        }

        // NOVO: Converte para lista e ordena por data decrescente
        final sortedGrupos = agrupados.entries.toList();
        sortedGrupos.sort((a, b) {
          // Extrai a data da chave (ex: "30/10/25 - T1" -> "30/10/25")
          final dateStrA = a.key.split(' - ')[0];
          final dateStrB = b.key.split(' - ')[0];

          // Converte para DateTime (dd/MM/yy) para comparação
          final dateA = DateFormat('dd/MM/yy').parse(dateStrA);
          final dateB = DateFormat('dd/MM/yy').parse(dateStrB);

          // Compara de forma decrescente (b.compareTo(a))
          return dateB.compareTo(dateA);
        });

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80, top: 8),
          itemCount: sortedGrupos.length,
          itemBuilder: (context, index) {
            final grupo = sortedGrupos.elementAt(index);
            final totalPeso = grupo.value.fold<double>(0, (s, r) => s + r.peso);
            final totalQuantidade = grupo.value.fold<int>(
              0,
              (s, r) => s + r.quantidade,
            );

            // Verifica se todos os itens no grupo estão selecionados
            final groupKeys = grupo.value.map(_getRegistroKey).toSet();
            final allGroupSelected = groupKeys.every(
              _selectedEmbalagemKeys.contains,
            );

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  iconColor: _kPrimaryColorEmbalagem,
                  collapsedIconColor: Colors.black54,
                  // Título com Checkbox de Seleção em Massa
                  title: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24, // Ajusta a altura do checkbox
                        child: Checkbox(
                          value: allGroupSelected,
                          activeColor: _kPrimaryColorEmbalagem,
                          onChanged: (bool? newValue) {
                            _toggleGroupSelection(grupo.value);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Título do Grupo (Data - Turno)
                      Flexible(
                        child: Text(
                          grupo.key,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  // Subtítulo com Totais
                  subtitle: Padding(
                    padding: const EdgeInsets.only(left: 32.0),
                    child: Text(
                      'Peso: ${totalPeso.toStringAsFixed(3)} Kg | Tambores: $totalQuantidade',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  childrenPadding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 12,
                  ),
                  children: [
                    const Divider(height: 1, thickness: 1),
                    // Cabeçalho da Tabela
                    _buildEmbalagemHeaderRow(),
                    ...grupo.value.asMap().entries.map((entry) {
                      final r = entry.value;
                      final isEven = entry.key % 2 == 0;
                      return _buildRegistroEmbalagemRow(r, isEven);
                    }).toList(),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // NOVO: Cabeçalho com distribuição otimizada para mais colunas
  Widget _buildEmbalagemHeaderRow() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 30), // Espaço para o checkbox
          Expanded(flex: 2, child: Text('OP', style: _kHeaderStyle)),
          Expanded(flex: 4, child: Text('Artigo/Cor', style: _kHeaderStyle)),
          Expanded(flex: 2, child: Text('Qtd', style: _kHeaderStyle)),
          Expanded(flex: 3, child: Text('Peso (Kg)', style: _kHeaderStyle)),
          Expanded(flex: 3, child: Text('Conf.', style: _kHeaderStyle)),
          Expanded(flex: 4, child: Text('Ting./Corte', style: _kHeaderStyle)),
        ],
      ),
    );
  }

  // NOVO: Row da Tabela mais limpa
  Widget _buildRegistroEmbalagemRow(Registro r, bool isEven) {
    final key = _getRegistroKey(r);
    final isSelected = _selectedEmbalagemKeys.contains(key);

    final style = TextStyle(
      fontSize: 10.5,
      color: isSelected
          ? _kPrimaryColorEmbalagem.darken(10)
          : (isEven ? Colors.black87 : Colors.black54),
      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
    );
    final dataTingimentoStr =
        (r.dataTingimento != null && r.dataTingimento!.isNotEmpty)
        ? _formatarData(DateTime.parse(r.dataTingimento!))
        : '-';

    final tingimentoCorte = '$dataTingimentoStr / ${r.numCorte ?? '-'}';
    final artigoCor = '${r.artigo} / ${r.cor}';

    return Container(
      // Fundo em destaque quando selecionado
      color: isSelected
          ? _kPrimaryColorEmbalagem.withOpacity(0.1)
          : (isEven ? Colors.white : Colors.grey.shade50),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: () => _toggleEmbalagemSelection(
          r,
        ), // Permite selecionar pelo toque na linha
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox
            SizedBox(
              width: 30,
              height: 18,
              child: Checkbox(
                value: isSelected,
                activeColor: _kPrimaryColorEmbalagem,
                onChanged: (bool? newValue) {
                  _toggleEmbalagemSelection(r);
                },
              ),
            ),
            Expanded(flex: 2, child: Text('${r.ordemProducao}', style: style)),
            Expanded(
              flex: 4,
              child: Text(
                artigoCor,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(flex: 2, child: Text('${r.quantidade}', style: style)),
            Expanded(
              flex: 3,
              child: Text(r.peso.toStringAsFixed(3), style: style),
            ),
            Expanded(
              flex: 3,
              child: Text(
                r.conferente,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(flex: 4, child: Text(tingimentoCorte, style: style)),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // ABA TINTURARIA (Mais Bonita e Organizada)
  // =========================================================================

  Widget _buildTinturariaTab() {
    return FutureBuilder<List<RegistroTinturaria>>(
      future: _tinturariaFuture, // Usa o future pré-carregado
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(
            child: Text(
              'Erro na Tinturaria: ${snapshot.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          );
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text('Nenhum registro de tinturaria encontrado.'),
          );
        }

        final registros = snapshot.data!;
        final agrupados = <String, List<RegistroTinturaria>>{};
        for (var r in registros) {
          final chave = '${r.dataCorte} - ${r.turno}';
          agrupados.putIfAbsent(chave, () => []).add(r);
        }

        // NOVO: Converte para lista e ordena por data de corte decrescente
        final sortedGrupos = agrupados.entries.toList();
        sortedGrupos.sort((a, b) {
          // Extrai a data da chave (ex: "2025-10-30 - T1" -> "2025-10-30")
          final dateStrA = a.key.split(' - ')[0];
          final dateStrB = b.key.split(' - ')[0];

          // CORREÇÃO: Usa tryParse e um fallback para tratar datas inválidas/vazias.
          // Datas inválidas/nulas são tratadas como sendo muito antigas (DateTime(0)) para
          // que sejam ordenadas por último (b.compareTo(a)).
          final dateA = DateTime.tryParse(dateStrA) ?? DateTime(0);
          final dateB = DateTime.tryParse(dateStrB) ?? DateTime(0);

          // Compara de forma decrescente (b.compareTo(a))
          return dateB.compareTo(dateA);
        });

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80, top: 8),
          itemCount: sortedGrupos.length,
          itemBuilder: (context, index) {
            final grupo = sortedGrupos.elementAt(index);

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  iconColor: _kPrimaryColorTinturaria,
                  collapsedIconColor: Colors.black54,
                  title: Text(
                    grupo.key,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    'Registros: ${grupo.value.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 12,
                  ),
                  children: [
                    const Divider(height: 1, thickness: 1),
                    _buildTinturariaHeaderRow(),
                    ...grupo.value.asMap().entries.map((entry) {
                      final r = entry.value;
                      final isEven = entry.key % 2 == 0;
                      return _buildRegistroTinturariaRow(r, isEven);
                    }).toList(),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // NOVO: Cabeçalho com distribuição otimizada
  Widget _buildTinturariaHeaderRow() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Material', style: _kHeaderStyle)),
          Expanded(flex: 2, child: Text('Larg./Elast.', style: _kHeaderStyle)),
          Expanded(flex: 2, child: Text('Máq.', style: _kHeaderStyle)),
          Expanded(flex: 3, child: Text('Lote Elástico', style: _kHeaderStyle)),
          Expanded(flex: 2, child: Text('Conf.', style: _kHeaderStyle)),
          Expanded(flex: 3, child: Text('Data/Turno', style: _kHeaderStyle)),
        ],
      ),
    );
  }

  // NOVO: Row da Tabela mais limpa
  Widget _buildRegistroTinturariaRow(RegistroTinturaria r, bool isEven) {
    final style = TextStyle(
      fontSize: 10.5,
      color: isEven ? Colors.black87 : Colors.black54,
    );
    final larguraElast = '${r.larguraCrua}/${r.elasticidadeCrua}';
    final dataTurno = '${r.dataCorte} / ${r.turno}';

    return Container(
      color: isEven ? Colors.white : Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              r.nomeMaterial,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(flex: 2, child: Text(larguraElast, style: style)),
          Expanded(flex: 2, child: Text(r.nMaquina, style: style)),
          Expanded(
            flex: 3,
            child: Text(
              r.loteElastico,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              r.conferente,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(flex: 3, child: Text(dataTurno, style: style)),
        ],
      ),
    );
  }

  // =========================================================================
  // ABA CONFRONTO (Mais Bonita e Organizada)
  // =========================================================================

  Widget _buildConfrontoTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: FutureBuilder<List<dynamic>>(
        // Usamos os futures pré-carregados, mas precisamos agrupá-los
        future: Future.wait([_embalagemFuture, _tinturariaFuture]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: Text(
                'Erro ao carregar dados: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text('Nenhum dado encontrado para comparação.'),
            );
          }

          final embalagemMap = snapshot.data![0] as Map<String, List<Registro>>;
          final embalagem = embalagemMap['Embalagem'] ?? [];
          final tinturaria = snapshot.data![1] as List<RegistroTinturaria>;

          final totalPesoEmbalagem = embalagem.fold<double>(
            0,
            (sum, r) => sum + r.peso,
          );
          final totalQuantidadeEmbalagem = embalagem.fold<int>(
            0,
            (sum, r) => sum + r.quantidade,
          );

          final totalMaquinasTinturaria = tinturaria
              .map((e) => e.nMaquina)
              .toSet()
              .length;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildComparisionCard(
                  title: 'RESUMO EMABALAGEM',
                  icon: Icons.inventory_2,
                  color: _kPrimaryColorEmbalagem,
                  metrics: {
                    'Total de Registros': embalagem.length.toString(),
                    'Peso Total': '${totalPesoEmbalagem.toStringAsFixed(3)} kg',
                    'Total de Tambores': totalQuantidadeEmbalagem.toString(),
                  },
                ),
                const SizedBox(height: 20),
                _buildComparisionCard(
                  title: 'RESUMO TINTURARIA',
                  icon: Icons.color_lens,
                  color: _kPrimaryColorTinturaria,
                  metrics: {
                    'Total de Registros': tinturaria.length.toString(),
                    'Lotes de Elástico Únicos': tinturaria
                        .map((e) => e.loteElastico)
                        .toSet()
                        .length
                        .toString(),
                    'Máquinas Utilizadas': totalMaquinasTinturaria.toString(),
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // NOVO: Card de Comparação mais elegante
  Widget _buildComparisionCard({
    required String title,
    required IconData icon,
    required Color color,
    required Map<String, String> metrics,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16), // Bordas mais arredondadas
        border: Border.all(color: color.withOpacity(0.4), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const Divider(height: 20, thickness: 0.5),
          ...metrics.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${entry.key}:',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  Text(
                    entry.value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: color.darken(
                        10,
                      ), // Valor em destaque com a cor do tema
                    ),
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

// =========================================================================
// FUNÇÕES DE EXTENSÃO PARA CORES (Reutilizadas da versão anterior)
// =========================================================================
extension ColorExtension on Color {
  Color darken([int percent = 10]) {
    assert(1 <= percent && percent <= 100);
    final f = 1 - percent / 100;
    return Color.fromARGB(
      alpha,
      (red * f).round(),
      (green * f).round(),
      (blue * f).round(),
    );
  }

  Color lighten([int percent = 10]) {
    assert(1 <= percent && percent <= 100);
    final f = percent / 100;
    return Color.fromARGB(
      alpha,
      (red + (255 - red) * f).round(),
      (green + (255 - green) * f).round(),
      (blue + (255 - blue) * f).round(),
    );
  }
}
