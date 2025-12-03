// services/estoque_db_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/estoque_item.dart'; // Importe o modelo criado

class EstoqueDbHelper {
  static final EstoqueDbHelper _instance = EstoqueDbHelper._internal();
  factory EstoqueDbHelper() => _instance;
  EstoqueDbHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'estoque_database.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  // Cria a tabela de estoque
  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE estoque(
        objetoID INTEGER PRIMARY KEY,
        objeto TEXT,
        detalheID INTEGER,
        detalhe TEXT
        -- Adicionar outras colunas aqui
      )
    ''');
  }

  // Insere uma lista de itens, substituindo se já existir (upsert)
  Future<void> insertAllEstoque(List<EstoqueItem> itens) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var item in itens) {
        await txn.insert(
          'estoque',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm
              .replace, // Substitui se a PK (objetoID) já existir
        );
      }
    });
  }

  // Consulta um item pelo objetoID (usado no QR Code)
  Future<EstoqueItem?> getEstoqueItem(int objetoID) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'estoque',
      where: 'objetoID = ?',
      whereArgs: [objetoID],
    );

    if (maps.isNotEmpty) {
      return EstoqueItem.fromMap(maps.first);
    }
    return null;
  }
}
