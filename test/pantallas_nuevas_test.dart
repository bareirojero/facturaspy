import 'dart:io';

import 'package:facturas_py/db/database_helper.dart';
import 'package:facturas_py/screens/bienvenida_screen.dart';
import 'package:facturas_py/screens/buscar_screen.dart';
import 'package:facturas_py/screens/categorias_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Widget app(Widget home) => MaterialApp(home: home);

void main() {
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('es', null);
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('pantallas_');
    DatabaseHelper.rutaDePrueba = '${tmp.path}/t.db';
    await DatabaseHelper.instance.cerrarParaTests();
  });

  tearDown(() async {
    await DatabaseHelper.instance.cerrarParaTests();
    await tmp.delete(recursive: true);
  });

  void telefonoAngosto(WidgetTester tester) {
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('bienvenida: recorre las 4 páginas sin desbordes y termina', (tester) async {
    telefonoAngosto(tester);
    var termino = false;
    await tester.pumpWidget(app(BienvenidaScreen(alTerminar: () => termino = true)));
    await tester.pumpAndSettle();
    for (final titulo in ['Conectá Gemini', 'Tus datos', 'Algunos consejos']) {
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text(titulo), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();
    expect(termino, isTrue);
    expect(await FlutterSecureStorage().read(key: 'bienvenida_vista'), '1');
  });

  testWidgets('categorías: lista, agregar y sin desbordes', (tester) async {
    telefonoAngosto(tester);
    await tester.pumpWidget(app(const CategoriasScreen()));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.text('Combustible'), findsOneWidget);
    await tester.tap(find.text('Nueva'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Mascotas');
    await tester.tap(find.text('Guardar'));
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
    }
    expect(find.text('Mascotas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('búsqueda: ayuda inicial sin desbordes', (tester) async {
    telefonoAngosto(tester);
    await tester.pumpWidget(app(const BuscarScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Busca en todas tus facturas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
