import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_batch_scanner/core/models/qr_lookup_result.dart';
import 'package:qr_batch_scanner/core/services/scan_history_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

QrLookupResultWithCount _entry(String value, {String? productName, DateTime? expiry, bool found = true}) {
  return QrLookupResultWithCount(
    qr: QrLookupResult(
      value: value,
      found: found,
      data: found
          ? QrData(gtin: '08699680090344', serialNo: 'SN-$value', batchNo: 'L1', expiryDate: expiry, productName: productName)
          : null,
      x: 0,
      y: 0,
      w: 0,
      h: 0,
    ),
    createdAt: DateTime.utc(2026, 10, 23, 10, 30),
    isOffline: true,
  );
}

void main() {
  sqfliteFfiInit();

  late ScanHistoryRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('scan_history_test');
    repo = ScanHistoryRepository(factory: databaseFactoryFfi, path: '${dir.path}/test.db');
    addTearDown(() async {
      await repo.close();
      await dir.delete(recursive: true);
    });
  });

  test('eklenen kayıtlar id alır ve bütün alanlarıyla geri okunur', () async {
    final entry = _entry('A', productName: 'PAROL', expiry: DateTime.utc(2028, 8, 31));
    await repo.insertAll(7, [entry]);
    expect(entry.id, isNotNull);

    final loaded = await repo.load(7);
    expect(loaded, hasLength(1));
    final item = loaded.single;
    expect(item.id, entry.id);
    expect(item.qr.value, 'A');
    expect(item.qr.found, isTrue);
    expect(item.qr.data!.productName, 'PAROL');
    expect(item.qr.data!.serialNo, 'SN-A');
    expect(item.qr.data!.expiryDate, DateTime.utc(2028, 8, 31));
    expect(item.createdAt, DateTime.utc(2026, 10, 23, 10, 30));
    expect(item.isOffline, isTrue);
  });

  test('bulunamayan karekod verisiz olarak geri okunur', () async {
    await repo.insertAll(7, [_entry('X', found: false)]);
    final item = (await repo.load(7)).single;
    expect(item.qr.found, isFalse);
    expect(item.qr.data, isNull);
  });

  test('kullanıcıların geçmişi birbirine karışmaz', () async {
    await repo.insertAll(7, [_entry('A')]);
    await repo.insertAll(8, [_entry('B'), _entry('C')]);

    expect((await repo.load(7)).map((e) => e.qr.value), ['A']);
    expect((await repo.load(8)).map((e) => e.qr.value), ['B', 'C']);

    await repo.clear(8);
    expect(await repo.load(8), isEmpty);
    expect(await repo.load(7), hasLength(1));
  });

  test('karekoda, ilaç adına ve id ye göre silme sadece ilgili kayıtları siler', () async {
    final a1 = _entry('A', productName: 'PAROL');
    final a2 = _entry('A', productName: 'PAROL');
    final b = _entry('B', productName: 'PAROL');
    final c = _entry('C', productName: 'MAJEZIK');
    await repo.insertAll(7, [a1, a2, b, c]);
    await repo.insertAll(8, [_entry('A', productName: 'PAROL')]);

    await repo.deleteById(a1.id!);
    expect((await repo.load(7)).map((e) => e.id), [a2.id, b.id, c.id]);

    await repo.deleteByValue(7, 'A');
    expect((await repo.load(7)).map((e) => e.qr.value), ['B', 'C']);

    await repo.deleteByProductName(7, 'PAROL');
    expect((await repo.load(7)).map((e) => e.qr.value), ['C']);
    expect(await repo.load(8), hasLength(1));
  });

  test('eski SharedPreferences geçmişi ilk yüklemede tabloya taşınır ve silinir', () async {
    final legacy = [_entry('A', productName: 'PAROL').toJson(), _entry('B', found: false).toJson()];
    SharedPreferences.setMockInitialValues({'qr_lookup_results_ali': jsonEncode(legacy)});

    final loaded = await repo.load(7, legacyUsername: 'ali');
    expect(loaded.map((e) => e.qr.value), ['A', 'B']);
    expect(loaded.first.qr.data!.productName, 'PAROL');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('qr_lookup_results_ali'), isFalse);
    expect(await repo.load(7, legacyUsername: 'ali'), hasLength(2));
  });

  test('bozuk eski kayıt silinmez ve yükleme hata vermez', () async {
    SharedPreferences.setMockInitialValues({'qr_lookup_results_ali': 'bozuk-veri'});

    expect(await repo.load(7, legacyUsername: 'ali'), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('qr_lookup_results_ali'), 'bozuk-veri');
  });
}
