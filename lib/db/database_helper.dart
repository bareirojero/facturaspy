import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/factura.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('facturas_py.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
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
        creado_en TEXT NOT NULL
      )
    ''');
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
      where: 'fecha LIKE ?',
      whereArgs: ['$prefix%'],
      orderBy: 'fecha DESC, id DESC',
    );
    return result.map((map) => Factura.fromMap(map)).toList();
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
