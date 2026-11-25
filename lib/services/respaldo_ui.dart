import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/formatters.dart';
import 'cola_procesamiento.dart';
import 'respaldo_service.dart';
import 'settings_service.dart';

/// Pasos de respaldo con diálogos, reutilizables desde Ajustes y desde el PDF.
class RespaldoUi {
  static void _mensaje(BuildContext context, String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  static void _mostrarEspera(BuildContext context, String texto) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(texto)),
            ],
          ),
        ),
      ),
    );
  }

  /// Crea el .zip y abre el menú de compartir (Drive, WhatsApp, mail...).
  static Future<void> exportar(BuildContext context) async {
    final ajustes = SettingsService.instance;
    _mostrarEspera(context, 'Preparando la copia de seguridad...');
    File? archivo;
    try {
      final tmp = await getTemporaryDirectory();
      // Borrar copias viejas que hayan quedado en la carpeta temporal.
      for (final e in tmp.listSync()) {
        if (e is File && p.basename(e.path).startsWith('facturas_py_respaldo_')) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
      archivo = await RespaldoService().crearArchivo(
        destino: tmp,
        nombreTitular: await ajustes.getNombreTitular(),
        rucTitular: await ajustes.getRucTitular(),
        modelo: await ajustes.getModel(),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _mensaje(context, 'No se pudo crear la copia: $e');
      }
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();

    final mb = archivo.lengthSync() / (1024 * 1024);
    final resultado = await Share.shareXFiles(
      [XFile(archivo.path, mimeType: 'application/zip')],
      subject: 'Copia de seguridad de Facturas PY',
      text: 'Copia de seguridad de Facturas PY (${mb.toStringAsFixed(1)} MB). '
          'Guardala en un lugar seguro.',
    );
    if (resultado.status != ShareResultStatus.dismissed) {
      await ajustes.setUltimoRespaldo(DateTime.now());
      if (context.mounted) {
        _mensaje(context, 'Copia de seguridad lista. Guardala en Drive o por mail.');
      }
    }
  }

  /// Elige un .zip, muestra qué contiene y, si se confirma, reemplaza todo.
  /// Devuelve true si se restauró.
  static Future<bool> restaurar(BuildContext context) async {
    final cola = ColaProcesamiento.instance;
    if (cola.pendientes > 0) {
      _mensaje(
        context,
        'Esperá a que terminen de leerse las facturas (${cola.pendientes}) y probá de nuevo.',
      );
      return false;
    }

    final elegido = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Copia de seguridad',
          extensions: ['zip'],
          mimeTypes: ['application/zip', 'application/x-zip-compressed'],
        ),
      ],
    );
    if (elegido == null || !context.mounted) return false;

    final servicio = RespaldoService();
    RespaldoLeido leido;
    _mostrarEspera(context, 'Leyendo la copia...');
    try {
      leido = await servicio.leer(elegido.path);
    } on RespaldoException catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _mensaje(context, e.mensaje);
      }
      return false;
    }
    if (!context.mounted) {
      await leido.cerrar();
      return false;
    }
    Navigator.of(context).pop();

    final fecha = leido.creado == null
        ? 'fecha desconocida'
        : AppFormatters.formatFechaCorta(leido.creado!.toIso8601String());
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.restore, size: 36),
        title: const Text('Restaurar copia'),
        content: Text(
          'Copia del $fecha con ${leido.cantidadFacturas} factura(s)'
          '${leido.nombreTitular.isNotEmpty ? ' de ${leido.nombreTitular}' : ''}.\n\n'
          'Se van a REEMPLAZAR todas las facturas y categorías que tenés ahora '
          'en la app. Esto no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reemplazar todo'),
          ),
        ],
      ),
    );
    if (confirmar != true || !context.mounted) {
      await leido.cerrar();
      return false;
    }

    _mostrarEspera(context, 'Restaurando facturas y fotos...');
    try {
      final docs = await getApplicationDocumentsDirectory();
      await servicio.aplicar(leido, dirFotos: Directory(p.join(docs.path, 'facturas_img')));
      final ajustes = SettingsService.instance;
      if (leido.nombreTitular.isNotEmpty) {
        await ajustes.setNombreTitular(leido.nombreTitular);
      }
      if (leido.rucTitular.isNotEmpty) await ajustes.setRucTitular(leido.rucTitular);
      if (leido.modelo.isNotEmpty) await ajustes.setModel(leido.modelo);
      await cola.reanudarPendientes();
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _mensaje(context, 'No se pudo restaurar: $e');
      }
      return false;
    }
    if (!context.mounted) return true;
    Navigator.of(context).pop();
    _mensaje(context, 'Listo: se restauraron ${leido.cantidadFacturas} factura(s).');
    return true;
  }
}
