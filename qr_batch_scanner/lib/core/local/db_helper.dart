import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class DBHelper {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    await init();
    return _db!;
  }

  // Initialize DB
  static Future<void> init() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = join(docsDir.path, 'offline_v2.db');

    _db = await openDatabase(
      dbPath,
      version: 4, // ⬅️ Versiyon 4 yapıldı (Tabloyu yenilemek için)
      onCreate: (db, version) async {
        await _createTable(db);
        await _seedData(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 4) {
          await db.execute('DROP TABLE IF EXISTS app_qrcodes');
          await _createTable(db);
          await _seedData(db);
        }
      },
    );
  }

  static Future<void> _createTable(Database db) async {
    await db.execute('''
      CREATE TABLE app_qrcodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        value TEXT NOT NULL UNIQUE, 
        gtin TEXT,
        serial_no TEXT,
        batch_no TEXT,
        expiry_date TEXT
      );
    ''');
  }

  // Veritabanındaki veriler orijinal (I harfi içeren) haliyle kalıyor.
  static Future<void> _seedData(Database db) async {
    final batch = db.batch();

    final List<Map<String, dynamic>> initialData = [
      {
        'value': '010869968009034421I01001000766908617290831102502730009',
        'gtin': '08699680090344',
        'serial_no': 'I010010007669086',
        'batch_no': '2502730009',
        'expiry_date': '2029-08-31',
      },
      {
        'value': '010869968009034421I01001000766876517290831102502730009',
        'gtin': '08699680090344',
        'serial_no': 'I010010007668765',
        'batch_no': '2502730009',
        'expiry_date': '2029-08-31',
      },
      {
        'value': '010869968009034421I01001000766909417290831102502730009',
        'gtin': '08699680090344',
        'serial_no': 'I010010007669094',
        'batch_no': '2502730009',
        'expiry_date': '2029-08-31',
      },
      {
        'value': '010869968009034421I01001000766909017290831102502730009',
        'gtin': '08699680090344',
        'serial_no': 'I010010007669090',
        'batch_no': '2502730009',
        'expiry_date': '2029-08-31',
      },
      {
        'value': '010869968009034421I01001000766876917290831102502730009',
        'gtin': '08699680090344',
        'serial_no': 'I010010007668769',
        'batch_no': '2502730009',
        'expiry_date': '2029-08-31',
      },
      {
        'value': '010869968009034421I01001000766343417260531102502730009',
        'gtin': '08699680090344',
        'serial_no': 'I010010007663434',
        'batch_no': '2502730009',
        'expiry_date': '2026-05-31',
      }
    ];

    for (var data in initialData) {
      batch.insert('app_qrcodes', data, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  // ✅ GÜNCELLENMİŞ SORGU MANTIĞI
  static Future<Map<String, dynamic>?> getByValue(String value) async {
    final db = await database;
    final cleanValue = value.trim();

    // 1. Önce birebir eşleşme dene.
    final exactRows = await db.query(
      'app_qrcodes',
      where: 'value = ?',
      whereArgs: [cleanValue],
      limit: 1,
    );
    if (exactRows.isNotEmpty) return exactRows.first;

    // 2. Eğer bulunamazsa (Görünmez karakter veya I/1 hatası için esnek arama):
    // SQL'deki LIKE operatörü ile veritabanındaki 52 karakterin, 
    // kameradan gelen 54 karakterin İÇİNDE olup olmadığını kontrol ediyoruz.
    final flexibleRows = await db.query(
      'app_qrcodes',
      where: '? LIKE "%" || value || "%"',
      whereArgs: [cleanValue],
      limit: 1,
    );

    return flexibleRows.isNotEmpty ? flexibleRows.first : null;
  }

  static Future<void> clearAll() async {
    final db = await database;
    await db.delete('app_qrcodes');
  }
}