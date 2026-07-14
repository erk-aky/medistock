import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import 'local_db_service.dart';

/// Backend'deki TİTCK senkronundan gelen güncel ilaç listesini kontrol edip,
/// gerçekten değiştiyse offline SQLite (ilaclar.db) veritabanını günceller.
class DbSyncService {
  final LocalDbService _localDb = LocalDbService();

  /// Uygulama açılışında çağrılır. Hiçbir hata dışarı fırlatmaz —
  /// internet yoksa veya backend'e ulaşılamıyorsa sessizce vazgeçer,
  /// mevcut offline veri olduğu gibi kalır.
  Future<void> checkAndUpdateIfNeeded() async {
    try {
      final remoteVersion = await _fetchRemoteVersion();
      final prefs = await SharedPreferences.getInstance();
      final localVersion = prefs.getInt('localDbVersion') ?? 0;

      if (remoteVersion <= localVersion) {
        print("DbSyncService: yerel veritabanı zaten güncel (v$localVersion).");
        return;
      }

      print("DbSyncService: yeni sürüm bulundu (v$localVersion -> v$remoteVersion), indiriliyor...");
      final rows = await _fetchAllDrugs();
      await _localDb.replaceAllData(rows);
      await prefs.setInt('localDbVersion', remoteVersion);
      print("DbSyncService: yerel veritabanı güncellendi (${rows.length} satır).");
    } catch (e) {
      print("DbSyncService: güncelleme atlandı ($e)");
    }
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
