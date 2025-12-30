// services/estoque_db_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/estoque_item.dart';

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
    // ATENÇÃO: Alterado para versão 5 para disparar o _onUpgrade
    return await openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // Criação inicial das tabelas
  Future _onCreate(Database db, int version) async {
    // Tabela de estoque de produtos (QR Code)
    await db.execute('''
      CREATE TABLE estoque(
        objetoID INTEGER PRIMARY KEY,
        objeto TEXT,
        detalheID INTEGER,
        detalhe TEXT
      )
    ''');

    // Tabela para Cache do Mapa de Produção
    await db.execute('''
      CREATE TABLE mapa_producao(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        data_iso TEXT,
        produtoId INTEGER,
        quantidade REAL,
        operacaoId INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE catalogo_produtos (
        produtoId INTEGER PRIMARY KEY,
        nome TEXT,
        detalhe TEXT
      )
    ''');

    // Tabela para Cache do Gráfico de Produção
    await db.execute('''
      CREATE TABLE cache_grafico (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        periodo TEXT,
        valor REAL,
        tipo_grafico TEXT,
        atualizado_em TEXT
      )
    ''');

    // NOVA: Tabela para Login Offline
    await db.execute('''
      CREATE TABLE usuarios_autorizados (
        username TEXT PRIMARY KEY,
        ultima_autenticacao TEXT
      )
    ''');
  }

  // Gerencia a atualização do banco sem perder dados antigos
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'CREATE TABLE mapa_producao(id INTEGER PRIMARY KEY AUTOINCREMENT, data_iso TEXT, produtoId INTEGER, quantidade REAL, operacaoId INTEGER)',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        'CREATE TABLE cache_grafico (id INTEGER PRIMARY KEY AUTOINCREMENT, periodo TEXT, valor REAL, tipo_grafico TEXT, atualizado_em TEXT)',
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        'CREATE TABLE usuarios_autorizados (username TEXT PRIMARY KEY, ultima_autenticacao TEXT)',
      );
    }
    // O SEGREDO ESTÁ AQUI: Se a versão for menor que 5, cria a tabela que está faltando
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS catalogo_produtos (
          produtoId INTEGER PRIMARY KEY,
          nome TEXT,
          detalhe TEXT
        )
      ''');
    }
  }

  // --- MÉTODOS DE LOGIN OFFLINE ---

  /// Salva o usuário que logou com sucesso via API
  Future<void> salvarUsuarioLocal(String username) async {
    final db = await database;
    await db.insert('usuarios_autorizados', {
      'username': username.toLowerCase().trim(),
      'ultima_autenticacao': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Verifica se o usuário já logou anteriormente neste dispositivo
  Future<bool> verificarUsuarioLocal(String username) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'usuarios_autorizados',
      where: 'username = ?',
      whereArgs: [username.toLowerCase().trim()],
    );
    return maps.isNotEmpty;
  }

  // --- MÉTODOS DO ESTOQUE (QR CODE) ---

  Future<void> insertAllEstoque(List<EstoqueItem> itens) async {
    final db = await database;
    await db.transaction((txn) async {
      for (var item in itens) {
        await txn.insert(
          'estoque',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<EstoqueItem>> getAllEstoque() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('estoque');

    return List.generate(maps.length, (i) {
      return EstoqueItem.fromMap(maps[i]);
    });
  }

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

  // --- MÉTODOS DO MAPA DE PRODUÇÃO (CACHE) ---

  Future<void> insertMapas(
    List<Map<String, dynamic>> registros,
    String isoDate,
  ) async {
    final db = await database;
    final batch = db.batch();

    for (var reg in registros) {
      batch.insert('mapa_producao', {
        'data_iso': isoDate,
        'produtoId': reg['produtoId'],
        'quantidade': reg['quantidade'],
        'operacaoId': reg['operacaoId'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getMapasByDate(String isoDate) async {
    final db = await database;
    return await db.query(
      'mapa_producao',
      where: 'data_iso = ?',
      whereArgs: [isoDate],
    );
  }

  // Métodos para persistir o catálogo
  Future<void> salvarProdutosCatalogo(
    List<Map<String, dynamic>> produtos,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (var p in produtos) {
      batch.insert('catalogo_produtos', {
        'produtoId': p['objetoID'],
        'nome': p['objeto'],
        'detalhe': p['detalhe'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<Map<int, Map<String, String>>> getCatalogoMap() async {
    final db = await database;
    final List<Map<String, dynamic>> res = await db.query('catalogo_produtos');
    return {
      for (var item in res)
        item['produtoId'] as int: {
          'nome': item['nome'] as String,
          'detalhe': item['detalhe'] as String,
        },
    };
  }
  // --- MÉTODOS DO GRÁFICO DE PRODUÇÃO (CACHE & AUTO-UPDATE) ---

  /// Salva todos os pontos do gráfico de uma vez (Batch)
  Future<void> salvarCacheGrafico(
    List<Map<String, dynamic>> dados,
    String tipo,
  ) async {
    final db = await database;
    final batch = db.batch();

    // Limpa o cache anterior do tipo específico (ex: 'diario' ou 'mensal')
    batch.delete('cache_grafico', where: 'tipo_grafico = ?', whereArgs: [tipo]);

    for (var item in dados) {
      batch.insert('cache_grafico', {
        'periodo': item['periodo'], // Data ou Nome do Eixo X
        'valor': item['valor'], // Valor do Eixo Y
        'tipo_grafico': tipo,
        'atualizado_em': DateTime.now().toIso8601String(),
      });
    }
    await batch.commit(noResult: true);
  }

  /// Recupera os dados do gráfico salvos localmente
  Future<List<Map<String, dynamic>>> buscarCacheGrafico(String tipo) async {
    final db = await database;
    return await db.query(
      'cache_grafico',
      where: 'tipo_grafico = ?',
      whereArgs: [tipo],
    );
  }

  // --- LIMPEZA DE CACHE ---

  Future<void> clearMapaCache() async {
    final db = await database;
    await db.delete('mapa_producao');
  }

  Future<void> clearGraficoCache() async {
    final db = await database;
    await db.delete('cache_grafico');
  }
}
