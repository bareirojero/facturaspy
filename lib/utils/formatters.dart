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

  /// Formato corto para ejes y etiquetas: 1250000 -> "1,3 M", 85000 -> "85 mil".
  static String formatCompacto(int valor) {
    if (valor >= 1000000) {
      final m = valor / 1000000;
      return '${NumberFormat(m >= 10 ? '#0' : '#0.#', 'es').format(m)} M';
    }
    if (valor >= 1000) return '${(valor / 1000).round()} mil';
    return valor.toString();
  }

  /// Nombre del mes capitalizado: 3 -> "Marzo".
  static String nombreMes(int month) {
    final raw = DateFormat('MMMM', 'es').format(DateTime(2000, month, 1));
    return raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1);
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
