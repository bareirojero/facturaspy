import 'package:flutter/foundation.dart';
import '../db/database_helper.dart';
import '../models/factura.dart';
import 'ekuatia_qr.dart';
import 'gemini_service.dart';

/// Cola que envía las fotos a Gemini de a una, en segundo plano, mientras
/// el usuario sigue sacando fotos. Notifica a la UI cada vez que cambia algo.
class ColaProcesamiento extends ChangeNotifier {
  static final ColaProcesamiento instance = ColaProcesamiento._();
  ColaProcesamiento._();

  final List<int> _cola = [];
  bool _trabajando = false;

  /// Cantidad de facturas que faltan leer (incluida la que se está leyendo).
  int get pendientes => _cola.length;

  /// Guarda la foto, crea la factura en estado "procesando" y la encola.
  Future<void> agregarFoto(String tempPath) async {
    final db = DatabaseHelper.instance;
    String path = tempPath;
    try {
      path = await db.guardarImagenLocal(tempPath);
    } catch (_) {}
    final id = await db.insertFactura(Factura.borrador(imagenPath: path));
    _cola.add(id);
    notifyListeners();
    _procesar();
  }

  /// Manda de nuevo una factura existente a Gemini (descarta lo leído antes).
  Future<void> reintentar(Factura f) async {
    if (f.id == null) return;
    await DatabaseHelper.instance.updateFactura(
      f.copyWith(estado: EstadoFactura.procesando, limpiarError: true),
    );
    if (!_cola.contains(f.id)) _cola.add(f.id!);
    notifyListeners();
    _procesar();
  }

  /// Vuelve a encolar facturas que quedaron a medio leer al cerrar la app.
  Future<void> reanudarPendientes() async {
    final ids = await DatabaseHelper.instance.getIdsProcesando();
    for (final id in ids) {
      if (!_cola.contains(id)) _cola.add(id);
    }
    if (ids.isNotEmpty) notifyListeners();
    _procesar();
  }

  /// Saca una factura de la cola (p. ej. si el usuario la borra).
  void quitar(int id) {
    // La que se está leyendo ahora no se quita; al terminar se descarta sola
    // porque ya no existe en la base.
    final enCurso = _trabajando && _cola.isNotEmpty ? _cola.first : null;
    if (id != enCurso) _cola.remove(id);
    notifyListeners();
  }

  Future<void> _procesar() async {
    if (_trabajando) return;
    _trabajando = true;
    final db = DatabaseHelper.instance;

    while (_cola.isNotEmpty) {
      final id = _cola.first;
      try {
        final f = await db.getFactura(id);
        if (f != null && f.estaProcesando) {
          final actualizada = await _leerConReintentos(f);
          // Pudo haberse borrado mientras Gemini la leía.
          if (await db.getFactura(id) != null) {
            await db.updateFactura(actualizada);
          }
        }
      } catch (_) {
        // Nunca dejar la cola trabada por un error inesperado.
      }
      _cola.remove(id);
      notifyListeners();
    }

    _trabajando = false;
    notifyListeners();
  }

  /// Lee el QR (si es factura electrónica) y llama a Gemini; si Gemini
  /// responde 429 (límite por minuto), espera y reintenta.
  Future<Factura> _leerConReintentos(Factura f) async {
    final qr = await EkuatiaQr.leerDeImagen(f.imagenPath);
    final categorias = await DatabaseHelper.instance.getCategorias();
    const esperas = [Duration(seconds: 20), Duration(seconds: 45)];
    for (int intento = 0;; intento++) {
      try {
        final r = await GeminiService.instance.extraerDatosFactura(
          f.imagenPath,
          categorias: categorias,
        );
        final leida = f.copyWith(
          fecha: r.fecha ?? f.fecha,
          rucEmisor: r.rucEmisor ?? '',
          razonSocial: r.razonSocial ?? '',
          timbrado: r.timbrado ?? '',
          numeroFactura: r.numeroFactura ?? '',
          condicion: r.condicion ?? 'contado',
          gravada10: r.gravada10,
          gravada5: r.gravada5,
          exenta: r.exenta,
          iva10: r.iva10,
          iva5: r.iva5,
          total: r.total,
          estado: EstadoFactura.porRevisar,
          limpiarError: true,
        );
        final conQr = _aplicarQr(leida, qr);
        return conQr.copyWith(
          categoria: await _elegirCategoria(conQr, r.categoria, categorias),
        );
      } on GeminiException catch (e) {
        if (e.statusCode == 429 && intento < esperas.length) {
          await Future.delayed(esperas[intento]);
          continue;
        }
        final fallida = _fallo(f, qr, e.message);
        return fallida.copyWith(
          categoria: await _elegirCategoria(fallida, null, categorias),
        );
      } catch (e) {
        return _fallo(f, qr, 'Error inesperado: $e');
      }
    }
  }

  /// Prioridad: 1) la categoría que el usuario le puso antes a ese proveedor,
  /// 2) la que propone Gemini (si está en la lista), 3) "Otros" o la primera.
  Future<String> _elegirCategoria(
    Factura f,
    String? deGemini,
    List<String> categorias,
  ) async {
    final previa = await DatabaseHelper.instance.ultimaCategoriaDeRuc(
      f.rucEmisor,
      excluirId: f.id,
    );
    if (previa != null && categorias.contains(previa)) return previa;
    if (deGemini != null) {
      for (final c in categorias) {
        if (c.toLowerCase() == deGemini.toLowerCase()) return c;
      }
    }
    if (categorias.contains('Otros')) return 'Otros';
    return categorias.isNotEmpty ? categorias.first : '';
  }

  /// Los datos del QR son exactos: reemplazan lo que haya leído Gemini.
  Factura _aplicarQr(Factura f, DatosQrEkuatia? qr) {
    if (qr == null) return f;
    final notaCdc = 'CDC: ${qr.cdc}';
    return f.copyWith(
      rucEmisor: qr.rucEmisor,
      numeroFactura: qr.numeroFactura,
      fecha: qr.fecha,
      total: qr.total ?? f.total,
      notas: f.notas.contains(qr.cdc)
          ? f.notas
          : (f.notas.isEmpty ? notaCdc : '${f.notas}\n$notaCdc'),
    );
  }

  Factura _fallo(Factura f, DatosQrEkuatia? qr, String mensaje) {
    if (qr != null) {
      return _aplicarQr(f, qr).copyWith(
        estado: EstadoFactura.porRevisar,
        errorExtraccion: '$mensaje\nDel QR se completaron RUC, número, fecha'
            '${qr.total != null ? ' y total' : ''}. Falta el resto.',
      );
    }
    return f.copyWith(estado: EstadoFactura.porRevisar, errorExtraccion: mensaje);
  }
}
