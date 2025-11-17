// qr_code_data_tinturaria.dart
class QrCodeDataTinturaria {
  final String nomeMaterial;
  final String larguraCrua;
  final String elasticidadeCrua;
  final String nMaquina;
  final String dataCorte;
  final String loteElastico;

  QrCodeDataTinturaria({
    required this.nomeMaterial,
    required this.larguraCrua,
    required this.elasticidadeCrua,
    required this.nMaquina,
    required this.dataCorte,
    required this.loteElastico,
  });

  factory QrCodeDataTinturaria.fromJson(Map<String, dynamic> json) {
    String parseString(dynamic valor) {
      if (valor == null) return '';
      return valor.toString();
    }

    return QrCodeDataTinturaria(
      nomeMaterial: parseString(json['nomeMaterial']).toUpperCase(),
      larguraCrua: parseString(json['larguraCrua']),
      elasticidadeCrua: parseString(json['elasticidadeCrua']),
      nMaquina: parseString(json['nMaquina']),
      dataCorte: parseString(json['dataCorte']),
      loteElastico: parseString(json['loteElastico']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nomeMaterial': nomeMaterial,
      'larguraCrua': larguraCrua,
      'elasticidadeCrua': elasticidadeCrua,
      'nMaquina': nMaquina,
      'dataCorte': dataCorte,
      'loteElastico': loteElastico,
    };
  }
}
