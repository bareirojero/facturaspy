import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'settings_service.dart';

class GeminiException implements Exception {
  final String message;
  final int? statusCode;

  GeminiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class GeminiExtractionResult {
  final String? fecha;
  final String? rucEmisor;
  final String? razonSocial;
  final String? timbrado;
  final String? numeroFactura;
  final String? condicion;
  final int gravada10;
  final int gravada5;
  final int exenta;
  final int iva10;
  final int iva5;
  final int total;

  GeminiExtractionResult({
    this.fecha,
    this.rucEmisor,
    this.razonSocial,
    this.timbrado,
    this.numeroFactura,
    this.condicion,
    required this.gravada10,
    required this.gravada5,
    required this.exenta,
    required this.iva10,
    required this.iva5,
    required this.total,
  });

  factory GeminiExtractionResult.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic val) {
      if (val == null) return 0;
      if (val is int) return val;
      if (val is double) return val.round();
      if (val is String) {
        final cleaned = val.replaceAll(RegExp(r'[^0-9-]'), '');
        return int.tryParse(cleaned) ?? 0;
      }
      return 0;
    }

    String? toCleanString(dynamic val) {
      if (val == null) return null;
      final s = val.toString().trim();
      return s.isEmpty || s.toLowerCase() == 'null' ? null : s;
    }

    final g10 = toInt(json['gravada_10']);
    final g5 = toInt(json['gravada_5']);
    final ex = toInt(json['exenta']);
    int i10 = toInt(json['iva_10']);
    int i5 = toInt(json['iva_5']);
    final tot = toInt(json['total']);

    // Respaldo de cálculo IVA incluido según normativa paraguaya si vino en 0 pero hay gravada
    if (i10 == 0 && g10 > 0) {
      i10 = (g10 / 11).round();
    }
    if (i5 == 0 && g5 > 0) {
      i5 = (g5 / 21).round();
    }

    String? cond = toCleanString(json['condicion'])?.toLowerCase();
    if (cond != null) {
      if (cond.contains('cr') || cond.contains('cred')) {
        cond = 'credito';
      } else {
        cond = 'contado';
      }
    }

    return GeminiExtractionResult(
      fecha: toCleanString(json['fecha']),
      rucEmisor: toCleanString(json['ruc_emisor']),
      razonSocial: toCleanString(json['razon_social']),
      timbrado: toCleanString(json['timbrado']),
      numeroFactura: toCleanString(json['numero_factura']),
      condicion: cond,
      gravada10: g10,
      gravada5: g5,
      exenta: ex,
      iva10: i10,
      iva5: i5,
      total: tot,
    );
  }
}

/// Función top-level para ejecutar redimensionamiento en isolate (compute)
Uint8List _procesarImagenIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return bytes;
  }

  final oriented = img.bakeOrientation(decoded);
  final maxSide = oriented.width > oriented.height ? oriented.width : oriented.height;

  img.Image resized = oriented;
  if (maxSide > 1600) {
    if (oriented.width >= oriented.height) {
      resized = img.copyResize(oriented, width: 1600);
    } else {
      resized = img.copyResize(oriented, height: 1600);
    }
  }

  return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
}

/// Extrae el mensaje de error que devuelve la API de Google, si lo hay.
String _mensajeErrorApi(String body) {
  try {
    final err = (jsonDecode(body) as Map<String, dynamic>)['error'];
    if (err is Map && err['message'] is String) return err['message'] as String;
  } catch (_) {}
  return body.length > 200 ? '${body.substring(0, 200)}...' : body;
}

bool _esKeyInvalida(int status, String body) =>
    status == 401 ||
    status == 403 ||
    (status == 400 && body.contains('API_KEY_INVALID'));

class GeminiService {
  static final GeminiService instance = GeminiService._init();
  GeminiService._init();

  static const String _prompt = '''
Analizá la imagen de esta factura comercial de Paraguay y extraé los datos fiscales solicitados en formato JSON estricto.

Reglas importantes:
1. Es una factura paraguaya (SET / DNIT).
2. Todos los montos están expresados en guaraníes (Gs.), sin decimales. En Paraguay se usa el punto "." como separador de miles (por ejemplo, "150.000" equivale al entero 150000). Devolvé todos los montos como números enteros puros sin puntos ni símbolos.
3. Los importes gravados en Paraguay ya tienen el IVA incluido:
   - Liquidación IVA 10% = gravada_10 / 11 (redondeado al entero más cercano).
   - Liquidación IVA 5% = gravada_5 / 21 (redondeado al entero más cercano).
4. Formato de fecha: "yyyy-MM-dd".
5. Formato de RUC del emisor: "1234567-8" (con guion y dígito verificador).
6. Timbrado: número de 8 dígitos.
7. Número de factura: formato "001-001-0000123" (establecimiento-punto de expedición-número).
8. Condición de venta: únicamente "contado" o "credito".
9. Si algún campo no es legible o no aparece en la factura, devolvé null para ese campo. NO inventes ni supongas datos que no estén visibles.
''';

  static Map<String, dynamic> get _responseSchema => {
        'type': 'OBJECT',
        'properties': {
          'fecha': {
            'type': 'STRING',
            'nullable': true,
            'description': 'Fecha de emisión en formato ISO yyyy-MM-dd',
          },
          'ruc_emisor': {
            'type': 'STRING',
            'nullable': true,
            'description': 'RUC del emisor en formato 1234567-8',
          },
          'razon_social': {
            'type': 'STRING',
            'nullable': true,
            'description': 'Nombre o razón social del comercio o empresa emisora',
          },
          'timbrado': {
            'type': 'STRING',
            'nullable': true,
            'description': 'Número de timbrado de 8 dígitos',
          },
          'numero_factura': {
            'type': 'STRING',
            'nullable': true,
            'description': 'Número de comprobante formato 001-001-0000123',
          },
          'condicion': {
            'type': 'STRING',
            'nullable': true,
            'enum': ['contado', 'credito'],
            'description': 'Condición de venta: contado o credito',
          },
          'gravada_10': {
            'type': 'INTEGER',
            'nullable': true,
            'description': 'Total gravada 10% en guaraníes enteros (IVA incluido)',
          },
          'gravada_5': {
            'type': 'INTEGER',
            'nullable': true,
            'description': 'Total gravada 5% en guaraníes enteros (IVA incluido)',
          },
          'exenta': {
            'type': 'INTEGER',
            'nullable': true,
            'description': 'Total exenta en guaraníes enteros',
          },
          'iva_10': {
            'type': 'INTEGER',
            'nullable': true,
            'description': 'Liquidación IVA 10% en guaraníes enteros (gravada_10 / 11)',
          },
          'iva_5': {
            'type': 'INTEGER',
            'nullable': true,
            'description': 'Liquidación IVA 5% en guaraníes enteros (gravada_5 / 21)',
          },
          'total': {
            'type': 'INTEGER',
            'nullable': true,
            'description': 'Monto total general de la factura en guaraníes enteros',
          },
        },
        'required': [
          'fecha',
          'ruc_emisor',
          'razon_social',
          'timbrado',
          'numero_factura',
          'condicion',
          'gravada_10',
          'gravada_5',
          'exenta',
          'iva_10',
          'iva_5',
          'total',
        ],
      };

  Future<GeminiExtractionResult> extraerDatosFactura(String imagePath) async {
    final apiKey = await SettingsService.instance.getApiKey();
    if (apiKey.isEmpty) {
      throw GeminiException(
        'No configuraste tu API Key de Gemini. Podés cargarla en Ajustes o completar los datos a mano.',
      );
    }

    final model = await SettingsService.instance.getModel();
    final rawBytes = await File(imagePath).readAsBytes();
    final processedBytes = await compute(_procesarImagenIsolate, rawBytes);
    final base64Image = base64Encode(processedBytes);

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    );

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': _prompt},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Image,
              },
            },
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'responseMimeType': 'application/json',
        'responseSchema': _responseSchema,
      },
    });

    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw GeminiException(
        'Gemini tardó demasiado en responder. Probá de nuevo o completá los datos a mano.',
      );
    } on SocketException {
      throw GeminiException(
        'Sin conexión a internet. Verificá tu red o completá la factura manualmente.',
      );
    } on http.ClientException {
      throw GeminiException(
        'Error de red al conectar con Gemini. Completá los datos manualmente.',
      );
    } catch (e) {
      throw GeminiException(
        'Tiempo de espera agotado o error de conexión ($e).',
      );
    }

    if (_esKeyInvalida(response.statusCode, response.body)) {
      throw GeminiException(
        'API Key inválida o sin permisos (HTTP ${response.statusCode}). Revisala en Ajustes.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode == 429) {
      throw GeminiException(
        'Límite de solicitudes excedido en Gemini (HTTP 429). Esperá unos segundos o cargá a mano.',
        statusCode: 429,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GeminiException(
        'Error de Gemini (HTTP ${response.statusCode}): ${_mensajeErrorApi(response.body)}',
        statusCode: response.statusCode,
      );
    }

    try {
      final decodedResponse = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = decodedResponse['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        throw GeminiException('Gemini no devolvió resultados para esta imagen.');
      }

      final content = candidates[0]['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) {
        throw GeminiException('Respuesta vacía del modelo.');
      }

      String rawText = (parts[0]['text'] as String?) ?? '';
      rawText = rawText
          .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
          .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
          .trim();

      final extractedJson = jsonDecode(rawText) as Map<String, dynamic>;
      return GeminiExtractionResult.fromJson(extractedJson);
    } catch (e) {
      if (e is GeminiException) rethrow;
      throw GeminiException(
        'No se pudo interpretar el JSON devuelto por Gemini. Completá los campos manualmente.',
      );
    }
  }

  /// Prueba rápida: consulta los datos del modelo (no genera texto, así que
  /// responde en menos de un segundo) y valida la API Key y el nombre del modelo.
  Future<String> probarConexion({
    required String apiKey,
    required String model,
  }) async {
    final cleanKey = apiKey.trim();
    final cleanModel = model.trim().isEmpty ? SettingsService.defaultModel : model.trim();

    if (cleanKey.isEmpty) {
      throw GeminiException('Ingresá una API Key antes de probar.');
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$cleanModel',
    );

    http.Response response;
    try {
      response = await http
          .get(uri, headers: {'x-goog-api-key': cleanKey})
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw GeminiException(
        'No hubo respuesta de Google en 20 segundos. Revisá tu conexión a internet.',
      );
    } on SocketException {
      throw GeminiException('Sin conexión a internet.');
    } catch (e) {
      throw GeminiException('Error de conexión: $e');
    }

    if (response.statusCode == 200) {
      String nombre = cleanModel;
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        nombre = (data['displayName'] as String?) ?? cleanModel;
      } catch (_) {}
      return 'Conexión exitosa. API Key válida y modelo disponible: $nombre.';
    }
    if (_esKeyInvalida(response.statusCode, response.body)) {
      throw GeminiException(
        'API Key inválida. Verificá que la copiaste completa desde Google AI Studio.',
      );
    }
    if (response.statusCode == 404) {
      throw GeminiException('El modelo "$cleanModel" no existe o no está disponible.');
    }
    if (response.statusCode == 429) {
      throw GeminiException('Límite de uso alcanzado (429). La API Key es válida; probá más tarde.');
    }
    throw GeminiException(
      'Error HTTP ${response.statusCode}: ${_mensajeErrorApi(response.body)}',
    );
  }
}
