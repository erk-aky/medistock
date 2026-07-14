import 'dart:io';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDbService {
  static Database? _database;

  // Veritabanı bağlantısını Singleton olarak yönetiyoruz
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    var dbPath = await getDatabasesPath();
    var path = join(dbPath, "ilaclar.db");

    // Dosya telefonun yerel hafızasında var mı kontrol et
    bool exists = await databaseExists(path);

    if (!exists) {
      print("📦 Veritabanı ilk kez kuruluyor, assets'ten kopyalanıyor...");
      try {
        await Directory(dirname(path)).create(recursive: true);
      } catch (_) {}

      // Assets'teki ilaclar.db dosyasını bayt olarak oku
      ByteData data = await rootBundle.load(join("assets/database", "ilaclar.db"));
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      
      // Telefonun kalıcı hafızasına yaz
      await File(path).writeAsBytes(bytes, flush: true);
    }

    // Yazılabilir modda açıyoruz: backend senkronu ile içerik güncellenebilsin diye.
    return await openDatabase(path);
  }

  /// Backend'den gelen güncel ilaç listesiyle tüm tabloyu tek bir transaction
  /// içinde yeniden doldurur. İşlem yarıda kesilirse eski veri korunur.
  Future<void> replaceAllData(List<Map<String, dynamic>> rows) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete('filtreli_veriler');

      final batch = txn.batch();
      for (final row in rows) {
        batch.insert('filtreli_veriler', row);
      }
      await batch.commit(noResult: true);
    });
  }

  /// ✅ 13 haneli barkod ile sorgu yapan fonksiyon
  /// Geriye tüm satırı (barkod, ürün_adı) Map olarak döner.
  Future<Map<String, dynamic>?> findDrugByBarcode(String barcode) async {
    try {
      final db = await database;
      
      // NOT: 'drugs' tablo adın, 'BARKOD' ise sütun adın.
      // DB Browser'da farklı yaptıysan burayı ona göre güncellemelisin.
      List<Map<String, dynamic>> results = await db.query(
        'filtreli_veriler', 
        where: 'BARKOD = ?', 
        whereArgs: [barcode],
        limit: 1,
      );

      if (results.isNotEmpty) {
        print("✅ İlaç bulundu: ${results.first}");
        return results.first;
      }
    } catch (e) {
      print("❌ LocalDbService Sorgu Hatası: $e");
    }
    return null;
  }
}