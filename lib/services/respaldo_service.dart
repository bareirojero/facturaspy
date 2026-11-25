import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../db/database_helper.dart';
import '../models/factura.dart';

/// Error con un mensaje para mostrar al usuario.
class RespaldoException implements Exception {
  final String mensaje;
  RespaldoException(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Contenido de un respaldo ya leído, listo para mostrar y confirmar.
class RespaldoLeido {
  final DateTime? creado;
  final String nombreTitular;
  final String rucTitular;
  final String modelo;
  final List<String> categorias;
  final List<Map<String, Object?>> facturas;
  final InputFileStream _entrada;
  final Archive _zip;

  RespaldoLeido._({
    required this.creado,
    required this.nombreTitular,
    required this.rucTitular,
    required this.modelo,
    required this.categorias,
    required this.facturas,
    required InputFileStream entrada,
    required Archive zip,
  })  : _entrada = entrada,
        _zip = zip;

  int get cantidadFacturas => facturas.length;

  Future<void> cerrar() => _entrada.close();
}

/// Copia de seguridad en un .zip: respaldo.json (facturas, categorías y datos
/// del titular, sin la API key) + carpeta fotos/.
class RespaldoService {
  static const _formato = 'facturas_py_respaldo';
  static const _version = 1;
  static const _json = 'respaldo.json';

  final DatabaseHelper _db;
  RespaldoService([DatabaseHelper? db]) : _db = db ?? DatabaseHelper.instance;

  /// Crea el .zip en [destino] y lo devuelve.
  Future<File> crearArchivo({
    required Directory destino,
    required String nombreTitular,
    required String rucTitular,
    required String modelo,
  }) async {
    final filas = await _db.getFilasFacturas();
    final categorias = await _db.getCategorias();
    final ahora = DateTime.now();
    final nombre =
        'facturas_py_respaldo_${DateFormat('yyyy-MM-dd_HHmm').format(ahora)}.zip';
    final ruta = p.join(destino.path, nombre);

    final zip = ZipFileEncoder();
    // Las fotos ya están comprimidas (JPEG): se guardan sin recomprimir.
    zip.create(ruta, level: ZipFileEncoder.store);
    try {
      final facturas = <Map<String, Object?>>[];
      for (final fila in filas) {
        final copia = Map<String, Object?>.from(fila);
        final img = (fila['imagen_path'] as String?) ?? '';
        if (img.isNotEmpty && File(img).existsSync()) {
          final enZip = 'fotos/${fila['id']}_${p.basename(img)}';
          await zip.addFile(File(img), enZip);
          copia['imagen_path'] = enZip;
        } else {
          copia['imagen_path'] = '';
        }
        facturas.add(copia);
      }

      final contenido = jsonEncode({
        'formato': _formato,
        'version': _version,
        'creado': ahora.toIso8601String(),
        'titular': {'nombre': nombreTitular, 'ruc': rucTitular},
        'modelo': modelo,
        'categorias': categorias,
        'facturas': facturas,
      });
      zip.addArchiveFile(ArchiveFile.string(_json, contenido));
    } finally {
      await zip.close();
    }
    return File(ruta);
  }

  /// Lee y valida el .zip sin tocar nada. Llamar a [aplicar] o
  /// [RespaldoLeido.cerrar] después.
  Future<RespaldoLeido> leer(String rutaZip) async {
    InputFileStream? entrada;
    try {
      entrada = InputFileStream(rutaZip);
      final zip = ZipDecoder().decodeStream(entrada);
      final archivoJson = zip.find(_json);
      if (archivoJson == null) {
        throw RespaldoException(
          'El archivo no es una copia de seguridad de Facturas PY.',
        );
      }
      final datos = jsonDecode(utf8.decode(archivoJson.content));
      if (datos is! Map || datos['formato'] != _formato) {
        throw RespaldoException(
          'El archivo no es una copia de seguridad de Facturas PY.',
        );
      }
      final version = datos['version'];
      if (version is! int || version > _version) {
        throw RespaldoException(
          'La copia es de una versión más nueva de la app. Actualizá la app y probá de nuevo.',
        );
      }

      final titular = (datos['titular'] as Map?) ?? const {};
      final facturas = <Map<String, Object?>>[];
      for (final f in (datos['facturas'] as List? ?? const [])) {
        if (f is! Map) continue;
        // Pasar por el modelo normaliza campos faltantes o de tipo raro.
        final normalizada = Factura.fromMap(Map<String, dynamic>.from(f)).toMap();
        facturas.add(normalizada);
      }
      final categorias = [
        for (final c in (datos['categorias'] as List? ?? const []))
          if (c is String && c.trim().isNotEmpty) c.trim(),
      ];

      return RespaldoLeido._(
        creado: DateTime.tryParse('${datos['creado']}'),
        nombreTitular: '${titular['nombre'] ?? ''}',
        rucTitular: '${titular['ruc'] ?? ''}',
        modelo: '${datos['modelo'] ?? ''}',
        categorias:
            categorias.isEmpty ? List.of(Factura.categoriasDefecto) : categorias,
        facturas: facturas,
        entrada: entrada,
        zip: zip,
      );
    } on RespaldoException {
      await entrada?.close();
      rethrow;
    } catch (_) {
      await entrada?.close();
      throw RespaldoException('No se pudo leer el archivo. ¿Es un .zip de respaldo válido?');
    }
  }

  /// Reemplaza todas las facturas y categorías por las del respaldo.
  /// Las fotos se extraen a [dirFotos]; las fotos viejas se borran al final.
  Future<void> aplicar(RespaldoLeido r, {required Directory dirFotos}) async {
    try {
      if (!dirFotos.existsSync()) dirFotos.createSync(recursive: true);
      final prefijo = 'r${DateTime.now().millisecondsSinceEpoch}_';

      // 1) Extraer las fotos con nombres nuevos (no pisan las actuales).
      final rutas = <String, String>{};
      for (final archivo in r._zip.files) {
        if (!archivo.isFile || !archivo.name.startsWith('fotos/')) continue;
        final destino = p.join(dirFotos.path, '$prefijo${p.basename(archivo.name)}');
        final salida = OutputFileStream(destino);
        try {
          archivo.writeContent(salida);
        } finally {
          await salida.close();
        }
        rutas[archivo.name] = destino;
      }

      // 2) Reemplazar los datos en una sola transacción.
      final filas = [
        for (final f in r.facturas)
          {...f, 'imagen_path': rutas[f['imagen_path']] ?? ''},
      ];
      await _db.reemplazarTodo(facturas: filas, categorias: r.categorias);

      // 3) Borrar fotos que ya no usa ninguna factura.
      final enUso = rutas.values.toSet();
      for (final e in dirFotos.listSync()) {
        if (e is File && !enUso.contains(e.path)) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
    } finally {
      await r.cerrar();
    }
  }
}
