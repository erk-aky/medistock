import 'package:flutter_test/flutter_test.dart';
import 'package:qr_batch_scanner/core/models/qr_lookup_result.dart';
import 'package:qr_batch_scanner/features/qr_scan/scan_list_filter.dart';

QrLookupResultWithCount _item(String value, {String? name, bool found = true, int count = 1}) {
  return QrLookupResultWithCount(
    qr: QrLookupResult(
      value: value,
      found: found,
      data: name == null ? null : QrData(productName: name),
      x: 0, y: 0, w: 0, h: 0,
    ),
    count: count,
  );
}

void main() {
  group('matchesTimeFilter', () {
    final now = DateTime(2026, 10, 29, 1, 30);

    test('Tümü her kaydı kabul eder', () {
      expect(matchesTimeFilter(DateTime(2020, 1, 1), TimeFilterPreset.all, now), isTrue);
    });

    test('Son 1 saat sadece son bir saati alır', () {
      expect(matchesTimeFilter(now.subtract(const Duration(minutes: 30)), TimeFilterPreset.last1Hour, now), isTrue);
      expect(matchesTimeFilter(now.subtract(const Duration(minutes: 90)), TimeFilterPreset.last1Hour, now), isFalse);
    });

    test('Bugün ve Dün yerel güne göre ayrılır', () {
      final todayEarly = DateTime(2026, 10, 29, 0, 10);
      final yesterdayLate = DateTime(2026, 10, 28, 23, 50);
      expect(matchesTimeFilter(todayEarly, TimeFilterPreset.today, now), isTrue);
      expect(matchesTimeFilter(todayEarly, TimeFilterPreset.yesterday, now), isFalse);
      expect(matchesTimeFilter(yesterdayLate, TimeFilterPreset.yesterday, now), isTrue);
      expect(matchesTimeFilter(yesterdayLate, TimeFilterPreset.today, now), isFalse);
    });

    test('UTC kayıt yerel saate çevrilerek karşılaştırılır', () {
      final todayEarly = DateTime(2026, 10, 29, 0, 10);
      expect(matchesTimeFilter(todayEarly.toUtc(), TimeFilterPreset.today, now), isTrue);
    });

    test('Ayın ilk günü Dün önceki ayın son günüdür', () {
      final firstOfMonth = DateTime(2026, 11, 1, 9);
      expect(matchesTimeFilter(DateTime(2026, 10, 31, 15), TimeFilterPreset.yesterday, firstOfMonth), isTrue);
    });
  });

  group('groupByProductName', () {
    test('aynı addaki kayıtları adetleri toplayarak birleştirir', () {
      final result = groupByProductName([
        _item('a', name: 'PAROL', count: 2),
        _item('b', name: 'PAROL', count: 3),
        _item('c', name: 'ARVELES'),
      ]);
      expect(result.length, 2);
      expect(result[0].qr.data?.productName, 'PAROL');
      expect(result[0].count, 5);
      expect(result[1].count, 1);
    });

    test('bulunamayan ve adı olmayan kayıtlar ayrı kalır', () {
      final result = groupByProductName([
        _item('a', found: false),
        _item('b', found: false),
        _item('c', name: ''),
        _item('d'),
      ]);
      expect(result.length, 4);
    });

    test('verilen listedeki kayıtları değiştirmez', () {
      final first = _item('a', name: 'PAROL', count: 2);
      groupByProductName([first, _item('b', name: 'PAROL')]);
      expect(first.count, 2);
    });
  });
}
