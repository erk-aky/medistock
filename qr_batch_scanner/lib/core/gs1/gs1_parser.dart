class Gs1Data {
  final String? gtin;
  final String? serialNo;
  final String? batchNo;
  final DateTime? expiryDate;

  const Gs1Data({this.gtin, this.serialNo, this.batchNo, this.expiryDate});
}

class Gs1Parser {
  static const String _gs = '\x1D';
  static const List<String> _symbologyPrefixes = [']d2', ']Q3', ']C1'];
  static const Map<String, int> _fixedLengths = {
    '00': 20, '01': 16, '02': 16, '03': 16, '04': 18,
    '11': 8, '12': 8, '13': 8, '14': 8, '15': 8, '16': 8, '17': 8, '18': 8, '19': 8,
    '20': 4,
    '31': 10, '32': 10, '33': 10, '34': 10, '35': 10, '36': 10,
    '41': 16,
  };

  // Karekod metnini GTIN, seri no, parti no ve SKT alanlarına ayırır
  static Gs1Data parse(String raw) {
    final s = _normalize(raw);
    String? gtin, serial, batch;
    DateTime? expiry;

    int pos = 0;
    while (pos < s.length) {
      if (s[pos] == _gs) {
        pos++;
        continue;
      }
      if (pos + 2 > s.length) break;

      final ai = s.substring(pos, pos + 2);
      final start = pos + 2;

      if (ai == '01') {
        if (!_isDigits(s, start, 14)) break;
        final full = s.substring(start, start + 14);
        gtin = full.startsWith('0') ? full.substring(1) : full;
        pos = start + 14;
      } else if (ai == '17') {
        if (!_isDigits(s, start, 6)) break;
        expiry = parseExpiry(s.substring(start, start + 6));
        pos = start + 6;
      } else if (ai == '21' || ai == '10') {
        final end = _findVariableEnd(s, start);
        final value = s.substring(start, end);
        if (ai == '21') {
          serial = value;
        } else {
          batch = value;
        }
        pos = end;
      } else if (_fixedLengths.containsKey(ai)) {
        final next = pos + _fixedLengths[ai]!;
        if (next > s.length) break;
        pos = next;
      } else {
        final nextGs = s.indexOf(_gs, pos);
        if (nextGs == -1) break;
        pos = nextGs + 1;
      }
    }

    return Gs1Data(gtin: gtin, serialNo: serial, batchNo: batch, expiryDate: expiry);
  }

  // YYAAGG formatındaki SKT'yi tarihe çevirir, gün 00 ise ayın son günü kabul edilir
  static DateTime? parseExpiry(String yymmdd) {
    if (!_isDigits(yymmdd, 0, 6)) return null;
    final year = 2000 + int.parse(yymmdd.substring(0, 2));
    final month = int.parse(yymmdd.substring(2, 4));
    final day = int.parse(yymmdd.substring(4, 6));
    if (month < 1 || month > 12) return null;

    final lastDay = DateTime(year, month + 1, 0).day;
    if (day == 0) return DateTime(year, month, lastDay);
    if (day > lastDay) return null;
    return DateTime(year, month, day);
  }

  // Okuyucunun eklediği önekleri temizler ve boşlukları GS ayırıcısına çevirir
  static String _normalize(String raw) {
    var s = raw.trim();
    for (final prefix in _symbologyPrefixes) {
      if (s.startsWith(prefix)) {
        s = s.substring(prefix.length);
        break;
      }
    }
    return s.replaceAll(' ', _gs);
  }

  // Değişken uzunluklu alanın bittiği yeri bulur, GS yoksa ardından SKT ve yeni alan gelen 17 aranır
  static int _findVariableEnd(String s, int start) {
    final nextGs = s.indexOf(_gs, start);
    if (nextGs != -1) return nextGs;

    for (int i = start + 1; i + 10 <= s.length; i++) {
      if (s.startsWith('17', i) &&
          parseExpiry(s.substring(i + 2, i + 8)) != null &&
          (s.startsWith('10', i + 8) || s.startsWith('21', i + 8))) {
        return i;
      }
    }
    return s.length;
  }

  // Verilen aralığın tamamen rakam olup olmadığını kontrol eder
  static bool _isDigits(String s, int start, int length) {
    if (start + length > s.length) return false;
    for (int i = start; i < start + length; i++) {
      final c = s.codeUnitAt(i);
      if (c < 48 || c > 57) return false;
    }
    return true;
  }
}
