import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import '../db/database_helper.dart';
import '../models/factura.dart';
import '../services/cola_procesamiento.dart';
import '../services/pdf_service.dart';
import '../utils/formatters.dart';
import 'ajustes_screen.dart';
import 'factura_form_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  final ColaProcesamiento _cola = ColaProcesamiento.instance;

  late int _selectedYear;
  late int _selectedMonth;
  List<Factura> _facturas = []; // revisadas del mes elegido
  List<Factura> _pendientes = []; // leyéndose o por revisar (todos los meses)
  bool _cargando = true;
  bool _generandoPdf = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _cola.addListener(_cargarFacturas);
    _cargarFacturas();
  }

  @override
  void dispose() {
    _cola.removeListener(_cargarFacturas);
    super.dispose();
  }

  Future<void> _cargarFacturas() async {
    final db = DatabaseHelper.instance;
    final lista = await db.getFacturasPorMes(_selectedYear, _selectedMonth);
    final pendientes = await db.getPendientes();
    if (!mounted) return;
    setState(() {
      _facturas = lista;
      _pendientes = pendientes;
      _cargando = false;
    });
  }

  void _cambiarMes(int delta) {
    final dt = DateTime(_selectedYear, _selectedMonth + delta, 1);
    setState(() {
      _selectedYear = dt.year;
      _selectedMonth = dt.month;
      _cargando = true;
    });
    _cargarFacturas();
  }

  /// Escáner de documentos de Google (ML Kit): detecta los bordes solo,
  /// permite ajustar las esquinas a mano, rotar y escanear varias facturas
  /// seguidas. Funciona en el teléfono, sin internet ni costo.
  Future<void> _escanear() async {
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg},
        pageLimit: 30,
        mode: ScannerMode.full,
        isGalleryImport: true,
      ),
    );
    try {
      final resultado = await scanner.scanDocument();
      final paginas = resultado.images ?? const <String>[];
      for (final path in paginas) {
        await _cola.agregarFoto(path);
      }
      if (paginas.isNotEmpty) {
        _mostrarMensaje(
          paginas.length == 1
              ? 'Factura en proceso. Aparecerá en "Por revisar".'
              : '${paginas.length} facturas en proceso. Aparecerán en "Por revisar".',
        );
      }
    } on PlatformException catch (e) {
      if ((e.message ?? '').toLowerCase().contains('cancel')) return;
      _mostrarMensaje(
        'No se pudo abrir el escáner (${e.message}). Probá con "Foto simple".',
      );
    } catch (e) {
      _mostrarMensaje('No se pudo abrir el escáner: $e. Probá con "Foto simple".');
    } finally {
      scanner.close();
    }
  }

  /// Abre la cámara una y otra vez hasta que el usuario cancela.
  /// Cada foto se encola y Gemini la lee en segundo plano.
  Future<void> _sacarFotos() async {
    int sacadas = 0;
    try {
      while (true) {
        final XFile? foto = await _picker.pickImage(source: ImageSource.camera);
        if (foto == null) break;
        await _cola.agregarFoto(foto.path);
        sacadas++;
        if (!mounted) return;
        final otra = await _preguntarOtraFoto(sacadas);
        if (otra != true) break;
      }
    } catch (e) {
      _mostrarMensaje('No se pudo usar la cámara: $e');
    }
    if (sacadas > 0) {
      _mostrarMensaje(
        sacadas == 1
            ? 'Factura en proceso. Aparecerá en "Por revisar".'
            : '$sacadas facturas en proceso. Aparecerán en "Por revisar".',
      );
    }
  }

  Future<bool?> _preguntarOtraFoto(int sacadas) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline, size: 36),
        title: Text(sacadas == 1 ? '1 factura agregada' : '$sacadas facturas agregadas'),
        content: const Text('Se está leyendo en segundo plano. ¿Sacás otra?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Listo'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.camera_alt),
            label: const Text('Otra foto'),
          ),
        ],
      ),
    );
  }

  Future<void> _elegirDeGaleria() async {
    try {
      final fotos = await _picker.pickMultiImage();
      if (fotos.isEmpty) return;
      for (final f in fotos) {
        await _cola.agregarFoto(f.path);
      }
      _mostrarMensaje(
        fotos.length == 1
            ? 'Factura en proceso.'
            : '${fotos.length} facturas en proceso.',
      );
    } catch (e) {
      _mostrarMensaje('No se pudieron obtener las imágenes: $e');
    }
  }

  void _mostrarMensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
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
              leading: const Icon(Icons.document_scanner),
              title: const Text('Escanear facturas'),
              subtitle: const Text('Recorta los bordes solo. Varias seguidas.'),
              onTap: () {
                Navigator.pop(ctx);
                _escanear();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Foto simple'),
              subtitle: const Text('Sin recorte, por si el escáner falla'),
              onTap: () {
                Navigator.pop(ctx);
                _sacarFotos();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de la galería'),
              subtitle: const Text('Podés seleccionar varias'),
              onTap: () {
                Navigator.pop(ctx);
                _elegirDeGaleria();
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
      _mostrarMensaje('No hay facturas confirmadas en este mes para exportar.');
      return;
    }

    if (_pendientes.isNotEmpty) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hay facturas sin revisar'),
          content: Text(
            'Tenés ${_pendientes.length} factura(s) en "Por revisar". '
            'No se incluyen en el PDF hasta que las confirmes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Revisar primero'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Generar igual'),
            ),
          ],
        ),
      );
      if (seguir != true) return;
    }

    setState(() => _generandoPdf = true);
    try {
      await PdfService.instance.generarYCompartirReporteMensual(
        year: _selectedYear,
        month: _selectedMonth,
        facturas: _facturas,
      );
    } catch (e) {
      _mostrarMensaje('Error al generar el PDF: $e');
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }

  Future<bool?> _confirmarEliminacion(Factura f) {
    final nombre = f.razonSocial.isNotEmpty ? '"${f.razonSocial}"' : 'esta factura';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar factura'),
        content: Text(
          f.total > 0
              ? '¿Seguro que querés eliminar $nombre por ${AppFormatters.formatGuaranies(f.total)}?'
              : '¿Seguro que querés eliminar $nombre?',
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

  Future<void> _eliminar(Factura f) async {
    setState(() {
      _facturas.removeWhere((x) => x.id == f.id);
      _pendientes.removeWhere((x) => x.id == f.id);
    });
    if (f.id != null) {
      _cola.quitar(f.id!);
      await DatabaseHelper.instance.deleteFactura(f.id!, imagenPath: f.imagenPath);
    }
    _cargarFacturas();
  }

  Future<void> _abrirFactura(Factura f) async {
    if (f.estaProcesando) {
      _mostrarMensaje('Todavía se está leyendo esta factura. Esperá unos segundos.');
      return;
    }
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FacturaFormScreen(facturaInicial: f, esNueva: false),
      ),
    );
    if (cambio == true) _cargarFacturas();
  }

  Widget _envolverDismissible(Factura f, Widget child) {
    return Dismissible(
      key: ValueKey('fac-${f.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmarEliminacion(f),
      onDismissed: (_) => _eliminar(f),
      background: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onError),
      ),
      child: child,
    );
  }

  Widget _miniatura(Factura f) {
    final file = File(f.imagenPath);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 44,
        child: f.imagenPath.isNotEmpty && file.existsSync()
            ? Image.file(file, fit: BoxFit.cover, cacheWidth: 120)
            : const Icon(Icons.receipt_long),
      ),
    );
  }

  Widget _tilePendiente(Factura f) {
    final scheme = Theme.of(context).colorScheme;
    Widget subtitulo;
    Widget trailing;

    if (f.estaProcesando) {
      subtitulo = const Text('Leyendo con Gemini...');
      trailing = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    } else if (f.errorExtraccion != null) {
      subtitulo = Text(
        'No se pudo leer. Tocá para cargarla a mano.',
        style: TextStyle(color: scheme.error),
      );
      trailing = Icon(Icons.error_outline, color: scheme.error);
    } else {
      subtitulo = Text(
        '${AppFormatters.formatFechaCorta(f.fecha)}  •  ${AppFormatters.formatGuaranies(f.total)}',
      );
      trailing = FilledButton.tonal(
        onPressed: () => _abrirFactura(f),
        child: const Text('Revisar'),
      );
    }

    return _envolverDismissible(
      f,
      ListTile(
        onTap: () => _abrirFactura(f),
        leading: _miniatura(f),
        title: Text(
          f.estaProcesando
              ? 'Factura nueva'
              : (f.razonSocial.isNotEmpty ? f.razonSocial : '(Sin razón social)'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: subtitulo,
        trailing: trailing,
      ),
    );
  }

  Widget _tileRevisada(Factura f) {
    return _envolverDismissible(
      f,
      ListTile(
        onTap: () => _abrirFactura(f),
        leading: CircleAvatar(
          child: Text(f.categoria.isNotEmpty ? f.categoria[0].toUpperCase() : 'F'),
        ),
        title: Text(
          f.razonSocial.isNotEmpty ? f.razonSocial : '(Sin razón social)',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('${AppFormatters.formatFechaCorta(f.fecha)}  •  ${f.categoria}'),
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
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _encabezado(String texto, {Widget? extra}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Text(
            texto,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          if (extra != null) ...[const SizedBox(width: 8), extra],
        ],
      ),
    );
  }

  Widget _vacio() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            'No hay facturas confirmadas en este mes',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Tocá el botón + para fotografiar o subir facturas.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
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

    final leyendo = _pendientes.where((f) => f.estaProcesando).length;

    final items = <Widget>[];
    if (_pendientes.isNotEmpty) {
      items.add(_encabezado(
        'Por revisar (${_pendientes.length})',
        extra: leyendo > 0
            ? Text(
                '$leyendo leyéndose',
                style: Theme.of(context).textTheme.bodySmall,
              )
            : null,
      ));
      for (final f in _pendientes) {
        items.add(_tilePendiente(f));
      }
      items.add(const Divider(height: 24));
    }
    items.add(_encabezado(
      'Confirmadas de ${AppFormatters.formatMesAnio(_selectedYear, _selectedMonth)}',
    ));
    if (_facturas.isEmpty) {
      items.add(_vacio());
    } else {
      for (int i = 0; i < _facturas.length; i++) {
        if (i > 0) items.add(const Divider(height: 1));
        items.add(_tileRevisada(_facturas[i]));
      }
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
                : ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: items,
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 84, 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(
                top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
        tooltip: 'Agregar facturas',
        child: const Icon(Icons.add),
      ),
    );
  }
}
