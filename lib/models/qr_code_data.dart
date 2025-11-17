class QrCodeData {
  final int ordem;
  final String artigo;
  final String cor;
  final int numeroTambores;
  final double peso;
  final double metros;
  final String dataTingimento;
  final String numCorte;
  final String volumeProg;
  final String caixa; // 🔥 NOVO CAMPO ADICIONADO: caixa

  QrCodeData({
    required this.ordem,
    required this.artigo,
    required this.cor,
    required this.numeroTambores,
    required this.peso,
    required this.metros,
    required this.dataTingimento,
    required this.numCorte,
    required this.volumeProg,
    required this.caixa, // ✅ Adicionado ao construtor
  });

  factory QrCodeData.fromJson(Map<String, dynamic> json) {
    // Função auxiliar para analisar números com segurança
    double parseDouble(dynamic valor) {
      if (valor == null) return 0.0;
      if (valor is num) return valor.toDouble();
      final texto = valor.toString().replaceAll(',', '.').trim();
      return double.tryParse(texto) ?? 0.0;
    }

    // Função auxiliar para analisar inteiros com segurança
    int parseInt(dynamic valor) {
      if (valor == null) return 0;
      if (valor is int) return valor;
      final texto = valor.toString().trim();
      return int.tryParse(texto) ?? 0;
    }

    // Função auxiliar para pegar strings com segurança
    String parseString(dynamic valor) {
      if (valor == null) return '';
      return valor.toString();
    }

    return QrCodeData(
      ordem: parseInt(json['Ordem']),
      artigo: parseString(json['Artigo']),
      cor: parseString(json['Cor']),
      numeroTambores: parseInt(json['Tambores']),
      peso: parseDouble(json['Peso']),
      metros: parseDouble(json['Metros']),
      dataTingimento: parseString(json['DataTingimento']),
      numCorte: parseString(json['NumCorte']),
      volumeProg: parseString(json['VolumeProg']),
      caixa: parseString(json['Caixa']), 
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Ordem': ordem,
      'Artigo': artigo,
      'Cor': cor,
      'Tambores': numeroTambores,
      'Peso': peso.toStringAsFixed(3), // Aplicar formatação aqui
      'Metros': metros.toStringAsFixed(3), // Aplicar formatação aqui
      'DataTingimento': dataTingimento,
      'NumCorte': numCorte,
      'VolumeProg': volumeProg,
      'Caixa': caixa, // ✅ Adicionado ao toJson
    };
  }
}
