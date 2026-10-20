import 'package:flutter_test/flutter_test.dart';
import 'package:qr_batch_scanner/core/gs1/gs1_parser.dart';

const gs = '\x1D';

void main() {
  test('standart karekod tüm alanları doğru ayrılır', () {
    final r = Gs1Parser.parse('0108699123456789' '21ABC123${gs}17260331' '10LOT55');
    expect(r.gtin, '8699123456789');
    expect(r.serialNo, 'ABC123');
    expect(r.expiryDate, DateTime(2026, 3, 31));
    expect(r.batchNo, 'LOT55');
  });

  test('gün 00 ise ayın son günü alınır', () {
    final r = Gs1Parser.parse('0108699123456789' '21ABC123${gs}17260200' '10LOT55');
    expect(r.expiryDate, DateTime(2026, 2, 28));
  });

  test('seri no içinde 17 geçse de kesilmez', () {
    final r = Gs1Parser.parse('0108699123456789' '21ABC1745XY${gs}17260331' '10LOT55');
    expect(r.serialNo, 'ABC1745XY');
    expect(r.expiryDate, DateTime(2026, 3, 31));
  });

  test('parti no içinde 10 ve 17 geçse de bozulmaz', () {
    final r = Gs1Parser.parse('0108699123456789' '21ABC123${gs}17260331' '10AB1017');
    expect(r.batchNo, 'AB1017');
  });

  test('GS olmayan karekodda SKT ve parti no tahminle ayrılır', () {
    final r = Gs1Parser.parse('0108699123456789' '21ABC1745XY' '17260331' '10LOT55');
    expect(r.serialNo, 'ABC1745XY');
    expect(r.expiryDate, DateTime(2026, 3, 31));
    expect(r.batchNo, 'LOT55');
  });

  test('geçersiz tarih boş kalır diğer alanlar okunur', () {
    final r = Gs1Parser.parse('0108699123456789' '21ABC123${gs}17260230' '10LOT55');
    expect(r.expiryDate, isNull);
    expect(r.gtin, '8699123456789');
    expect(r.serialNo, 'ABC123');
    expect(r.batchNo, 'LOT55');
  });

  test('farklı alan sırası da doğru ayrılır', () {
    final r = Gs1Parser.parse('0108699123456789' '17260331' '10LOT55${gs}21ABC123');
    expect(r.gtin, '8699123456789');
    expect(r.expiryDate, DateTime(2026, 3, 31));
    expect(r.batchNo, 'LOT55');
    expect(r.serialNo, 'ABC123');
  });

  test('bilinen sabit uzunluklu alanlar atlanıp okumaya devam edilir', () {
    final r = Gs1Parser.parse('0108699123456789' '11250101' '3103000500' '17260331' '10LOT55${gs}21ABC123');
    expect(r.gtin, '8699123456789');
    expect(r.expiryDate, DateTime(2026, 3, 31));
    expect(r.batchNo, 'LOT55');
    expect(r.serialNo, 'ABC123');
  });

  test('bilinmeyen değişken uzunluklu alan GS ile atlanır', () {
    final r = Gs1Parser.parse('0108699123456789' '240XYZ${gs}21ABC123${gs}17260331');
    expect(r.serialNo, 'ABC123');
    expect(r.expiryDate, DateTime(2026, 3, 31));
  });

  test('boş veya anlamsız metinde hata vermez', () {
    for (final raw in ['', '   ', 'merhaba', '01123', '17', gs]) {
      final r = Gs1Parser.parse(raw);
      expect(r.gtin, isNull);
      expect(r.expiryDate, isNull);
    }
  });
}
