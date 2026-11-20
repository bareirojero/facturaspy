import 'dart:io';
import 'dart:ui' as ui;

import 'package:facturas_py/models/factura.dart';
import 'package:facturas_py/models/resumen_anual.dart';
import 'package:facturas_py/screens/resumen_anual_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Factura fac(String fecha, int total, String cat, String razon, String ruc) => Factura(
      fecha: fecha,
      rucEmisor: ruc,
      razonSocial: razon,
      timbrado: '12345678',
      numeroFactura: '001-001-0000001',
      condicion: 'contado',
      gravada10: total,
      gravada5: 0,
      exenta: 0,
      iva10: (total / 11).round(),
      iva5: 0,
      total: total,
      categoria: cat,
      notas: '',
      imagenPath: '',
      creadoEn: '2026-01-01T00:00:00',
    );

ResumenAnual datos() {
  final now = DateTime.now().year;
  final f = <Factura>[];
  final montos = [850000, 1200000, 640000, 2350000, 980000, 0, 1500000, 720000, 1100000, 3100000, 1890000, 0];
  for (int m = 0; m < 12; m++) {
    if (montos[m] == 0) continue;
    final mes = (m + 1).toString().padLeft(2, '0');
    f.add(fac('$now-$mes-05', (montos[m] * 0.6).round(), 'Combustible', 'Estación de Servicios Petropar Ruta 2', '80000519-8'));
    f.add(fac('$now-$mes-12', (montos[m] * 0.3).round(), 'Alimentación', 'Supermercado Stock', '80012345-6'));
    f.add(fac('$now-$mes-20', (montos[m] * 0.1).round(), 'Salud', 'Farmacia Catedral', '80055555-1'));
  }
  return ResumenAnual(now, f);
}

Future<void> cargarFuentes() async {
  const dir = '/opt/flutter-sdk/flutter/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final n in ['Roboto-Regular', 'Roboto-Medium', 'Roboto-Bold']) {
    roboto.addFont(Future.value(ByteData.sublistView(File('$dir/$n.ttf').readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('$dir/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

void main() {
  final salida = Platform.environment['SCREENSHOT_DIR'];

  for (final oscuro in [false, true]) {
    testWidgets('resumen anual se dibuja sin desbordes (${oscuro ? 'oscuro' : 'claro'})', (tester) async {
      await initializeDateFormatting('es', null);
      if (salida != null) await tester.runAsync(cargarFuentes);
      tester.view.physicalSize = const Size(390 * 2, 2600 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final r = datos();
      final clave = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: clave,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: const Color(0xFF0F4C81),
            brightness: oscuro ? Brightness.dark : Brightness.light,
            fontFamily: salida != null ? 'Roboto' : null,
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('es')],
          locale: const Locale('es'),
          home: ResumenAnualScreen(yearInicial: r.year, resumenDePrueba: r),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Gasto por mes'), findsOneWidget);

      // Tocar una barra cambia el detalle mostrado.
      await tester.tap(find.text('O').first);
      await tester.pump();
      expect(find.textContaining('Octubre:'), findsOneWidget);

      if (salida != null) {
        await tester.runAsync(() async {
          final boundary = clave.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final img = await boundary.toImage(pixelRatio: 2);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$salida/resumen_${oscuro ? 'oscuro' : 'claro'}.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
    });
  }
}
