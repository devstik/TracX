// services/estoque_db_helper.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/estoque_item.dart'; // Importe o modelo criado

class EstoqueDbHelper {
  static final EstoqueDbHelper _instance = EstoqueDbHelper._internal();
  factory EstoqueDbHelper() => _instance;
  EstoqueDbHelper._internal();

  static Database? _database;
  static const _dbVersion = 7;

  Future<Database?> get database async {
    if (kIsWeb) return null;
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'estoque_database.db');
    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
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
    await _createCaixasTable(db);
    await _seedCaixasTable(db);
    await _createRomaneioCacheTables(db);
    await _createAlocacaoCacheTables(db);
    await _createConferenciaAuditoriaTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createCaixasTable(db);
      await _seedCaixasTable(db);
    }
    if (oldVersion < 3) {
      await _createRomaneioCacheTables(db);
    }
    if (oldVersion < 4) {
      await _createAlocacaoCacheTables(db);
    }
    if (oldVersion < 5) {
      await _createCaixasTable(db);
      await db.execute('''
        UPDATE caixas
        SET caixa_p = 1200
        WHERE artigo = 'X Nillo 25 mm'
      ''');
    }
    if (oldVersion < 6) {
      await _createCaixasTable(db);
      await db.execute('''
        UPDATE caixas
        SET caixa_p = 600
        WHERE artigo = 'Dayane 17 UP N mm'
      ''');
    }
    if (oldVersion < 7) {
      await _createConferenciaAuditoriaTable(db);
    }
  }

  Future<void> _createCaixasTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS caixas (
        artigo TEXT PRIMARY KEY,
        caixa_p DECIMAL(18,2),
        enfestado DECIMAL(18,2),
        enfraldado DECIMAL(18,2),
        caixa_g DECIMAL(18,2),
        disco DECIMAL(18,2)
      )
    ''');
  }

  Future<void> _createRomaneioCacheTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS romaneio_cache (
        cache_key TEXT NOT NULL,
        item_key TEXT NOT NULL,
        payload TEXT NOT NULL,
        PRIMARY KEY (cache_key, item_key)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS romaneio_sync (
        cache_key TEXT PRIMARY KEY,
        last_sync TEXT
      )
    ''');
  }

  Future<void> _createAlocacaoCacheTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS alocacao_cache (
        sku TEXT NOT NULL,
        endereco TEXT NOT NULL,
        detalhe TEXT,
        detalhe_id INTEGER,
        saldo INTEGER,
        PRIMARY KEY (sku, endereco, detalhe_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS alocacao_sync (
        sku TEXT PRIMARY KEY,
        last_sync TEXT
      )
    ''');
  }

  Future<void> _createConferenciaAuditoriaTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conferencia_auditoria (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        tipo TEXT NOT NULL,
        romaneio INTEGER,
        pedido INTEGER,
        usuario TEXT,
        opcao TEXT,
        sucesso INTEGER,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_conf_auditoria_romaneio_ts
      ON conferencia_auditoria (romaneio, timestamp)
    ''');
  }

  Future<void> _seedCaixasTable(Database db) async {
    const caixasSeeds = [
      {'artigo': 'Agda 06 mm', 'caixa_p': 600, 'caixa_g': 4000},
      {'artigo': 'Agda 08 mm', 'caixa_p': 600, 'caixa_g': 4000},
      {'artigo': 'Agda 25 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Ana 80 mm', 'caixa_p': 600, 'caixa_g': 550},
      {'artigo': 'Atlas 11 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Belly 60 mm', 'caixa_p': 300, 'caixa_g': 550},
      {'artigo': 'Beta 15 mm', 'caixa_p': 1200, 'caixa_g': 2000},
      {'artigo': 'Beta 20 mm', 'caixa_p': 1000, 'caixa_g': 2000},
      {'artigo': 'Camila 80 mm', 'caixa_p': 300, 'caixa_g': 550},
      {'artigo': 'Capi 35 mm', 'caixa_p': 550, 'caixa_g': 1100},
      {'artigo': 'Caricia 11 mm', 'caixa_p': 600, 'caixa_g': 2200},
      {'artigo': 'Caricia 14 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Cela II 25 mm', 'caixa_p': 600, 'caixa_g': 1000},
      {'artigo': 'Chll 05 mm', 'caixa_p': 1200, 'caixa_g': 8000},
      {'artigo': 'Canoa 40 mm', 'enfestado': 500, 'disco': 750},
      {'artigo': 'Canoa 50 mm', 'enfestado': 500, 'disco': 900},
      {'artigo': 'Cinta 180 mm', 'enfestado': 80, 'enfraldado': 100},
      {'artigo': 'Cintra 22 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Dayane 10 UP N mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Dayane 13 UP N mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Dayane 17 UP N mm', 'caixa_p': 600, 'caixa_g': 1100},
      {'artigo': 'Egito 16 mm', 'caixa_p': 1200, 'caixa_g': 3000},
      {'artigo': 'Egito 17 mm', 'caixa_p': 1200, 'caixa_g': 3000},
      {'artigo': 'Egito 25 mm', 'caixa_p': 600, 'caixa_g': 2200},
      {'artigo': 'Eros 11 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Esbelt 140 mm', 'enfraldado': 200},
      {'artigo': 'Eva 65 mm', 'caixa_p': 300, 'caixa_g': 550},
      {'artigo': 'Flor 100 mm', 'enfestado': 80, 'disco': 100},
      {'artigo': 'Flor 80 mm', 'enfestado': 80, 'caixa_g': 100},
      {'artigo': 'Fortim 40 mm', 'enfestado': 1000, 'enfraldado': 1050},
      {'artigo': 'Fortim 50 mm', 'enfestado': 1000, 'enfraldado': 900},
      {'artigo': 'Grecia 10 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Grecia 14 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Grecia 17 mm', 'caixa_p': 550, 'caixa_g': 1100},
      {'artigo': 'Ina 33 mm', 'caixa_p': 550, 'caixa_g': 1100},
      {'artigo': 'Barra 20 UP mm', 'enfestado': 1000, 'disco': 1600},
      {'artigo': 'Barra 30 UP mm', 'enfestado': 1000, 'disco': 1500},
      {'artigo': 'Barra 35 UP mm', 'enfestado': 1000, 'disco': 1200},
      {'artigo': 'Barra 40 UP mm', 'enfestado': 1000, 'disco': 1050},
      {'artigo': 'Barra 50 UP mm', 'enfestado': 1000, 'disco': 900},
      {'artigo': 'Taiba 05 mm', 'caixa_p': 2000, 'caixa_g': 4000},
      {'artigo': 'Taiba 07 mm', 'caixa_p': 2000, 'caixa_g': 4000},
      {'artigo': 'Taiba 10 mm', 'caixa_p': 2000, 'caixa_g': 4000},
      {'artigo': 'Taiba 12 mm', 'caixa_p': 2000, 'caixa_g': 4000},
      {'artigo': 'Taiba 15 mm', 'caixa_p': 1500, 'caixa_g': 3000},
      {'artigo': 'Taiba 20 mm', 'caixa_p': 1100, 'caixa_g': 2200},
      {'artigo': 'Taiba 25 mm', 'caixa_p': 1000, 'caixa_g': 1800},
      {'artigo': 'Taiba 30 mm', 'caixa_p': 1000, 'caixa_g': 1500},
      {'artigo': 'Taiba 35 mm', 'caixa_p': 1000, 'caixa_g': 1200},
      {'artigo': 'Taiba 40 mm', 'caixa_p': 1000, 'caixa_g': 1050},
      {'artigo': 'Taiba 50 mm', 'caixa_p': 1000, 'caixa_g': 900},
      {'artigo': 'Lady 11 mm', 'caixa_p': 600, 'caixa_g': 2200},
      {'artigo': 'Lady 14 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Lara 25 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Leno 11 mm', 'caixa_p': 600, 'caixa_g': 2200},
      {'artigo': 'Leno 13 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Leno 17 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Lirio 25 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Listras 50 mm', 'caixa_p': 300, 'caixa_g': 550},
      {'artigo': 'Luna 30 mm', 'caixa_p': 550, 'caixa_g': 1100},
      {'artigo': 'Magno 10 UP mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Magno 14 UP mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Magno 18 UP mm', 'caixa_p': 550, 'caixa_g': 1100},
      {'artigo': 'Mirela 07 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Mirela 10 UP mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Mirela 14 UP mm', 'caixa_p': 600, 'caixa_g': 1500},
      {'artigo': 'Mirela 17 UP mm', 'caixa_p': 550, 'caixa_g': 1100},
      {'artigo': 'Mirra 50 mm', 'caixa_p': 550, 'caixa_g': 1100},
      {'artigo': 'Nadia 10 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Nadia 14 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Nadia 17 mm', 'caixa_p': 550, 'caixa_g': 1100},
      {'artigo': 'Nadia 22 mm', 'caixa_p': 550, 'caixa_g': 1100},
      {'artigo': 'Nayane 30 mm', 'caixa_p': 550, 'caixa_g': 1100},
      {'artigo': 'Nud 11 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Plla 10 mm', 'caixa_p': 2000, 'caixa_g': 4000},
      {'artigo': 'Plla 12 mm', 'caixa_p': 2000, 'caixa_g': 4000},
      {'artigo': 'Plla 15 mm', 'caixa_p': 1500, 'caixa_g': 3000},
      {
        'artigo': 'Plus II 30 Cru mm',
        'enfestado': 1000,
        'enfraldado': 500,
        'disco': 1500,
      },
      {
        'artigo': 'Plus II 35 Cru mm',
        'enfestado': 500,
        'enfraldado': 500,
        'disco': 1200,
      },
      {
        'artigo': 'Plus II 40 Cru mm',
        'enfestado': 500,
        'enfraldado': 500,
        'disco': 750,
      },
      {'artigo': 'Senna 16 mm', 'caixa_p': 1200, 'caixa_g': 3000},
      {'artigo': 'Senna 25 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Senna 28 mm', 'caixa_p': 600, 'caixa_g': 2200},
      {'artigo': 'Sofia 20 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Sud 11 mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'Sud 11 UP mm', 'caixa_p': 600, 'caixa_g': 2000},
      {'artigo': 'X Nillo 16 mm', 'caixa_p': 1200, 'caixa_g': 3000},
      {'artigo': 'X Nillo 25 mm', 'caixa_p': 1200, 'caixa_g': 2200},
    ];

    final batch = db.batch();
    for (final seed in caixasSeeds) {
      batch.insert(
        'caixas',
        seed,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // Insere uma lista de itens, substituindo se já existir (upsert)
  Future<void> insertAllEstoque(List<EstoqueItem> itens) async {
    final db = await database;
    if (db == null) return;
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

  // ✅ FUNÇÃO ADICIONADA: Consulta TODOS os itens do estoque
  Future<List<EstoqueItem>> getAllEstoque() async {
    final db = await database;
    if (db == null) return [];
    final List<Map<String, dynamic>> maps = await db.query('estoque');

    return List.generate(maps.length, (i) {
      return EstoqueItem.fromMap(maps[i]);
    });
  }

  // Consulta um item pelo objetoID (usado no QR Code)
  Future<EstoqueItem?> getEstoqueItem(int objetoID) async {
    final db = await database;
    if (db == null) return null;
    final List<Map<String, dynamic>> maps = await db.query(
      'estoque',
      where: 'objetoID = ?',
      whereArgs: [objetoID],
    );

    if (maps.isNotEmpty) {
      // Como objetoID é a chave primária, maps.first deve ser o único resultado.
      return EstoqueItem.fromMap(maps.first);
    }
    return null;
  }

  Future<Map<String, dynamic>?> buscarCaixaPorArtigo(String artigo) async {
    final db = await database;
    if (db == null) return null;
    await _createCaixasTable(db);
    final result = await db.query(
      'caixas',
      where: 'LOWER(artigo) = ?',
      whereArgs: [artigo.toLowerCase()],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<void> salvarPadraoCaixa(Map<String, dynamic> padrao) async {
    final db = await database;
    if (db == null) return;
    await _createCaixasTable(db);
    final artigo = (padrao['artigo'] ?? '').toString().trim();
    if (artigo.isEmpty) return;
    await db.insert('caixas', {
      'artigo': artigo,
      'caixa_p': padrao['caixa_p'],
      'enfestado': padrao['enfestado'],
      'enfraldado': padrao['enfraldado'],
      'caixa_g': padrao['caixa_g'],
      'disco': padrao['disco'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> salvarPadroesCaixa(List<Map<String, dynamic>> padroes) async {
    final db = await database;
    if (db == null || padroes.isEmpty) return;
    await _createCaixasTable(db);
    await db.transaction((txn) async {
      for (final padrao in padroes) {
        final artigo = (padrao['artigo'] ?? '').toString().trim();
        if (artigo.isEmpty) continue;
        await txn.insert('caixas', {
          'artigo': artigo,
          'caixa_p': padrao['caixa_p'],
          'enfestado': padrao['enfestado'],
          'enfraldado': padrao['enfraldado'],
          'caixa_g': padrao['caixa_g'],
          'disco': padrao['disco'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getRomaneioCache(String cacheKey) async {
    final db = await database;
    if (db == null) return [];
    final rows = await db.query(
      'romaneio_cache',
      columns: ['payload'],
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
    );
    final List<Map<String, dynamic>> result = [];
    for (final row in rows) {
      final payload = row['payload'] as String?;
      if (payload == null || payload.isEmpty) continue;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          result.add(Map<String, dynamic>.from(decoded));
        } else if (decoded is Map) {
          result.add(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    return result;
  }

  Future<void> saveRomaneioCache(
    String cacheKey,
    List<Map<String, dynamic>> itens,
  ) async {
    final db = await database;
    if (db == null) return;
    await db.transaction((txn) async {
      await txn.delete(
        'romaneio_cache',
        where: 'cache_key = ?',
        whereArgs: [cacheKey],
      );
      for (final item in itens) {
        final itemKey = _buildRomaneioItemKey(item);
        if (itemKey.isEmpty) continue;
        await txn.insert('romaneio_cache', {
          'cache_key': cacheKey,
          'item_key': itemKey,
          'payload': jsonEncode(item),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<String?> getRomaneioSync(String cacheKey) async {
    final db = await database;
    if (db == null) return null;
    final rows = await db.query(
      'romaneio_sync',
      columns: ['last_sync'],
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['last_sync'] as String?;
  }

  Future<void> setRomaneioSync(String cacheKey, String timestamp) async {
    final db = await database;
    if (db == null) return;
    await db.insert('romaneio_sync', {
      'cache_key': cacheKey,
      'last_sync': timestamp,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearRomaneioCache(String cacheKey) async {
    final db = await database;
    if (db == null) return;
    await db.transaction((txn) async {
      await txn.delete(
        'romaneio_cache',
        where: 'cache_key = ?',
        whereArgs: [cacheKey],
      );
      await txn.delete(
        'romaneio_sync',
        where: 'cache_key = ?',
        whereArgs: [cacheKey],
      );
    });
  }

  Future<Map<String, List<Map<String, dynamic>>>> getAlocacaoCache(
    Set<String> skus,
  ) async {
    final db = await database;
    if (db == null || skus.isEmpty) return {};
    final args = skus.toList();
    final placeholders = List.filled(args.length, '?').join(',');
    final rows = await db.query(
      'alocacao_cache',
      where: 'sku IN ($placeholders)',
      whereArgs: args,
    );
    final Map<String, List<Map<String, dynamic>>> result = {};
    for (final row in rows) {
      final sku = (row['sku'] as String?)?.trim().toUpperCase();
      if (sku == null || sku.isEmpty) continue;
      result.putIfAbsent(sku, () => []).add({
        'endereco': row['endereco'],
        'detalhe': row['detalhe'],
        'detalhe_id': row['detalhe_id'],
        'saldo': row['saldo'],
      });
    }
    return result;
  }

  Future<Set<String>> getAlocacaoSyncedSkus(Set<String> skus) async {
    final db = await database;
    if (db == null || skus.isEmpty) return {};
    final args = skus.toList();
    final placeholders = List.filled(args.length, '?').join(',');
    final rows = await db.query(
      'alocacao_sync',
      columns: ['sku'],
      where: 'sku IN ($placeholders)',
      whereArgs: args,
    );
    return rows
        .map((row) => (row['sku'] as String?)?.trim().toUpperCase())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Future<Map<String, String>> getAlocacaoSyncTimes(Set<String> skus) async {
    final db = await database;
    if (db == null || skus.isEmpty) return {};
    final args = skus.toList();
    final placeholders = List.filled(args.length, '?').join(',');
    final rows = await db.query(
      'alocacao_sync',
      columns: ['sku', 'last_sync'],
      where: 'sku IN ($placeholders)',
      whereArgs: args,
    );
    final Map<String, String> result = {};
    for (final row in rows) {
      final sku = (row['sku'] as String?)?.trim().toUpperCase();
      final lastSync = row['last_sync']?.toString();
      if (sku == null || sku.isEmpty || lastSync == null || lastSync.isEmpty) {
        continue;
      }
      result[sku] = lastSync;
    }
    return result;
  }

  Future<void> saveAlocacaoCache(
    Set<String> skus,
    List<Map<String, dynamic>> rows,
  ) async {
    final db = await database;
    if (db == null || skus.isEmpty) return;
    await db.transaction((txn) async {
      final args = skus.toList();
      final placeholders = List.filled(args.length, '?').join(',');
      await txn.delete(
        'alocacao_cache',
        where: 'sku IN ($placeholders)',
        whereArgs: args,
      );
      for (final row in rows) {
        final sku = (row['sku'] as String?)?.trim().toUpperCase();
        final endereco = (row['endereco'] as String?)?.trim().toUpperCase();
        if (sku == null ||
            sku.isEmpty ||
            endereco == null ||
            endereco.isEmpty) {
          continue;
        }
        await txn.insert('alocacao_cache', {
          'sku': sku,
          'endereco': endereco,
          'detalhe': row['detalhe'],
          'detalhe_id': row['detalhe_id'],
          'saldo': row['saldo'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final timestamp = DateTime.now().toIso8601String();
      for (final sku in skus) {
        final normalized = sku.trim().toUpperCase();
        if (normalized.isEmpty) continue;
        await txn.insert('alocacao_sync', {
          'sku': normalized,
          'last_sync': timestamp,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  String _buildRomaneioItemKey(Map<String, dynamic> item) {
    final nrRomaneio = _toInt(item['NrRomaneio']);
    final cdVpo = _toInt(item['CdVpo']);
    if (nrRomaneio <= 0 || cdVpo <= 0) return '';
    return '$nrRomaneio|$cdVpo';
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<List<Map<String, dynamic>>> listarPadroesCaixa({
    String? filtro,
  }) async {
    final db = await database;
    if (db == null) return [];
    final normalizedFilter = filtro?.trim().toLowerCase();
    final result = await db.query(
      'caixas',
      where: normalizedFilter != null && normalizedFilter.isNotEmpty
          ? 'LOWER(artigo) LIKE ?'
          : null,
      whereArgs: normalizedFilter != null && normalizedFilter.isNotEmpty
          ? ['%$normalizedFilter%']
          : null,
      orderBy: 'LOWER(artigo) ASC',
    );
    return result;
  }

  Future<void> addConferenciaAuditoriaEvento(
    Map<String, dynamic> evento, {
    int maxItems = 500,
  }) async {
    final db = await database;
    if (db == null) return;
    final timestamp = (evento['timestamp'] ?? DateTime.now().toIso8601String())
        .toString();
    final tipo = (evento['tipo'] ?? '').toString().trim();
    if (tipo.isEmpty) return;
    final romaneio = _toInt(evento['romaneio']);
    final pedido = _toInt(evento['pedido']);
    final usuario = evento['usuario']?.toString();
    final opcao = evento['opcao']?.toString();
    final sucesso = evento['sucesso'] == null
        ? null
        : ((evento['sucesso'] == true || evento['sucesso'].toString() == '1')
              ? 1
              : 0);
    await db.transaction((txn) async {
      await txn.insert('conferencia_auditoria', {
        'timestamp': timestamp,
        'tipo': tipo,
        'romaneio': romaneio > 0 ? romaneio : null,
        'pedido': pedido > 0 ? pedido : null,
        'usuario': usuario,
        'opcao': opcao,
        'sucesso': sucesso,
        'payload': jsonEncode(evento),
      });
      final countResult = await txn.rawQuery(
        'SELECT COUNT(*) AS total FROM conferencia_auditoria',
      );
      final total = _toInt(countResult.first['total']);
      if (maxItems > 0 && total > maxItems) {
        final excess = total - maxItems;
        await txn.rawDelete(
          'DELETE FROM conferencia_auditoria WHERE id IN ('
          'SELECT id FROM conferencia_auditoria ORDER BY id ASC LIMIT ?'
          ')',
          [excess],
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> loadConferenciaAuditoria({
    int limit = 200,
  }) async {
    final db = await database;
    if (db == null) return <Map<String, dynamic>>[];
    final rows = await db.query(
      'conferencia_auditoria',
      columns: ['id', 'payload'],
      orderBy: 'id DESC',
      limit: limit > 0 ? limit : null,
    );
    final eventos = <Map<String, dynamic>>[];
    for (final row in rows) {
      final payload = row['payload']?.toString();
      if (payload == null || payload.isEmpty) continue;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          eventos.add(Map<String, dynamic>.from(decoded));
        } else if (decoded is Map) {
          eventos.add(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    return eventos.reversed.toList();
  }

  Future<void> clearConferenciaAuditoria() async {
    final db = await database;
    if (db == null) return;
    await db.delete('conferencia_auditoria');
  }
}
