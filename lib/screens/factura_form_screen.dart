import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import '../models/factura.dart';
import '../services/cola_procesamiento.dart';
import '../utils/formatters.dart';
import '../widgets/imagen_zoom_dialog.dart';

class FacturaFormScreen extends StatefulWidget {
  final Factura facturaInicial;
  final bool esNueva;
  final String? errorExtraccion;

  const FacturaFormScreen({
    super.key,
    required this.facturaInicial,
    required this.esNueva,
    this.errorExtraccion,
  });

  @override
  State<FacturaFormScreen> createState() => _FacturaFormScreenState();
}

class _FacturaFormScreenState extends State<FacturaFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _fechaCtrl;
  late TextEditingController _rucCtrl;
  late TextEditingController _razonSocialCtrl;
  late TextEditingController _timbradoCtrl;
  late TextEditingController _numeroFacturaCtrl;
  late TextEditingController _gravada10Ctrl;
  late TextEditingController _gravada5Ctrl;
  late TextEditingController _exentaCtrl;
  late TextEditingController _iva10Ctrl;
  late TextEditingController _iva5Ctrl;
  late TextEditingController _totalCtrl;
  late TextEditingController _notasCtrl;

  late String _condicion;
  late String _categoria;
  List<String> _categorias = List.of(Factura.categoriasDefecto);
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final f = widget.facturaInicial;
    _fechaCtrl = TextEditingController(text: f.fecha);
    _rucCtrl = TextEditingController(text: f.rucEmisor);
    _razonSocialCtrl = TextEditingController(text: f.razonSocial);
    _timbradoCtrl = TextEditingController(text: f.timbrado);
    _numeroFacturaCtrl = TextEditingController(text: f.numeroFactura);
    _gravada10Ctrl = TextEditingController(text: f.gravada10.toString());
    _gravada5Ctrl = TextEditingController(text: f.gravada5.toString());
    _exentaCtrl = TextEditingController(text: f.exenta.toString());
    _iva10Ctrl = TextEditingController(text: f.iva10.toString());
    _iva5Ctrl = TextEditingController(text: f.iva5.toString());
    _totalCtrl = TextEditingController(text: f.total.toString());
    _notasCtrl = TextEditingController(text: f.notas);

    _condicion = (f.condicion == 'credito') ? 'credito' : 'contado';
    _categoria = f.categoria;
    _ajustarCategoria();
    _cargarCategorias();
  }

  Future<void> _cargarCategorias() async {
    final lista = await DatabaseHelper.instance.getCategorias();
    if (!mounted || lista.isEmpty) return;
    setState(() {
      _categorias = lista;
      _ajustarCategoria();
    });
  }

  /// Si la factura tiene una categoría que ya no está en la lista (se borró),
  /// se muestra igual para no perderla. Si no tiene, se propone "Otros".
  void _ajustarCategoria() {
    if (_categoria.isEmpty) {
      _categoria = _categorias.contains('Otros') ? 'Otros' : _categorias.first;
    } else if (!_categorias.contains(_categoria)) {
      _categorias = [..._categorias, _categoria];
    }
  }

  @override
  void dispose() {
    _fechaCtrl.dispose();
    _rucCtrl.dispose();
    _razonSocialCtrl.dispose();
    _timbradoCtrl.dispose();
    _numeroFacturaCtrl.dispose();
    _gravada10Ctrl.dispose();
    _gravada5Ctrl.dispose();
    _exentaCtrl.dispose();
    _iva10Ctrl.dispose();
    _iva5Ctrl.dispose();
    _totalCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  int get _g10 => AppFormatters.parseGuaranies(_gravada10Ctrl.text);
  int get _g5 => AppFormatters.parseGuaranies(_gravada5Ctrl.text);
  int get _ex => AppFormatters.parseGuaranies(_exentaCtrl.text);
  int get _i10 => AppFormatters.parseGuaranies(_iva10Ctrl.text);
  int get _i5 => AppFormatters.parseGuaranies(_iva5Ctrl.text);
  int get _tot => AppFormatters.parseGuaranies(_totalCtrl.text);

  bool get _hayDiscrepancia {
    final suma = _g10 + _g5 + _ex;
    return (suma - _tot).abs() > 1;
  }

  void _onGravada10Changed(String val) {
    final g10 = AppFormatters.parseGuaranies(val);
    _iva10Ctrl.text = (g10 / 11).round().toString();
    setState(() {});
  }

  void _onGravada5Changed(String val) {
    final g5 = AppFormatters.parseGuaranies(val);
    _iva5Ctrl.text = (g5 / 21).round().toString();
    setState(() {});
  }

  Future<void> _seleccionarFecha() async {
    DateTime inicial = DateTime.now();
    try {
      inicial = DateTime.parse(_fechaCtrl.text);
    } catch (_) {}

    final picked = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('es', 'PY'),
    );

    if (picked != null) {
      setState(() {
        _fechaCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    try {
      final factura = Factura(
        id: widget.facturaInicial.id,
        fecha: _fechaCtrl.text.trim(),
        rucEmisor: _rucCtrl.text.trim(),
        razonSocial: _razonSocialCtrl.text.trim(),
        timbrado: _timbradoCtrl.text.trim(),
        numeroFactura: _numeroFacturaCtrl.text.trim(),
        condicion: _condicion,
        gravada10: _g10,
        gravada5: _g5,
        exenta: _ex,
        iva10: _i10,
        iva5: _i5,
        total: _tot,
        categoria: _categoria,
        notas: _notasCtrl.text.trim(),
        imagenPath: widget.facturaInicial.imagenPath,
        creadoEn: widget.facturaInicial.creadoEn,
        estado: EstadoFactura.revisada,
        errorExtraccion: null,
      );

      if (widget.esNueva) {
        await DatabaseHelper.instance.insertFactura(factura);
      } else {
        await DatabaseHelper.instance.updateFactura(factura);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar factura: $e')),
      );
    }
  }

  Future<void> _releer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.auto_awesome),
        title: const Text('Volver a leer con Gemini'),
        content: const Text(
          'Gemini va a leer la foto de nuevo y la factura pasa a "Por revisar". '
          'Los datos que cargaste o corregiste se reemplazan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Volver a leer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ColaProcesamiento.instance.reintentar(widget.facturaInicial);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _eliminar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar factura'),
        content: const Text('Se borra la factura y su foto. No se puede deshacer.'),
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
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final f = widget.facturaInicial;
    await DatabaseHelper.instance.deleteFactura(f.id!, imagenPath: f.imagenPath);
    ColaProcesamiento.instance.quitar(f.id!);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.errorExtraccion ?? widget.facturaInicial.errorExtraccion;
    final porRevisar = widget.esNueva || widget.facturaInicial.estaPorRevisar;
    final imageFile = File(widget.facturaInicial.imagenPath);
    final tieneImagen =
        widget.facturaInicial.imagenPath.isNotEmpty && imageFile.existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text(porRevisar ? 'Revisar Factura' : 'Editar Factura'),
        actions: [
          if (widget.facturaInicial.id != null &&
              widget.facturaInicial.imagenPath.isNotEmpty)
            IconButton(
              tooltip: 'Volver a leer con Gemini',
              icon: const Icon(Icons.auto_awesome),
              onPressed: _guardando ? null : _releer,
            ),
          if (widget.facturaInicial.id != null)
            IconButton(
              tooltip: 'Eliminar factura',
              icon: const Icon(Icons.delete_outline),
              onPressed: _guardando ? null : _eliminar,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$error\nPodés completar los campos manualmente.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (tieneImagen) ...[
              GestureDetector(
                onTap: () => ImagenZoomDialog.show(
                  context,
                  widget.facturaInicial.imagenPath,
                ),
                child: Container(
                  height: 170,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(imageFile, fit: BoxFit.cover),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.zoom_in, color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text(
                                'Tocar para ampliar',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_hayDiscrepancia) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'La suma de Gravada 10% + Gravada 5% + Exenta (${AppFormatters.formatGuaranies(_g10 + _g5 + _ex)}) difiere del Total (${AppFormatters.formatGuaranies(_tot)}). Verificá los montos.',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _fechaCtrl,
                    readOnly: true,
                    onTap: _seleccionarFecha,
                    decoration: const InputDecoration(
                      labelText: 'Fecha (yyyy-MM-dd)',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Requerido';
                      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v.trim())) {
                        return 'Formato yyyy-MM-dd';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _condicion,
                    decoration: const InputDecoration(
                      labelText: 'Condición',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'contado', child: Text('Contado')),
                      DropdownMenuItem(value: 'credito', child: Text('Crédito')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _condicion = val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            TextFormField(
              controller: _razonSocialCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Razón Social del Emisor',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingresá la razón social' : null,
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _rucCtrl,
                    decoration: const InputDecoration(
                      labelText: 'RUC Emisor',
                      hintText: '80012345-6',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _timbradoCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 8,
                    decoration: const InputDecoration(
                      labelText: 'Timbrado (8 díg.)',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Requerido';
                      if (v.trim().length != 8) return 'Debe tener 8 dígitos';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: TextFormField(
                    controller: _numeroFacturaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nº Factura',
                      hintText: '001-001-0000123',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('cat-${_categorias.join('|')}'),
                    value: _categoria,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Categoría',
                      border: OutlineInputBorder(),
                    ),
                    items: _categorias
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _categoria = val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Text(
              'Importes en Guaraníes (sin decimales)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: _buildMontoField(
                    controller: _gravada10Ctrl,
                    label: 'Gravada 10%',
                    onChanged: _onGravada10Changed,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMontoField(
                    controller: _iva10Ctrl,
                    label: 'IVA 10% (÷11)',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _buildMontoField(
                    controller: _gravada5Ctrl,
                    label: 'Gravada 5%',
                    onChanged: _onGravada5Changed,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMontoField(
                    controller: _iva5Ctrl,
                    label: 'IVA 5% (÷21)',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _buildMontoField(
                    controller: _exentaCtrl,
                    label: 'Exenta',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMontoField(
                    controller: _totalCtrl,
                    label: 'Total Factura',
                    isBold: true,
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      if (AppFormatters.parseGuaranies(v ?? '') <= 0) {
                        return 'Debe ser > 0';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            TextFormField(
              controller: _notasCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Confirmar y guardar', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMontoField({
    required TextEditingController controller,
    required String label,
    required ValueChanged<String> onChanged,
    bool isBold = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: TextStyle(
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      ),
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'Gs.',
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
      validator: validator ??
          (v) {
            if (v == null || v.trim().isEmpty) return 'Requerido';
            return null;
          },
    );
  }
}
