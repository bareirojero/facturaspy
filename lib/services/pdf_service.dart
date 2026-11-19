import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/factura.dart';
import '../utils/formatters.dart';
import 'settings_service.dart';

/// Optimiza la imagen de la factura para incrustarla en el PDF sin agotar RAM
Uint8List? _prepararImagenPdf(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final bytes = file.readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    final oriented = img.bakeOrientation(decoded);
    final maxSide = oriented.width > oriented.height ? oriented.width : oriented.height;
    img.Image resized = oriented;
    if (maxSide > 1400) {
      if (oriented.width >= oriented.height) {
        resized = img.copyResize(oriented, width: 1400);
      } else {
        resized = img.copyResize(oriented, height: 1400);
      }
    }
    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  } catch (_) {
    return null;
  }
}

class PdfService {
  static final PdfService instance = PdfService._init();
  PdfService._init();

  Future<void> generarYCompartirReporteMensual({
    required int year,
    required int month,
    required List<Factura> facturas,
  }) async {
    final nombreTitular = await SettingsService.instance.getNombreTitular();
    final rucTitular = await SettingsService.instance.getRucTitular();

    final mesAnio = AppFormatters.formatMesAnio(year, month);
    final fechaEmision = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // Ordenar cronológicamente ascendente para el reporte contable
    final facturasOrdenadas = List<Factura>.from(facturas)
      ..sort((a, b) => a.fecha.compareTo(b.fecha));

    // Totales generales
    int sumGravada10 = 0;
    int sumGravada5 = 0;
    int sumExenta = 0;
    int sumIva10 = 0;
    int sumIva5 = 0;
    int sumTotal = 0;

    // Subtotales por categoría
    final Map<String, int> subtotalesCategoria = {};
    final Map<String, int> conteoCategoria = {};

    for (final f in facturasOrdenadas) {
      sumGravada10 += f.gravada10;
      sumGravada5 += f.gravada5;
      sumExenta += f.exenta;
      sumIva10 += f.iva10;
      sumIva5 += f.iva5;
      sumTotal += f.total;

      subtotalesCategoria[f.categoria] =
          (subtotalesCategoria[f.categoria] ?? 0) + f.total;
      conteoCategoria[f.categoria] = (conteoCategoria[f.categoria] ?? 0) + 1;
    }

    final pdf = pw.Document(
      title: 'Gastos de $mesAnio',
      author: nombreTitular.isNotEmpty ? nombreTitular : 'Facturas PY',
    );

    // Página 1+: Resumen en orientación horizontal (Landscape)
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Gastos de $mesAnio',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blueGrey900,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Titular: ${nombreTitular.isNotEmpty ? nombreTitular : "No especificado"}   |   RUC: ${rucTitular.isNotEmpty ? rucTitular : "No especificado"}',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey800,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  'Fecha de emisión: $fechaEmision',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(color: PdfColors.blueGrey300, thickness: 1),
            pw.SizedBox(height: 6),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Reporte generado por Facturas PY (Montos en Guaraníes)',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
        build: (context) => [
          // Tabla principal de comprobantes
          _buildTablaResumen(
            facturasOrdenadas,
            sumGravada10: sumGravada10,
            sumGravada5: sumGravada5,
            sumExenta: sumExenta,
            sumIva10: sumIva10,
            sumIva5: sumIva5,
            sumTotal: sumTotal,
          ),
          pw.SizedBox(height: 18),
          // Subtotales por categoría
          pw.Text(
            'Subtotales por Categoría',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey900,
            ),
          ),
          pw.SizedBox(height: 6),
          _buildTablaCategorias(subtotalesCategoria, conteoCategoria, sumTotal),
        ],
      ),
    );

    // Páginas siguientes: Una página vertical por cada factura con sus datos e imagen
    for (int i = 0; i < facturasOrdenadas.length; i++) {
      final f = facturasOrdenadas[i];
      pw.MemoryImage? memImage;

      if (f.imagenPath.isNotEmpty) {
        final imgBytes = await compute(_prepararImagenPdf, f.imagenPath);
        if (imgBytes != null) {
          memImage = pw.MemoryImage(imgBytes);
        }
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Comprobante #${i + 1} de ${facturasOrdenadas.length}',
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blueGrey900,
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.blueGrey100,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(
                        '${f.categoria} - ${f.condicion.toUpperCase()}',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blueGrey900,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: 0.7),
                    borderRadius: pw.BorderRadius.circular(4),
                    color: PdfColors.grey50,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            flex: 3,
                            child: pw.Text(
                              'Razón Social: ${f.razonSocial}',
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              'RUC: ${f.rucEmisor}',
                              style: const pw.TextStyle(fontSize: 10),
                              textAlign: pw.TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Fecha: ${AppFormatters.formatFechaCorta(f.fecha)}',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                          pw.Text(
                            'Nº Factura: ${f.numeroFactura}',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                          pw.Text(
                            'Timbrado: ${f.timbrado}',
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 6),
                      pw.Divider(color: PdfColors.grey300, height: 1),
                      pw.SizedBox(height: 6),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Grav. 10%: ${AppFormatters.formatGuaranies(f.gravada10)}',
                            style: const pw.TextStyle(fontSize: 8.5),
                          ),
                          pw.Text(
                            'Grav. 5%: ${AppFormatters.formatGuaranies(f.gravada5)}',
                            style: const pw.TextStyle(fontSize: 8.5),
                          ),
                          pw.Text(
                            'Exenta: ${AppFormatters.formatGuaranies(f.exenta)}',
                            style: const pw.TextStyle(fontSize: 8.5),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 3),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'IVA 10%: ${AppFormatters.formatGuaranies(f.iva10)}',
                            style: const pw.TextStyle(fontSize: 8.5),
                          ),
                          pw.Text(
                            'IVA 5%: ${AppFormatters.formatGuaranies(f.iva5)}',
                            style: const pw.TextStyle(fontSize: 8.5),
                          ),
                          pw.Text(
                            'TOTAL: ${AppFormatters.formatGuaranies(f.total)}',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blueGrey900,
                            ),
                          ),
                        ],
                      ),
                      if (f.notas.trim().isNotEmpty) ...[
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Notas: ${f.notas}',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontStyle: pw.FontStyle.italic,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Expanded(
                  child: pw.Container(
                    width: double.infinity,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                    ),
                    alignment: pw.Alignment.center,
                    child: memImage != null
                        ? pw.Image(memImage, fit: pw.BoxFit.contain)
                        : pw.Text(
                            'Imagen del comprobante no disponible',
                            style: const pw.TextStyle(
                              fontSize: 10,
                              color: PdfColors.grey600,
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    final bytes = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final monthStr = month.toString().padLeft(2, '0');
    final fileName = 'facturas_${year}_$monthStr.pdf';
    final file = File(p.join(tempDir.path, fileName));
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Gastos de $mesAnio',
      text: 'Adjunto reporte de facturas de $mesAnio.',
    );
  }

  pw.Widget _buildTablaResumen(
    List<Factura> facturas, {
    required int sumGravada10,
    required int sumGravada5,
    required int sumExenta,
    required int sumIva10,
    required int sumIva5,
    required int sumTotal,
  }) {
    const headers = [
      'Fecha',
      'RUC',
      'Razón Social',
      'Nº Factura',
      'Timbrado',
      'Gravada 10%',
      'Gravada 5%',
      'Exenta',
      'IVA 10%',
      'IVA 5%',
      'Total',
    ];

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
        children: headers
            .asMap()
            .entries
            .map(
              (entry) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                child: pw.Text(
                  entry.value,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: entry.key >= 5 ? pw.TextAlign.right : pw.TextAlign.left,
                ),
              ),
            )
            .toList(),
      ),
    ];

    for (int i = 0; i < facturas.length; i++) {
      final f = facturas[i];
      final bg = i.isEven ? PdfColors.white : PdfColors.grey100;

      final cells = [
        AppFormatters.formatFechaCorta(f.fecha),
        f.rucEmisor,
        f.razonSocial,
        f.numeroFactura,
        f.timbrado,
        AppFormatters.formatGuaranies(f.gravada10),
        AppFormatters.formatGuaranies(f.gravada5),
        AppFormatters.formatGuaranies(f.exenta),
        AppFormatters.formatGuaranies(f.iva10),
        AppFormatters.formatGuaranies(f.iva5),
        AppFormatters.formatGuaranies(f.total),
      ];

      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: bg),
          children: cells
              .asMap()
              .entries
              .map(
                (entry) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: pw.Text(
                    entry.value,
                    style: pw.TextStyle(
                      fontSize: 7,
                      fontWeight:
                          entry.key == 10 ? pw.FontWeight.bold : pw.FontWeight.normal,
                    ),
                    textAlign:
                        entry.key >= 5 ? pw.TextAlign.right : pw.TextAlign.left,
                  ),
                ),
              )
              .toList(),
        ),
      );
    }

    // Fila final de totales
    final totalCells = [
      'TOTALES',
      '',
      '${facturas.length} comprobante(s)',
      '',
      '',
      AppFormatters.formatGuaranies(sumGravada10),
      AppFormatters.formatGuaranies(sumGravada5),
      AppFormatters.formatGuaranies(sumExenta),
      AppFormatters.formatGuaranies(sumIva10),
      AppFormatters.formatGuaranies(sumIva5),
      AppFormatters.formatGuaranies(sumTotal),
    ];

    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
        children: totalCells
            .asMap()
            .entries
            .map(
              (entry) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                child: pw.Text(
                  entry.value,
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900,
                  ),
                  textAlign: entry.key >= 5 ? pw.TextAlign.right : pw.TextAlign.left,
                ),
              ),
            )
            .toList(),
      ),
    );

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.15),
        1: pw.FlexColumnWidth(1.25),
        2: pw.FlexColumnWidth(2.4),
        3: pw.FlexColumnWidth(1.65),
        4: pw.FlexColumnWidth(1.05),
        5: pw.FlexColumnWidth(1.45),
        6: pw.FlexColumnWidth(1.35),
        7: pw.FlexColumnWidth(1.35),
        8: pw.FlexColumnWidth(1.35),
        9: pw.FlexColumnWidth(1.3),
        10: pw.FlexColumnWidth(1.55),
      },
      children: rows,
    );
  }

  pw.Widget _buildTablaCategorias(
    Map<String, int> subtotales,
    Map<String, int> conteo,
    int totalGeneral,
  ) {
    final entries = subtotales.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return pw.SizedBox(
      width: 380,
      child: pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
        columnWidths: const {
          0: pw.FlexColumnWidth(2.2),
          1: pw.FlexColumnWidth(1.0),
          2: pw.FlexColumnWidth(2.0),
          3: pw.FlexColumnWidth(1.1),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
            children: [
              _catHeaderCell('Categoría', pw.TextAlign.left),
              _catHeaderCell('Cant.', pw.TextAlign.center),
              _catHeaderCell('Subtotal', pw.TextAlign.right),
              _catHeaderCell('%', pw.TextAlign.right),
            ],
          ),
          ...entries.map((e) {
            final pct = totalGeneral > 0
                ? ((e.value / totalGeneral) * 100).toStringAsFixed(1)
                : '0.0';
            return pw.TableRow(
              children: [
                _catBodyCell(e.key, pw.TextAlign.left),
                _catBodyCell('${conteo[e.key] ?? 0}', pw.TextAlign.center),
                _catBodyCell(
                  AppFormatters.formatGuaranies(e.value),
                  pw.TextAlign.right,
                ),
                _catBodyCell('$pct%', pw.TextAlign.right),
              ],
            );
          }),
        ],
      ),
    );
  }

  pw.Widget _catHeaderCell(String text, pw.TextAlign align) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
        ),
        textAlign: align,
      ),
    );
  }

  pw.Widget _catBodyCell(String text, pw.TextAlign align) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 8),
        textAlign: align,
      ),
    );
  }
}
