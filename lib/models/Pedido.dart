class Pedido {
  final int id;
  final int nrOrdem;
  final String artigo;
  final String cor;
  final double quantidade;
  final double peso;
  final String conferente;
  final String turno;
  final double metros;
  final DateTime dataEntrada;
  final DateTime? dataSaida;
  final String? numCorte;
  final double volumeProg;
  final String? localizacao;
  final String? caixa; // 🔥 NOVO CAMPO: caixa

  Pedido({
    required this.id,
    required this.nrOrdem,
    required this.artigo,
    required this.cor,
    required this.quantidade,
    required this.peso,
    required this.conferente,
    required this.turno,
    required this.metros,
    required this.dataEntrada,
    this.dataSaida,
    this.numCorte,
    required this.volumeProg,
    this.localizacao,
    this.caixa, // ✅ Adicionado ao construtor
  });

  factory Pedido.fromJson(Map<String, dynamic> json) => Pedido(
    id: json['ID'],
    nrOrdem: json['NrOrdem'],
    artigo: json['Artigo'],
    cor: json['Cor'],
    quantidade: (json['Quantidade'] as num).toDouble(),
    peso: (json['Peso'] as num).toDouble(),
    conferente: json['Conferente'],
    turno: json['Turno'],
    metros: (json['Metros'] as num).toDouble(),
    dataEntrada: DateTime.parse(json['DataEntrada']),
    dataSaida: json['DataSaida'] != null
        ? DateTime.parse(json['DataSaida'])
        : null,
    numCorte: json['NumCorte'],
    volumeProg: (json['VolumeProg'] as num).toDouble(),
    localizacao: json['Localizacao'],
    caixa: json['Caixa'], // ✅ Mapeamento do campo Caixa
  );
}
