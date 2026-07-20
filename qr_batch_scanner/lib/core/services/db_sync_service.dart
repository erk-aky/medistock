import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'local_db_service.dart';

/// Backend'deki TİTCK senkronundan gelen güncel ilaç listesini kontrol edip,
/// gerçekten değiştiyse offline SQLite (ilaclar.db) veritabanını günceller.
class DbSyncService {
  final LocalDbService _localDb = LocalDbService();

  /// Telefonda kayıtlı olan versiyon numarası (hiç senkron olmadıysa 0).
  Future<int> getLocalVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('localDbVersion') ?? 0;
  }

  /// Backend'deki güncel versiyon numarasını döner, backend'e hiç
  /// ulaşılamıyorsa (internet yok / sunucu kapalı) `null` döner.
  Future<int?> getRemoteVersionOrNull() async {
    try {
      return await _fetchRemoteVersion();
    } catch (e) {
      print("DbSyncService: versiyon bilgisi alınamadı ($e)");
      return null;
    }
  }

  /// Backend'den tüm ilaç listesini indirip yerel `ilaclar.db`'ye yazar ve
  /// kayıtlı versiyonu günceller. Başarısız olursa exception fırlatır —
  /// çağıran taraf bunu yakalayıp kullanıcıyı bilgilendirmeli.
  Future<void> downloadAndApplyUpdate(int remoteVersion) async {
    final rows = await _fetchAllDrugs();
    await _localDb.replaceAllData(rows);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('localDbVersion', remoteVersion);
    print("DbSyncService: yerel veritabanı güncellendi (${rows.length} satır, v$remoteVersion).");
  }

  Future<int> _fetchRemoteVersion() async {
    final resp = await http.get(
      Uri.parse(ApiConstants.dbVersion),
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
    ).timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) {
      throw Exception('Versiyon bilgisi alınamadı (${resp.statusCode})');
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    return decoded['version'] as int? ?? 0;
  }

  Future<List<Map<String, dynamic>>> _fetchAllDrugs() async {
    final resp = await http.get(
      Uri.parse(ApiConstants.dbExport),
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
    ).timeout(const Duration(seconds: 60));

    if (resp.statusCode != 200) {
      throw Exception('İlaç listesi indirilemedi (${resp.statusCode})');
    }

    final List<dynamic> decoded = jsonDecode(resp.body);
    return decoded.map((item) {
      final map = item as Map<String, dynamic>;
      return <String, dynamic>{
        'BARKOD': map['barkod'],
        'ÜRÜN ADI': map['urunAdi'],
      };
    }).toList();
  }
}
