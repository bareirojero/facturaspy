import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import '../models/factura.dart';
import '../services/gemini_service.dart';
import 'factura_form_screen.dart';

class ProcesandoScreen extends StatefulWidget {
  final String tempImagePath;

  const ProcesandoScreen({super.key, required this.tempImagePath});

  @override
  State<ProcesandoScreen> createState() => _ProcesandoScreenState();
}

class _ProcesandoScreenState extends State<ProcesandoScreen> {
  String _estado = 'Guardando copia local de la imagen...';

  @override
  void initState() {
    super.initState();
    _procesarFactura();
  }

  Future<void> _procesarFactura() async {
    String savedImagePath = widget.tempImagePath;
    try {
      savedImagePath =
          await DatabaseHelper.instance.guardarImagenLocal(widget.tempImagePath);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _estado = 'Analizando factura con Gemini AI...';
    });

    final hoyIso = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final ahoraIso = DateTime.now().toIso8601String();

    try {
      final extracted =
          await GeminiService.instance.extraerDatosFactura(savedImagePath);

      if (!mounted) return;

      final facturaPrecargada = Factura(
        fecha: extracted.fecha ?? hoyIso,
        rucEmisor: extracted.rucEmisor ?? '',
        razonSocial: extracted.razonSocial ?? '',
        timbrado: extracted.timbrado ?? '',
        numeroFactura: extracted.numeroFactura ?? '',
        condicion: extracted.condicion ?? 'contado',
        gravada10: extracted.gravada10,
        gravada5: extracted.gravada5,
        exenta: extracted.exenta,
        iva10: extracted.iva10,
        iva5: extracted.iva5,
        total: extracted.total,
        categoria: Factura.categoriasDefecto.first,
        notas: '',
        imagenPath: savedImagePath,
        creadoEn: ahoraIso,
      );

      await _abrirFormulario(facturaPrecargada);
    } catch (e) {
      if (!mounted) return;

      final facturaVacia = Factura(
        fecha: hoyIso,
        rucEmisor: '',
        razonSocial: '',
        timbrado: '',
        numeroFactura: '',
        condicion: 'contado',
        gravada10: 0,
        gravada5: 0,
        exenta: 0,
        iva10: 0,
        iva5: 0,
        total: 0,
        categoria: Factura.categoriasDefecto.first,
        notas: '',
        imagenPath: savedImagePath,
        creadoEn: ahoraIso,
      );

      await _abrirFormulario(facturaVacia, error: e.toString());
    }
  }

  /// Abre el formulario y, al volver, cierra esta pantalla devolviendo
  /// si se guardó la factura (para que el inicio recargue la lista).
  Future<void> _abrirFormulario(Factura factura, {String? error}) async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FacturaFormScreen(
          facturaInicial: factura,
          esNueva: true,
          errorExtraccion: error,
        ),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(guardado == true);
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.tempImagePath);

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Procesando factura'),
          automaticallyImplyLeading: false,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: file.existsSync()
                      ? Image.file(file, fit: BoxFit.contain)
                      : const Icon(Icons.receipt_long, size: 96),
                ),
              ),
              const SizedBox(height: 28),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _estado,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Redimensionando y extrayendo RUC, timbrado, gravadas e IVA...',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
