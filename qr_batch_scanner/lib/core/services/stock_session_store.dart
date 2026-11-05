import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StockSessionStore {
  static final StockSessionStore instance = StockSessionStore();

  static const String _targetKey = 'stock_target';
  static const String _sessionKey = 'stock_session';

  // Kullanıcının yarım kalan stok sayımını okur, eski kayıtları varsa önce kullanıcı id'sine taşır
  Future<({Map<String, int> target, Map<String, int> scanned})> load() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _userSuffix(prefs);
    await _migrateLegacyKeys(prefs, user);
    return (
      target: _decode(prefs.getString('${_targetKey}_$user')),
      scanned: _decode(prefs.getString('${_sessionKey}_$user')),
    );
  }

  // Hedef listeyi ve okunan adetleri kullanıcıya ait anahtarlarla kaydeder
  Future<void> save(Map<String, int> target, Map<String, int> scanned) async {
    final prefs = await SharedPreferences.getInstance();
    final user = _userSuffix(prefs);
    await prefs.setString('${_targetKey}_$user', jsonEncode(target));
    await prefs.setString('${_sessionKey}_$user', jsonEncode(scanned));
  }

  // Kullanıcının kayıtlı stok sayımını siler
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _userSuffix(prefs);
    await prefs.remove('${_targetKey}_$user');
    await prefs.remove('${_sessionKey}_$user');
  }

  // Kayıtlı JSON'u barkod ve adet listesine çevirir, bozuksa boş liste döner
  Map<String, int> _decode(String? json) {
    if (json == null) return {};
    try {
      final Map<String, dynamic> decoded = jsonDecode(json);
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  // Stok sayımı anahtarlarının sonuna eklenecek kullanıcı id'sini döner
  String _userSuffix(SharedPreferences prefs) => prefs.getInt('userId')?.toString() ?? 'guest';

  // Kullanıcı adına bağlı eski stok sayımı kayıtlarını kullanıcı id'sine taşır
  Future<void> _migrateLegacyKeys(SharedPreferences prefs, String user) async {
    final username = prefs.getString('username');
    if (user == 'guest' || username == null || username.isEmpty || username == user) return;
    for (final baseKey in [_targetKey, _sessionKey]) {
      final legacy = prefs.getString('${baseKey}_$username');
      if (legacy == null) continue;
      if (!prefs.containsKey('${baseKey}_$user')) {
        await prefs.setString('${baseKey}_$user', legacy);
      }
      await prefs.remove('${baseKey}_$username');
    }
  }
}
