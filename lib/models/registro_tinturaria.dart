// registro_tinturaria.dart
import 'package:hive/hive.dart';
part 'registro_tinturaria.g.dart';

@HiveType(typeId: 0)
class RegistroTinturaria extends HiveObject {
  @HiveField(0)
  String nomeMaterial;

  @HiveField(1)
  String larguraCrua;

  @HiveField(2)
  String elasticidadeCrua;

  @HiveField(3)
  String nMaquina;

  @HiveField(4)
  String dataCorte;

  @HiveField(5)
  String loteElastico;

  @HiveField(6)
  String conferente;

  @HiveField(7)
  String turno;

  RegistroTinturaria({
    required this.nomeMaterial,
    required this.larguraCrua,
    required this.elasticidadeCrua,
    required this.nMaquina,
    required this.dataCorte,
    required this.loteElastico,
    required this.conferente,
    required this.turno,
  });

  Map<String, dynamic> toJson() => {
    'nomeMaterial': nomeMaterial,
    'larguraCrua': larguraCrua,
    'elasticidadeCrua': elasticidadeCrua,
    'nMaquina': nMaquina,
    'dataCorte': dataCorte,
    'loteElastico': loteElastico,
    'conferente': conferente,
    'turno': turno,
  };
}
