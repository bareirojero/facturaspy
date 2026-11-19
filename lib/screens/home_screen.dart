import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../db/database_helper.dart';
import '../models/factura.dart';
import '../services/pdf_service.dart';
import '../utils/formatters.dart';
import 'ajustes_screen.dart';
import 'factura_form_screen.dart';
import 'procesando_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();

  late int _selectedYear;
  late int _selectedMonth;
  List<Factura> _facturas = [];
  bool _cargando = true;
  bool _generandoPdf = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _cargarFacturas();
  }

  Future<void> _cargarFacturas() async {
    setState(() => _cargando = true);
    final lista = await DatabaseHelper.instance
        .getFacturasPorMes(_selectedYear, _selectedMonth);
    if (!mounted) return;
    setState(() {
      _facturas = lista;
      _cargando = false;
    });
  }

  void _cambiarMes(int delta) {
    final dt = DateTime(_selectedYear, _selectedMonth + delta, 1);
    setState(() {
      _selectedYear = dt.year;
      _selectedMonth = dt.month;
    });
    _cargarFacturas();
  }

  Future<void> _capturarImagen(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(source: source);
      if (picked == null || !mounted) return;

      final guardado = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ProcesandoScreen(tempImagePath: picked.path),
        ),
      );

      if (guardado == true) {
        _cargarFacturas();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo obtener la imagen: $e')),
      );
    }
  }

  void _mostrarOpcionesCaptura() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Sacar foto con la cámara'),
              onTap: () {
                Navigator.pop(ctx);
                _capturarImagen(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de la galería'),
              onTap: () {
                Navigator.pop(ctx);
                _capturarImagen(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _generarPdf() async {
    if (_facturas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay facturas registradas en este mes para exportar.'),
        ),
      );
      return;
    }

    setState(() => _generandoPdf = true);
    try {
      await PdfService.instance.generarYCompartirReporteMensual(
        year: _selectedYear,
        month: _selectedMonth,
        facturas: _facturas,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al generar el PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }

  Future<bool?> _confirmarEliminacion(Factura f) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar factura'),
        content: Text(
          '¿Seguro que querés eliminar la factura de "${f.razonSocial}" por ${AppFormatters.formatGuaranies(f.total)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int totalMes = 0;
    int totalIva10 = 0;
    int totalIva5 = 0;

    for (final f in _facturas) {
      totalMes += f.total;
      totalIva10 += f.iva10;
      totalIva5 += f.iva5;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Facturas PY'),
        actions: [
          IconButton(
            tooltip: 'Generar PDF mensual',
            onPressed: _generandoPdf ? null : _generarPdf,
            icon: _generandoPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf),
          ),
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AjustesScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _cambiarMes(-1),
                ),
                Text(
                  AppFormatters.formatMesAnio(_selectedYear, _selectedMonth),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _cambiarMes(1),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _facturas.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 64,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No hay facturas en este mes',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tocá el botón + para fotografiar o subir una factura.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 88, top: 6),
                        itemCount: _facturas.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final f = _facturas[index];
                          return Dismissible(
                            key: ValueKey(f.id),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) => _confirmarEliminacion(f),
                            onDismissed: (_) async {
                              setState(() => _facturas.removeAt(index));
                              if (f.id != null) {
                                await DatabaseHelper.instance.deleteFactura(
                                  f.id!,
                                  imagenPath: f.imagenPath,
                                );
                                _cargarFacturas();
                              }
                            },
                            background: Container(
                              color: Theme.of(context).colorScheme.error,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Icon(
                                Icons.delete,
                                color: Theme.of(context).colorScheme.onError,
                              ),
                            ),
                            child: ListTile(
                              onTap: () async {
                                final editado =
                                    await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) => FacturaFormScreen(
                                      facturaInicial: f,
                                      esNueva: false,
                                    ),
                                  ),
                                );
                                if (editado == true) {
                                  _cargarFacturas();
                                }
                              },
                              leading: CircleAvatar(
                                child: Text(
                                  f.categoria.isNotEmpty
                                      ? f.categoria[0].toUpperCase()
                                      : 'F',
                                ),
                              ),
                              title: Text(
                                f.razonSocial.isNotEmpty
                                    ? f.razonSocial
                                    : '(Sin razón social)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                '${AppFormatters.formatFechaCorta(f.fecha)}  •  ${f.categoria}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (f.tieneDiscrepanciaMontos)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Icon(
                                        Icons.warning_amber_rounded,
                                        color: Colors.amber.shade800,
                                        size: 18,
                                      ),
                                    ),
                                  Text(
                                    AppFormatters.formatGuaranies(f.total),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 84, 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total gastado:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        AppFormatters.formatGuaranies(totalMes),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'IVA 10%: ${AppFormatters.formatGuaranies(totalIva10)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        'IVA 5%: ${AppFormatters.formatGuaranies(totalIva5)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _mostrarOpcionesCaptura,
        tooltip: 'Agregar factura',
        child: const Icon(Icons.add),
      ),
    );
  }
}
