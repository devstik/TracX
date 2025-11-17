class HistoricoMov {
  final int id;
  final int nrOrdem;
  final String localizacaoOrigem;
  final String localizacaoDestino;
  final DateTime dataMovimentacao;
  final String conferente;
  final String tipoMovimentacao;

  HistoricoMov({
    required this.id,
    required this.nrOrdem,
    required this.localizacaoOrigem,
    required this.localizacaoDestino,
    required this.dataMovimentacao,
    required this.conferente,
    required this.tipoMovimentacao,
  });

  factory HistoricoMov.fromJson(Map<String, dynamic> json) {
    return HistoricoMov(
      id: json['ID'] ?? 0,
      nrOrdem: json['NrOrdem'] ?? 0,
      localizacaoOrigem: json['LocalizacaoOrigem'] ?? 'N/A',
      localizacaoDestino: json['LocalizacaoDestino'] ?? 'N/A',
      dataMovimentacao: json['DataMovimentacao'] != null
          ? DateTime.parse(json['DataMovimentacao'])
          : DateTime.now(),
      conferente: json['Conferente'] ?? '',
      tipoMovimentacao: json['TipoMovimentacao'] ?? 'NORMAL',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ID': id,
      'NrOrdem': nrOrdem,
      'LocalizacaoOrigem': localizacaoOrigem,
      'LocalizacaoDestino': localizacaoDestino,
      'DataMovimentacao': dataMovimentacao.toIso8601String(),
      'Conferente': conferente,
      'TipoMovimentacao': tipoMovimentacao,
    };
  }
}
