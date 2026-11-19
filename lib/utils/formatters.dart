import 'package:intl/intl.dart';

class AppFormatters {
  static final NumberFormat _guaraniFormat = NumberFormat('#,##0', 'es');

  /// Formatea enteros con punto como separador de miles: 1250000 -> "1.250.000"
  static String formatNumero(int valor) {
    return _guaraniFormat.format(valor);
  }

  /// Formatea con sufijo Gs.: 1250000 -> "1.250.000 Gs."
  static String formatGuaranies(int valor) {
    return '${_guaraniFormat.format(valor)} Gs.';
  }

  /// Parsea texto con puntos o espacios a int: "1.250.000" -> 1250000
  static int parseGuaranies(String texto) {
    final limpio = texto.replaceAll(RegExp(r'[^0-9-]'), '');
    if (limpio.isEmpty || limpio == '-') return 0;
    return int.tryParse(limpio) ?? 0;
  }

  /// Convierte fecha ISO yyyy-MM-dd a dd/MM/yyyy
  static String formatFechaCorta(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      return isoDate;
    }
  }

  /// Devuelve "Noviembre 2026" capitalizado
  static String formatMesAnio(int year, int month) {
    final dt = DateTime(year, month, 1);
    final raw = DateFormat('MMMM yyyy', 'es').format(dt);
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1);
  }
}
