class CheckinTambores {
  const CheckinTambores({
    required this.id,
    required this.quantidadeTambores,
    required this.volumeTotal,
    required this.checkinInicialEm,
    this.checkinFinalEm,
  });

  final String id;
  final int quantidadeTambores;
  final double volumeTotal;
  final DateTime checkinInicialEm;
  final DateTime? checkinFinalEm;

  bool get finalizado => checkinFinalEm != null;

  String get status => finalizado ? 'FINALIZADO' : 'EM_ANDAMENTO';

  CheckinTambores copyWith({
    int? quantidadeTambores,
    double? volumeTotal,
    DateTime? checkinInicialEm,
    DateTime? checkinFinalEm,
  }) {
    return CheckinTambores(
      id: id,
      quantidadeTambores: quantidadeTambores ?? this.quantidadeTambores,
      volumeTotal: volumeTotal ?? this.volumeTotal,
      checkinInicialEm: checkinInicialEm ?? this.checkinInicialEm,
      checkinFinalEm: checkinFinalEm ?? this.checkinFinalEm,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_checkin_tambores': id,
      'quantidade_tambores': quantidadeTambores,
      'volume_total': volumeTotal,
      'checkin_inicial_em': checkinInicialEm.toIso8601String(),
      'checkin_final_em': checkinFinalEm?.toIso8601String(),
      'status': status,
    };
  }

  factory CheckinTambores.fromJson(Map<String, dynamic> json) {
    return CheckinTambores(
      id: (json['id_checkin_tambores'] ?? json['id'] ?? '').toString(),
      quantidadeTambores: _toInt(json['quantidade_tambores']),
      volumeTotal: _toDouble(json['volume_total']),
      checkinInicialEm: DateTime.parse(json['checkin_inicial_em'].toString()),
      checkinFinalEm:
          json['checkin_final_em'] == null ||
              json['checkin_final_em'].toString().trim().isEmpty
          ? null
          : DateTime.tryParse(json['checkin_final_em'].toString()),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('${value ?? ''}'.trim()) ?? 0;
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}'.trim().replaceAll(',', '.')) ?? 0;
  }
}

class CheckinTamboresItem {
  const CheckinTamboresItem({
    required this.id,
    required this.idCheckin,
    required this.codigoTambor,
    required this.volume,
    required this.bipadoEm,
    required this.ordemProducao,
    required this.artigo,
    required this.quantidadeTambores,
  });

  final String id;
  final String idCheckin;
  final String codigoTambor;
  final double volume;
  final DateTime bipadoEm;
  final String ordemProducao;
  final String artigo;
  final int quantidadeTambores;

  factory CheckinTamboresItem.fromJson(Map<String, dynamic> json) {
    return CheckinTamboresItem(
      id: (json['id_checkin_tambores_item'] ?? json['id'] ?? '').toString(),
      idCheckin: (json['id_checkin_tambores'] ?? '').toString(),
      codigoTambor: (json['codigo_tambor'] ?? '').toString(),
      volume: CheckinTambores._toDouble(json['volume']),
      bipadoEm: DateTime.tryParse((json['bipado_em'] ?? '').toString()) ??
          DateTime.now(),
      ordemProducao: (json['ordem_producao'] ?? '').toString(),
      artigo: (json['artigo'] ?? '').toString(),
      quantidadeTambores: CheckinTambores._toInt(
        json['quantidade_tambores'] ?? 1,
      ),
    );
  }
}
