import 'dart:convert';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// Datos que se pueden obtener con certeza del QR de una factura
/// electrónica (KuDE / e-Kuatia). El QR no trae razón social, timbrado ni el
/// desglose de gravadas, así que esos datos siguen viniendo de Gemini.
class DatosQrEkuatia {
  final String cdc; // Código de Control, 44 dígitos
  final String rucEmisor; // "1234567-8"
  final String numeroFactura; // "001-001-0000123"
  final String fecha; // "yyyy-MM-dd"
  final int? total; // dTotGralOpe, si viene en el QR
  final bool esFactura; // tipo de documento 01

  DatosQrEkuatia({
    required this.cdc,
    required this.rucEmisor,
    required this.numeroFactura,
    required this.fecha,
    required this.total,
    required this.esFactura,
  });
}

class EkuatiaQr {
  /// Busca un QR de e-Kuatia en la imagen. Devuelve null si no hay o no es válido.
  static Future<DatosQrEkuatia?> leerDeImagen(String path) async {
    final scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
    try {
      final codigos = await scanner.processImage(InputImage.fromFilePath(path));
      for (final c in codigos) {
        final datos = interpretar(c.rawValue ?? c.displayValue ?? '');
        if (datos != null) return datos;
      }
      return null;
    } catch (_) {
      return null; // Sin QR legible: se sigue solo con Gemini.
    } finally {
      await scanner.close();
    }
  }

  /// Interpreta el texto del QR (una URL de consulta de e-Kuatia).
  static DatosQrEkuatia? interpretar(String texto) {
    if (texto.isEmpty) return null;

    Map<String, String> params = {};
    try {
      params = Uri.parse(texto.trim()).queryParameters;
    } catch (_) {}

    // El CDC viene en el parámetro "Id"; si no, se busca cualquier 44 dígitos.
    String? cdc = params['Id'] ?? params['id'];
    if (cdc == null || !RegExp(r'^\d{44}$').hasMatch(cdc)) {
      cdc = RegExp(r'\d{44}').firstMatch(texto)?.group(0);
    }
    if (cdc == null || !cdcValido(cdc)) return null;

    // Estructura del CDC:
    // tipo(2) RUC(8) DV(1) est(3) pto(3) num(7) tipoContrib(1)
    // fecha AAAAMMDD(8) tipoEmision(1) codSeg(9) DV(1)
    final tipo = cdc.substring(0, 2);
    final ruc = int.parse(cdc.substring(2, 10)).toString();
    final dv = cdc.substring(10, 11);
    final est = cdc.substring(11, 14);
    final pto = cdc.substring(14, 17);
    final num = cdc.substring(17, 24);
    final f = cdc.substring(25, 33);
    String fecha = '${f.substring(0, 4)}-${f.substring(4, 6)}-${f.substring(6, 8)}';

    // dFeEmiDE suele venir como texto en hexadecimal ("2026-11-19T10:20:30").
    final feHex = params['dFeEmiDE'];
    if (feHex != null) {
      final decodificada = _decodificarHex(feHex);
      final m = RegExp(r'^\d{4}-\d{2}-\d{2}').firstMatch(decodificada ?? feHex);
      if (m != null) fecha = m.group(0)!;
    }

    int? total;
    final tot = params['dTotGralOpe'];
    if (tot != null) {
      final v = double.tryParse(tot.replaceAll(',', '.'));
      if (v != null && v > 0) total = v.round();
    }

    return DatosQrEkuatia(
      cdc: cdc,
      rucEmisor: '$ruc-$dv',
      numeroFactura: '$est-$pto-$num',
      fecha: fecha,
      total: total,
      esFactura: tipo == '01',
    );
  }

  /// Verifica el dígito verificador del CDC (módulo 11, como el del RUC).
  static bool cdcValido(String cdc) {
    if (!RegExp(r'^\d{44}$').hasMatch(cdc)) return false;
    final base = cdc.substring(0, 43);
    int suma = 0;
    int k = 2;
    for (int i = base.length - 1; i >= 0; i--) {
      suma += int.parse(base[i]) * k;
      k = k == 11 ? 2 : k + 1;
    }
    final resto = suma % 11;
    final dv = resto > 1 ? 11 - resto : 0;
    return dv == int.parse(cdc[43]);
  }

  static String? _decodificarHex(String hex) {
    if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;
    try {
      final bytes = <int>[];
      for (int i = 0; i < hex.length; i += 2) {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }
}
