import 'dart:io';

import 'package:facturas_py/db/database_helper.dart';
import 'package:facturas_py/models/factura.dart';
import 'package:facturas_py/services/respaldo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Factura fac({
  required String fecha,
  required String razon,
  required String ruc,
  required int total,
  String categoria = 'Otros',
  String imagen = '',
  String estado = EstadoFactura.revisada,
  String numero = '001-001-0000001',
}) =>
    Factura(
      fecha: fecha,
      rucEmisor: ruc,
      razonSocial: razon,
      timbrado: '12345678',
      numeroFactura: numero,
      condicion: 'contado',
      gravada10: total,
      gravada5: 0,
      exenta: 0,
      iva10: (total / 11).round(),
      iva5: 0,
      total: total,
      categoria: categoria,
      notas: '',
      imagenPath: imagen,
      creadoEn: '$fecha' 'T10:00:00',
      estado: estado,
    );

void main() {
  late Directory tmp;
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('facturas_test_');
    DatabaseHelper.rutaDePrueba = '${tmp.path}/test.db';
    await db.cerrarParaTests();
  });

  tearDown(() async {
    await db.cerrarParaTests();
    await tmp.delete(recursive: true);
  });

  test('categorías: lista inicial, agregar, renombrar, borrar con traspaso', () async {
    expect(await db.getCategorias(), Factura.categoriasDefecto);
    expect(await db.agregarCategoria('Ropa'), isTrue);
    expect(await db.agregarCategoria('ropa'), isFalse, reason: 'sin distinguir mayúsculas');

    await db.insertFactura(fac(fecha: '2026-11-01', razon: 'Tienda', ruc: '1-1', total: 1000, categoria: 'Ropa'));
    expect(await db.contarFacturasDeCategoria('Ropa'), 1);

    expect(await db.renombrarCategoria('Ropa', 'Vestimenta', actualizarFacturas: true), isTrue);
    expect((await db.getFacturasPorMes(2026, 11)).single.categoria, 'Vestimenta');
    expect(await db.renombrarCategoria('Vestimenta', 'Salud', actualizarFacturas: true), isFalse,
        reason: 'no puede chocar con otra');

    await db.borrarCategoria('Vestimenta', moverA: 'Otros');
    expect(await db.getCategorias(), isNot(contains('Vestimenta')));
    expect((await db.getFacturasPorMes(2026, 11)).single.categoria, 'Otros');

    await db.reordenarCategorias(['Salud', ...Factura.categoriasDefecto.where((c) => c != 'Salud')]);
    expect((await db.getCategorias()).first, 'Salud');
  });

  test('última categoría por proveedor solo mira facturas confirmadas', () async {
    await db.insertFactura(fac(fecha: '2026-10-01', razon: 'Petropar', ruc: '80000519-8', total: 100, categoria: 'Combustible'));
    await db.insertFactura(fac(fecha: '2026-11-01', razon: 'Petropar', ruc: '80000519-8', total: 100, categoria: 'Vehículo'));
    await db.insertFactura(fac(fecha: '2026-11-20', razon: 'Petropar', ruc: '80000519-8', total: 100, categoria: 'Salud', estado: EstadoFactura.porRevisar));
    expect(await db.ultimaCategoriaDeRuc('80000519-8'), 'Vehículo');
    expect(await db.ultimaCategoriaDeRuc('999'), isNull);
    expect(await db.ultimaCategoriaDeRuc(''), isNull);
  });

  test('búsqueda por nombre, monto, fecha y en cualquier año', () async {
    await db.insertFactura(fac(fecha: '2026-11-17', razon: 'Supermercado Stock', ruc: '80012345-6', total: 150000));
    await db.insertFactura(fac(fecha: '2062-11-17', razon: 'Farmacia Catedral', ruc: '80055555-1', total: 31000, numero: '002-003-0004567'));
    await db.insertFactura(fac(fecha: '2026-01-05', razon: 'Petropar', ruc: '80000519-8', total: 250000));

    expect((await db.buscarFacturas('stock')).single.razonSocial, 'Supermercado Stock');
    expect((await db.buscarFacturas('150.000')).single.total, 150000);
    expect((await db.buscarFacturas('farmacia')).single.fecha, '2062-11-17',
        reason: 'encuentra la de fecha mal cargada');
    expect((await db.buscarFacturas('17/11')).length, 2);
    expect((await db.buscarFacturas('17/11/2026')).single.razonSocial, 'Supermercado Stock');
    expect((await db.buscarFacturas('0004567')).single.razonSocial, 'Farmacia Catedral');
    expect((await db.buscarFacturas('super stock')).length, 1, reason: 'todas las palabras');
    expect(await db.buscarFacturas('inexistente'), isEmpty);
    expect(await db.buscarFacturas('   '), isEmpty);
  });

  test('respaldo: exportar, borrar todo y restaurar deja todo igual', () async {
    final fotosApp = Directory('${tmp.path}/facturas_img')..createSync();
    final foto1 = File('${fotosApp.path}/fac_1.jpg')..writeAsBytesSync(List.filled(5000, 7));
    final foto2 = File('${fotosApp.path}/fac_2.jpg')..writeAsBytesSync(List.filled(3000, 9));

    await db.insertFactura(fac(fecha: '2026-11-01', razon: 'Stock', ruc: '1-1', total: 1000, imagen: foto1.path, categoria: 'Alimentación'));
    await db.insertFactura(fac(fecha: '2026-11-02', razon: 'Petropar', ruc: '2-2', total: 2000, imagen: foto2.path, categoria: 'Mascotas'));
    await db.insertFactura(fac(fecha: '2026-11-03', razon: 'Sin foto', ruc: '3-3', total: 3000));
    await db.agregarCategoria('Mascotas');

    final servicio = RespaldoService(db);
    final salida = Directory('${tmp.path}/salida')..createSync();
    final zip = await servicio.crearArchivo(
      destino: salida,
      nombreTitular: 'Titular de prueba',
      rucTitular: '1234567-8',
      modelo: 'gemini-3.1-flash-lite',
    );
    expect(zip.existsSync(), isTrue);

    // Se pierde todo: se borran las facturas y se cambian las categorías.
    for (final f in await db.getFacturasPorMes(2026, 11)) {
      await db.deleteFactura(f.id!, imagenPath: f.imagenPath);
    }
    await db.borrarCategoria('Mascotas');
    await db.insertFactura(fac(fecha: '2026-12-01', razon: 'Otra', ruc: '9-9', total: 1));
    expect(foto1.existsSync(), isFalse);

    final leido = await servicio.leer(zip.path);
    expect(leido.cantidadFacturas, 3);
    expect(leido.nombreTitular, 'Titular de prueba');
    expect(leido.modelo, 'gemini-3.1-flash-lite');
    expect(leido.categorias, contains('Mascotas'));

    await servicio.aplicar(leido, dirFotos: fotosApp);

    final restauradas = await db.getFacturasPorMes(2026, 11);
    expect(restauradas.map((f) => f.razonSocial).toSet(), {'Stock', 'Petropar', 'Sin foto'});
    expect(await db.getFacturasPorMes(2026, 12), isEmpty, reason: 'reemplaza, no mezcla');
    expect(await db.getCategorias(), contains('Mascotas'));

    final stock = restauradas.firstWhere((f) => f.razonSocial == 'Stock');
    expect(File(stock.imagenPath).readAsBytesSync().length, 5000);
    expect(stock.categoria, 'Alimentación');
    expect(restauradas.firstWhere((f) => f.razonSocial == 'Sin foto').imagenPath, '');
    expect(fotosApp.listSync().length, 2, reason: 'solo quedan las fotos en uso');
  });

  test('respaldo: rechaza archivos que no son respaldos', () async {
    final falso = File('${tmp.path}/falso.zip')..writeAsStringSync('no es un zip');
    expect(() => RespaldoService(db).leer(falso.path), throwsA(isA<RespaldoException>()));
  });

  test('migración desde la versión anterior conserva facturas y crea categorías', () async {
    // Base como la tiene hoy el teléfono (versión 2, sin tabla de categorías).
    final vieja = await databaseFactory.openDatabase(
      DatabaseHelper.rutaDePrueba!,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (d, v) async {
          await d.execute('''
            CREATE TABLE facturas (
              id INTEGER PRIMARY KEY AUTOINCREMENT, fecha TEXT NOT NULL,
              ruc_emisor TEXT NOT NULL, razon_social TEXT NOT NULL,
              timbrado TEXT NOT NULL, numero_factura TEXT NOT NULL,
              condicion TEXT NOT NULL, gravada_10 INTEGER NOT NULL,
              gravada_5 INTEGER NOT NULL, exenta INTEGER NOT NULL,
              iva_10 INTEGER NOT NULL, iva_5 INTEGER NOT NULL,
              total INTEGER NOT NULL, categoria TEXT NOT NULL,
              notas TEXT NOT NULL, imagen_path TEXT NOT NULL,
              creado_en TEXT NOT NULL,
              estado TEXT NOT NULL DEFAULT 'revisada', error_extraccion TEXT
            )
          ''');
        },
      ),
    );
    final f = fac(fecha: '2026-11-17', razon: 'María Remigia', ruc: '1-1', total: 31000, categoria: 'Mascotas').toMap();
    await vieja.insert('facturas', f);
    await vieja.close();

    final facturas = await db.getFacturasPorMes(2026, 11);
    expect(facturas.single.razonSocial, 'María Remigia');
    final cats = await db.getCategorias();
    expect(cats.take(8), Factura.categoriasDefecto);
    expect(cats, contains('Mascotas'), reason: 'conserva categorías ya usadas');
  });
}
