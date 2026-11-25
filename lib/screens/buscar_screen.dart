import 'dart:async';
import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/factura.dart';
import '../utils/formatters.dart';
import 'factura_form_screen.dart';

/// Búsqueda en todas las facturas, de cualquier mes y estado. Sirve también
/// para encontrar una factura a la que se le cargó mal la fecha.
class BuscarScreen extends StatefulWidget {
  const BuscarScreen({super.key});

  @override
  State<BuscarScreen> createState() => _BuscarScreenState();
}

class _BuscarScreenState extends State<BuscarScreen> {
  final _ctrl = TextEditingController();
  Timer? _espera;
  List<Factura>? _resultados; // null = todavía no se buscó nada
  bool _buscando = false;
  bool _huboCambios = false;

  @override
  void dispose() {
    _espera?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _alEscribir(String _) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 250), _buscar);
    setState(() {});
  }

  Future<void> _buscar() async {
    final texto = _ctrl.text;
    if (texto.trim().isEmpty) {
      setState(() => _resultados = null);
      return;
    }
    setState(() => _buscando = true);
    final r = await DatabaseHelper.instance.buscarFacturas(texto);
    if (!mounted || texto != _ctrl.text) return;
    setState(() {
      _resultados = r;
      _buscando = false;
    });
  }

  Future<void> _abrir(Factura f) async {
    if (f.estaProcesando) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todavía se está leyendo esta factura.')),
      );
      return;
    }
    final cambio = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FacturaFormScreen(facturaInicial: f, esNueva: false),
      ),
    );
    if (cambio == true) {
      _huboCambios = true;
      _buscar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _resultados;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_huboCambios);
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _alEscribir,
            onSubmitted: (_) => _buscar(),
            decoration: const InputDecoration(
              hintText: 'Buscar facturas',
              border: InputBorder.none,
            ),
          ),
          actions: [
            if (_ctrl.text.isNotEmpty)
              IconButton(
                tooltip: 'Borrar',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _ctrl.clear();
                  _alEscribir('');
                },
              ),
          ],
        ),
        body: _buscando && r == null
            ? const Center(child: CircularProgressIndicator())
            : r == null
                ? _ayuda(theme)
                : r.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No se encontraron facturas con "${_ctrl.text.trim()}".',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: r.length + 1,
                        separatorBuilder: (_, i) =>
                            i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                r.length == 1
                                    ? '1 factura encontrada'
                                    : '${r.length} facturas encontradas',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            );
                          }
                          return _tile(r[i - 1], theme);
                        },
                      ),
      ),
    );
  }

  Widget _tile(Factura f, ThemeData theme) {
    final etiqueta = f.estaProcesando
        ? 'Leyendo'
        : f.estaPorRevisar
            ? 'Por revisar'
            : null;
    return ListTile(
      onTap: () => _abrir(f),
      title: Text(
        f.razonSocial.isNotEmpty ? f.razonSocial : '(Sin razón social)',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          AppFormatters.formatFechaCorta(f.fecha),
          if (f.numeroFactura.isNotEmpty) f.numeroFactura,
          if (f.categoria.isNotEmpty) f.categoria,
        ].join('  •  '),
        maxLines: 2,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            AppFormatters.formatGuaranies(f.total),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (etiqueta != null)
            Text(
              etiqueta,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _ayuda(ThemeData theme) {
    final estilo = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.search, size: 56, color: theme.colorScheme.outline),
        const SizedBox(height: 12),
        Text(
          'Busca en todas tus facturas, de cualquier mes.',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Text('Podés escribir:', style: estilo),
        const SizedBox(height: 6),
        Text('• Nombre del comercio: "stock", "petropar"', style: estilo),
        Text('• RUC, número de factura o timbrado', style: estilo),
        Text('• Monto: "150.000"', style: estilo),
        Text('• Fecha: "17/11" o "17/11/2026"', style: estilo),
        Text('• Categoría o algo de las notas', style: estilo),
        const SizedBox(height: 12),
        Text(
          'Si una factura "desapareció" por una fecha mal cargada, buscala por el '
          'comercio o el monto, abrila y corregí la fecha.',
          style: estilo,
        ),
      ],
    );
  }
}
