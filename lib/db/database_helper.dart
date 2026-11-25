import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/factura.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  /// Solo para tests: ruta completa de una base temporal.
  static String? rutaDePrueba;

  /// Solo para tests: cierra la base para que la próxima use [rutaDePrueba].
  Future<void> cerrarParaTests() async {
    await _database?.close();
    _database = null;
  }

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('facturas_py.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final path = rutaDePrueba ?? p.join(await getDatabasesPath(), filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE facturas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT NOT NULL,
        ruc_emisor TEXT NOT NULL,
        razon_social TEXT NOT NULL,
        timbrado TEXT NOT NULL,
        numero_factura TEXT NOT NULL,
        condicion TEXT NOT NULL,
        gravada_10 INTEGER NOT NULL,
        gravada_5 INTEGER NOT NULL,
        exenta INTEGER NOT NULL,
        iva_10 INTEGER NOT NULL,
        iva_5 INTEGER NOT NULL,
        total INTEGER NOT NULL,
        categoria TEXT NOT NULL,
        notas TEXT NOT NULL,
        imagen_path TEXT NOT NULL,
        creado_en TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'revisada',
        error_extraccion TEXT
      )
    ''');
    await _crearCategorias(db);
  }

  /// Tabla de categorías editables. Arranca con la lista por defecto más
  /// cualquier categoría que ya usen las facturas existentes.
  Future<void> _crearCategorias(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categorias (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL UNIQUE COLLATE NOCASE,
        orden INTEGER NOT NULL
      )
    ''');
    final usadas = await db.rawQuery(
      "SELECT DISTINCT categoria FROM facturas WHERE categoria != ''",
    );
    final nombres = <String>[...Factura.categoriasDefecto];
    for (final r in usadas) {
      final c = (r['categoria'] as String).trim();
      if (c.isNotEmpty && !nombres.any((n) => n.toLowerCase() == c.toLowerCase())) {
        nombres.add(c);
      }
    }
    final batch = db.batch();
    for (int i = 0; i < nombres.length; i++) {
      batch.insert(
        'categorias',
        {'nombre': nombres[i], 'orden': i},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE facturas ADD COLUMN estado TEXT NOT NULL DEFAULT 'revisada'",
      );
      await db.execute('ALTER TABLE facturas ADD COLUMN error_extraccion TEXT');
    }
    if (oldVersion < 3) {
      await _crearCategorias(db);
    }
  }

  // ---------------------------------------------------------------------
  // Categorías
  // ---------------------------------------------------------------------

  Future<List<String>> getCategorias() async {
    final db = await database;
    final rows = await db.query('categorias', orderBy: 'orden ASC, id ASC');
    return rows.map((r) => r['nombre'] as String).toList();
  }

  /// Devuelve false si ya existe una con ese nombre.
  Future<bool> agregarCategoria(String nombre) async {
    final db = await database;
    final limpio = nombre.trim();
    if (limpio.isEmpty) return false;
    final max = Sqflite.firstIntValue(
          await db.rawQuery('SELECT MAX(orden) FROM categorias'),
        ) ??
        -1;
    final id = await db.insert(
      'categorias',
      {'nombre': limpio, 'orden': max + 1},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id > 0;
  }

  /// Devuelve false si el nombre nuevo ya existe (en otra categoría).
  Future<bool> renombrarCategoria(
    String viejo,
    String nuevo, {
    required bool actualizarFacturas,
  }) async {
    final db = await database;
    final limpio = nuevo.trim();
    if (limpio.isEmpty) return false;
    final choca = await db.query(
      'categorias',
      where: 'nombre = ? COLLATE NOCASE AND nombre != ?',
      whereArgs: [limpio, viejo],
    );
    if (choca.isNotEmpty) return false;
    await db.transaction((txn) async {
      await txn.update('categorias', {'nombre': limpio},
          where: 'nombre = ?', whereArgs: [viejo]);
      if (actualizarFacturas) {
        await txn.update('facturas', {'categoria': limpio},
            where: 'categoria = ?', whereArgs: [viejo]);
      }
    });
    return true;
  }

  /// Borra la categoría; si [moverA] no es null, pasa sus facturas a esa.
  Future<void> borrarCategoria(String nombre, {String? moverA}) async {
    final db = await database;
    await db.transaction((txn) async {
      if (moverA != null) {
        await txn.update('facturas', {'categoria': moverA},
            where: 'categoria = ?', whereArgs: [nombre]);
      }
      await txn.delete('categorias', where: 'nombre = ?', whereArgs: [nombre]);
    });
  }

  Future<void> reordenarCategorias(List<String> nombres) async {
    final db = await database;
    final batch = db.batch();
    for (int i = 0; i < nombres.length; i++) {
      batch.update('categorias', {'orden': i},
          where: 'nombre = ?', whereArgs: [nombres[i]]);
    }
    await batch.commit(noResult: true);
  }

  Future<int> contarFacturasDeCategoria(String nombre) async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM facturas WHERE categoria = ?',
          [nombre],
        )) ??
        0;
  }

  /// Categoría que el usuario le puso a la última factura confirmada de ese
  /// proveedor (por RUC). Null si no hay ninguna.
  Future<String?> ultimaCategoriaDeRuc(String ruc, {int? excluirId}) async {
    final limpio = ruc.trim();
    if (limpio.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'facturas',
      columns: ['categoria'],
      where: "ruc_emisor = ? AND estado = 'revisada' AND categoria != ''"
          '${excluirId != null ? ' AND id != ?' : ''}',
      whereArgs: [limpio, if (excluirId != null) excluirId],
      orderBy: 'fecha DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['categoria'] as String;
  }

  Future<Factura?> getFactura(int id) async {
    final db = await database;
    final rows = await db.query('facturas', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Factura.fromMap(rows.first);
  }

  /// Facturas que todavía no fueron confirmadas (leyéndose o por revisar),
  /// de cualquier mes.
  Future<List<Factura>> getPendientes() async {
    final db = await database;
    final rows = await db.query(
      'facturas',
      where: 'estado != ?',
      whereArgs: ['revisada'],
      orderBy: 'creado_en ASC, id ASC',
    );
    return rows.map((m) => Factura.fromMap(m)).toList();
  }

  /// IDs que quedaron a medio leer (p. ej. si se cerró la app).
  Future<List<int>> getIdsProcesando() async {
    final db = await database;
    final rows = await db.query(
      'facturas',
      columns: ['id'],
      where: 'estado = ?',
      whereArgs: ['procesando'],
      orderBy: 'id ASC',
    );
    return rows.map((m) => m['id'] as int).toList();
  }

  Future<int> insertFactura(Factura factura) async {
    final db = await database;
    return await db.insert('facturas', factura.toMap());
  }

  Future<int> updateFactura(Factura factura) async {
    final db = await database;
    return await db.update(
      'facturas',
      factura.toMap(),
      where: 'id = ?',
      whereArgs: [factura.id],
    );
  }

  Future<int> deleteFactura(int id, {String? imagenPath}) async {
    final db = await database;
    if (imagenPath != null && imagenPath.isNotEmpty) {
      try {
        final file = File(imagenPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    return await db.delete(
      'facturas',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Factura>> getFacturasPorMes(int year, int month) async {
    final db = await database;
    final prefix = '$year-${month.toString().padLeft(2, '0')}';
    final result = await db.query(
      'facturas',
      where: 'fecha LIKE ? AND estado = ?',
      whereArgs: ['$prefix%', 'revisada'],
      orderBy: 'fecha DESC, id DESC',
    );
    return result.map((map) => Factura.fromMap(map)).toList();
  }

  /// Busca en todas las facturas (cualquier fecha y estado). Cada palabra del
  /// texto tiene que aparecer en algún campo. Acepta montos ("150.000") y
  /// fechas ("17/11", "17/11/2026", "2026").
  Future<List<Factura>> buscarFacturas(String texto, {int limite = 200}) async {
    final palabras = texto
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (palabras.isEmpty) return [];

    final condiciones = <String>[];
    final args = <Object>[];
    for (final palabra in palabras) {
      final opciones = <String>[];
      final like = '%$palabra%';
      for (final campo in [
        'razon_social',
        'ruc_emisor',
        'numero_factura',
        'timbrado',
        'notas',
        'categoria',
        'fecha',
      ]) {
        opciones.add('$campo LIKE ?');
        args.add(like);
      }
      // Monto: "150.000" o "150000" busca en el total.
      final digitos = palabra.replaceAll('.', '');
      if (RegExp(r'^\d{3,}$').hasMatch(digitos)) {
        opciones.add('CAST(total AS TEXT) LIKE ?');
        args.add('%$digitos%');
      }
      // Fecha escrita como dd/mm o dd/mm/aaaa.
      final f = RegExp(r'^(\d{1,2})/(\d{1,2})(?:/(\d{4}))?$').firstMatch(palabra);
      if (f != null) {
        final dd = f.group(1)!.padLeft(2, '0');
        final mm = f.group(2)!.padLeft(2, '0');
        final yyyy = f.group(3);
        opciones.add('fecha LIKE ?');
        args.add(yyyy != null ? '$yyyy-$mm-$dd' : '%-$mm-$dd');
      }
      condiciones.add('(${opciones.join(' OR ')})');
    }

    final db = await database;
    final rows = await db.query(
      'facturas',
      where: condiciones.join(' AND '),
      whereArgs: args,
      orderBy: 'fecha DESC, id DESC',
      limit: limite,
    );
    return rows.map((m) => Factura.fromMap(m)).toList();
  }

  /// Facturas confirmadas de todo un año.
  Future<List<Factura>> getFacturasPorAnio(int year) async {
    final db = await database;
    final result = await db.query(
      'facturas',
      where: 'fecha LIKE ? AND estado = ?',
      whereArgs: ['$year-%', 'revisada'],
      orderBy: 'fecha ASC, id ASC',
    );
    return result.map((map) => Factura.fromMap(map)).toList();
  }

  /// Todas las filas de facturas, tal cual están en la base (para respaldo).
  Future<List<Map<String, Object?>>> getFilasFacturas() async {
    final db = await database;
    return db.query('facturas', orderBy: 'id ASC');
  }

  /// Reemplaza TODAS las facturas y categorías (restaurar respaldo).
  /// Es una transacción: si algo falla, no se pierde nada.
  Future<void> reemplazarTodo({
    required List<Map<String, Object?>> facturas,
    required List<String> categorias,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('facturas');
      await txn.delete('categorias');
      for (final f in facturas) {
        await txn.insert('facturas', f);
      }
      for (int i = 0; i < categorias.length; i++) {
        await txn.insert(
          'categorias',
          {'nombre': categorias[i], 'orden': i},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  /// Guarda una copia persistente de la imagen en el directorio privado de la app
  Future<String> guardarImagenLocal(String sourcePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final facturasDir = Directory(p.join(appDir.path, 'facturas_img'));
    if (!await facturasDir.exists()) {
      await facturasDir.create(recursive: true);
    }

    final ext = p.extension(sourcePath).isNotEmpty ? p.extension(sourcePath) : '.jpg';
    final fileName = 'fac_${DateTime.now().millisecondsSinceEpoch}$ext';
    final destPath = p.join(facturasDir.path, fileName);

    final sourceFile = File(sourcePath);
    await sourceFile.copy(destPath);
    return destPath;
  }
}
