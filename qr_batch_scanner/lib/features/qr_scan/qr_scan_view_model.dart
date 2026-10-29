import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; 
import 'package:flutter/services.dart';
import 'dart:async';

import '../../core/gs1/gs1_parser.dart';
import '../../core/models/qr_lookup_result.dart';
import '../../core/services/excel_service.dart';
import '../../core/services/local_db_service.dart';
import '../../core/services/scan_history_repository.dart';
import '../../core/services/stock_session_store.dart';
import 'scan_list_filter.dart';
// Abonelik özelliği aktif edileceği zaman kullanılacak
// import '../../core/subscription/subscription_page.dart';

class QrScanViewModel extends ChangeNotifier {
  final LocalDbService _localDbService = LocalDbService();

  List<Barcode> _detectedBarcodes = [];
  List<Barcode> get detectedBarcodes => _detectedBarcodes;

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

  // O anki sayımda hangi barkoddan kaç tane okunduğunu tutar (stok modu)
  Map<String, int> _currentScanSession = {};

  int _sessionScanCount = 0;
  int get sessionScanCount => _sessionScanCount;
  int get totalComparisonScanned => _currentScanSession.values.fold(0, (a, b) => a + b);

  bool _isComparisonMode = false;
  bool get isComparisonMode => _isComparisonMode;

  // Normal mod: kamera açılmadan önce tarananlar (önceki)
  Map<String, int> _normalPreviousCounts = {};

  // Normal mod: bu kamera oturumunda tarananlar (şimdi)
  Map<String, int> _normalScanSession = {};

  // Normal mod kamera overlay sayaçları
  int get normalSessionScanCount => _normalScanSession.values.fold(0, (a, b) => a + b);
  int get normalTotalScanned =>
      _normalPreviousCounts.values.fold(0, (a, b) => a + b) + normalSessionScanCount;

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

  TimeFilterPreset _timeFilter = TimeFilterPreset.all;
  TimeFilterPreset get timeFilter => _timeFilter;

  // Listede ve Excel paylaşımında kullanılacak zaman filtresini değiştirir
  void setTimeFilter(TimeFilterPreset preset) {
    _timeFilter = preset;
    notifyListeners();
  }

  List<QrLookupResultWithCount> get _filteredHistory {
    if (_timeFilter == TimeFilterPreset.all) return _history;
    final now = DateTime.now();
    return _history.where((item) => matchesTimeFilter(item.createdAt, _timeFilter, now)).toList();
  }

  List<QrLookupResultWithCount> get history => List.unmodifiable(_history);
  List<QrLookupResultWithCount> get lookupResults => aggregate(_filteredHistory);
  List<QrLookupResultWithCount> get groupedResults => groupByProductName(lookupResults);

  String _searchQuery = '';
  void updateSearchQuery(String value) {
    _searchQuery = value;
    notifyListeners();
  }

  final StockSessionStore _stockStore = StockSessionStore.instance;

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
    final stock = await _stockStore.load();
    _targetInventory = stock.target;
    _currentScanSession = stock.scanned;

    // 4. SKT UYARI AYINI YÜKLE
    _expiryMonthLimit = prefs.getInt('expiry_month_limit') ?? 6;

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

  // Seçilen Excel'deki barkod ve miktarları hedef sayım olarak yükler, dosya seçilmezse null döner
  Future<Map<String, int>?> pickExcelFile() async {
    final loaded = await ExcelService.instance.pickStockFile();
    if (loaded == null) return null;

    _targetInventory = loaded;
    notifyListeners();
    unawaited(_saveStockSession());
    return Map.from(_targetInventory);
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

  // Stok sayımının güncel halini telefona kaydeder
  Future<void> _saveStockSession() => _stockStore.save(_targetInventory, _currentScanSession);

  // Stok sayımını ekrandan ve telefondan siler
  Future<void> clearStockSession() async {
    _targetInventory.clear();
    _currentScanSession.clear();
    _isComparisonMode = false;
    notifyListeners();
    await _stockStore.clear();
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

  // Stok sayım sonuçlarını hesaplayıp Excel raporu olarak paylaşır
  Future<void> exportComparisonReport() async {
    await ExcelService.instance.shareComparisonReport(await getComparisonResults());
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
  void removeByProductName(String productName) { _history.removeWhere((h) => h.qr.data?.productName == productName); notifyListeners(); _persistHistory((userId) => _historyRepository.deleteByProductName(userId, productName)); }

  // Bulunan kayıtları seçilen türe göre süzüp Excel olarak paylaşır, aktarılacak kayıt yoksa false döner
  Future<bool> exportFoundToExcel({String type = 'all'}) async {
    final now = DateTime.now();
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

    if (rawList.isEmpty) return false;

    rawList.sort((a, b) {
      String nameA = (a.qr.data?.productName ?? "").toLowerCase();
      String nameB = (b.qr.data?.productName ?? "").toLowerCase();
      return nameA.compareTo(nameB);
    });

    await ExcelService.instance.shareInventoryList(rawList, type: type);
    return true;
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
    _uiRefreshTimer?.cancel();
    _subscriptionTimer?.cancel(); 
    super.dispose();
  }
}
