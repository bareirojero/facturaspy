import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/resumen_anual.dart';
import '../utils/formatters.dart';

/// Resumen de un año: totales, gasto por mes, categorías, proveedores e IVA.
/// Al tocar un mes devuelve (año, mes) para que el inicio salte a ese mes.
class ResumenAnualScreen extends StatefulWidget {
  final int yearInicial;

  /// Solo para tests: datos ya calculados, sin leer la base.
  @visibleForTesting
  final ResumenAnual? resumenDePrueba;

  const ResumenAnualScreen({
    super.key,
    required this.yearInicial,
    this.resumenDePrueba,
  });

  @override
  State<ResumenAnualScreen> createState() => _ResumenAnualScreenState();
}

class _ResumenAnualScreenState extends State<ResumenAnualScreen> {
  late int _year;
  ResumenAnual? _resumen;
  int? _mesSeleccionado; // 0..11

  @override
  void initState() {
    super.initState();
    _year = widget.yearInicial;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _resumen = null);
    final prueba = widget.resumenDePrueba;
    final ResumenAnual r;
    if (prueba != null && prueba.year == _year) {
      r = prueba;
    } else {
      final facturas = await DatabaseHelper.instance.getFacturasPorAnio(_year);
      r = ResumenAnual(_year, facturas);
    }
    if (!mounted) return;
    final hoy = DateTime.now();
    setState(() {
      _resumen = r;
      _mesSeleccionado = _year == hoy.year ? hoy.month - 1 : null;
    });
  }

  void _cambiarAnio(int delta) {
    _year += delta;
    _cargar();
  }

  void _irAlMes(int mes) {
    Navigator.of(context).pop(DateTime(_year, mes + 1, 1));
  }

  @override
  Widget build(BuildContext context) {
    final r = _resumen;
    return Scaffold(
      appBar: AppBar(title: const Text('Resumen anual')),
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
                  onPressed: () => _cambiarAnio(-1),
                ),
                Text(
                  '$_year',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _cambiarAnio(1),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: r == null
                ? const Center(child: CircularProgressIndicator())
                : r.anio.cantidad == 0
                    ? _sinDatos()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: [
                          _tiles(r),
                          const SizedBox(height: 16),
                          _tarjeta(
                            'Gasto por mes',
                            _GraficoMensual(
                              resumen: r,
                              seleccionado: _mesSeleccionado,
                              onSeleccionar: (i) =>
                                  setState(() => _mesSeleccionado = i),
                              onAbrir: _irAlMes,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _tarjeta('Detalle por mes', _tablaMeses(r)),
                          const SizedBox(height: 16),
                          _tarjeta('Por categoría', _categorias(r)),
                          const SizedBox(height: 16),
                          _tarjeta('Principales proveedores', _proveedores(r)),
                          const SizedBox(height: 16),
                          _tarjeta('Impuestos del año', _impuestos(r)),
                          const SizedBox(height: 12),
                          Text(
                            'Solo se cuentan las facturas confirmadas. '
                            'Las que están en "Por revisar" no se incluyen.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _sinDatos() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              'No hay facturas confirmadas en $_year',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjeta(String titulo, Widget contenido) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            contenido,
          ],
        ),
      ),
    );
  }

  Widget _tiles(ResumenAnual r) {
    Widget tile(String etiqueta, String valor, {String? detalle}) {
      final theme = Theme.of(context);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                etiqueta,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  valor,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (detalle != null)
                Text(
                  detalle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            tile('Total del año', AppFormatters.formatGuaranies(r.anio.total)),
            const SizedBox(width: 12),
            tile('Facturas', '${r.anio.cantidad}',
                detalle: '${r.mesesConDatos} mes(es) con datos'),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            tile('IVA total', AppFormatters.formatGuaranies(r.anio.ivaTotal)),
            const SizedBox(width: 12),
            tile('Promedio mensual', AppFormatters.formatGuaranies(r.promedioMensual)),
          ],
        ),
      ],
    );
  }

  Widget _tablaMeses(ResumenAnual r) {
    final theme = Theme.of(context);
    final estiloCab = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.bold,
    );
    final estilo = theme.textTheme.bodySmall;

    Widget fila(List<String> celdas, {TextStyle? style, VoidCallback? onTap, bool resaltar = false}) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          color: resaltar ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4) : null,
          child: Row(
            children: [
              Expanded(flex: 3, child: Text(celdas[0], style: style)),
              Expanded(flex: 2, child: Text(celdas[1], style: style, textAlign: TextAlign.right)),
              Expanded(flex: 4, child: Text(celdas[2], style: style, textAlign: TextAlign.right)),
              Expanded(flex: 4, child: Text(celdas[3], style: style, textAlign: TextAlign.right)),
            ],
          ),
        ),
      );
    }

    final filas = <Widget>[
      fila(['Mes', 'Fact.', 'Total', 'IVA'], style: estiloCab),
      const Divider(height: 1),
    ];
    for (int i = 0; i < 12; i++) {
      final m = r.meses[i];
      filas.add(fila(
        [
          AppFormatters.nombreMes(i + 1),
          m.cantidad == 0 ? '–' : '${m.cantidad}',
          m.cantidad == 0 ? '–' : AppFormatters.formatNumero(m.total),
          m.cantidad == 0 ? '–' : AppFormatters.formatNumero(m.ivaTotal),
        ],
        style: m.cantidad == 0
            ? estilo?.copyWith(color: theme.colorScheme.onSurfaceVariant)
            : estilo,
        onTap: () => _irAlMes(i),
        resaltar: i == _mesSeleccionado,
      ));
    }
    filas.add(const Divider(height: 1));
    filas.add(fila(
      [
        'Total',
        '${r.anio.cantidad}',
        AppFormatters.formatNumero(r.anio.total),
        AppFormatters.formatNumero(r.anio.ivaTotal),
      ],
      style: estilo?.copyWith(fontWeight: FontWeight.bold),
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...filas,
        const SizedBox(height: 6),
        Text(
          'Montos en guaraníes. Tocá un mes para ver sus facturas.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// Barras horizontales de un solo color: la longitud codifica el monto.
  Widget _barraHorizontal({
    required String nombre,
    required String detalle,
    required int valor,
    required int maximo,
  }) {
    final theme = Theme.of(context);
    final ratio = maximo == 0 ? 0.0 : valor / maximo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(AppFormatters.formatGuaranies(valor), style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, c) => Stack(
              children: [
                Container(
                  height: 8,
                  width: c.maxWidth,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  height: 8,
                  width: c.maxWidth * ratio,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detalle,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _categorias(ResumenAnual r) {
    final lista = r.categoriasOrdenadas;
    final maximo = lista.isEmpty ? 0 : lista.first.value.total;
    return Column(
      children: [
        for (final e in lista)
          _barraHorizontal(
            nombre: e.key,
            valor: e.value.total,
            maximo: maximo,
            detalle: '${e.value.cantidad} factura(s) · '
                '${r.anio.total == 0 ? 0 : (e.value.total * 100 / r.anio.total).toStringAsFixed(1)}% del año',
          ),
      ],
    );
  }

  Widget _proveedores(ResumenAnual r) {
    final top = r.proveedores.take(5).toList();
    final maximo = top.isEmpty ? 0 : top.first.totales.total;
    return Column(
      children: [
        for (final p in top)
          _barraHorizontal(
            nombre: p.nombre.isNotEmpty ? p.nombre : '(Sin razón social)',
            valor: p.totales.total,
            maximo: maximo,
            detalle: '${p.ruc.isNotEmpty ? 'RUC ${p.ruc} · ' : ''}'
                '${p.totales.cantidad} factura(s)',
          ),
        if (r.proveedores.length > 5)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'y ${r.proveedores.length - 5} proveedor(es) más',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _impuestos(ResumenAnual r) {
    final theme = Theme.of(context);
    Widget linea(String etiqueta, int valor, {bool negrita = false}) {
      final estilo = theme.textTheme.bodyMedium?.copyWith(
        fontWeight: negrita ? FontWeight.bold : FontWeight.normal,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(etiqueta, style: estilo)),
            Text(AppFormatters.formatGuaranies(valor), style: estilo),
          ],
        ),
      );
    }

    final a = r.anio;
    return Column(
      children: [
        linea('Gravada 10%', a.gravada10),
        linea('Gravada 5%', a.gravada5),
        linea('Exenta', a.exenta),
        const Divider(),
        linea('IVA 10%', a.iva10),
        linea('IVA 5%', a.iva5),
        linea('IVA total', a.ivaTotal, negrita: true),
      ],
    );
  }
}

/// Gráfico de barras verticales del gasto mensual. Un solo color (es una
/// sola serie); el mes tocado se resalta y su valor se muestra arriba.
class _GraficoMensual extends StatelessWidget {
  final ResumenAnual resumen;
  final int? seleccionado;
  final ValueChanged<int> onSeleccionar;
  final ValueChanged<int> onAbrir;

  const _GraficoMensual({
    required this.resumen,
    required this.seleccionado,
    required this.onSeleccionar,
    required this.onAbrir,
  });

  static const _iniciales = ['E', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maximo = resumen.maximoMensual;
    const alto = 150.0;
    final sel = seleccionado;
    final mSel = sel == null ? null : resumen.meses[sel];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Detalle del mes elegido (hace de tooltip, también accesible al tacto).
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: sel == null
              ? Text(
                  'Tocá una barra para ver el detalle del mes.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                )
              : Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${AppFormatters.nombreMes(sel + 1)}: '
                            '${AppFormatters.formatGuaranies(mSel!.total)}',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${mSel.cantidad} factura(s) · IVA ${AppFormatters.formatGuaranies(mSel.ivaTotal)}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => onAbrir(sel),
                      child: const Text('Ver mes'),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        // Referencia del máximo (eje recesivo).
        Text(
          'máx. ${AppFormatters.formatCompacto(maximo)}',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: alto + 24,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(12, (i) {
              final m = resumen.meses[i];
              final ratio = maximo == 0 ? 0.0 : m.total / maximo;
              final elegido = i == sel;
              final color = elegido
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primary.withValues(alpha: 0.55);
              return Expanded(
                child: Semantics(
                  label: '${AppFormatters.nombreMes(i + 1)}: '
                      '${AppFormatters.formatGuaranies(m.total)}, ${m.cantidad} facturas',
                  button: true,
                  child: InkWell(
                    // Zona táctil = toda la columna, más grande que la barra.
                    onTap: () => onSeleccionar(i),
                    borderRadius: BorderRadius.circular(6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // La barra usa el alto disponible, así la etiqueta
                        // nunca se corta aunque la letra del teléfono sea grande.
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, c) => Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                height: m.total == 0
                                    ? 0
                                    : (c.maxHeight * ratio).clamp(3.0, c.maxHeight),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Container(height: 1, color: theme.colorScheme.outlineVariant),
                        const SizedBox(height: 4),
                        Text(
                          _iniciales[i],
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: elegido ? FontWeight.bold : FontWeight.normal,
                            color: elegido
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
