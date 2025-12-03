// models/estoque_item.dart
class EstoqueItem {
  final int objetoID;
  final String objeto;
  final int detalheID;
  final String detalhe;
  // Adicione outros campos relevantes que deseja armazenar

  EstoqueItem({
    required this.objetoID,
    required this.objeto,
    required this.detalheID,
    required this.detalhe,
    // ...
  });

  // Converte um Map (do JSON da API ou do SQLite) para um EstoqueItem
  factory EstoqueItem.fromMap(Map<String, dynamic> map) {
    return EstoqueItem(
      // A API retorna objetoID, mas o SQLite retorna int ou BigInt
      objetoID: map['objetoID'] as int,
      objeto: map['objeto'] as String,
      detalheID: map['detalheID'] as int,
      detalhe: map['detalhe'] as String,
      // ...
    );
  }

  // Converte um EstoqueItem para um Map (para salvar no SQLite)
  Map<String, dynamic> toMap() {
    return {
      'objetoID': objetoID,
      'objeto': objeto,
      'detalheID': detalheID,
      'detalhe': detalhe,
      // ...
    };
  }
}