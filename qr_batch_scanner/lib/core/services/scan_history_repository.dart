import 'dart:convert';

import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/qr_lookup_result.dart';

class ScanHistoryRepository {
  static final ScanHistoryRepository instance = ScanHistoryRepository();

  static const String _table = 'scan_history';

  final DatabaseFactory? _factory;
  final String? _path;
  Future<Database>? _opening;

  ScanHistoryRepository({DatabaseFactory? factory, String? path})
      : _factory = factory,
        _path = path;

  static String _legacyKey(String username) => 'qr_lookup_results_$username';

  Future<Database> get _database => _opening ??= _open();

  // Geçmiş veritabanını açar, ilk açılışta tabloyu oluşturur
  Future<Database> _open() async {
    final factory = _factory ?? databaseFactory;
    final path = _path ?? join(await factory.getDatabasesPath(), 'tarama_gecmisi.db');
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_table (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id INTEGER NOT NULL,
              value TEXT NOT NULL,
              found INTEGER NOT NULL,
              gtin TEXT,
              serial_no TEXT,
              batch_no TEXT,
              expiry_date TEXT,
              product_name TEXT,
              count INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              is_offline INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('CREATE INDEX idx_${_table}_user_value ON $_table (user_id, value)');
        },
      ),
    );
  }

  // Kullanıcının geçmişini okuma sırasıyla getirir, eski SharedPreferences kaydı varsa önce tabloya taşır
  Future<List<QrLookupResultWithCount>> load(int userId, {String? legacyUsername}) async {
    if (legacyUsername != null && legacyUsername.isNotEmpty) {
      await _migrateLegacy(userId, legacyUsername);
    }
    final db = await _database;
    final rows = await db.query(_table, where: 'user_id = ?', whereArgs: [userId], orderBy: 'id');
    return rows.map(_fromRow).toList();
  }

  // Kayıtları tek seferde ekler ve veritabanının verdiği id'leri kayıtlara yazar
  Future<void> insertAll(int userId, List<QrLookupResultWithCount> entries) async {
    if (entries.isEmpty) return;
    final db = await _database;
    final ids = await db.transaction((txn) async {
      final batch = txn.batch();
      for (final entry in entries) {
        batch.insert(_table, _toRow(userId, entry));
      }
      return batch.commit();
    });
    for (var i = 0; i < entries.length; i++) {
      entries[i].id = ids[i] as int;
    }
  }

  // Tek bir kaydı id'sine göre siler
  Future<void> deleteById(int id) async {
    final db = await _database;
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  // Kullanıcının aynı karekoda ait tüm kayıtlarını siler
  Future<void> deleteByValue(int userId, String value) async {
    final db = await _database;
    await db.delete(_table, where: 'user_id = ? AND value = ?', whereArgs: [userId, value]);
  }

  // Kullanıcının aynı ilaç adına ait tüm kayıtlarını siler
  Future<void> deleteByProductName(int userId, String productName) async {
    final db = await _database;
    await db.delete(_table, where: 'user_id = ? AND product_name = ?', whereArgs: [userId, productName]);
  }

  // Kullanıcının bütün geçmişini siler
  Future<void> clear(int userId) async {
    final db = await _database;
    await db.delete(_table, where: 'user_id = ?', whereArgs: [userId]);
  }

  // Veritabanı bağlantısını kapatır, sonraki kullanımda yeniden açılır
  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }

  // Eski metin halindeki geçmişi tabloya aktarır, aktarma başarılı olursa eski kaydı siler
  Future<void> _migrateLegacy(int userId, String username) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyKey(username));
    if (raw == null) return;

    final List<QrLookupResultWithCount> entries;
    try {
      entries = (jsonDecode(raw) as List)
          .map((item) => QrLookupResultWithCount.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return;
    }

    await insertAll(userId, entries);
    await prefs.remove(_legacyKey(username));
  }

  Map<String, Object?> _toRow(int userId, QrLookupResultWithCount entry) {
    final data = entry.qr.data;
    return {
      'user_id': userId,
      'value': entry.qr.value,
      'found': entry.qr.found ? 1 : 0,
      'gtin': data?.gtin,
      'serial_no': data?.serialNo,
      'batch_no': data?.batchNo,
      'expiry_date': data?.expiryDate?.toIso8601String(),
      'product_name': data?.productName,
      'count': entry.count,
      'created_at': entry.createdAt.toUtc().toIso8601String(),
      'is_offline': entry.isOffline ? 1 : 0,
    };
  }

  QrLookupResultWithCount _fromRow(Map<String, Object?> row) {
    final expiryRaw = row['expiry_date'] as String?;
    final hasData = ['gtin', 'serial_no', 'batch_no', 'expiry_date', 'product_name'].any((c) => row[c] != null);
    return QrLookupResultWithCount(
      id: row['id'] as int,
      qr: QrLookupResult(
        value: row['value'] as String,
        found: row['found'] == 1,
        data: hasData
            ? QrData(
                gtin: row['gtin'] as String?,
                serialNo: row['serial_no'] as String?,
                batchNo: row['batch_no'] as String?,
                expiryDate: expiryRaw != null ? DateTime.tryParse(expiryRaw) : null,
                productName: row['product_name'] as String?,
              )
            : null,
        x: 0,
        y: 0,
        w: 0,
        h: 0,
      ),
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
      count: row['count'] as int,
      isOffline: row['is_offline'] == 1,
    );
  }
}
