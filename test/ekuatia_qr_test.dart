import 'dart:convert';
import 'package:facturas_py/services/ekuatia_qr.dart';
import 'package:flutter_test/flutter_test.dart';

/// Arma un CDC válido calculando su dígito verificador.
String cdcCon(String base43) {
  int suma = 0;
  int k = 2;
  for (int i = base43.length - 1; i >= 0; i--) {
    suma += int.parse(base43[i]) * k;
    k = k == 11 ? 2 : k + 1;
  }
  final resto = suma % 11;
  return '$base43${resto > 1 ? 11 - resto : 0}';
}

String hex(String s) =>
    utf8.encode(s).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // tipo 01, RUC 80012345, DV 6, est 001, pto 002, num 0000123,
  // tipoContrib 2, fecha 20261115, tipoEmision 1, codSeg 123456789
  final cdc = cdcCon('0180012345600100200001232202611151123456789');

  test('CDC válido e inválido', () {
    expect(cdc.length, 44);
    expect(EkuatiaQr.cdcValido(cdc), isTrue);
    final malo = cdc.substring(0, 43) + ((int.parse(cdc[43]) + 1) % 10).toString();
    expect(EkuatiaQr.cdcValido(malo), isFalse);
  });

  test('interpreta URL de consulta completa', () {
    final url = 'https://ekuatia.set.gov.py/consultas/qr?nVersion=150&Id=$cdc'
        '&dFeEmiDE=${hex('2026-11-15T09:30:00')}&dRucRec=5304515'
        '&dTotGralOpe=150000&dTotIVA=13636&cItems=2&DigestValue=abc'
        '&IdCSC=0001&cHashQR=def';
    final d = EkuatiaQr.interpretar(url)!;
    expect(d.rucEmisor, '80012345-6');
    expect(d.numeroFactura, '001-002-0000123');
    expect(d.fecha, '2026-11-15');
    expect(d.total, 150000);
    expect(d.esFactura, isTrue);
  });

  test('usa la fecha del CDC si no hay dFeEmiDE y acepta total con decimales', () {
    final d = EkuatiaQr.interpretar('https://x/qr?Id=$cdc&dTotGralOpe=99500.00')!;
    expect(d.fecha, '2026-11-15');
    expect(d.total, 99500);
  });

  test('ignora QR que no son de e-Kuatia', () {
    expect(EkuatiaQr.interpretar('https://example.com'), isNull);
    expect(EkuatiaQr.interpretar(''), isNull);
  });
}
