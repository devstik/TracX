// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'registro_tinturaria.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RegistroTinturariaAdapter extends TypeAdapter<RegistroTinturaria> {
  @override
  final int typeId = 0;

  @override
  RegistroTinturaria read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RegistroTinturaria(
      nomeMaterial: fields[0] as String,
      larguraCrua: fields[1] as String,
      elasticidadeCrua: fields[2] as String,
      nMaquina: fields[3] as String,
      dataCorte: fields[4] as String,
      loteElastico: fields[5] as String,
      conferente: fields[6] as String,
      turno: fields[7] as String,
    );
  }

  @override
  void write(BinaryWriter writer, RegistroTinturaria obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.nomeMaterial)
      ..writeByte(1)
      ..write(obj.larguraCrua)
      ..writeByte(2)
      ..write(obj.elasticidadeCrua)
      ..writeByte(3)
      ..write(obj.nMaquina)
      ..writeByte(4)
      ..write(obj.dataCorte)
      ..writeByte(5)
      ..write(obj.loteElastico)
      ..writeByte(6)
      ..write(obj.conferente)
      ..writeByte(7)
      ..write(obj.turno);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegistroTinturariaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
