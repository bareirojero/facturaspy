import 'factura.dart';

/// Totales de un grupo de facturas (un mes, una categoría, un proveedor...).
class Totales {
  int cantidad = 0;
  int total = 0;
  int gravada10 = 0;
  int gravada5 = 0;
  int exenta = 0;
  int iva10 = 0;
  int iva5 = 0;

  int get ivaTotal => iva10 + iva5;

  void sumar(Factura f) {
    cantidad++;
    total += f.total;
    gravada10 += f.gravada10;
    gravada5 += f.gravada5;
    exenta += f.exenta;
    iva10 += f.iva10;
    iva5 += f.iva5;
  }
}

class Proveedor {
  final String nombre;
  final String ruc;
  final Totales totales = Totales();
  Proveedor(this.nombre, this.ruc);
}

/// Resumen de un año a partir de sus facturas confirmadas.
class ResumenAnual {
  final int year;
  final Totales anio = Totales();
  final List<Totales> meses = List.generate(12, (_) => Totales()); // índice 0 = enero
  final Map<String, Totales> categorias = {};
  final List<Proveedor> proveedores = [];

  ResumenAnual(this.year, List<Factura> facturas) {
    final porRuc = <String, Proveedor>{};
    for (final f in facturas) {
      final mes = DateTime.tryParse(f.fecha)?.month;
      if (mes == null) continue;
      anio.sumar(f);
      meses[mes - 1].sumar(f);
      categorias.putIfAbsent(f.categoria, () => Totales()).sumar(f);

      final clave = f.rucEmisor.trim().isNotEmpty
          ? f.rucEmisor.trim()
          : f.razonSocial.trim().toLowerCase();
      porRuc
          .putIfAbsent(clave, () => Proveedor(f.razonSocial.trim(), f.rucEmisor.trim()))
          .totales
          .sumar(f);
    }
    proveedores
      ..addAll(porRuc.values)
      ..sort((a, b) => b.totales.total.compareTo(a.totales.total));
  }

  int get mesesConDatos => meses.where((m) => m.cantidad > 0).length;

  /// Promedio por mes, contando solo los meses con facturas.
  int get promedioMensual =>
      mesesConDatos == 0 ? 0 : (anio.total / mesesConDatos).round();

  int get maximoMensual =>
      meses.fold(0, (max, m) => m.total > max ? m.total : max);

  /// Categorías ordenadas de mayor a menor gasto.
  List<MapEntry<String, Totales>> get categoriasOrdenadas =>
      categorias.entries.toList()
        ..sort((a, b) => b.value.total.compareTo(a.value.total));
}
