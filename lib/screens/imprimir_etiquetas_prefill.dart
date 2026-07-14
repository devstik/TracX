class EtiquetaDetalhePrefill {
  final int detalheId;
  final String detalheTexto;
  final String loteTexto;

  const EtiquetaDetalhePrefill({
    required this.detalheId,
    required this.detalheTexto,
    required this.loteTexto,
  });
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('${value ?? ''}'.trim()) ?? 0;
}

String _firstText(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return '';
}

EtiquetaDetalhePrefill resolverDetalheAutomatico({
  required List<Map<String, dynamic>> lotes,
  required bool temPreto,
  required bool usaDropdownDetalhe,
  Map<String, dynamic>? fallback,
}) {
  final fallbackDetalheId = _toInt(
    fallback?['CdLot'] ??
        fallback?['cdLot'] ??
        fallback?['cd_lot'] ??
        fallback?['DetalheId'] ??
        fallback?['detalhe_id'] ??
        fallback?['Detalhe'] ??
        fallback?['detalhe'],
  );
  final fallbackDetalheTexto = _firstText(fallback ?? const {}, const [
    'NmLot',
    'nmLot',
    'nm_lot',
    'NmDetalhe',
    'nmDetalhe',
    'Detalhe',
    'detalhe',
  ]);
  final fallbackLoteTexto = _firstText(fallback ?? const {}, const [
    'Lote',
    'lote',
    'NmLot',
    'nmLot',
    'nm_lot',
    'NmDetalhe',
    'nmDetalhe',
  ]);

  if (lotes.isEmpty) {
    return EtiquetaDetalhePrefill(
      detalheId: fallbackDetalheId,
      detalheTexto: temPreto ? '' : fallbackDetalheTexto,
      loteTexto: temPreto ? fallbackLoteTexto : '',
    );
  }

  Map<String, dynamic>? primeiroValido;
  for (final lot in lotes) {
    final cdLot = _toInt(
      lot['CdLot'] ??
          lot['cdLot'] ??
          lot['cd_lot'] ??
          lot['DetalheId'] ??
          lot['detalhe_id'] ??
          lot['Detalhe'] ??
          lot['detalhe'],
    );
    if (cdLot > 0) {
      primeiroValido = lot;
      break;
    }
  }

  if (primeiroValido == null) {
    return EtiquetaDetalhePrefill(
      detalheId: fallbackDetalheId,
      detalheTexto: temPreto ? '' : fallbackDetalheTexto,
      loteTexto: temPreto ? fallbackLoteTexto : '',
    );
  }

  final detalheId = _toInt(
    primeiroValido['CdLot'] ??
        primeiroValido['cdLot'] ??
        primeiroValido['cd_lot'] ??
        primeiroValido['DetalheId'] ??
        primeiroValido['detalhe_id'] ??
        primeiroValido['Detalhe'] ??
        primeiroValido['detalhe'],
  );
  final loteTexto = _firstText(primeiroValido, const [
    'NmLot',
    'nmLot',
    'nm_lot',
    'NmDetalhe',
    'nmDetalhe',
    'Detalhe',
    'detalhe',
  ]);

  if (temPreto) {
    return EtiquetaDetalhePrefill(
      detalheId: detalheId,
      detalheTexto: '',
      loteTexto: loteTexto,
    );
  }

  return EtiquetaDetalhePrefill(
    detalheId: detalheId,
    detalheTexto: usaDropdownDetalhe ? '' : loteTexto,
    loteTexto: '',
  );
}
