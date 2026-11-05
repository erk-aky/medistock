import '../../core/models/qr_lookup_result.dart';

enum TimeFilterPreset { all, last1Hour, today, yesterday }

// Kaydın okutulma zamanının seçilen zaman filtresine uyup uymadığını söyler
bool matchesTimeFilter(DateTime createdAt, TimeFilterPreset preset, DateTime now) {
  final local = createdAt.toLocal();
  switch (preset) {
    case TimeFilterPreset.all:
      return true;
    case TimeFilterPreset.last1Hour:
      return local.isAfter(now.subtract(const Duration(hours: 1)));
    case TimeFilterPreset.today:
      return _isSameDay(local, now);
    case TimeFilterPreset.yesterday:
      return _isSameDay(local, DateTime(now.year, now.month, now.day - 1));
  }
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// Aynı ilaç adındaki kayıtları adetlerini toplayarak tek satırda birleştirir, adı olmayanları ayrı bırakır
List<QrLookupResultWithCount> groupByProductName(List<QrLookupResultWithCount> items) {
  final Map<String, QrLookupResultWithCount> nameToGroup = {};
  final List<QrLookupResultWithCount> result = [];

  for (final item in items) {
    final name = item.qr.found ? item.qr.data?.productName : null;
    if (name == null || name.isEmpty) {
      result.add(item);
      continue;
    }
    final group = nameToGroup[name];
    if (group == null) {
      final grouped = QrLookupResultWithCount(
        qr: item.qr,
        createdAt: item.createdAt,
        count: item.count,
        isOffline: item.isOffline,
      );
      nameToGroup[name] = grouped;
      result.add(grouped);
    } else {
      group.count += item.count;
    }
  }

  return result;
}
