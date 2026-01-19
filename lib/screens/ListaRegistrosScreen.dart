import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/registro.dart';
import '../models/registro_tinturaria.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:hive/hive.dart';

// CORES E ESTILOS GLOBAIS

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
  final String? conferente;
  const ListaRegistrosScreen({super.key, this.conferente});

  @override
  _ListaRegistrosScreenState createState() => _ListaRegistrosScreenState();
}

class _ListaRegistrosScreenState extends State<ListaRegistrosScreen>
    with SingleTickerProviderStateMixin {
  // ATUALIZADO: Formatadores globais com separador de milhar (ponto)
  final _kBrDecimalFormatter = NumberFormat('0.00', 'pt_BR');
  final _kBrThreeDecimalFormatter = NumberFormat('#,##0.000', 'pt_BR');
  final _kBrIntegerFormatter = NumberFormat('#,##0', 'pt_BR');

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

  // Conjunto para rastrear os registros de Embalagem selecionados
  Set<String> _selectedEmbalagemKeys = {};
  // Conjunto para rastrear os registros de Tinturaria selecionados
  Set<String> _selectedTinturariaKeys = {};

  late TabController _tabController;
  // Future para evitar refazer a requisição a cada setState (melhora performance percebida)
  late Future<Map<String, List<Registro>>> _embalagemFuture;
  late Future<List<RegistroTinturaria>> _tinturariaFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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

  // Gera uma chave única para um registro de Embalagem
  String _getRegistroKey(Registro r) {
    // Usamos Data e Turno para garantir unicidade, já que a OP pode se repetir.
    return '${r.ordemProducao}|${r.data.toIso8601String()}|${r.turno}';
  }

  // Gera uma chave única para um registro de Tinturaria (Raschelina)
  String _getTinturariaKey(RegistroTinturaria r) {
    // A chave será a combinação da Data de Corte, Máquina, Material e Turno
    return '${r.dataCorte}|${r.nMaquina}|${r.nomeMaterial}|${r.turno}';
  }

  // Alterna o estado de seleção da Embalagem
  void _toggleEmbalagemSelection(Registro registro) {
    final key = _getRegistroKey(registro);
    setState(() {
      if (_selectedEmbalagemKeys.contains(key)) {
        _selectedEmbalagemKeys.remove(key);
      } else {
        _selectedEmbalagemKeys.add(key);
      }
      // Limpa a seleção da outra aba ao selecionar uma (Comportamento opcional, mas seguro)
      _selectedTinturariaKeys.clear();
    });
  }

  // Alterna o estado de seleção da Tinturaria
  void _toggleTinturariaSelection(RegistroTinturaria registro) {
    final key = _getTinturariaKey(registro);
    setState(() {
      if (_selectedTinturariaKeys.contains(key)) {
        _selectedTinturariaKeys.remove(key);
      } else {
        _selectedTinturariaKeys.add(key);
      }
      // Limpa a seleção da outra aba ao selecionar uma (Comportamento opcional, mas seguro)
      _selectedEmbalagemKeys.clear();
    });
  }

  // Seleciona/Desseleciona todos os registros visíveis em um grupo de Embalagem
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

  // Seleciona/Desseleciona todos os registros visíveis em um grupo de Tinturaria
  void _toggleTinturariaGroupSelection(List<RegistroTinturaria> registros) {
    // Verifica se todos os registros do grupo estão atualmente selecionados
    final allSelected = registros.every(
      (r) => _selectedTinturariaKeys.contains(_getTinturariaKey(r)),
    );

    setState(() {
      if (allSelected) {
        // Se todos estiverem selecionados, remove todos.
        for (var r in registros) {
          _selectedTinturariaKeys.remove(_getTinturariaKey(r));
        }
      } else {
        // Caso contrário, adiciona todos.
        for (var r in registros) {
          _selectedTinturariaKeys.add(_getTinturariaKey(r));
        }
      }
    });
  }

  String _formatarData(DateTime data) {
    return DateFormat('dd/MM/yy').format(data);
  }

  // Função para editar um registro
  void _editarRegistro(Registro registro, int indexNoBox) {
    final ordemController = TextEditingController(
      text: registro.ordemProducao.toString(),
    );
    final quantidadeController = TextEditingController(
      text: registro.quantidade.toString(),
    );
    final artigoController = TextEditingController(text: registro.artigo);
    final corController = TextEditingController(text: registro.cor);
    final pesoController = TextEditingController(
      text: registro.peso.toStringAsFixed(3).replaceAll('.', ','),
    );
    final metrosController = TextEditingController(
      text: (registro.metros ?? 0.0).toStringAsFixed(3).replaceAll('.', ','),
    );
    final dataTingimentoController = TextEditingController(
      text: registro.dataTingimento ?? '',
    );
    final numCorteController = TextEditingController(
      text: registro.numCorte ?? '',
    );
    final volumeProgController = TextEditingController(
      text: (registro.volumeProg ?? 0.0)
          .toStringAsFixed(3)
          .replaceAll('.', ','),
    );
    final caixaController = TextEditingController(text: registro.caixa ?? '0');
    String? localizacaoSelecionada = registro.localizacao;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Registro'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ordemController,
                decoration: const InputDecoration(labelText: 'Ordem Produção'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: artigoController,
                decoration: const InputDecoration(labelText: 'Artigo'),
              ),
              TextField(
                controller: corController,
                decoration: const InputDecoration(labelText: 'Cor'),
              ),
              TextField(
                controller: quantidadeController,
                decoration: const InputDecoration(labelText: 'Quantidade'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              TextField(
                controller: pesoController,
                decoration: const InputDecoration(labelText: 'Peso (Kg)'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              TextField(
                controller: metrosController,
                decoration: const InputDecoration(labelText: 'Metros'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              TextField(
                controller: volumeProgController,
                decoration: const InputDecoration(labelText: 'Volume'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              TextField(
                controller: caixaController,
                decoration: const InputDecoration(labelText: 'Caixa'),
              ),
              TextField(
                controller: dataTingimentoController,
                decoration: const InputDecoration(labelText: 'Data Tingimento'),
              ),
              TextField(
                controller: numCorteController,
                decoration: const InputDecoration(labelText: 'Num Corte'),
              ),
              DropdownButtonFormField<String>(
                value: localizacaoSelecionada,
                decoration: const InputDecoration(labelText: 'Localização'),
                items: const ['Mesas', 'Imatecs']
                    .map(
                      (loc) => DropdownMenuItem(value: loc, child: Text(loc)),
                    )
                    .toList(),
                onChanged: (value) {
                  localizacaoSelecionada = value;
                },
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
            onPressed: () async {
              final novoRegistro = Registro(
                data: registro.data,
                ordemProducao: int.tryParse(ordemController.text) ?? 0,
                quantidade: int.tryParse(quantidadeController.text) ?? 0,
                artigo: artigoController.text,
                cor: corController.text,
                peso:
                    double.tryParse(pesoController.text.replaceAll(',', '.')) ??
                    0.0,
                conferente: registro.conferente,
                turno: registro.turno,
                metros:
                    double.tryParse(
                      metrosController.text.replaceAll(',', '.'),
                    ) ??
                    0.0,
                dataTingimento: dataTingimentoController.text,
                numCorte: numCorteController.text,
                volumeProg:
                    double.tryParse(
                      volumeProgController.text.replaceAll(',', '.'),
                    ) ??
                    0.0,
                localizacao: localizacaoSelecionada ?? 'Manual',
                caixa: caixaController.text,
              );

              final box = Hive.box<Registro>('registros');
              final registrosMap = await _buscarTodos();
              final allRegistros = registrosMap['Embalagem'] ?? [];

              // Encontrar o índice correto
              int indexToUpdate = -1;
              for (int i = 0; i < allRegistros.length; i++) {
                if (_getRegistroKey(allRegistros[i]) ==
                    _getRegistroKey(registro)) {
                  indexToUpdate = i;
                  break;
                }
              }

              if (indexToUpdate != -1) {
                await box.putAt(indexToUpdate, novoRegistro);
                setState(() {
                  _embalagemFuture = _buscarTodos();
                });

                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Registro atualizado com sucesso!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  // Função para deletar um registro
  Future<void> _deletarRegistro(Registro registro) async {
    // Verificar se o usuário está autorizado a deletar
    const List<String> usuariosAutorizados = ['Leide', 'João'];

    if (widget.conferente == null ||
        !usuariosAutorizados.contains(widget.conferente)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apenas Leide e João podem excluir registros.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: const Text(
          'Tem certeza que deseja excluir este registro? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final box = Hive.box<Registro>('registros');
              final registrosMap = await _buscarTodos();
              final allRegistros = registrosMap['Embalagem'] ?? [];

              // Encontrar o índice correto
              int indexToDelete = -1;
              for (int i = 0; i < allRegistros.length; i++) {
                if (_getRegistroKey(allRegistros[i]) ==
                    _getRegistroKey(registro)) {
                  indexToDelete = i;
                  break;
                }
              }

              if (indexToDelete != -1) {
                await box.deleteAt(indexToDelete);
                setState(() {
                  _embalagemFuture = _buscarTodos();
                });

                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Registro excluído com sucesso!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Manteve as funções de compartilhamento de texto e PDF (fora do escopo de refatoração de UI)
  String _gerarTextoCompartilhamento(Map<String, List<Registro>> agrupados) {
    final buffer = StringBuffer();
    // ATUALIZADO: Usando o formatador brasileiro de 3 decimais
    final formatter = _kBrThreeDecimalFormatter;

    agrupados.forEach((chave, registros) {
      final totalPeso = registros.fold<double>(0, (s, r) => s + r.peso);
      final totalQuantidade = registros.fold<int>(
        0,
        (s, r) => s + r.quantidade,
      );

      buffer.writeln(
        'Data: $chave | Peso: ${formatter.format(totalPeso)} Kg | Tambores: ${totalQuantidade.toString()}',
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

  // Função para gerar texto de compartilhamento para Tinturaria (Raschelina)
  String _gerarTinturariaTextoCompartilhamento(
    Map<String, List<RegistroTinturaria>> agrupados,
  ) {
    final buffer = StringBuffer();

    agrupados.forEach((chave, registros) {
      buffer.writeln('Data/Turno: $chave | Registros: ${registros.length}');

      buffer.writeln(
        '----------------------------------------------------------------------------------',
      );
      buffer.writeln(
        'Material         Larg. Crua Elast. Crua Máquina Data Corte Lote Elástico Conf. Turno',
      );
      buffer.writeln(
        '----------------------------------------------------------------------------------',
      );

      for (var r in registros) {
        buffer.writeln(
          '${r.nomeMaterial.padRight(17)}'
          '${r.larguraCrua.padRight(13)}'
          '${r.elasticidadeCrua.padRight(13)}'
          '${r.nMaquina.padRight(8)}'
          '${r.dataCorte.padRight(11)}'
          '${r.loteElastico.padRight(15)}'
          '${r.conferente.padRight(6)}'
          '${r.turno.padRight(5)}',
        );
      }
      buffer.writeln();
    });

    return buffer.toString().trim();
  }

  Future<void> _generateEmbalagemExcel(
    Map<String, List<Registro>> agrupados,
  ) async {
    final excel = Excel.createExcel();
    final sheet = excel['Registros Embalagem'];

    // Remove a sheet padrão se existir
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Cabeçalhos
    final headers = [
      'Data/Turno',
      'OP',
      'Artigo',
      'Cor',
      'Qtd',
      'Peso (Kg)',
      'Conferente',
      'Data Tingimento',
      'Nº Corte',
      'Vol. Prog.',
      'Metros',
    ];

    int rowIndex = 0;

    // Adiciona cabeçalhos
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIndex),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#CD1818'),
        fontColorHex: ExcelColor.white,
      );
    }
    rowIndex++;

    // Adiciona dados
    agrupados.forEach((chave, registros) {
      for (var r in registros) {
        final dataTingimento =
            (r.dataTingimento != null && r.dataTingimento!.isNotEmpty)
            ? _formatarData(DateTime.parse(r.dataTingimento!))
            : '-';

        final volumeProgStr = (r.volumeProg != null && r.volumeProg! > 0)
            ? _kBrThreeDecimalFormatter.format(r.volumeProg!)
            : '-';

        final metrosStr = (r.metros != null && r.metros! > 0)
            ? _kBrThreeDecimalFormatter.format(r.metros!)
            : '-';

        final rowData = [
          chave,
          r.ordemProducao.toString(),
          r.artigo,
          r.cor,
          _kBrIntegerFormatter.format(r.quantidade),
          _kBrThreeDecimalFormatter.format(r.peso),
          r.conferente,
          dataTingimento,
          r.numCorte ?? '-',
          volumeProgStr,
          metrosStr,
        ];

        for (var i = 0; i < rowData.length; i++) {
          sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIndex),
              )
              .value = TextCellValue(
            rowData[i],
          );
        }
        rowIndex++;
      }
    });

    // Salva e compartilha
    final bytes = excel.encode();
    if (bytes != null) {
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/Registros_Embalagem_${DateFormat('ddMMyy').format(DateTime.now())}.xlsx',
      );
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([
        XFile(file.path),
      ], subject: 'Relatório de Embalagem');
    }
  }

  // Manteve a função de geração de PDF para Embalagem (fora do escopo de refatoração de UI)
  Future<void> _generateEmbalagemPdf(
    Map<String, List<Registro>> agrupados,
  ) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.openSansRegular();
    final boldFont = await PdfGoogleFonts.openSansBold();
    // ATUALIZADO: Usando o formatador brasileiro de 3 decimais
    final formatter = _kBrThreeDecimalFormatter;
    // ATUALIZADO: Usando o formatador brasileiro de inteiro
    final intFormatter = _kBrIntegerFormatter;

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
                // ATUALIZADO: Formatando totalPeso e totalQuantidade para padrão brasileiro
                '${grupo.key} | Peso Total: ${formatter.format(totalPeso)} Kg | Tambores: ${intFormatter.format(totalQuantidade)}',
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
                  // ATUALIZADO: Formatando volumeProg para padrão brasileiro
                  ? formatter.format(r.volumeProg!)
                  : '-';

              // CORRIGIDO: Usando o campo 'metros' que JÁ EXISTE no seu modelo 'Registro'.
              final metrosStr = (r.metros != null && r.metros! > 0)
                  // ATUALIZADO: Formatando metros para padrão brasileiro
                  ? formatter.format(r.metros!)
                  : '-';

              return [
                r.ordemProducao.toString(),
                r.artigo,
                r.cor,
                r.quantidade.toString(),
                // ATUALIZADO: Formatando peso para padrão brasileiro
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

  Future<void> _generateTinturariaExcel(
    List<RegistroTinturaria> registros,
  ) async {
    final excel = Excel.createExcel();
    final sheet = excel['Registros Tinturaria'];

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final headers = [
      'Data/Turno',
      'Material',
      'Larg. Crua',
      'Elast. Crua',
      'Nº Máquina',
      'Data Corte',
      'Lote Elástico',
      'Conferente',
      'Turno',
    ];

    int rowIndex = 0;

    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIndex),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#090057'),
        fontColorHex: ExcelColor.white,
      );
    }
    rowIndex++;

    final agrupados = <String, List<RegistroTinturaria>>{};
    for (var r in registros) {
      final chave = '${r.dataCorte} - ${r.turno}';
      agrupados.putIfAbsent(chave, () => []).add(r);
    }

    agrupados.forEach((chave, registrosList) {
      for (var r in registrosList) {
        final rowData = [
          chave,
          r.nomeMaterial,
          r.larguraCrua,
          r.elasticidadeCrua,
          r.nMaquina,
          r.dataCorte,
          r.loteElastico,
          r.conferente,
          r.turno,
        ];

        for (var i = 0; i < rowData.length; i++) {
          sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIndex),
              )
              .value = TextCellValue(
            rowData[i],
          );
        }
        rowIndex++;
      }
    });

    final bytes = excel.encode();
    if (bytes != null) {
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/Registros_Tinturaria_${DateFormat('ddMMyy').format(DateTime.now())}.xlsx',
      );
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([
        XFile(file.path),
      ], subject: 'Relatório de Tinturaria');
    }
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

  // Refatorado para Widget de Diálogo de Busca Mais Elegante
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
    // Conta a seleção total para o botão de compartilhamento
    final totalSelectedCount =
        _selectedEmbalagemKeys.length + _selectedTinturariaKeys.length;

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
              (_tabController.index == 0 &&
                      (_searchOrdemProducao.isNotEmpty ||
                          _searchArtigo.isNotEmpty ||
                          _searchCor.isNotEmpty ||
                          _searchConferente.isNotEmpty ||
                          _selectedDate != null))
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
              color: totalSelectedCount > 0
                  ? Colors.yellowAccent
                  : Colors.white,
            ),
            onPressed: () {
              // Lógica de contagem de seleção
              final selectedEmbalagemCount = _selectedEmbalagemKeys.length;
              final selectedTinturariaCount = _selectedTinturariaKeys.length;

              // Determina qual relatório será gerado por padrão
              String defaultReport = '';
              if (selectedEmbalagemCount > 0) {
                defaultReport = 'Registros de Embalagem selecionados';
              } else if (selectedTinturariaCount > 0) {
                defaultReport = 'Registros de Raschelina selecionados';
              }

              showDialog(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Compartilhar Relatório'),
                  content: Text(
                    selectedEmbalagemCount > 0
                        ? 'Deseja exportar $selectedEmbalagemCount registros selecionados de Embalagem?'
                        : selectedTinturariaCount > 0
                        ? 'Deseja exportar $selectedTinturariaCount registros selecionados de Raschelina?'
                        : 'Deseja exportar todos os registros visíveis de Embalagem ou Raschelina?',
                  ),
                  actions: [
                    // EMBALAGEM - PDF
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        await _handleEmbalagemExport(
                          isPdf: true,
                          selectedCount: selectedEmbalagemCount,
                        );
                      },
                      child: Text(
                        'Embalagem (PDF) ${selectedEmbalagemCount > 0 ? '($selectedEmbalagemCount)' : ''}',
                        style: const TextStyle(color: _kPrimaryColorEmbalagem),
                      ),
                    ),
                    // EMBALAGEM - EXCEL (NOVO)
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        await _handleEmbalagemExport(
                          isPdf: false,
                          isExcel: true,
                          selectedCount: selectedEmbalagemCount,
                        );
                      },
                      child: Text(
                        'Embalagem (Excel) ${selectedEmbalagemCount > 0 ? '($selectedEmbalagemCount)' : ''}',
                        style: const TextStyle(color: _kPrimaryColorEmbalagem),
                      ),
                    ),
                    // EMBALAGEM - TEXTO
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        await _handleEmbalagemExport(
                          isPdf: false,
                          selectedCount: selectedEmbalagemCount,
                        );
                      },
                      child: Text(
                        'Embalagem (Texto) ${selectedEmbalagemCount > 0 ? '($selectedEmbalagemCount)' : ''}',
                        style: const TextStyle(color: _kPrimaryColorEmbalagem),
                      ),
                    ),
                    // TINTURARIA - PDF
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        await _handleTinturariaExport(
                          selectedCount: selectedTinturariaCount,
                          isPdf: true,
                        );
                      },
                      child: Text(
                        'Raschelina (PDF) ${selectedTinturariaCount > 0 ? '($selectedTinturariaCount)' : ''}',
                        style: const TextStyle(color: _kPrimaryColorTinturaria),
                      ),
                    ),
                    // TINTURARIA - EXCEL (NOVO)
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        await _handleTinturariaExport(
                          selectedCount: selectedTinturariaCount,
                          isPdf: false,
                          isExcel: true,
                        );
                      },
                      child: Text(
                        'Raschelina (Excel) ${selectedTinturariaCount > 0 ? '($selectedTinturariaCount)' : ''}',
                        style: const TextStyle(color: _kPrimaryColorTinturaria),
                      ),
                    ),
                    // TINTURARIA - TEXTO
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        await _handleTinturariaExport(
                          selectedCount: selectedTinturariaCount,
                          isPdf: false,
                        );
                      },
                      child: Text(
                        'Raschelina (Texto) ${selectedTinturariaCount > 0 ? '($selectedTinturariaCount)' : ''}',
                        style: const TextStyle(color: _kPrimaryColorTinturaria),
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
            Tab(text: 'Relatório', icon: Icon(Icons.compare_arrows)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEmbalagemTab(),
          _buildTinturariaTab(),
          _buildConfrontoTab(),
          _buildRelatorioTab(),
        ],
      ),
    );
  }

  // =======================================================
  // NOVA ABA: RELATÓRIO DIÁRIO POR ARTIGO
  // =======================================================
  Widget _buildRelatorioTab() {
    return FutureBuilder<Map<String, List<Registro>>>(
      future: _embalagemFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        } else if (!snapshot.hasData || snapshot.data!['Embalagem']!.isEmpty) {
          return const Center(child: Text('Nenhum dado para relatório.'));
        }

        // 1. Aplica os filtros atuais (se houver) ou pega tudo
        final allRegistros = snapshot.data!['Embalagem']!;
        final registrosFiltrados = _filtrarRegistros(allRegistros);

        if (registrosFiltrados.isEmpty) {
          return const Center(child: Text('Nenhum registro encontrado.'));
        }

        // 2. Agrupamento: Data -> Artigo -> Soma Peso
        // Map<DataIsoString, Map<NomeArtigo, DoublePeso>>
        final Map<String, Map<String, double>> groupedData = {};

        for (var r in registrosFiltrados) {
          // Normaliza a data para ignorar hora/minuto (apenas a data do dia)
          final dateKey = DateTime(
            r.data.year,
            r.data.month,
            r.data.day,
          ).toIso8601String();

          if (!groupedData.containsKey(dateKey)) {
            groupedData[dateKey] = {};
          }

          // Atualiza o peso do artigo naquela data
          groupedData[dateKey]!.update(
            r.artigo,
            (currentWeight) => currentWeight + r.peso,
            ifAbsent: () => r.peso,
          );
        }

        // 3. Ordenação das Datas (Recente -> Antigo)
        final sortedDateKeys = groupedData.keys.toList()
          ..sort((a, b) => DateTime.parse(b).compareTo(DateTime.parse(a)));

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: sortedDateKeys.length,
          itemBuilder: (context, index) {
            final dateKeyStr = sortedDateKeys[index];
            final dateObj = DateTime.parse(dateKeyStr);
            final artigosMap = groupedData[dateKeyStr]!;

            // Calcula o total do dia para exibir no cabeçalho
            final totalPesoDia = artigosMap.values.fold<double>(
              0,
              (sum, v) => sum + v,
            );

            // Ordena os artigos do dia por peso (do maior para o menor) para melhor visualização
            final sortedArtigos = artigosMap.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExpansionTile(
                initiallyExpanded:
                    index ==
                    0, // Abre o primeiro item (dia mais recente) automaticamente
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: Colors.white,
                collapsedBackgroundColor: Colors.white,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kPrimaryColorEmbalagem.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.calendar_month,
                    color: _kPrimaryColorEmbalagem,
                  ),
                ),
                title: Text(
                  DateFormat('dd/MM/yyyy').format(dateObj),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: Text(
                  'Total: ${_kBrThreeDecimalFormatter.format(totalPesoDia)} Kg',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                children: [
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 16,
                    ),
                    child: Column(
                      children: [
                        // Cabeçalho da sub-lista
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Text(
                                'Artigo',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                'Peso Total',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Lista de Artigos
                        ...sortedArtigos.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.key, // Nome do Artigo
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    '${_kBrThreeDecimalFormatter.format(entry.value)} Kg',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _kPrimaryColorEmbalagem.darken(10),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Função para consolidar a lógica de exportação de Tinturaria
  Future<void> _handleTinturariaExport({
    required bool isPdf,
    required int selectedCount,
    bool isExcel = false, // ADICIONE ESTE PARÂMETRO
  }) async {
    if (!mounted) return;
    try {
      final allTinturaria = await _tinturariaFuture;

      final List<RegistroTinturaria> registrosToExport = selectedCount > 0
          ? allTinturaria
                .where(
                  (r) => _selectedTinturariaKeys.contains(_getTinturariaKey(r)),
                )
                .toList()
          : allTinturaria; // Se não houver seleção, exporta todos

      if (registrosToExport.isEmpty) {
        throw Exception("Nenhum pedido para exportar.");
      }

      final agrupadosTinturaria = <String, List<RegistroTinturaria>>{};
      for (var r in registrosToExport) {
        final chave = '${r.dataCorte} - ${r.turno}';
        agrupadosTinturaria.putIfAbsent(chave, () => []).add(r);
      }

      // ADICIONE ESTA CONDIÇÃO
      if (isPdf) {
        await _generateTinturariaPdf(registrosToExport);
      } else if (isExcel) {
        await _generateTinturariaExcel(registrosToExport);
      } else {
        final texto = _gerarTinturariaTextoCompartilhamento(
          agrupadosTinturaria,
        );
        if (texto.isNotEmpty) Share.share(texto);
      }

      // Desseleciona após a exportação (limpa o estado do widget)
      if (selectedCount > 0 && mounted) {
        setState(() => _selectedTinturariaKeys.clear());
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao compartilhar: ${e.toString()}')),
      );
    }
  }

  // Função para consolidar a lógica de exportação de Embalagem
  Future<void> _handleEmbalagemExport({
    required bool isPdf,
    required int selectedCount,
    bool isExcel = false, // ADICIONE ESTE PARÂMETRO
  }) async {
    if (!mounted) return;

    try {
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

      // ADICIONE ESTA CONDIÇÃO
      if (isPdf) {
        await _generateEmbalagemPdf(agrupadosEmbalagem);
      } else if (isExcel) {
        await _generateEmbalagemExcel(agrupadosEmbalagem);
      } else {
        final texto = _gerarTextoCompartilhamento(agrupadosEmbalagem);
        if (texto.isNotEmpty) Share.share(texto);
      }

      // Desseleciona após a exportação (limpa o estado do widget)
      if (selectedCount > 0 && mounted) {
        setState(() => _selectedEmbalagemKeys.clear());
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao compartilhar: ${e.toString()}')),
      );
    }
  }

  // ABA EMABALAGEM
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

        // Converte para lista e ordena por data decrescente
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
                      // ATUALIZADO: Usando o formatador brasileiro de 3 decimais e inteiro
                      'Peso: ${_kBrThreeDecimalFormatter.format(totalPeso)} Kg | Tambores: ${_kBrIntegerFormatter.format(totalQuantidade)}',
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

  // Cabeçalho com distribuição otimizada para mais colunas
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

  // Row da Tabela mais limpa
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
        onLongPress: () {
          // Menu ao fazer long-press
          showModalBottomSheet(
            context: context,
            builder: (context) => Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.edit, color: Colors.blue),
                    title: const Text('Editar'),
                    onTap: () {
                      Navigator.pop(context);
                      _editarRegistro(r, 0);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: const Text('Excluir'),
                    onTap: () {
                      Navigator.pop(context);
                      _deletarRegistro(r);
                    },
                  ),
                ],
              ),
            ),
          );
        },
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
            Expanded(
              flex: 2,
              // ATUALIZADO: Usando o formatador brasileiro de inteiro para quantidade
              child: Text(
                _kBrIntegerFormatter.format(r.quantidade),
                style: style,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                // ATUALIZADO: Usando o formatador brasileiro de 3 decimais
                _kBrThreeDecimalFormatter.format(r.peso),
                style: style,
              ),
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

  // ABA TINTURARIA
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

        // Converte para lista e ordena por data de corte decrescente
        final sortedGrupos = agrupados.entries.toList();
        sortedGrupos.sort((a, b) {
          final dateStrA = a.key.split(' - ')[0];
          final dateStrB = b.key.split(' - ')[0];
          final dateA = DateTime.tryParse(dateStrA) ?? DateTime(0);
          final dateB = DateTime.tryParse(dateStrB) ?? DateTime(0);
          return dateB.compareTo(dateA);
        });

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80, top: 8),
          itemCount: sortedGrupos.length,
          itemBuilder: (context, index) {
            final grupo = sortedGrupos.elementAt(index);

            // Verifica se todos os itens no grupo estão selecionados
            final groupKeys = grupo.value.map(_getTinturariaKey).toSet();
            final allGroupSelected = groupKeys.every(
              _selectedTinturariaKeys.contains,
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
                  iconColor: _kPrimaryColorTinturaria,
                  collapsedIconColor: Colors.black54,
                  // Título com Checkbox de Seleção em Massa
                  title: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24, // Ajusta a altura do checkbox
                        child: Checkbox(
                          value: allGroupSelected,
                          activeColor: _kPrimaryColorTinturaria,
                          onChanged: (bool? newValue) {
                            _toggleTinturariaGroupSelection(grupo.value);
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
                  subtitle: Padding(
                    padding: const EdgeInsets.only(left: 32.0),
                    child: Text(
                      'Registros: ${_kBrIntegerFormatter.format(grupo.value.length)}',
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

  // Cabeçalho com distribuição otimizada para Tinturaria
  Widget _buildTinturariaHeaderRow() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 30), // Espaço para o checkbox
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

  // Row da Tabela mais limpa com Checkbox e destaque
  Widget _buildRegistroTinturariaRow(RegistroTinturaria r, bool isEven) {
    final key = _getTinturariaKey(r);
    final isSelected = _selectedTinturariaKeys.contains(key);

    final style = TextStyle(
      fontSize: 10.5,
      color: isSelected
          ? _kPrimaryColorTinturaria.darken(10)
          : (isEven ? Colors.black87 : Colors.black54),
      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
    );

    final larguraElast = '${r.larguraCrua}/${r.elasticidadeCrua}';
    final dataTurno = '${r.dataCorte} / ${r.turno}';

    return Container(
      // Fundo em destaque quando selecionado
      color: isSelected
          ? _kPrimaryColorTinturaria.withOpacity(0.1)
          : (isEven ? Colors.white : Colors.grey.shade50),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: () => _toggleTinturariaSelection(
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
                activeColor: _kPrimaryColorTinturaria,
                onChanged: (bool? newValue) {
                  _toggleTinturariaSelection(r);
                },
              ),
            ),
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
      ),
    );
  }

  // ABA CONFRONTO (APRIMORADA)

  // NOVO: Função auxiliar para calcular rankings
  Map<String, double> _getTopRankings<T>(
    List<T> data,
    String Function(T item) groupKey,
    double Function(T item) valueExtractor,
    int topN,
  ) {
    if (data.isEmpty) return {};

    final Map<String, double> grouped = {};
    for (var item in data) {
      // Garante que a chave não é vazia para evitar problemas de agrupamento
      final key = groupKey(item).isEmpty ? 'N/A' : groupKey(item);
      final value = valueExtractor(item);
      // Soma o valor para a chave (Artigo, Conferente, etc.)
      grouped.update(
        key,
        (existing) => existing + value,
        ifAbsent: () => value,
      );
    }

    // Ordena de forma decrescente
    final sorted = grouped.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Pega o Top N
    final Map<String, double> topMap = {};
    for (var i = 0; i < sorted.length && i < topN; i++) {
      topMap[sorted[i].key] = sorted[i].value;
    }

    return topMap;
  }

  // NOVO: Widget para construir a lista de Rankings
  Widget _buildRankingList({
    required String title,
    required Map<String, double> rankings,
    required Color color,
    required String unit,
    int decimalPlaces = 0,
  }) {
    if (rankings.isEmpty) {
      return const SizedBox.shrink();
    }

    String formatValue(double value) {
      // ATUALIZADO: Usa o formatador apropriado com padrão brasileiro
      if (decimalPlaces == 0) {
        return _kBrIntegerFormatter.format(value);
      } else if (decimalPlaces == 3) {
        return _kBrThreeDecimalFormatter.format(value);
      } else {
        return _kBrDecimalFormatter.format(value);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color.darken(10),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            children: rankings.entries.map((entry) {
              final rank = rankings.keys.toList().indexOf(entry.key) + 1;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Text(
                      '#$rank',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${formatValue(entry.value)} $unit',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: color.darken(10),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // Card de Comparação mais elegante (mantido)
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
              Flexible(
                // Adicionado Flexible para evitar overflow
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
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

  // ATUALIZADO: Aba de confronto com mais dados e rankings
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

          // =======================================================
          // ANÁLISE ESTATÍSTICA - EMBALAGEM
          // =======================================================
          final totalPesoEmbalagem = embalagem.fold<double>(
            0,
            (sum, r) => sum + r.peso,
          );
          final totalQuantidadeEmbalagem = embalagem.fold<int>(
            0,
            (sum, r) => sum + r.quantidade,
          );
          final avgPesoPerDrum = totalQuantidadeEmbalagem > 0
              ? totalPesoEmbalagem / totalQuantidadeEmbalagem
              : 0.0;
          final uniqueArtigos = embalagem.map((r) => r.artigo).toSet().length;
          final uniqueOPs = embalagem
              .map((r) => r.ordemProducao)
              .toSet()
              .length;

          // Rankings Embalagem
          final topArtigos = _getTopRankings(
            embalagem,
            (r) => r.artigo,
            (r) => r.peso,
            5,
          );
          final topConferentesEmbalagem = _getTopRankings(
            embalagem,
            (r) => r.conferente,
            (r) => 1.0, // Contagem
            5,
          );

          // =======================================================
          // ANÁLISE ESTATÍSTICA - TINTURARIA
          // =======================================================
          final totalMaquinasTinturaria = tinturaria
              .map((e) => e.nMaquina)
              .where((m) => m.isNotEmpty)
              .toSet()
              .length;
          final totalLotesElastico = tinturaria
              .map((e) => e.loteElastico)
              .where((l) => l.isNotEmpty)
              .toSet()
              .length;
          final uniqueMateriais = tinturaria
              .map((e) => e.nomeMaterial)
              .where((m) => m.isNotEmpty)
              .toSet()
              .length;

          // Rankings Tinturaria
          final topMaquinas = _getTopRankings(
            tinturaria,
            (r) => r.nMaquina,
            (r) => 1.0,
            5,
          );
          final topConferentesTinturaria = _getTopRankings(
            tinturaria,
            (r) => r.conferente,
            (r) => 1.0,
            5,
          );

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ----------------------------------------------------
                // CARD RESUMO EMBALAGEM
                // ----------------------------------------------------
                _buildComparisionCard(
                  title: 'RESUMO GERAL - EMBALAGEM',
                  icon: Icons.inventory_2,
                  color: _kPrimaryColorEmbalagem,
                  metrics: {
                    // ATUALIZADO: Usando o formatador de inteiro
                    'Total de Registros': _kBrIntegerFormatter.format(
                      embalagem.length,
                    ),
                    'Peso Total':
                        // ATUALIZADO: Usando o formatador brasileiro de 3 decimais (agora com ponto de milhar)
                        '${_kBrThreeDecimalFormatter.format(totalPesoEmbalagem)} kg',
                    'Total de Tambores': _kBrIntegerFormatter.format(
                      totalQuantidadeEmbalagem,
                    ),
                    'Peso Médio por Tambor':
                        // ATUALIZADO: Usando o formatador brasileiro de 3 decimais (agora com ponto de milhar)
                        '${_kBrThreeDecimalFormatter.format(avgPesoPerDrum)} kg',
                  },
                ),
                // Rankings de Embalagem
                _buildRankingList(
                  title: 'TOP 5 Artigos por Peso Registrado',
                  rankings: topArtigos,
                  color: _kPrimaryColorEmbalagem,
                  unit: 'Kg',
                  decimalPlaces: 3,
                ),
                const SizedBox(height: 30),
                // ----------------------------------------------------
                // CARD RESUMO TINTURARIA
                // ----------------------------------------------------
                _buildComparisionCard(
                  title: 'RESUMO GERAL - RASCHELINA',
                  icon: Icons.color_lens,
                  color: _kPrimaryColorTinturaria,
                  metrics: {
                    // ATUALIZADO: Usando o formatador de inteiro
                    'Total de Registros': _kBrIntegerFormatter.format(
                      tinturaria.length,
                    ),
                    // ATUALIZADO: Usando o formatador de inteiro
                    'Lotes de Elástico Únicos': _kBrIntegerFormatter.format(
                      totalLotesElastico,
                    ),
                    // ATUALIZADO: Usando o formatador de inteiro
                    'Nomes de Material Únicos': _kBrIntegerFormatter.format(
                      uniqueMateriais,
                    ),
                  },
                ),
                // Rankings de Tinturaria
                _buildRankingList(
                  title: 'TOP 5 Máquinas por Contagem de Registros',
                  rankings: topMaquinas,
                  color: _kPrimaryColorTinturaria,
                  unit: 'Registros',
                  decimalPlaces: 0,
                ),
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }
}

// FUNÇÕES DE EXTENSÃO PARA CORES
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
