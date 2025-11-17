import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';
part 'registro.g.dart';

@HiveType(typeId: 0)
class Registro extends HiveObject {
  // O campo 'data' será usado como Data de Entrada
  @HiveField(0)
  DateTime data;

  @HiveField(1)
  int ordemProducao;

  @HiveField(2)
  int quantidade;

  @HiveField(3)
  String artigo;

  @HiveField(4)
  String cor;

  @HiveField(5)
  double peso;

  @HiveField(6)
  String conferente;

  @HiveField(7)
  String turno;

  @HiveField(8)
  double? metros;

  @HiveField(9)
  String? dataTingimento;

  @HiveField(10)
  String? numCorte;

  @HiveField(11)
  double? volumeProg;

  @HiveField(12)
  String? localizacao;

  @HiveField(13)
  DateTime? dataMovimentacao;

  // 🔥 NOVO CAMPO: Caixa
  @HiveField(14)
  String? caixa;

  Registro({
    required this.data,
    required this.ordemProducao,
    required this.quantidade,
    required this.artigo,
    required this.cor,
    required this.peso,
    required this.conferente,
    required this.turno,
    required this.metros,
    required this.dataTingimento,
    required this.numCorte,
    this.volumeProg,
    this.localizacao,
    this.dataMovimentacao,
    this.caixa, // ✅ O parâmetro nomeado 'caixa' está definido aqui.
  });

  // =======================================================================
  // Getters para formatação
  // =======================================================================

  /// Retorna o peso formatado com 3 casas decimais (ex: '0.500').
  String get pesoFormatado => peso.toStringAsFixed(3);

  /// Retorna os metros formatados com 3 casas decimais (ex: '100.000'),
  /// ou '0.000' se o valor for nulo.
  String get metrosFormatados => metros?.toStringAsFixed(3) ?? '0.000';

  /// Retorna o volume de programação formatado com 3 casas decimais.
  String get volumeProgFormatado => volumeProg?.toStringAsFixed(3) ?? '0.000';

  // =======================================================================
  // Construtor de Fábrica para mapear do JSON da API
  // =======================================================================
  factory Registro.fromJson(Map<String, dynamic> json) {
    final dataEntrada = json['DataEntrada'] != null
        ? DateTime.parse(json['DataEntrada'] as String)
        : DateTime.now();

    final dataSaida = json['DataSaida'] != null
        ? DateTime.parse(json['DataSaida'] as String)
        : null;

    return Registro(
      ordemProducao: json['NrOrdem'] as int,
      data: dataEntrada,
      artigo: json['Artigo'] as String,
      cor: json['Cor'] as String,
      quantidade: (json['Quantidade'] as num).toInt(),
      peso: (json['Peso'] as num).toDouble(),
      metros: (json['Metros'] as num?)?.toDouble(),
      volumeProg: (json['VolumeProg'] as num?)?.toDouble(),
      conferente: json['Conferente'] as String,
      turno: json['Turno'] as String,
      numCorte: json['NumCorte'] as String?,
      dataTingimento: '',
      localizacao: json['Localizacao'] as String?,
      dataMovimentacao: dataSaida,
      caixa: json['Caixa'] as String?, // ✅ Mapeamento do campo Caixa
    );
  }

  Map<String, dynamic> toJson() => {
    'data': data.toIso8601String(),
    'ordem_producao': ordemProducao,
    'quantidade': quantidade,
    'artigo': artigo,
    'cor': cor,
    'peso': peso,
    'conferente': conferente,
    'turno': turno,
    'metros': metros,
    'data_tingimento': dataTingimento,
    'num_corte': numCorte,
    'volume_prog': volumeProg,
    'localizacao': localizacao,
    'data_movimentacao': dataMovimentacao?.toIso8601String(),
    'caixa': caixa, // ✅ Adicionado ao toJson
  };
}
