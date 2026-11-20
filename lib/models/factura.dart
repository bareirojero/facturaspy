/// Estados de una factura dentro de la app.
class EstadoFactura {
  static const procesando = 'procesando'; // Gemini la está leyendo
  static const porRevisar = 'por_revisar'; // leída, falta confirmar
  static const revisada = 'revisada'; // confirmada por el usuario
}

class Factura {
  final int? id;
  final String fecha; // ISO yyyy-MM-dd
  final String rucEmisor; // Formato 1234567-8
  final String razonSocial;
  final String timbrado; // 8 dígitos
  final String numeroFactura; // Formato 001-001-0000123
  final String condicion; // "contado" | "credito"
  final int gravada10;
  final int gravada5;
  final int exenta;
  final int iva10;
  final int iva5;
  final int total;
  final String categoria;
  final String notas;
  final String imagenPath;
  final String creadoEn; // ISO
  final String estado; // ver EstadoFactura
  final String? errorExtraccion; // mensaje si Gemini no pudo leerla

  static const List<String> categoriasDefecto = [
    'Combustible',
    'Alimentación',
    'Servicios',
    'Salud',
    'Educación',
    'Vehículo',
    'Oficina',
    'Otros',
  ];

  Factura({
    this.id,
    required this.fecha,
    required this.rucEmisor,
    required this.razonSocial,
    required this.timbrado,
    required this.numeroFactura,
    required this.condicion,
    required this.gravada10,
    required this.gravada5,
    required this.exenta,
    required this.iva10,
    required this.iva5,
    required this.total,
    required this.categoria,
    required this.notas,
    required this.imagenPath,
    required this.creadoEn,
    this.estado = EstadoFactura.revisada,
    this.errorExtraccion,
  });

  /// Factura recién fotografiada, sin datos, esperando a Gemini.
  factory Factura.borrador({required String imagenPath}) {
    final ahora = DateTime.now();
    return Factura(
      fecha: ahora.toIso8601String().substring(0, 10),
      rucEmisor: '',
      razonSocial: '',
      timbrado: '',
      numeroFactura: '',
      condicion: 'contado',
      gravada10: 0,
      gravada5: 0,
      exenta: 0,
      iva10: 0,
      iva5: 0,
      total: 0,
      categoria: categoriasDefecto.first,
      notas: '',
      imagenPath: imagenPath,
      creadoEn: ahora.toIso8601String(),
      estado: EstadoFactura.procesando,
    );
  }

  bool get estaProcesando => estado == EstadoFactura.procesando;
  bool get estaPorRevisar => estado == EstadoFactura.porRevisar;

  bool get tieneDiscrepanciaMontos {
    final suma = gravada10 + gravada5 + exenta;
    return (suma - total).abs() > 1;
  }

  Factura copyWith({
    int? id,
    String? fecha,
    String? rucEmisor,
    String? razonSocial,
    String? timbrado,
    String? numeroFactura,
    String? condicion,
    int? gravada10,
    int? gravada5,
    int? exenta,
    int? iva10,
    int? iva5,
    int? total,
    String? categoria,
    String? notas,
    String? imagenPath,
    String? creadoEn,
    String? estado,
    String? errorExtraccion,
    bool limpiarError = false,
  }) {
    return Factura(
      id: id ?? this.id,
      fecha: fecha ?? this.fecha,
      rucEmisor: rucEmisor ?? this.rucEmisor,
      razonSocial: razonSocial ?? this.razonSocial,
      timbrado: timbrado ?? this.timbrado,
      numeroFactura: numeroFactura ?? this.numeroFactura,
      condicion: condicion ?? this.condicion,
      gravada10: gravada10 ?? this.gravada10,
      gravada5: gravada5 ?? this.gravada5,
      exenta: exenta ?? this.exenta,
      iva10: iva10 ?? this.iva10,
      iva5: iva5 ?? this.iva5,
      total: total ?? this.total,
      categoria: categoria ?? this.categoria,
      notas: notas ?? this.notas,
      imagenPath: imagenPath ?? this.imagenPath,
      creadoEn: creadoEn ?? this.creadoEn,
      estado: estado ?? this.estado,
      errorExtraccion:
          limpiarError ? null : (errorExtraccion ?? this.errorExtraccion),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'fecha': fecha,
      'ruc_emisor': rucEmisor,
      'razon_social': razonSocial,
      'timbrado': timbrado,
      'numero_factura': numeroFactura,
      'condicion': condicion,
      'gravada_10': gravada10,
      'gravada_5': gravada5,
      'exenta': exenta,
      'iva_10': iva10,
      'iva_5': iva5,
      'total': total,
      'categoria': categoria,
      'notas': notas,
      'imagen_path': imagenPath,
      'creado_en': creadoEn,
      'estado': estado,
      'error_extraccion': errorExtraccion,
    };
  }

  factory Factura.fromMap(Map<String, dynamic> map) {
    return Factura(
      id: map['id'] as int?,
      fecha: (map['fecha'] as String?) ?? '',
      rucEmisor: (map['ruc_emisor'] as String?) ?? '',
      razonSocial: (map['razon_social'] as String?) ?? '',
      timbrado: (map['timbrado'] as String?) ?? '',
      numeroFactura: (map['numero_factura'] as String?) ?? '',
      condicion: (map['condicion'] as String?) ?? 'contado',
      gravada10: (map['gravada_10'] as int?) ?? 0,
      gravada5: (map['gravada_5'] as int?) ?? 0,
      exenta: (map['exenta'] as int?) ?? 0,
      iva10: (map['iva_10'] as int?) ?? 0,
      iva5: (map['iva_5'] as int?) ?? 0,
      total: (map['total'] as int?) ?? 0,
      categoria: (map['categoria'] as String?) ?? 'Otros',
      notas: (map['notas'] as String?) ?? '',
      imagenPath: (map['imagen_path'] as String?) ?? '',
      creadoEn: (map['creado_en'] as String?) ?? DateTime.now().toIso8601String(),
      estado: (map['estado'] as String?) ?? EstadoFactura.revisada,
      errorExtraccion: map['error_extraccion'] as String?,
    );
  }
}
