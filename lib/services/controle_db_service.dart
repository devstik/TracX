import 'package:sqflite/sqflite.dart';

class ControleGrupo {
  const ControleGrupo({
    this.id,
    required this.titulo,
    required this.valorBase,
    required this.mesReferencia,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String titulo;
  final double valorBase;
  final String mesReferencia;
  final String createdAt;
  final String updatedAt;

  ControleGrupo copyWith({
    int? id,
    String? titulo,
    double? valorBase,
    String? mesReferencia,
    String? createdAt,
    String? updatedAt,
  }) {
    return ControleGrupo(
      id: id ?? this.id,
      titulo: titulo ?? this.titulo,
      valorBase: valorBase ?? this.valorBase,
      mesReferencia: mesReferencia ?? this.mesReferencia,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'titulo': titulo,
      'valor_base': valorBase,
      'mes_referencia': mesReferencia,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory ControleGrupo.fromMap(Map<String, dynamic> map) {
    return ControleGrupo(
      id: map['id'] as int?,
      titulo: (map['titulo'] ?? '').toString(),
      valorBase: _toDouble(map['valor_base']),
      mesReferencia: (map['mes_referencia'] ?? '').toString(),
      createdAt: (map['created_at'] ?? '').toString(),
      updatedAt: (map['updated_at'] ?? '').toString(),
    );
  }
}

class ControleLinha {
  const ControleLinha({
    this.id,
    required this.grupoId,
    required this.data,
    required this.artigo,
    required this.cdObj,
    required this.metrosEnviado,
    required this.conferencia,
    required this.createdAt,
  });

  final int? id;
  final int grupoId;
  final String data;
  final String artigo;
  final int? cdObj;
  final double metrosEnviado;
  final String conferencia;
  final String createdAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'grupo_id': grupoId,
      'data': data,
      'artigo': artigo,
      'cd_obj': cdObj,
      'metros_enviado': metrosEnviado,
      'conferencia': conferencia,
      'created_at': createdAt,
    };
  }

  factory ControleLinha.fromMap(Map<String, dynamic> map) {
    return ControleLinha(
      id: map['id'] as int?,
      grupoId: map['grupo_id'] as int,
      data: (map['data'] ?? '').toString(),
      artigo: (map['artigo'] ?? '').toString(),
      cdObj: map['cd_obj'] as int?,
      metrosEnviado: _toDouble(map['metros_enviado']),
      conferencia: _normalizarConferencia(map['conferencia']),
      createdAt: (map['created_at'] ?? '').toString(),
    );
  }
}

class ControleDbService {
  ControleDbService._();
  static final ControleDbService instance = ControleDbService._();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _init();
    return _database!;
  }

  Future<Database> _init() async {
    final basePath = await getDatabasesPath();
    final path = '$basePath/controle_database.db';
    return openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE controle_grupos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        titulo TEXT NOT NULL,
        valor_base REAL NOT NULL DEFAULT 0,
        mes_referencia TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE controle_linhas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        grupo_id INTEGER NOT NULL,
        data TEXT NOT NULL,
        artigo TEXT NOT NULL,
        cd_obj INTEGER,
        metros_enviado REAL NOT NULL DEFAULT 0,
        conferencia TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (grupo_id) REFERENCES controle_grupos(id)
          ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_controle_grupos_mes
      ON controle_grupos (mes_referencia)
    ''');
    await db.execute('''
      CREATE INDEX idx_controle_linhas_grupo
      ON controle_linhas (grupo_id)
    ''');
  }

  Future<List<ControleGrupo>> listarGrupos({
    String? mesReferencia,
    String filtro = '',
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if ((mesReferencia ?? '').trim().isNotEmpty) {
      where.add('mes_referencia = ?');
      args.add(mesReferencia!.trim());
    }
    if (filtro.trim().isNotEmpty) {
      where.add('UPPER(titulo) LIKE ?');
      args.add('%${filtro.trim().toUpperCase()}%');
    }
    final rows = await db.query(
      'controle_grupos',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'updated_at DESC, id DESC',
    );
    return rows.map(ControleGrupo.fromMap).toList();
  }

  Future<int> salvarGrupo(ControleGrupo grupo) async {
    final db = await database;
    if (grupo.id == null) {
      return db.insert('controle_grupos', grupo.toMap());
    }
    await db.update(
      'controle_grupos',
      grupo.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [grupo.id],
    );
    return grupo.id!;
  }

  Future<void> excluirGrupo(int id) async {
    final db = await database;
    await db.delete('controle_linhas', where: 'grupo_id = ?', whereArgs: [id]);
    await db.delete('controle_grupos', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ControleLinha>> listarLinhas(int grupoId) async {
    final db = await database;
    final rows = await db.query(
      'controle_linhas',
      where: 'grupo_id = ?',
      whereArgs: [grupoId],
      orderBy: 'data ASC, id ASC',
    );
    return rows.map(ControleLinha.fromMap).toList();
  }

  Future<int> salvarLinha(ControleLinha linha) async {
    final db = await database;
    await db.update(
      'controle_grupos',
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [linha.grupoId],
    );
    if (linha.id == null) {
      return db.insert('controle_linhas', linha.toMap());
    }
    await db.update(
      'controle_linhas',
      linha.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [linha.id],
    );
    return linha.id!;
  }

  Future<void> excluirLinha(int id, int grupoId) async {
    final db = await database;
    await db.delete('controle_linhas', where: 'id = ?', whereArgs: [id]);
    await db.update(
      'controle_grupos',
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [grupoId],
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return 0;
  final normalized = raw.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(normalized) ?? 0;
}

String _normalizarConferencia(dynamic value) {
  final raw = (value ?? 'Não enviado ainda').toString().trim();
  if (raw.isEmpty) return 'Não enviado ainda';
  final lower = raw.toLowerCase();
  if (lower == 'nao enviado ainda' ||
      (lower.startsWith('n') && lower.contains('enviado ainda'))) {
    return 'Não enviado ainda';
  }
  return raw;
}
