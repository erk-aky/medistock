import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; 
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart' as mlkit;
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/gs1/gs1_parser.dart';
import '../../core/models/qr_lookup_result.dart';
import '../../core/network/api_client.dart';
import '../../core/services/its_credential_store.dart';
import '../../core/services/qr_service.dart';
import '../../core/services/qr_mlkit_service.dart';
import '../../core/services/local_db_service.dart';
import '../../core/services/scan_history_repository.dart';
// Abonelik özelliği aktif edileceği zaman kullanılacak
// import '../../core/subscription/subscription_page.dart';
import '../auth/auth_view_model.dart';
import 'package:provider/provider.dart';
import '../../core/constants/api_constants.dart'; // Dosya yolun AuthService ile aynıysa bu şekilde olmalı

class QrScanViewModel extends ChangeNotifier {
  final ImagePicker _picker = ImagePicker();
  final QrService _qrService = QrService();
  final ApiClient _apiClient = ApiClient();
  final QrMlkitService _mlkit_service = QrMlkitService();
  final LocalDbService _localDbService = LocalDbService();

  Function(String msg)? onScanError;

  File? _lastScannedFile;
  File? get lastScannedFile => _lastScannedFile;

  List<QrLookupResult> _lastResults = [];
  List<QrLookupResult> get lastResults => _lastResults;

  List<Barcode> _detectedBarcodes = [];
  List<Barcode> get detectedBarcodes => _detectedBarcodes;
  Timer? _clearTimer;

  Size? _lastImageSize;
  Size? get lastImageSize => _lastImageSize;

  int _expiryMonthLimit = 6; 
  int get expiryMonthLimit => _expiryMonthLimit;

  String _subscriptionStatus = "None";
  DateTime? _trialEndDate;
  DateTime? _subscriptionEndDate;

  Timer? _subscriptionTimer; 
  Timer? _uiRefreshTimer;

  // Karşılaştırmalı sayım için hedef stok verileri
  Map<String, int> _targetInventory = {};
  Map<String, int> get targetInventory => _targetInventory;
  
  bool _isCompareMode = false;
  bool get isCompareMode => _isCompareMode;

  // O anki sayımda hangi barkoddan kaç tane okunduğunu tutar (stok modu)
  Map<String, int> _currentScanSession = {};
  Map<String, int> get currentScanSession => _currentScanSession;

  int _sessionScanCount = 0;
  int get sessionScanCount => _sessionScanCount;
  int get totalComparisonScanned => _currentScanSession.values.fold(0, (a, b) => a + b);

  bool _isComparisonMode = false;
  bool get isComparisonMode => _isComparisonMode;

  // Normal mod: kamera açılmadan önce tarananlar (önceki)
  Map<String, int> _normalPreviousCounts = {};
  Map<String, int> get normalPreviousCounts => _normalPreviousCounts;

  // Normal mod: bu kamera oturumunda tarananlar (şimdi)
  Map<String, int> _normalScanSession = {};
  Map<String, int> get normalScanSession => _normalScanSession;

  // Normal mod kamera overlay sayaçları
  int get normalSessionScanCount => _normalScanSession.values.fold(0, (a, b) => a + b);
  int get normalTotalScanned =>
      _normalPreviousCounts.values.fold(0, (a, b) => a + b) + normalSessionScanCount;
  

  bool showReportAfterCamera = false;

  // Abonelik özelliği aktif edileceği zaman kullanılacak
  /*
  bool get canExport {
    final now = DateTime.now().toUtc();
    
    // Eğer deneme bitiş tarihi varsa ve henüz geçmemişse izin ver
    if (_trialEndDate != null && _trialEndDate!.isAfter(now)) {
      return true;
    }

    // Eğer abonelik bitiş tarihi varsa ve henüz geçmemişse izin ver
    if (_subscriptionEndDate != null && _subscriptionEndDate!.isAfter(now)) {
      return true;
    }

    // Diğer tüm durumlarda (süre bittiyse veya tarihler yoksa) engelle
    return false;
  }
  */

  String get remainingTrialTime {
    if (_subscriptionStatus != "Trialing" || _trialEndDate == null) return "";
    
    final now = DateTime.now().toUtc();
    final difference = _trialEndDate!.difference(now);

    if (difference.isNegative) return "Deneme Süresi Doldu";

    String twoDigits(int n) => n.toString().padLeft(2, "0");
    int minutes = difference.inMinutes; 
    int seconds = difference.inSeconds.remainder(60);
    
    return "$minutes:${twoDigits(seconds)}"; 
  }

  final Set<String> _scannedSessionValues = {};

  bool _offlineMode = false;
  bool get offlineMode => _offlineMode;

  void toggleOfflineMode(void Function(String message, bool isOffline) onMessage) {
    _offlineMode = !_offlineMode;
    notifyListeners();
    String msg = _offlineMode 
        ? "Offline Mod Aktif: Yerel veri kullanılacak." 
        : "Online Mod Aktif: Sunucu üzerinden taranacak.";
    onMessage(msg, _offlineMode);
  }

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  final List<QrLookupResultWithCount> _history = [];
  final ScanHistoryRepository _historyRepository = ScanHistoryRepository.instance;
  int? _historyUserId;

  DateTime? _startDate;
  DateTime? _endDate;

  void setDateFilter(DateTime? start, DateTime? end) {
    _startDate = start;
    _endDate = end;
    notifyListeners();
  }

  List<QrLookupResultWithCount> get _filteredHistory {
    if (_startDate == null && _endDate == null) return _history;
    return _history.where((item) {
      if (_startDate != null && item.createdAt.isBefore(_startDate!)) return false;
      if (_endDate != null && item.createdAt.isAfter(_endDate!)) return false;
      return true;
    }).toList();
  }

  List<QrLookupResultWithCount> get history => List.unmodifiable(_history);
  List<QrLookupResultWithCount> get lookupResults => aggregate(_filteredHistory);

  String? _error;
  String? get error => _error;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;
  void updateSearchQuery(String value) {
    _searchQuery = value;
    notifyListeners();
  }

  static const String _stockTargetKey = 'stock_target';
  static const String _stockSessionKey = 'stock_session';

  bool get hasActiveStockSession => _targetInventory.isNotEmpty;

  QrScanViewModel() {
    loadSavedResults();
  }

  Future<void> loadSavedResults() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. ABONELİK DURUMUNU VE TARİHLERİ YÜKLE
    String? trialStr = prefs.getString('trialEndDate');

    if (trialStr == null) {
      // --- SENARYO: İLK DEFA GİRİŞ YAPILIYOR ---
      // Kullanıcı ilk defa girdiğinde süreyi şimdi başlatıyoruz (Örn: 60 dakika)
      DateTime firstLaunchTrial = DateTime.now().toUtc().add(const Duration(minutes: 60)); 
      
      // Cihaza kaydet ki bir sonraki girişte kaldığı yerden devam etsin
      await prefs.setString('trialEndDate', firstLaunchTrial.toIso8601String());
      
      _trialEndDate = firstLaunchTrial;
      _subscriptionStatus = "Trialing";
      debugPrint("DEBUG_DIALOG: Uygulamaya ilk giriş yapıldı. Deneme süresi başlatıldı.");
    } else {
      // --- SENARYO: DAHA ÖNCE GİRİŞ YAPILMIŞ ---
      // Kayıtlı olan tarihi yükle
      DateTime parsedDate = DateTime.parse(trialStr);
      _trialEndDate = DateTime.utc(
        parsedDate.year, parsedDate.month, parsedDate.day,
        parsedDate.hour, parsedDate.minute, parsedDate.second,
      );
      _subscriptionStatus = "Trialing";
      debugPrint("DEBUG_DIALOG: Mevcut deneme süresi yüklendi.");
    }
    
    // 2. TARAMA GEÇMİŞİNİ YÜKLE
    _historyUserId = prefs.getInt('userId');
    _history.clear();
    if (_historyUserId != null) {
      try {
        _history.addAll(await _historyRepository.load(
          _historyUserId!,
          legacyUsername: prefs.getString('username'),
        ));
        debugPrint("✅ Hafızadan ${_history.length} adet kayıt yüklendi.");
      } catch (e) {
        debugPrint("❌ Geçmiş veriler yüklenirken hata oluştu: $e");
      }
    }

    // 3. STOK SAYIM OTURUMUNU YÜKLE
    final username = prefs.getString('username') ?? 'guest';
    final stockTarget = prefs.getString('${_stockTargetKey}_$username');
    if (stockTarget != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(stockTarget);
        _targetInventory = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {}
    }
    final stockSession = prefs.getString('${_stockSessionKey}_$username');
    if (stockSession != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(stockSession);
        _currentScanSession = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {}
    }

    // Abonelik özelliği aktif edileceği zaman kullanılacak
    // startSubscriptionTimer();
    notifyListeners();
  }


  // Abonelik özelliği aktif edileceği zaman kullanılacak
  /*
  void startSubscriptionTimer() {
    _subscriptionTimer?.cancel(); 
    
    // Anlık kontrolü de UTC üzerinden yapıyoruz
    if (_trialEndDate != null && _trialEndDate!.isBefore(DateTime.now().toUtc())) {
      notifyListeners();
      return;
    }

    _subscriptionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now().toUtc();
      
      if (_subscriptionStatus == "Trialing" && _trialEndDate != null) {
        if (_trialEndDate!.isBefore(now)) {
          timer.cancel(); 
          notifyListeners(); 
        } else {
          notifyListeners(); 
        }
      } else {
        timer.cancel();
      }
    });
  }
  */

  // Geçmişteki değişikliği veritabanına yazar, hata olursa ekrandaki listeyi bozmadan loga yazar
  Future<void> _persistHistory(Future<void> Function(int userId) write) async {
    final userId = _historyUserId;
    if (userId == null) return;
    try {
      await write(userId);
    } catch (e) {
      debugPrint("❌ Geçmiş kaydedilemedi: $e");
    }
  }

  final Map<String, (Barcode, DateTime)> _activeBarcodesMap = {};

  Future<void> onBarcodesDetected(BarcodeCapture capture) async {
    _lastImageSize = capture.size;
    final now = DateTime.now().toUtc();
    bool isNewFound = false;

    // Painter (Yeşil kutular) için barkodları haritaya ekle
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null) {
        _activeBarcodesMap[barcode.rawValue!] = (barcode, now);
        isNewFound = true;
      }
    }

    if (!isNewFound && _activeBarcodesMap.isEmpty) return;

    _uiRefreshTimer?.cancel();
    _uiRefreshTimer = Timer(const Duration(milliseconds: 150), () {
      if (_activeBarcodesMap.isNotEmpty) {
        _activeBarcodesMap.clear();
        _detectedBarcodes = [];
        notifyListeners();
      }
    });

    _activeBarcodesMap.removeWhere((key, value) => 
        now.difference(value.$2).inMilliseconds > 800);

    _detectedBarcodes = _activeBarcodesMap.values.map((e) => e.$1).toList();
    notifyListeners(); 

    if (_isProcessing) return;

    final List<String> toProcess = [];
    for (var barcode in capture.barcodes) {
      final val = barcode.rawValue;
      if (val == null) continue;

      // Aynı oturumda (kamera kapanmadan) üst üste okumayı engelle
      if (_scannedSessionValues.contains(val)) continue;

      if (isComparisonMode) {
        // --- STOK MODU: Anasayfada kayıtlı olsa bile sayım için içeri al ---
        toProcess.add(val);
      } else {
        // --- NORMAL MOD: Sadece anasayfada yoksa içeri al ---
        if (!_history.any((item) => item.qr.value == val)) {
          toProcess.add(val);
        }
      }
    }

    if (toProcess.isEmpty) return;

    _isProcessing = true;
    _scannedSessionValues.addAll(toProcess); // Okunanı oturuma ekle (tekrar okumayı keser)
    _runBackgroundTask(toProcess);
  }

  Future<void> _runBackgroundTask(List<String> codes) async {
    try {
      for (var val in codes) {
        // 1. Barkodu temizle (GTIN elde et)
        String cleanGtin = _getGtinFromRaw(val);

        if (isComparisonMode) {
          // --- 📊 STOK MODU İŞLEMLERİ ---
          print("🎯 TERMİNAL: Stok Modunda Okundu: $cleanGtin");

          String? matchedKey;
          // Excel listesinde 13 veya 14 haneli olarak var mı?
          if (_targetInventory.containsKey(cleanGtin)) {
            matchedKey = cleanGtin;
          } else if (_targetInventory.containsKey("0$cleanGtin")) {
            matchedKey = "0$cleanGtin";
          }

          if (matchedKey != null) {
            // Sayaç artırma
            _currentScanSession[matchedKey] = (_currentScanSession[matchedKey] ?? 0) + 1;
            _sessionScanCount++;
            HapticFeedback.lightImpact();
            print("📈 SAYAÇ GÜNCELLENDİ: $matchedKey -> ${_currentScanSession[matchedKey]}");
            unawaited(_saveStockSession());
          } else {
            print("⚠️ TERMİNAL: Okunan barkod Excel listesinde bulunamadı.");
          }
        } else {
          // --- 🏠 NORMAL MOD İŞLEMLERİ ---
          print("✅ TERMİNAL: Normal Mod - Anasayfaya Ekleniyor: $cleanGtin");
          await _processSingleBarcode(val);
          _normalScanSession[val] = (_normalScanSession[val] ?? 0) + 1;
        }
      }
    } catch (e) {
      debugPrint("❌ Arka Plan Hatası: $e");
    } finally {
      _isProcessing = false;
      notifyListeners(); // UI'daki sayaç ve listeleri tazeler
    }
  }

  void setExpiryMonthLimit(int month) {
    _expiryMonthLimit = month;
    _saveSettings(); 
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('expiry_month_limit', _expiryMonthLimit);
  }

  Set<String> get alreadyScannedValues {
    if (isComparisonMode) {
      return _scannedSessionValues;
    } else {
      final set = Set<String>.from(_scannedSessionValues);
      set.addAll(_history.map((e) => e.qr.value));
      return set;
    }
  }

  Map<String, Color> getBarcodeColors() {
    Map<String, Color> colors = {};
    final now = DateTime.now().toUtc();
    final oneMonthLimit = now.add(const Duration(days: 30));

    for (var barcode in _detectedBarcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      if (isComparisonMode) {
        // ✅ 1. ADIM: Barkodu arka plandaki gibi temizle (GTIN elde et)
        String cleanGtin = _getGtinFromRaw(raw);

        // ✅ 2. ADIM: Arka plandaki ikili kontrol mantığının aynısını yap
        bool isMatch = _targetInventory.containsKey(cleanGtin) || 
                      _targetInventory.containsKey("0$cleanGtin");

        if (isMatch) {
          // Excel listesinde (temizlenmiş haliyle veya 0 ekli haliyle) VARSA
          colors[raw] = Colors.greenAccent;
        } else {
          // Hiçbir şekilde YOKSA
          colors[raw] = Colors.redAccent;
        }
      } else {
        // --- NORMAL MOD İŞLEMLERİ (SKT Kontrolü) ---
        final matchedResult = _history.where((item) => item.qr.value == raw).toList();

        if (matchedResult.isNotEmpty) {
          final expiry = matchedResult.first.qr.data?.expiryDate;
          if (expiry != null) {
            final customLimitDate = now.add(Duration(days: _expiryMonthLimit * 30));
            if (expiry.isBefore(oneMonthLimit)) {
              colors[raw] = Colors.redAccent;
            } else if (expiry.isBefore(customLimitDate)) {
              colors[raw] = Colors.orangeAccent;
            } else {
              colors[raw] = Colors.greenAccent;
            }
          } else {
            colors[raw] = Colors.greenAccent;
          }
        } else {
          colors[raw] = Colors.greenAccent;
        }
      }
    }
    return colors;
  }

  Future<void> _processSingleBarcode(String value) async {
    final qr = await _valueToQrResult(value, Rect.zero);
    await _appendToHistory([QrLookupResultWithCount(qr: qr, createdAt: DateTime.now().toUtc(), isOffline: _offlineMode)]);
  }

  void clearCurrentSession() {
    // Kamera açılmadan önce mevcut history'yi "önceki" olarak snapshot'la
    _normalPreviousCounts = {};
    for (final item in _history) {
      _normalPreviousCounts[item.qr.value] =
          (_normalPreviousCounts[item.qr.value] ?? 0) + item.count;
    }
    _normalScanSession = {};

    _scannedSessionValues.clear();
    _detectedBarcodes.clear();
    _sessionScanCount = 0;
    notifyListeners();
  }

  // Tüm listeyi temizler
  void clearAllHistory() async {
    _history.clear();
    notifyListeners();
    await _persistHistory((userId) => _historyRepository.clear(userId));
  }

  Future<void> openCameraAndScan({bool allowGalleryFallback = true}) async {
    _error = null;
    final Stopwatch totalStopwatch = Stopwatch()..start();
    try {
      _isProcessing = true;
      _lastScannedFile = null;
      _lastResults = [];
      notifyListeners();

      XFile? file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 2000, maxHeight: 2000);
      if (file == null && allowGalleryFallback) {
        file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 2000, maxHeight: 2000);
      }

      if (file == null) { _isProcessing = false; notifyListeners(); return; }

      final imageFile = File(file.path);
      _lastScannedFile = imageFile;
      
      if (_offlineMode) {
        await _handleOfflineScan(imageFile);
      } else {
        await _handleOnlineScan(imageFile, totalStopwatch);
      }

      if (_error != null && onScanError != null) onScanError!(_error!);
    } catch (e) {
      _error = 'Hata: $e';
      if (onScanError != null) onScanError!(_error!);
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  // 1. Kullanıcının dış IP adresini öğrenmek için yardımcı fonksiyon
  Future<String> getPublicIP() async {
    try {
      final response = await http.get(Uri.parse(ExternalUrls.publicIp)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (e) {
      print("IP tespiti başarısız: $e");
    }
    return "Tespit edilemedi";
  }

  Future<String?> checkDrugStatusWithIts({
    required BuildContext context,
    required String gtin,
    required String sn,
    required String lot,
    required String skt,
  }) async {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final userIdStr = authVm.userId?.toString() ?? "guest";

    final credentials = await ItsCredentialStore.instance.read(userIdStr);
    final String gln = credentials.gln.trim();
    final String pass = credentials.password.trim();

    try {
      print("🔑 [ADIM 1] İTS Token İsteniyor...");

      final tokenResponse = await http.post(
        Uri.parse(ExternalUrls.itsToken),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "username": gln,
          "password": pass,
        }),
      ).timeout(const Duration(seconds: 10));

      if (tokenResponse.statusCode == 200) {
        final tokenData = jsonDecode(tokenResponse.body);
        String accessToken = tokenData['access_token'] ?? tokenData['accessToken'] ?? tokenData['token'] ?? "";

        if (accessToken.isEmpty) return "Hata: İTS yetki anahtarı alınamadı.";

        print("🌐 [ADIM 2] İlaç İTS'ye Sorgulanıyor...");

        final Map<String, dynamic> requestBody = {
          "productList": [
            {
              "gtin": gtin.padLeft(14, '0'),
              "sn": sn,
              "bn": lot,
              "xd": skt.length >= 10 ? skt.substring(0, 10) : skt
            }
          ]
        };

        final response = await http.post(
          Uri.parse(ExternalUrls.itsCheckStatus),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode(requestBody),
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final resData = jsonDecode(response.body);
          var uc = resData['responseObjectList']?[0]?['uc'] ?? "Bilinmiyor";

          print("📦 [ITS] Dönen UC Kodu: $uc");

          // 🔹 [ADIM 3] UC kodunu Kendi Backend'ine gönder (Ngrok ayarıyla birlikte)
          try {
            print("🌐 [ADIM 3] Backend'den resmi açıklama isteniyor...");
            final backendData = await _apiClient.post(ApiConstants.itsResolveCode, {"code": uc.toString()});
            return backendData['message'] ?? uc.toString();
          } on ApiException catch (e) {
            print("⚠️ Backend Hatası: $e");
            if (e.statusCode != null) return "Kod: $uc (Açıklama getirilemedi)";
            return "Kod: $uc (Sunucu bağlantı hatası)";
          } catch (e) {
            print("⚠️ Backend Hatası: $e");
            return "Kod: $uc (Sunucu bağlantı hatası)";
          }
        } else {
          return "İTS servisi hata döndürdü: ${response.statusCode}";
        }
      } else if (tokenResponse.statusCode == 401 || tokenResponse.statusCode == 403) {
        return "İTS Kullanıcı adı veya şifre hatalı.";
      } else {
        return "İTS Bağlantı hatası: ${tokenResponse.statusCode}";
      }
    } on SocketException {
      return "İnternet bağlantısı yok veya sunucuya ulaşılamıyor.";
    } catch (e) {
      return "Beklenmedik hata: $e";
    }
  }


  // ✅ EXCEL DOSYASI SEÇME VE ANALİZ ETME
  Future<Map<String, int>?> pickExcelFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: false, // Performans için: Sadece yolu alalım
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final bytes = file.readAsBytesSync();
        final excel = Excel.decodeBytes(bytes);

        _targetInventory.clear();

        for (var table in excel.tables.keys) {
          var rows = excel.tables[table]!.rows;
          if (rows.isEmpty) continue;

          int barkodIndex = -1;
          int miktarIndex = -1;

          // --- Başlık Analizi ---
          var headerRow = rows.first;
          for (int i = 0; i < headerRow.length; i++) {
            // .value?.toString() yerine daha güvenli olan yöntem:
            String val = headerRow[i]?.value?.toString().toLowerCase().trim() ?? "";
            if (val.contains("barkod") || val.contains("gtin")) barkodIndex = i;
            if (val.contains("miktar") || val.contains("adet")) miktarIndex = i;
          }

          if (barkodIndex == -1 || miktarIndex == -1) {
            throw "Excel'de 'Barkod' ve 'Miktar' sütunları bulunamadı!";
          }

          // --- Veri Okuma ---
          for (int i = 1; i < rows.length; i++) {
            var row = rows[i];
            
            // Satır uzunluğu indexlerden küçükse hata almamak için kontrol:
            if (row.length <= barkodIndex || row.length <= miktarIndex) continue;

            // Veriyi güvenli çekme
            var barkodRaw = row[barkodIndex]?.value?.toString() ?? "";
            var barkod = barkodRaw.trim();
            
            var miktarRaw = row[miktarIndex]?.value?.toString() ?? "0";
            int miktar = int.tryParse(miktarRaw) ?? 0;

            if (barkod.isNotEmpty && miktar > 0) {
              _targetInventory[barkod] = miktar;
            }
          }
        }

        notifyListeners();
        unawaited(_saveStockSession());
        // Önemli: Boş bir map dönse bile null dönmediği için View tarafı
        // işlemin bittiğini anlar ama miktar 0 ise diyalog göstermez.
        return Map.from(_targetInventory);
      }
      return null;
    } catch (e) {
      debugPrint("Excel okuma hatası detayı: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red),
        );
      }
      return null;
    }
  }

  // Sayım miktarını 1 artıran fonksiyon
  void incrementScannedProduct(String barcode) {
    _currentScanSession[barcode] = (_currentScanSession[barcode] ?? 0) + 1;
    notifyListeners();
  }
  
  // Yeni bir sayıma başlarken session'ı sıfırlamak istersen:
  void clearScanSession() {
    _currentScanSession.clear();
    notifyListeners();
  }

  void setComparisonMode(bool value) {
    _isComparisonMode = value;
    if (value) {
      _currentScanSession.clear(); // Yeni sayım başladığında eski session'ı sıfırla
    }
    notifyListeners();
  }

  void resumeComparisonMode() {
    _isComparisonMode = true;
    notifyListeners();
  }

  void resetSessionCount() {
    if (_isComparisonMode) {
      _sessionScanCount = 0;
    } else {
      _normalScanSession.clear();
    }
    notifyListeners();
  }

  Future<void> _saveStockSession() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? 'guest';
    await prefs.setString('${_stockTargetKey}_$username', jsonEncode(_targetInventory));
    await prefs.setString('${_stockSessionKey}_$username', jsonEncode(_currentScanSession));
  }

  Future<void> clearStockSession() async {
    _targetInventory.clear();
    _currentScanSession.clear();
    _isComparisonMode = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? 'guest';
    await prefs.remove('${_stockTargetKey}_$username');
    await prefs.remove('${_stockSessionKey}_$username');
  }

  Future<Map<String, dynamic>> getComparisonResults() async {
    List<Map<String, dynamic>> missing = [];
    List<Map<String, dynamic>> extra = [];
    List<Map<String, dynamic>> matched = [];

    int totalExpectedBoxes = 0;
    int totalScannedBoxes = 0;

    _targetInventory.values.forEach((qty) => totalExpectedBoxes += qty);

    // 1️⃣ Hedef Envanteri Tara
    for (var entry in _targetInventory.entries) {
      String barcode = entry.key;
      int targetQty = entry.value;
      int currentQty = _currentScanSession[barcode] ?? 0;

      totalScannedBoxes += currentQty;

      // 🔹 DB'den ilaç adını çek
      final drug = await _localDbService.findDrugByBarcode(barcode);
      final drugName = drug?['ÜRÜN ADI'] ?? barcode;

      var itemInfo = {
        "name": drugName,
        "barcode": barcode,
        "expected": targetQty,
        "scanned": currentQty
      };

      if (currentQty == 0) {
        missing.add(itemInfo);
      } else if (currentQty < targetQty) {
        missing.add(itemInfo);
      } else if (currentQty == targetQty) {
        matched.add(itemInfo);
      } else {
        extra.add(itemInfo);
      }
    }

    // 2️⃣ Listede olmayıp tarananlar
    for (var entry in _currentScanSession.entries) {
      String barcode = entry.key;
      int currentQty = entry.value;

      if (!_targetInventory.containsKey(barcode)) {
        totalScannedBoxes += currentQty;

        final drug = await _localDbService.findDrugByBarcode(barcode);
        final drugName = drug?['URUN_ADI'] ?? "Listede Bulunmuyor";

        extra.add({
          "name": drugName,
          "barcode": barcode,
          "expected": 0,
          "scanned": currentQty
        });
      }
    }

    double accuracy = totalExpectedBoxes > 0
        ? (totalScannedBoxes / totalExpectedBoxes) * 100
        : 0;

    if (accuracy > 100) accuracy = 100;

    return {
      "missing": missing,
      "extra": extra,
      "matched": matched,
      "stats": {
        "expected": totalExpectedBoxes,
        "scanned": totalScannedBoxes,
        "accuracy": accuracy.toStringAsFixed(1)
      }
    };
  }

  // QrScanViewModel dosyasının en altına ekle
  Future<void> exportComparisonReport(BuildContext context) async {
    try {
      final results = await getComparisonResults();
      final stats = results['stats'];
      final List missing = results['missing'] ?? [];
      final List extra = results['extra'] ?? [];
      final List matched = results['matched'] ?? [];

      var excel = Excel.createExcel();
      String sheetName = "Stok Analiz Raporu";
      excel.rename("Sheet1", sheetName);
      Sheet sheetObject = excel[sheetName];

      // ✅ RENK HATASI DÜZELTİLDİ: ExcelColor.fromHexString kullanıyoruz
      CellStyle headerStyle = CellStyle(
        bold: true,
        fontFamily: getFontFamily(FontFamily.Calibri),
        backgroundColorHex: ExcelColor.fromHexString("#0F4C75"), // Koyu Mavi
        fontColorHex: ExcelColor.fromHexString("#FFFFFF"),       // Beyaz
        horizontalAlign: HorizontalAlign.Center,
      );

      CellStyle subHeaderStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString("#F1F5F9"), // Açık Gri
        horizontalAlign: HorizontalAlign.Center,
      );

      // Başlık Bölümü
      sheetObject.merge(CellIndex.indexByString("A1"), CellIndex.indexByString("F1"));
      var cellA1 = sheetObject.cell(CellIndex.indexByString("A1"));
      cellA1.value = TextCellValue("ECZANE STOK SAYIM ANALİZ RAPORU");
      cellA1.cellStyle = headerStyle;

      // Özet Bilgiler
      sheetObject.cell(CellIndex.indexByString("A2")).value = TextCellValue("Tarih:");
      sheetObject.cell(CellIndex.indexByString("B2")).value = TextCellValue(DateTime.now().toString().substring(0, 16));

      sheetObject.cell(CellIndex.indexByString("A3")).value = TextCellValue("Beklenen Toplam:");
      sheetObject.cell(CellIndex.indexByString("B3")).value = IntCellValue(stats['expected'] ?? 0);
      sheetObject.cell(CellIndex.indexByString("C3")).value = TextCellValue("Okunan:");
      sheetObject.cell(CellIndex.indexByString("D3")).value = IntCellValue(stats['scanned'] ?? 0);
      sheetObject.cell(CellIndex.indexByString("E3")).value = TextCellValue("Doğruluk:");
      sheetObject.cell(CellIndex.indexByString("F3")).value = TextCellValue("%${stats['accuracy']}");

      // Tablo Kolon Başlıkları
      List<String> headers = ["DURUM", "ÜRÜN ADI", "BARKOD", "BEKLENEN", "OKUNAN", "FARK"];
      for (var i = 0; i < headers.length; i++) {
        var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 5));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = subHeaderStyle;
      }

      int currentRow = 6;

      void addRows(List items, String status) {
        for (var item in items) {
          sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow)).value = TextCellValue(status);
          sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: currentRow)).value = TextCellValue(item['name']?.toString() ?? "Bilinmeyen Ürün");
          sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: currentRow)).value = TextCellValue(item['barcode']?.toString() ?? "-");
          sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: currentRow)).value = IntCellValue(item['expected'] ?? 0);
          sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: currentRow)).value = IntCellValue(item['scanned'] ?? 0);
          
          int diff = (item['scanned'] ?? 0) - (item['expected'] ?? 0);
          sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentRow)).value = IntCellValue(diff);
          
          currentRow++;
        }
      }

      addRows(missing, "EKSIK");
      addRows(extra, "FAZLA/TANIMSIZ");
      addRows(matched, "TAMAM");

      final directory = await getTemporaryDirectory();
      final String filePath = "${directory.path}/stok_analiz_raporu.xlsx";
      final fileBytes = excel.save();
      
      if (fileBytes != null) {
        File(filePath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);

        await Share.shareXFiles(
          [XFile(filePath)],
          subject: 'Stok Sayım Analiz Raporu',
        );
      }
    } catch (e) {
      debugPrint("Excel Export Hatası: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Excel Hatası: ${e.toString()}")),
        );
      }
    }
  }

  void setShouldShowReport(bool value) {
    showReportAfterCamera = value;
    notifyListeners();
  }

  Future<void> _handleOnlineScan(File imageFile, Stopwatch totalStopwatch) async {
    try {
      _error = null;
      _lastResults = [];
      notifyListeners(); 
      final response = await _qrService.uploadQrImage(imageFile);
      _lastResults = response.results;

      if (_lastResults.isEmpty) {
        _error = "Fotoğrafta barkod bulunamadı."; 
        HapticFeedback.vibrate(); 
      } else {
        _error = null;
        HapticFeedback.lightImpact(); 
        final nowEntries = response.results.map((e) => QrLookupResultWithCount(qr: e, createdAt: DateTime.now().toUtc(), isOffline: false)).toList();
        await _appendToHistory(nowEntries);
      }
    } catch (e) {
      await _handleOfflineScan(imageFile);
    } finally {
      notifyListeners();
    }
  }

  Future<void> _handleOfflineScan(File imageFile) async {
    try {
      _error = null;
      _lastResults = [];
      notifyListeners();

      final mlkit.BarcodeScanner barcodeScanner = mlkit.BarcodeScanner(formats: [mlkit.BarcodeFormat.dataMatrix, mlkit.BarcodeFormat.qrCode]);
      final mlkit.InputImage inputImage = mlkit.InputImage.fromFile(imageFile);
      final List<mlkit.Barcode> barcodes = await barcodeScanner.processImage(inputImage);
      
      if (barcodes.isEmpty) {
        _error = "Fotoğrafta barkod bulunamadı.";
        HapticFeedback.vibrate(); 
      } else {
        _error = null;
        final newResults = <QrLookupResultWithCount>[];
        final List<QrLookupResult> tempLastResults = [];

        for (final barcode in barcodes) {
          final qr = await _valueToQrResult(barcode.rawValue ?? "", barcode.boundingBox);
          tempLastResults.add(qr);
          newResults.add(QrLookupResultWithCount(qr: qr, createdAt: DateTime.now().toUtc(), isOffline: true));
        }

        _lastResults = List.from(tempLastResults);
        await _appendToHistory(newResults);
      }
      await barcodeScanner.close();
    } catch (e) {
      _error = 'Hata: $e';
    } finally {
      notifyListeners();
    }
  }

  Future<QrLookupResult> _valueToQrResult(String v, Rect rect) async {
    String originalV = v;
    final parsed = Gs1Parser.parse(v);

    String? drugName;
    final gtin = parsed.gtin;
    final serial = parsed.serialNo;
    final batch = parsed.batchNo;
    final expiry = parsed.expiryDate;

    if (gtin != null) {
      final drugFromLib = await _localDbService.findDrugByBarcode(gtin);
      if (drugFromLib != null) {
        drugName = (drugFromLib['ÜRÜN ADI'] ?? drugFromLib['URUN_ADI'])?.toString();
      }
    }

    final bool isFound = drugName != null;
    final qrData = QrData(
      gtin: gtin,
      serialNo: serial,
      batchNo: batch,
      expiryDate: expiry,
      productName: drugName,
    );

    return QrLookupResult(
      value: originalV, found: isFound, data: isFound ? qrData : null,
      x: rect.left.toInt(), y: rect.top.toInt(), w: rect.width.toInt(), h: rect.height.toInt(),
    );
  }

  String _getGtinFromRaw(String raw) {
    return Gs1Parser.parse(raw).gtin ?? raw;
  }

  // Yeni kayıtları ekrandaki listeye ekler ve veritabanına yazar
  Future<void> _appendToHistory(List<QrLookupResultWithCount> entries) async {
    _history.addAll(entries);
    notifyListeners();
    await _persistHistory((userId) => _historyRepository.insertAll(userId, entries));
  }

  List<QrLookupResultWithCount> aggregate(List<QrLookupResultWithCount> items) {
    final filtered = items.where((r) {
      if (_searchQuery.isEmpty) return true;
      
      final query = _searchQuery.toLowerCase();
      
      // 1. Ham Barkod Değeri
      final rawValue = r.qr.value.toLowerCase();
      
      // 2. İlaç İsmi (Kartta productName olarak geçiyor)
      final productName = r.qr.data?.productName?.toLowerCase() ?? "";
      
      // 3. GTIN
      final gtin = r.qr.data?.gtin?.toLowerCase() ?? "";
      
      // 4. Seri No
      final serialNo = r.qr.data?.serialNo?.toLowerCase() ?? "";

      return rawValue.contains(query) || 
             productName.contains(query) || 
             gtin.contains(query) || 
             serialNo.contains(query);
    }).toList();

    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  void removeQrResultByValue(String value) { _history.removeWhere((h) => h.qr.value == value); notifyListeners(); _persistHistory((userId) => _historyRepository.deleteByValue(userId, value)); }
  void removeHistoryItem(QrLookupResultWithCount item) { _history.remove(item); notifyListeners(); _deleteEntry(item); }
  void removeByProductName(String productName) { _history.removeWhere((h) => h.qr.data?.productName == productName); notifyListeners(); _persistHistory((userId) => _historyRepository.deleteByProductName(userId, productName)); }

  void incrementQrCountByValue(String value) {
    if (_history.isEmpty) return;
    QrLookupResultWithCount? rep;
    for (final h in _history.reversed) { if (h.qr.value == value) { rep = h; break; } }
    if (rep == null) return;
    _appendToHistory([QrLookupResultWithCount(qr: rep.qr, createdAt: DateTime.now().toUtc(), count: 1)]);
  }

  void decrementQrCountByValue(String value) {
    for (int i = _history.length - 1; i >= 0; i--) {
      if (_history[i].qr.value == value) { _deleteEntry(_history.removeAt(i)); notifyListeners(); return; }
    }
  }

  // Tek kaydı veritabanından siler, id'si henüz yoksa yazılmamış demektir
  void _deleteEntry(QrLookupResultWithCount entry) {
    final id = entry.id;
    if (id == null) return;
    _persistHistory((_) => _historyRepository.deleteById(id));
  }

  Map<String, int> get typeSummary {
    int bulunan = _history.where((e) => e.qr.found).length;
    int bulunamayan = _history.where((e) => !e.qr.found).length;
    return { 'Bulunan': bulunan, 'Bulunamayan': bulunamayan, 'Toplam': _history.length };
  }

  Future<void> exportFoundToExcel(BuildContext context, {String type = 'all'}) async {
    try {
      final now = DateTime.now();
      
      // 1. Filtreleme: Bulunan ürünleri al
      var rawList = lookupResults.where((item) => item.qr.found).toList();

      if (type == 'return') {
        rawList = rawList.where((item) {
          final date = item.qr.data?.expiryDate;
          if (date == null) return false;
          if (item.qr.data!.isExpired) return false;
          return date.difference(now).inDays <= 90;
        }).toList();
      } else if (type == 'expired') {
        rawList = rawList.where((item) => item.qr.data?.isExpired ?? false).toList();
      }

      if (rawList.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(type == 'expired' ? "Miadı geçmiş ürün bulunamadı." : "Dışa aktarılacak kayıt bulunamadı."))
          );
        }
        return;
      }

      // 2. Sıralama: İlaç adına göre alfabetik (Flat list)
      rawList.sort((a, b) {
        String nameA = (a.qr.data?.productName ?? "").toLowerCase();
        String nameB = (b.qr.data?.productName ?? "").toLowerCase();
        return nameA.compareTo(nameB);
      });

      // 3. Excel Oluşturma
      var excel = Excel.createExcel();
      String sheetName = "Envanter Listesi";
      
      // Varsayılan sayfayı isimlendir
      var defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null) {
        excel.rename(defaultSheet, sheetName);
      }
      Sheet sheet = excel[sheetName];

      CellStyle headerStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString("#CCCCCC"),
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        fontColorHex: ExcelColor.fromHexString("#000000"),
      );

      // ✅ 5 SÜTUNLU BAŞLIKLAR (Her Karekod Ayrı Satır)
      List<String> headers = ["BARKOD", "İLAÇ ADI", "S.K.T", "PARTİ NO", "KAREKOD"];
      for (int i = 0; i < headers.length; i++) {
        var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      // 4. Verileri Yazma
      for (int i = 0; i < rawList.length; i++) {
        final item = rawList[i];
        final qrData = item.qr.data;
        final rowIndex = i + 1;

        bool isExpired = qrData?.isExpired ?? false;
        bool isNearExpiry = false;
        if (!isExpired && qrData?.expiryDate != null) {
          if (qrData!.expiryDate!.difference(now).inDays <= 90) isNearExpiry = true;
        }

        String formattedDate = qrData?.expiryDate != null 
            ? "${qrData!.expiryDate!.day.toString().padLeft(2, '0')}.${qrData.expiryDate!.month.toString().padLeft(2, '0')}.${qrData.expiryDate!.year}" 
            : "-";

        CellStyle rowStyle = CellStyle(
          backgroundColorHex: isExpired
              ? ExcelColor.fromHexString("#FFCDD2") 
              : isNearExpiry
                  ? ExcelColor.fromHexString("#FFEB3B") 
                  : ExcelColor.fromHexString("#FFFFFF"),
        );

        // Satır Verileri (Her item tek başına yazılır)
        List<String> rowData = [
          qrData?.gtin ?? "-",
          qrData?.productName ?? "-",
          formattedDate,
          qrData?.batchNo ?? "-",
          item.qr.value.replaceAll('\x1D', ' '),
        ];

        for (int j = 0; j < rowData.length; j++) {
          var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: rowIndex));
          cell.value = TextCellValue(rowData[j]);
          cell.cellStyle = rowStyle;
        }
      }

      // 5. Kaydetme İşlemi
      final directory = await getTemporaryDirectory();
      String baseFileName = "envanter_listesi";
      if (type == 'return') baseFileName = "DepoIadelistesi";
      if (type == 'expired') baseFileName = "miadi_gecenler_listesi";
      
      final String fullFileName = "${baseFileName}_${DateTime.now().millisecondsSinceEpoch}.xlsx";
      final String path = "${directory.path}/$fullFileName";
      
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final file = File(path);
        await file.writeAsBytes(fileBytes);

        // 6. Kritik Paylaşım Ayarları (Dosyayı Excel olarak tanıtır)
        await Share.shareXFiles(
          [
            XFile(
              path, 
              name: fullFileName, // Uzantının .xlsx olduğunu zorla belirtiyoruz
              mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            )
          ],
          text: 'Eczane Envanter Listesi',
        );
      }
    } catch (e) {
      debugPrint("Excel Hatası: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
      }
    }
  }

  // Abonelik özelliği aktif edileceği zaman kullanılacak
  /*
  void _showSubscriptionDialog(BuildContext context) {
    const Color primaryColor = Color(0xFFB71C1C);
    const Color healthTeal = Color(0xFF00ADB5);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        elevation: 10,
        child: Stack( // Çarpı butonunu gradyanın üzerine bindirmek için Stack kullandık
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Üst Kısım: Premium İkonu ve Başlık
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 25),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primaryColor, healthTeal],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 50),
                      SizedBox(height: 10),
                      Text(
                        "Profesyonel Özellik",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Orta Kısım: Açıklama
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    children: [
                      const Text(
                        "Dosya paylaşımı ve gelişmiş raporlama özellikleri sadece abonelerimize özeldir.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Yeni üyeyseniz, deneme süreniz boyunca tüm bu özellikleri ücretsiz deneyimleyebilirsiniz.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blueGrey.shade400,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 25),

                      // Aksiyon Butonları
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: healthTeal,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SubscriptionPage()),
                          );
                        },
                        child: const Text(
                          "Şimdi Abone Ol",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          "Daha Sonra",
                          style: TextStyle(
                            color: Colors.blueGrey.shade400,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // 🔥 SAĞ ÜST ÇARPI BUTONU 🔥
            Positioned(
              right: 12,
              top: 12,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2), // Hafif şeffaf beyaz yuvarlak
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white, // Gradyan üzerinde beyaz ikon daha net durur
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  */

  @override
  void dispose() {
    _clearTimer?.cancel();
    _subscriptionTimer?.cancel(); 
    super.dispose();
  }
}