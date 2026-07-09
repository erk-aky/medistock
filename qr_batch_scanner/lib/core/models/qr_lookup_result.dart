import 'package:flutter/material.dart';

class QrLookupResponse {
  final String? imageBase64; 
  final List<QrLookupResult> results;

  QrLookupResponse({this.imageBase64, required this.results});

  factory QrLookupResponse.fromJson(Map<String, dynamic> json) {
    return QrLookupResponse(
      imageBase64: json['image'] as String?, 
      results: (json['results'] as List? ?? [])
          .map((i) => QrLookupResult.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
}

class QrLookupResult {
  final String value; 
  final bool found;   
  final QrData? data; 
  
  // Ekranda çizim yapmak için koordinatlar
  final int x;
  final int y;
  final int w;
  final int h;
  
  // ✅ YENİ: Canlı çizim için köşe noktaları (JSON'a dahil etmiyoruz)
  final List<Offset>? corners;

  QrLookupResult({
    required this.value,
    required this.found,
    this.data,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.corners,
  });

  factory QrLookupResult.fromJson(Map<String, dynamic> json) {
    return QrLookupResult(
      value: json['value'] as String? ?? '',
      found: json['found'] as bool? ?? false,
      data: json['data'] != null ? QrData.fromJson(json['data'] as Map<String, dynamic>) : null,
      x: json['x'] as int? ?? 0,
      y: json['y'] as int? ?? 0,
      w: json['w'] as int? ?? 0,
      h: json['h'] as int? ?? 0,
      corners: null, // Veritabanından gelirken köşe bilgisi olmaz
    );
  }

  Map<String, dynamic> toJson() => {
        'value': value,
        'found': found,
        'data': data?.toJson(),
        'x': x,
        'y': y,
        'w': w,
        'h': h,
      };
}

class QrData {
  final String? gtin;       
  final String? serialNo;   
  final String? batchNo;    
  final DateTime? expiryDate; 
  final String? productName; 

  QrData({
    this.gtin,
    this.serialNo,
    this.batchNo,
    this.expiryDate,
    this.productName, 
  });

  factory QrData.fromJson(Map<String, dynamic> json) {
    DateTime? parsedExpiry;
    try {
      final raw = json['expiryDate'];
      if (raw is String && raw.isNotEmpty) {
        parsedExpiry = DateTime.parse(raw);
      }
    } catch (_) {
      parsedExpiry = null;
    }

    return QrData(
      gtin: (json['gtin'] ?? json['barkod']) as String?,
      serialNo: (json['serialNo'] ?? json['serial_no']) as String?,
      batchNo: (json['batchNo'] ?? json['batch_no']) as String?,
      expiryDate: parsedExpiry,
      productName: (json['productName'] ?? json['urun_adi']) as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'gtin': gtin,
        'serialNo': serialNo,
        'batchNo': batchNo,
        'expiryDate': expiryDate?.toIso8601String(),
        'productName': productName, 
      };

  bool get isExpired {
    if (expiryDate == null) return false;
    final now = DateTime.now();
    // Saati sıfırlayıp sadece güne bakıyoruz (Bugün dahil miadı geçmiştir)
    final today = DateTime(now.year, now.month, now.day);
    return expiryDate!.isBefore(today) || expiryDate!.isAtSameMomentAs(today);
  }

  bool get isExpirySoon {
    if (expiryDate == null || isExpired) return false;
    final now = DateTime.now();
    final sixMonths = DateTime(now.year, now.month + 6, now.day);
    return expiryDate!.isBefore(sixMonths);
  }
}