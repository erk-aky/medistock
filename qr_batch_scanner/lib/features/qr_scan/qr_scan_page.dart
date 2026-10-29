import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; 
import 'qr_scan_view_model.dart';
import 'qr_type_stats_page.dart'; 
import '../../core/gs1/gs1_parser.dart';
import '../../core/models/qr_lookup_result.dart';
import '../../core/services/its_credential_store.dart';
import '../../core/services/its_status_service.dart';
import 'package:flutter/services.dart';
import '../../core/subscription/subscription_page.dart';
// Abonelik özelliği aktif edileceği zaman kullanılacak
// import '../../core/subscription/trial_period_dialog.dart';
import 'stock_comparison_page.dart';
import 'widgets/export_options_sheet.dart';
import 'widgets/result_card.dart';
import 'widgets/scan_filter_bar.dart';
import '../settings/settings_page.dart';
import '../settings/account_details_page.dart'; // Dosyanın gerçek yolunu yazmalısın
import '../auth/auth_view_model.dart';


// Kamera tarama rengi modu: sırasıyla normal -> invert -> hybrid -> normal
// şeklinde döngüye giriyor (mod değiştirme butonu ile).
enum _ScanColorMode { normal, inverted, hybrid }

class QrScanPage extends StatelessWidget {
  const QrScanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => QrScanViewModel(),
      child: const _QrScanView(),
    );
  }
}

class _QrScanView extends StatefulWidget {
  const _QrScanView({super.key});

  @override
  State<_QrScanView> createState() => _QrScanViewState();
}

class _QrScanViewState extends State<_QrScanView> {
  final ScrollController _scrollController = ScrollController();
  late QrScanViewModel _vm;
  int _lastCount = 0;
  TimeFilterPreset _selectedFilter = TimeFilterPreset.all;
  bool _isFlashOn = false; // Flaşın açık olup olmadığını biz takip edeceğiz

  // class _QrScanPageState extends State<QrScanPage> {  satırının hemen altına:
  // Sınıfın en üstünde, diğer değişkenlerin yanında:
  late MobileScannerController scannerController;
  _ScanColorMode _colorMode = _ScanColorMode.normal;
  bool _isCameraRefreshing = false; // BU SATIRI EKLE (Sayfayı yenilemek için kullanacağız)

  void _initScanner() {
    // Eğer hali hazırda bir controller varsa temizlik yapıyoruz
    // scannerController?.dispose();

    scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.unrestricted,
      cameraResolution: const Size(1920, 1080),
      detectionTimeoutMs: 100,
      // ÖNEMLİ: Siyah/Mavi kutular için en hızlısı DataMatrix'e odaklanmaktır.
      // Eğer diğer modlarda QR okutman gerekiyorsa [BarcodeFormat.dataMatrix, BarcodeFormat.qrCode] yapabilirsin.
      formats: [BarcodeFormat.dataMatrix, BarcodeFormat.qrCode],
      facing: CameraFacing.back,
      returnImage: false,
      // İşte o sihirli özellik:
      invertImage: _colorMode == _ScanColorMode.inverted,
      // Hibrit modda kamera yeniden başlatılmadan her karede normal/ters
      // tarama alterne edilir (native tarafta uygulanan yama, bkz. packages/mobile_scanner).
      hybridMode: _colorMode == _ScanColorMode.hybrid,
    );

    // mobile_scanner, ekran yön kilidinden (SystemChrome.setPreferredOrientations)
    // BAĞIMSIZ olarak telefonun ham sensöründen (OrientationEventListener) okuduğu
    // yönü kullanıyor. Yani ekran dikeyde kilitli olsa bile, telefon 45 dereceden
    // fazla döndürülünce controller "landscape" sanıp önizlemeyi yanlış eksende
    // çiziyordu. Bunu telefonun fiziksel açısından tamamen bağımsız hale getirmek
    // için controller'ın raporladığı yönü sürekli portraitUp'a sabitliyoruz.
    scannerController.addListener(_lockScannerToPortrait);
  }

  // Mod değiştirme butonunun görseli: normal (düz gri), invert (düz turuncu)
  // ve hybrid (dikeyden ikiye bölünmüş, yarısı gri yarısı turuncu) durumlarını
  // ayırt eder. ClipOval + Row kullanımı statik bir çizim olduğundan
  // (animasyon yok) ekstra bir CustomPainter'a gerek bırakmaz.
  Widget _buildColorModeAvatar(_ScanColorMode mode) {
    const double size = 50;
    Widget background;
    switch (mode) {
      case _ScanColorMode.normal:
        background = Container(color: Colors.black54);
      case _ScanColorMode.inverted:
        background = Container(color: Colors.orangeAccent);
      case _ScanColorMode.hybrid:
        background = const Row(
          children: [
            Expanded(child: ColoredBox(color: Colors.black54)),
            Expanded(child: ColoredBox(color: Colors.orangeAccent)),
          ],
        );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipOval(child: background),
          Icon(
            mode == _ScanColorMode.normal
                ? Icons.brightness_6_outlined
                : Icons.brightness_6,
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  String _colorModeHintText(_ScanColorMode mode) {
    switch (mode) {
      case _ScanColorMode.normal:
        return "Beyaz zemindeki karekodu okutun.";
      case _ScanColorMode.inverted:
        return "Siyah zemindeki karekodu okutun.";
      case _ScanColorMode.hybrid:
        return "Siyah veya beyaz zemindeki karekodu okutun.";
    }
  }

  void _lockScannerToPortrait() {
    if (scannerController.value.deviceOrientation != DeviceOrientation.portraitUp) {
      scannerController.value = scannerController.value.copyWith(
        deviceOrientation: DeviceOrientation.portraitUp,
      );
    }
  }


  @override
  void initState() {
    super.initState();
    _initScanner();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _vm = context.read<QrScanViewModel>();
      
      // ignore: unused_element
      /* ---------------------------------------------------------
      // ABONELİK VE DENEME SÜRESİ KONTROL MANTIĞI (DEVRE DIŞI BIRAKILDI)
      // İleride tekrar aktif etmek isterseniz bu bloğu ve alttaki listener'ı açın.

      bool _infoDialogShownThisSession = false; 

      void autoCheckListener() async {
        final status = _vm.remainingTrialTime;
        final prefs = await SharedPreferences.getInstance();
        
        if (status.isNotEmpty) {
          debugPrint("⏱️ CANLI SÜRE: $status");
        }

        bool hasShownExpiredForever = prefs.getBool('hasShownExpiredForever') ?? false;

        // --- 1. AŞAMA: GİRİŞ BİLGİSİ ---
        if (status.isNotEmpty && status != "Deneme Süresi Doldu" && !_infoDialogShownThisSession) {
          _infoDialogShownThisSession = true;
          showTrialPeriodDialog(context, status);
          return; 
        }

        // --- 2. AŞAMA: SÜRE TAM BİTTİĞİ AN ---
        if (status == "Deneme Süresi Doldu" && !hasShownExpiredForever) {
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop(); 
          }
          showTrialPeriodDialog(context, status);
          await prefs.setBool('hasShownExpiredForever', true);
          _vm.removeListener(autoCheckListener);
        } 
        
        // --- 3. DURUM: SÜRE ZATEN DOLU ---
        else if (status == "Deneme Süresi Doldu" && hasShownExpiredForever) {
          _vm.removeListener(autoCheckListener);
        }
      }
      --------------------------------------------------------- */

      // --- DİĞER DİNLEYİCİLERİN (Aktif Kalmalı) ---
      _lastCount = _vm.history.length;
      _vm.addListener(_onVmChange);
      
      // --- ABONELİK DİNLEYİCİSİ (PASİFİZE EDİLDİ) ---
      // _vm.addListener(autoCheckListener);
      // autoCheckListener(); 
    });
  }

  void _onVmChange() {
    final currentCount = _vm.history.length;
    if (currentCount > _lastCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.fastOutSlowIn,
          );
        }
      });
    }
    _lastCount = currentCount;
  }

 @override
  void dispose() {
    _vm.removeListener(_onVmChange);
    _scrollController.dispose();

    // Çok kritik: Önce flaşı kapat, sonra controller'ı yok et
    if (_isFlashOn) {
      scannerController.toggleTorch();
    }
    scannerController.dispose();

    if (_vm.isComparisonMode) {
      _vm.setComparisonMode(false);
    }

    super.dispose();
  }



  bool _matchesFilter(DateTime createdAt, TimeFilterPreset preset) {
    final now = DateTime.now();
    switch (preset) {
      case TimeFilterPreset.all: return true;
      case TimeFilterPreset.last1Hour: return createdAt.isAfter(now.subtract(const Duration(hours: 1)));
      case TimeFilterPreset.today:
        return createdAt.year == now.year && createdAt.month == now.month && createdAt.day == now.day;
      case TimeFilterPreset.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        return createdAt.year == yesterday.year && createdAt.month == yesterday.month && createdAt.day == yesterday.day;
    }
  }

  // Seçilen zaman filtresini kaydeder ve view model'e tarih aralığı olarak iletir
  void _applyTimeFilter(QrScanViewModel vm, TimeFilterPreset preset) {
    setState(() => _selectedFilter = preset);
    final now = DateTime.now();
    switch (preset) {
      case TimeFilterPreset.all:
        vm.setDateFilter(null, null);
        break;
      case TimeFilterPreset.last1Hour:
        vm.setDateFilter(now.subtract(const Duration(hours: 1)), null);
        break;
      case TimeFilterPreset.today:
        vm.setDateFilter(DateTime(now.year, now.month, now.day), null);
        break;
      case TimeFilterPreset.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        vm.setDateFilter(
          DateTime(yesterday.year, yesterday.month, yesterday.day),
          DateTime(now.year, now.month, now.day),
        );
        break;
    }
  }

  Future<bool?> _openLiveScanner({String mode = 'normal'}) async {
    // Kamera ekranını dikeyde kilitli tut: telefon 45 derecenin üzerinde
    // döndüğünde mobile_scanner yön hesaplaması bozulup görüntüyü yanlış
    // eksende (yatayı dikeymiş gibi) basıyor. Dönüşe izin vermeyerek
    // bu hesaplamanın hiç tetiklenmesini engelliyoruz.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    if (!mounted) return null;

    // Yeni bir tarama oturumu başlat (Eski çizimleri temizle)
    _vm.clearCurrentSession();

    bool isCameraRefreshing = false;
    bool hasScannedIts = false;
    _initScanner();

    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, innerSetState) {
            return PopScope(
            // Geri tuşuyla çıkılırsa ekranı tekrar dikey moda kilitle
            onPopInvoked: (didPop) {
              if (didPop) {
                SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
              }
            },
            child: ChangeNotifierProvider.value(
              value: _vm,
              child: Scaffold(
                appBar: AppBar(
                  title: Consumer<QrScanViewModel>(
                    builder: (_, vm, __) => Text(
                      mode == 'itssorgu' 
                          ? "İTS Sorgulama" 
                          : (vm.isComparisonMode ? "Stok Karşılaştırma" : "Hızlı Tarama"),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  backgroundColor: mode == 'itssorgu' 
                      ? Colors.teal.shade700 
                      : (_vm.isComparisonMode ? Colors.orange.shade800 : const Color(0xFFD32F2F)),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ),
                body: Stack(
                  children: [
                    // --- 1. KAMERA KATMANI ---
                    if (!isCameraRefreshing)
                      MobileScanner(
                        key: ValueKey('scanner_${_colorMode}_${scannerController.hashCode}'),
                        fit: BoxFit.fitHeight,
                        controller: scannerController,
                      placeholderBuilder: (context) => Container(color: Colors.black),
                      errorBuilder: (context, error) => Container(
                        color: Colors.black,
                        child: const Center(child: Icon(Icons.error, color: Colors.white)),
                      ),
                      onDetect: (capture) async {
                        if (!mounted) return;
                        if (mode == 'itssorgu') {
                          if (!hasScannedIts && capture.barcodes.isNotEmpty) {
                            final String? rawValue = capture.barcodes.first.rawValue;
                            if (rawValue != null) {
                              hasScannedIts = true;
                              final parsed = Gs1Parser.parse(rawValue);
                              final gtin = parsed.gtin;
                              final sn = parsed.serialNo;
                              final lot = parsed.batchNo;
                              final skt = parsed.expiryDate;
                              final userId = Provider.of<AuthViewModel>(context, listen: false).userId?.toString() ?? "guest";
                              final String? ucKodu = await ItsStatusService.instance.checkDrugStatus(
                                userId: userId,
                                gtin: gtin ?? "",
                                sn: sn ?? "",
                                lot: lot ?? "",
                                skt: skt?.toIso8601String() ?? "",
                              );
                              if (context.mounted) {
                                await scannerController.stop();
                                if (!context.mounted) return;
                                Navigator.pop(context, true);
                                if (ucKodu != null && mounted) {
                                  showItsDialog(this.context, _vm, ucKodu, "00000", gtin ?? "", sn ?? "");
                                }
                              }
                            }
                          }
                        } else {
                          _vm.onBarcodesDetected(capture);
                        }
                      },
                    ),

                    // --- 2. ÇİZİM KATMANI (YEŞİL/KIRMIZI KUTULAR) ---
                    if (!isCameraRefreshing)
                      Consumer<QrScanViewModel>(
                        builder: (context, vm, child) {
                          return RepaintBoundary(
                          child: CustomPaint(
                            size: MediaQuery.of(context).size,
                            painter: LiveBarcodePainter(
                              barcodes: vm.detectedBarcodes,
                              imageSize: vm.lastImageSize,
                              barcodeColors: vm.getBarcodeColors(),
                              scannedBarcodes: vm.alreadyScannedValues,
                              context: context,
                            ),
                          ),
                        );
                      },
                    ),

                    // --- 3. FLAŞ BUTONU (v7.1.4 GÜNCEL VERSİYON) ---
                    if (!isCameraRefreshing)
                      Positioned(
                        top: 100,
                        right: 20,
                        child: ValueListenableBuilder<MobileScannerState>(
                        // Yeni sürümlerde controller'ın kendisi bir ValueListenable'dır
                        valueListenable: scannerController,
                        builder: (context, state, child) {
                          // Donanımdan gelen gerçek flaş durumu
                          final bool isFlashOn = state.torchState == TorchState.on;

                          return GestureDetector(
                            onTap: () async {
                              try {
                                await scannerController.toggleTorch();
                                // v7+'da toggleTorch sonrası state otomatik güncellenir
                              } catch (e) {
                                debugPrint("Flaş hatası: $e");
                              }
                            },
                            child: CircleAvatar(
                              radius: 25,
                              // Duruma göre renk değişimi
                              backgroundColor: isFlashOn ? Colors.white : Colors.black54,
                              child: Icon(
                                isFlashOn ? Icons.flash_on : Icons.flash_off,
                                color: isFlashOn ? Colors.black : Colors.white,
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // --- 4. TERS RENK (INVERT) BUTONU (İÇERİDE YENİLEME) ---
                    Positioned(
                      top: 170, right: 20,
                      child: GestureDetector(
                        onTap: () async {
                          // 1. Ekrandan kamerayı kaldır (Unmount olmasını sağla)
                          innerSetState(() {
                            isCameraRefreshing = true;
                          });

                          // Döngü: normal -> invert -> hybrid -> normal ...
                          _colorMode = _ScanColorMode.values[
                              (_colorMode.index + 1) % _ScanColorMode.values.length];

                          // 2. Widget tree'nin güncellenip eski controller'ı dinleyen widget'ları sökmesi için çok kısa bir bekleme yapıyoruz. 
                          // Bu bekleme dispose() çağrısına bağlı 'kırmızı hata ekranını' kesinlikle çözecek.
                          await Future.delayed(const Duration(milliseconds: 75));

                          try {
                            // 3. Artık güvenle durdurup silebiliriz.
                            await scannerController.stop();
                            await scannerController.dispose();
                            
                            // 4. Donanımsal kilitlenmeyi önlemek için kısa bir nefes payı
                            await Future.delayed(const Duration(milliseconds: 250));
                          } catch (e) {
                            debugPrint("Stop/Dispose Hatası: $e");
                          }

                          // 5. Yeni özelliklerle controller'ı başlat.
                          _initScanner();

                          // 6. Kamerayı ekrana geri bas.
                          if (context.mounted) {
                            innerSetState(() {
                              isCameraRefreshing = false;
                            });
                          }
                        },
                        child: _buildColorModeAvatar(_colorMode),
                      ),
                    ),

                    // --- YENİLENİRKEN ÇIKACAK LOADING EKRANI ---
                    if (isCameraRefreshing)
                      Container(
                        color: Colors.black.withOpacity(0.8),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: Colors.orangeAccent),
                              SizedBox(height: 16),
                              Text("Lütfen bekleyin...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),

                    // --- 5. ALT AKSİYON PANELİ VE KAPAT BUTONU (TAM HALİ) ---
                    Positioned(
                      bottom: 75,
                      left: 20, right: 20,
                      child: Consumer<QrScanViewModel>(
                        builder: (context, vm, child) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (vm.isComparisonMode) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    GestureDetector(
                                      onTap: () => _showResetSessionDialog(context, vm),
                                      child: _buildScanCounter("Bu Oturum", vm.sessionScanCount),
                                    ),
                                    const SizedBox(width: 12),
                                    _buildScanCounter("Toplam", vm.totalComparisonScanned),
                                  ],
                                ),
                                const SizedBox(height: 8),
                              ] else if (mode == 'normal') ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    GestureDetector(
                                      onTap: () => _showResetSessionDialog(context, vm),
                                      child: _buildScanCounter("Bu Oturum", vm.normalSessionScanCount),
                                    ),
                                    const SizedBox(width: 12),
                                    _buildScanCounter("Toplam", vm.normalTotalScanned),
                                  ],
                                ),
                                const SizedBox(height: 8),
                              ],
                              Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15), // ✅ yükseklik azaltıldı
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(15)),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  mode == 'itssorgu'
                                      ? "Lütfen sorgulanacak ürünü kameraya gösterin."
                                      : (vm.isComparisonMode 
                                          ? "Kutuları okutun. Eşleşmeyenler kırmızı yanar." 
                                          : "Karekodu kameraya gösterin.\n${_colorModeHintText(_colorMode)}"),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontSize: 12), // ✅ biraz küçültüldü
                                ),
                                const SizedBox(height: 8), // ✅ azaltıldı
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: Icon(vm.isComparisonMode ? Icons.assignment_turned_in : Icons.close),
                                    label: Text(
                                      vm.isComparisonMode ? "RAPORU GÖR & BİTİR" : "KAPAT",
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: vm.isComparisonMode ? Colors.orange.shade800 : Colors.red.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 7), // ✅ küçültüldü
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () {
                                      if (vm.isComparisonMode) {
                                        vm.setComparisonMode(false);
                                        Navigator.pop(context, 'show_comparison');
                                      } else {
                                        Navigator.pop(context, false);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            );
          },
        ),
      ),
    );

    if (result == 'show_comparison' && mounted) {
      final pageResult = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StockComparisonPage(vm: _vm)),
      );
      if (mounted && pageResult == 'resume') {
        _vm.resumeComparisonMode();
        _openLiveScanner();
      } else if (mounted && pageResult == 'show_summary') {
        final data = _vm.targetInventory;
        _showSummaryDialog(context, data.length, data.values.fold(0, (a, b) => a + b), _vm);
      }
    }

    return result is bool ? result : null;
  }


  @override
  Widget build(BuildContext context) {
    final vm = context.watch<QrScanViewModel>();
    final timeFilteredList = vm.history.where((r) => _matchesFilter(r.createdAt, _selectedFilter)).toList();
    final filteredResults = _groupByProductName(vm.aggregate(timeFilteredList));

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Eczane Paneli', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('İlaç Takip & Sorgulama', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
          ],
        ),
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        actions: [
          // ✅ YENİ: ITS SORGULAMA BUTONU
          Container(
            decoration: BoxDecoration(
              color: const ui.Color.fromARGB(255, 203, 207, 210).withOpacity(0.25), // Arka plan rengi ve şeffaflık
              shape: BoxShape.circle,                // Yuvarlak
            ),
            padding: const EdgeInsets.all(8),       // İç boşluk
            child: InkWell(
              borderRadius: BorderRadius.circular(50), // Tıklama efekti için yuvarlak
              onTap: () => _handleItsCheck(context, vm),
              child: Image.asset(
                'assets/itsicon.png',
                height: 25,
                width: 25,
              ),
            ),
          ),
          // ✅ YENİ: KARŞILAŞTIRMALI SAYIM (CHECKLIST) İKONU
          _buildActionIcon(
            icon: Icons.fact_check_outlined,
            onPressed: () async {
              if (vm.hasActiveStockSession) {
                final ctx = context;
                final result = await Navigator.push(
                  ctx,
                  MaterialPageRoute(builder: (_) => StockComparisonPage(vm: vm)),
                );
                if (!ctx.mounted) return;
                if (result == 'resume') {
                  _vm.resumeComparisonMode();
                  _openLiveScanner();
                } else if (result == 'show_summary') {
                  final data = _vm.targetInventory;
                  _showSummaryDialog(ctx, data.length, data.values.fold(0, (a, b) => a + b), _vm);
                }
              } else {
                _showFileUploadDialog(context, vm);
              }
            },
          ),
          // ✅ PAYLAŞ BUTONU
          _buildActionIcon(
            icon: Icons.share_rounded,
            onPressed: () => showExportOptionsSheet(context, vm),
          ),
          // ✅ İSTATİSTİK BUTONU
          _buildActionIcon(
            icon: Icons.bar_chart_rounded,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QrTypeStatsPage(
                    history: vm.history, // Sadece vm.history gönderiyoruz
                  ),
                ),
              );
            },
          ),
          // ✅ AYARLAR BUTONU
          _buildActionIcon(
            icon: Icons.settings_rounded,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: vm,
                    child: SettingsPage(vm: vm),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFD32F2F),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: _buildScanSection(vm),
          ),
          Expanded(
            child: Column(
              children: [
                const SizedBox(height: 10),
                if (vm.hasActiveStockSession)
                  GestureDetector(
                    onTap: () async {
                      final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => StockComparisonPage(vm: vm)));
                      if (!context.mounted) return;
                      if (result == 'resume') {
                        _vm.resumeComparisonMode();
                        _openLiveScanner();
                      } else if (result == 'show_summary') {
                        final data = _vm.targetInventory;
                        _showSummaryDialog(context, data.length, data.values.fold(0, (a, b) => a + b), _vm);
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB71C1C).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFB71C1C).withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 18, color: Color(0xFFB71C1C)),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              "Yarım kalan stok sayımı var",
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFB71C1C)),
                            ),
                          ),
                          const Text("Devam et →", style: TextStyle(fontSize: 12, color: Color(0xFFB71C1C))),
                        ],
                      ),
                    ),
                  ),
                ScanSearchRow(onChanged: vm.updateSearchQuery),
                ScanTimeFilterBar(
                  selected: _selectedFilter,
                  onSelected: (preset) => _applyTimeFilter(vm, preset),
                  hasItems: vm.history.isNotEmpty,
                  onClearHistory: () => _showDeleteDialog(context, vm),
                ),
                Expanded(
                  child: filteredResults.isEmpty
                      ? const ScanEmptyState()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                          itemCount: filteredResults.length,
                          itemBuilder: (context, index) => ScanResultCard(
                            item: filteredResults[index],
                            onDelete: () => _showSingleDeleteConfirm(this.context, vm, filteredResults[index]),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleItsCheck(BuildContext context, QrScanViewModel vm) async {
    // 1️⃣ AuthViewModel hazır olana kadar bekle
    final authVm = Provider.of<AuthViewModel>(context, listen: false);

    // Eğer userId henüz null ise küçük bir gecikme ile tekrar dene
    String? userId = authVm.userId?.toString();
    if (userId == null) {
      await Future.delayed(const Duration(milliseconds: 200));
      userId = authVm.userId?.toString();
    }

    // 2️⃣ Kullanıcı ID'sini string hâline getiriyoruz
    final userIdStr = userId?.toString() ?? "guest";

    // 3️⃣ SharedPreferences’ten doğru key ile verileri alıyoruz
    final credentials = await ItsCredentialStore.instance.read(userIdStr);
    String gln = credentials.gln;
    String pass = credentials.password;

    debugPrint("🔍 [ITS-CHECK] Kontrol ediliyor - ID: $userIdStr, GLN: $gln, Pass: ${pass.isNotEmpty ? '******' : ''}");

    // 4️⃣ Eksik bilgi varsa kullanıcıyı yönlendir
    if (gln.isEmpty || pass.isEmpty) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 10),
              Text("Bilgi Eksik"),
            ],
          ),
          content: const Text(
            "ITS sorgusu yapabilmeniz için profil ayarlarından GLN ve Şifre bilgilerinizi girmeniz gerekmektedir.",
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Dialogu kapat
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AccountDetailsPage(vm: vm),
                  ),
                );
              },
              child: const Text(
                "AYARLARA GİT",
                style: TextStyle(fontWeight: FontWeight.bold, color: const Color(0xFFE53935)),
              ),
            ),
          ],
        ),
      );
    } else {
      // 5️⃣ Veriler hazırsa ITS modunu aç
      debugPrint("✅ Bilgiler Tam: Kamera ITS modunda açılıyor...");
      await _openLiveScanner(mode: 'itssorgu');
    }
  }

  void showItsDialog(BuildContext context, QrScanViewModel vm, String itsMessage, String uc, String gtin, String sn) {
    // Başarı durumunu kontrol et (00000 başarılı, diğerleri genellikle hata/uyarıdır)
    bool isSuccess = uc == '00000' || uc == '40001';
    final Color statusBg = isSuccess ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- ÜST DURUM ÇUBUĞU ---
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        isSuccess ? Icons.verified_user_rounded : Icons.gpp_bad_rounded,
                        size: 50,
                        color: const Color(0xFFB71C1C),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "İTS SORGULAMA",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Color(0xFFB71C1C),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // --- MESAJ KISMI (Backend'den gelen hazır mesaj) ---
                    Text(
                      itsMessage.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB71C1C),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // --- VERİ KUTUCUKLARI ---
                    _buildInfoRow(Icons.qr_code_2_rounded, "GTIN", gtin),
                    const SizedBox(height: 8),
                    _buildInfoRow(Icons.pin_rounded, "S/N", sn),

                    // --- IP ADRESİ (Sadece yetki hatasında gösterilir) ---
                    if (itsMessage.contains("yetkilendirme") || uc == 'HATA_ERISIM') ...[
                      const SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blueGrey.withOpacity(0.1)),
                        ),
                        child: FutureBuilder<String>(
                          future: ItsStatusService.instance.getPublicIP(),
                          builder: (context, snapshot) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.language_rounded, size: 16, color: Colors.blueGrey),
                                const SizedBox(width: 8),
                                Text(
                                  "BAĞLANTI IP: ${snapshot.data ?? 'Sorgulanıyor...'}",
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 25),

                    // --- BUTON ---
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFB71C1C),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          "ANLADIM",
                          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Bilgi satırlarını oluşturmak için yardımcı widget
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFFB71C1C)),
          const SizedBox(width: 10),
          Text(
            "$label:",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ KOYU MEDİKAL TEMALI DOSYA YÜKLEME PANELİ
  void _showFileUploadDialog(BuildContext context, QrScanViewModel vm) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B262C), // Derin Lacivert/Siyah
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Küçük bir tutamaç çizgisi
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(10)),
              ),
              const SizedBox(height: 20),
              const Text(
                "Stok Karşılaştırma",
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                "Karşılaştırmalı sayım için 'Barkod' ve 'Miktar' sütunlarını içeren Excel dosyasını yükleyiniz.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFBBE1FA), fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 30),
              
              // ✅ TIKLANABİLİR YÜKLEME ALANI (GÜNCEL)
              InkWell(
                onTap: () async {
                  // 1. Önce dosyayı seçiyoruz (Panel hala açık kalsın ki context kopmasın)
                  Map<String, int>? loadedData;
                  try {
                    loadedData = await vm.pickExcelFile();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red),
                      );
                    }
                  }

                  // 2. Dosya seçme işlemi (iptal veya seçim) bittikten sonra alt paneli kapat
                  if (context.mounted) {
                    Navigator.pop(context); 
                  }

                  // 3. UI'ın kendine gelmesi için çok kısa bir bekleme (Loglardaki çakışmayı önler)
                  await Future.delayed(const Duration(milliseconds: 200));

                  // 4. Veri kontrolü ve Diyalog gösterimi
                  if (context.mounted) {
                    if (loadedData != null && loadedData.isNotEmpty) {
                      int products = loadedData.length;
                      int totalQty = loadedData.values.fold(0, (a, b) => a + b);
                      
                      // Diyaloğu sayfanın ana context'i ile çağırıyoruz
                      _showSummaryDialog(context, products, totalQty, vm);
                    } else if (loadedData == null) {
                      // Kullanıcı dosyayı seçmeden geri çıktıysa SnackBar göstermeye gerek olmayabilir
                      debugPrint("Dosya seçimi kullanıcı tarafından iptal edildi.");
                    } else {
                      // Dosya seçildi ama içi boşsa veya hatalıysa
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Geçerli bir Excel verisi bulunamadı."),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    }
                  }
                },
                child: Container(
                  // ... senin mevcut tasarım kodların (değiştirme) ...
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFEF5350), width: 1.5, style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(20),
                    color: const Color(0xFFB71C1C).withOpacity(0.3),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.upload_file_rounded, size: 48, color: Color(0xFFEF5350)),
                      SizedBox(height: 12),
                      Text(
                        "Excel Dosyası Seçin",
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 4),
                      Text(
                        ".xlsx veya .xls formatında",
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }

  // Eski hali: void _showSummaryDialog(BuildContext context, int products, int quantity)
  // GÜNCEL KOD:
  void _showSummaryDialog(BuildContext context, int products, int quantity, QrScanViewModel vm) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 10,
        backgroundColor: Colors.white,
        child: Stack( // Çarpı butonunu üstte tutmak için Stack ekledik
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Üst Kısım: Başarı İkonu
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.assignment_turned_in_rounded,
                      color: Colors.green,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // 2. Başlık
                  const Text(
                    "Veriler Hazır!",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // 3. Bilgi Kartı
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryItem("Ürün Tipi", products.toString(), Icons.category_outlined),
                        Container(width: 1, height: 30, color: Colors.grey.shade300),
                        _buildSummaryItem("Toplam Adet", quantity.toString(), Icons.inventory_2_outlined),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // 4. Açıklama Metni
                  const Text(
                    "Excel listesi başarıyla yüklendi. Şimdi kamerayı açarak sayıma başlayabilirsiniz.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  
                  // 5. Ana Buton
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2C3E50),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        vm.setComparisonMode(true);
                        Navigator.pop(dialogContext);
                        _openLiveScanner();
                      },
                      child: const Text(
                        "Hadi Başlayalım",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // ÇARPI BUTONU 
            Positioned(
              right: 8,
              top: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.grey),
                onPressed: () => Navigator.pop(dialogContext), // Sadece dialogu kapatır
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Yardımcı Widget: Bilgi öğelerini düzgün hizalamak için
  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.blueGrey),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
        ),
      ],
    );
  }

  Widget _buildActionIcon({required IconData icon, required VoidCallback onPressed, Color color = Colors.white}) {
    return IconButton(
      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: color),
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildScanSection(QrScanViewModel vm) {
    return Container(
      width: double.infinity,
      height: 135,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: vm.isProcessing
            ? const Center(child: CircularProgressIndicator())
            : InkWell(
                    onTap: () => _openLiveScanner(),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_rounded, size: 50, color: const Color(0xFFEF5350)),
                        const SizedBox(height: 12),
                        const Text('Yeni İlaç Tara', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFFE53935))),
                        const Text('Kamerayı açmak için dokunun', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
      ),
    );
  }

  void _showSingleDeleteConfirm(BuildContext context, QrScanViewModel vm, QrLookupResultWithCount item) {
    final String? productName = item.qr.data?.productName;
    final String displayName = productName != null
        ? productName.toUpperCase()
        : item.qr.value;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: EdgeInsets.zero,
        title: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0xFF1B262C),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: const Row(
            children: [
              Icon(Icons.delete_forever_rounded, color: Colors.white),
              SizedBox(width: 12),
              Text("Ürünü Sil", style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            '"$displayName" listeden silinecek. Emin misiniz?',
            style: const TextStyle(color: Color(0xFFB71C1C), fontWeight: FontWeight.w500),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("VAZGEÇ", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(context);
              if (productName != null) {
                vm.removeByProductName(productName);
              } else {
                vm.removeQrResultByValue(item.qr.value);
              }
            },
            child: const Text("EVET, SİL", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, QrScanViewModel vm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: EdgeInsets.zero,
        title: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0xFF1B262C), // Uygulama ana rengi (Navy)
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: const Row(
            children: [
              Icon(Icons.auto_delete_rounded, color: Colors.white),
              SizedBox(width: 12),
              Text("Geçmişi Temizle", style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
        ),
        content: const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text(
            "Tüm tarama geçmişiniz kalıcı olarak silinecektir. Bu işlemi onaylıyor musunuz?",
            style: TextStyle(color: Color(0xFFB71C1C), fontWeight: FontWeight.w500),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("VAZGEÇ", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              vm.clearAllHistory();
              Navigator.pop(context);
            },
            child: const Text("EVET, SİL", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }


  void _showResetSessionDialog(BuildContext context, QrScanViewModel vm) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: EdgeInsets.zero,
        title: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0xFF1B262C),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.restart_alt_rounded, color: Colors.white),
              SizedBox(width: 12),
              Text("Oturumu Sıfırla", style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
        ),
        content: const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text(
            "Bu oturumdaki tüm taramaları silmek istediğinize emin misiniz?",
            style: TextStyle(color: Color(0xFFB71C1C), fontWeight: FontWeight.w500),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("VAZGEÇ", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              vm.resetSessionCount();
              Navigator.pop(dialogContext);
            },
            child: const Text("EVET, SİFIRLA", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildScanCounter(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  List<QrLookupResultWithCount> _groupByProductName(List<QrLookupResultWithCount> items) {
    final Map<String, QrLookupResultWithCount> nameToGroup = {};
    final List<QrLookupResultWithCount> result = [];

    for (final item in items) {
      if (!item.qr.found) {
        result.add(item);
        continue;
      }
      final name = item.qr.data?.productName;
      if (name == null || name.isEmpty) {
        result.add(item);
        continue;
      }
      if (!nameToGroup.containsKey(name)) {
        final grouped = QrLookupResultWithCount(
          qr: item.qr,
          createdAt: item.createdAt,
          count: item.count,
          isOffline: item.isOffline,
        );
        nameToGroup[name] = grouped;
        result.add(grouped);
      } else {
        nameToGroup[name]!.count += item.count;
      }
    }

    return result;
  }
}


// ✅ CANLI TARAMA ESNASINDA KAREKODU BOYAYAN SINIF (GÜNCELLENMİŞ)
class LiveBarcodePainter extends CustomPainter {
  final List<Barcode> barcodes;
  final Size? imageSize; 
  final Map<String, Color> barcodeColors;
  final Set<String> scannedBarcodes;
  final BuildContext context;

  LiveBarcodePainter({
    required this.barcodes,
    this.imageSize,
    required this.barcodeColors,
    required this.scannedBarcodes,
    required this.context,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == null || barcodes.isEmpty) return;

    // 1. Dinamik Ölçekleme Hesabı
    // Kamera görüntüsünün ekranı (BoxFit.cover gibi) tam doldurması için gereken oran.
    // Artık inputWidth/inputHeight ayrımı yok, imageSize neyse o kabul edilir.
    final double scaleX = size.width / imageSize!.width;
    final double scaleY = size.height / imageSize!.height;
    
    // Görüntüyü ekranın en dar kenarına göre büyütüp boşluk bırakmamak için 'max' kullanıyoruz.
    final double scale = scaleX > scaleY ? scaleX : scaleY;

    // 2. Ortalama (Centering) Hesabı
    // Görüntü ekrandan büyükse (cover olduğu için taşacaktır), 
    // koordinatların kaymaması için bu taşma miktarını (offset) bulmalıyız.
    final double offsetX = (size.width - imageSize!.width * scale) / 2;
    final double offsetY = (size.height - imageSize!.height * scale) / 2;

    for (final barcode in barcodes) {
      final corners = barcode.corners;
      final rawValue = barcode.rawValue;
      if (corners == null || rawValue == null) continue;

      Color baseColor = barcodeColors[rawValue] ?? Colors.greenAccent;

      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = baseColor.withOpacity(0.3);

      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..color = baseColor;

      // 3. Koordinat Dönüşümü
      // Kameranın (0,0) noktası ile ekranın (0,0) noktasını scale ve offset ile eşitliyoruz.
      final List<Offset> transformedCorners = corners.map((corner) {
        return Offset(
          (corner.dx * scale) + offsetX,
          (corner.dy * scale) + offsetY,
        );
      }).toList();

      final path = Path()..addPolygon(transformedCorners, true);
      
      canvas.drawPath(path, paint);
      canvas.drawPath(path, borderPaint);

      // --- Zaten taranmışsa çarpı (X) işareti çiz ---
      if (scannedBarcodes.contains(rawValue) && transformedCorners.length >= 4) {
        final crossPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..color = baseColor;
          
        canvas.drawLine(transformedCorners[0], transformedCorners[2], crossPaint);
        canvas.drawLine(transformedCorners[1], transformedCorners[3], crossPaint);
      }
    }
  }

  @override
  bool shouldRepaint(LiveBarcodePainter oldDelegate) => true;
}
