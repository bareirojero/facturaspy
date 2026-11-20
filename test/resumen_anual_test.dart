import 'package:facturas_py/models/factura.dart';
import 'package:facturas_py/models/resumen_anual.dart';
import 'package:flutter_test/flutter_test.dart';

Factura fac(String fecha, int total, {String cat = 'Otros', String ruc = '80012345-6', String razon = 'Comercio SA', int g5 = 0}) {
  final g10 = total - g5;
  return Factura(
    fecha: fecha,
    rucEmisor: ruc,
    razonSocial: razon,
    timbrado: '12345678',
    numeroFactura: '001-001-0000001',
    condicion: 'contado',
    gravada10: g10,
    gravada5: g5,
    exenta: 0,
    iva10: (g10 / 11).round(),
    iva5: (g5 / 21).round(),
    total: total,
    categoria: cat,
    notas: '',
    imagenPath: '',
    creadoEn: '2026-01-01T00:00:00',
  );
}

void main() {
  final r = ResumenAnual(2026, [
    fac('2026-01-10', 110000, cat: 'Combustible'),
    fac('2026-01-20', 55000, cat: 'Alimentación', ruc: '1234567-8', razon: 'Despensa'),
    fac('2026-03-05', 220000, cat: 'Combustible'),
    fac('2026-03-06', 21000, cat: 'Salud', ruc: '1234567-8', razon: 'Despensa', g5: 21000),
  ]);

  test('totales del año y por mes', () {
    expect(r.anio.cantidad, 4);
    expect(r.anio.total, 406000);
    expect(r.meses[0].cantidad, 2);
    expect(r.meses[0].total, 165000);
    expect(r.meses[1].cantidad, 0);
    expect(r.meses[2].total, 241000);
    expect(r.anio.iva10, 10000 + 5000 + 20000);
    expect(r.anio.iva5, 1000);
  });

  test('promedio y máximo mensual usan solo meses con datos', () {
    expect(r.mesesConDatos, 2);
    expect(r.promedioMensual, 203000);
    expect(r.maximoMensual, 241000);
  });

  test('categorías y proveedores ordenados por gasto', () {
    expect(r.categoriasOrdenadas.first.key, 'Combustible');
    expect(r.categoriasOrdenadas.first.value.total, 330000);
    expect(r.proveedores.length, 2);
    expect(r.proveedores.first.nombre, 'Comercio SA');
    expect(r.proveedores.last.totales.cantidad, 2);
  });
}
