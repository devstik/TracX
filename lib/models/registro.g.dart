// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'registro.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RegistroAdapter extends TypeAdapter<Registro> {
  @override
  final int typeId = 0;

  @override
  Registro read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Registro(
      data: fields[0] as DateTime,
      ordemProducao: fields[1] as int,
      quantidade: fields[2] as int,
      artigo: fields[3] as String,
      cor: fields[4] as String,
      peso: fields[5] as double,
      conferente: fields[6] as String,
      turno: fields[7] as String,
      metros: fields[8] as double?,
      dataTingimento: fields[9] as String?,
      numCorte: fields[10] as String?,
      volumeProg: fields[11] as double?,
      localizacao: fields[12] as String?,
      dataMovimentacao: fields[13] as DateTime?,
      caixa: fields[14] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Registro obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.data)
      ..writeByte(1)
      ..write(obj.ordemProducao)
      ..writeByte(2)
      ..write(obj.quantidade)
      ..writeByte(3)
      ..write(obj.artigo)
      ..writeByte(4)
      ..write(obj.cor)
      ..writeByte(5)
      ..write(obj.peso)
      ..writeByte(6)
      ..write(obj.conferente)
      ..writeByte(7)
      ..write(obj.turno)
      ..writeByte(8)
      ..write(obj.metros)
      ..writeByte(9)
      ..write(obj.dataTingimento)
      ..writeByte(10)
      ..write(obj.numCorte)
      ..writeByte(11)
      ..write(obj.volumeProg)
      ..writeByte(12)
      ..write(obj.localizacao)
      ..writeByte(13)
      ..write(obj.dataMovimentacao)
      ..writeByte(14)
      ..write(obj.caixa);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegistroAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
