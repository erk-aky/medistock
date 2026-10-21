import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ 1. EKLEME: Ekran kilitleme için gerekli
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import yollarını kendi proje yapına göre kontrol et:
import 'features/auth/login_page.dart';
import 'features/qr_scan/qr_scan_page.dart';
import 'features/qr_scan/qr_scan_view_model.dart';
import 'features/auth/auth_view_model.dart';
import 'core/services/auth_service.dart';
import 'core/services/db_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 2. EKLEME: Uygulamayı sadece DİKEY (Portrait) modda çalışacak şekilde kilitliyoruz.
  // Bu satır sayesinde telefon yan çevrilse bile kamera ve UI bozulmaz.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,   // Sola Yatık
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    MultiProvider(
      providers: [
        // 1. Auth İşlemleri İçin
        ChangeNotifierProvider(
          create: (_) => AuthViewModel(authService: AuthService()),
        ),
        // 2. QR ve Sayaç İşlemleri İçin
        ChangeNotifierProvider(
          create: (_) => QrScanViewModel()..loadSavedResults(), 
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final DbSyncService _syncService = DbSyncService();

  bool _authChecked = false;
  bool _loggedIn = false;
  bool _isUpdatingDb = false;
  String? _dbSyncMessage;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<bool> _checkLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();

    // --- TERMINAL LOGLARI ---
    final loggedIn = prefs.getBool('isLoggedIn') ?? false;
    final trialEnd = prefs.getString('trialEndDate');

    print("-----------------------------------------");
    print("🚀 UYGULAMA BAŞLATILDI");
    print("👤 Giriş Durumu: $loggedIn");
    print("⏳ Kayıtlı Bitiş Tarihi: $trialEnd");

    if (trialEnd != null) {
      DateTime? endDate = DateTime.tryParse(trialEnd);
      if (endDate != null) {
        final now = DateTime.now();
        final diff = endDate.difference(now);
        print("🕒 Şimdiki Zaman: $now");
        print("📊 Kalan Fark: ${diff.inMinutes} dakika");
      }
    }
    print("-----------------------------------------");

    return loggedIn;
  }

  Future<void> _bootstrap() async {
    final loggedIn = await _checkLoggedIn();

    final remoteVersion = await _syncService.getRemoteVersionOrNull();

    if (remoteVersion == null) {
      // Backend'e hiç ulaşılamadı (internet yok / sunucu kapalı) — güncelleme
      // denenemedi, kullanıcıyı bilgilendirip normal akışa devam ediyoruz.
      await _showDbSyncMessageThenContinue(
        "Telefondaki veritabanı güncellenemedi",
        loggedIn: loggedIn,
      );
      return;
    }

    final localVersion = await _syncService.getLocalVersion();
    if (remoteVersion <= localVersion) {
      // Zaten güncel, senkron gerekmiyor.
      if (mounted) {
        setState(() {
          _loggedIn = loggedIn;
          _authChecked = true;
        });
      }
      return;
    }

    // Güncelleme gerekiyor — kullanıcıyı bilgilendiren yükleniyor ekranını göster.
    if (mounted) {
      setState(() {
        _isUpdatingDb = true;
      });
    }

    try {
      await _syncService
          .downloadAndApplyUpdate(remoteVersion)
          .timeout(const Duration(seconds: 60));
      // Başarılı: yükleniyor ekranını sessizce kapatıp devam ediyoruz.
      if (mounted) {
        setState(() {
          _isUpdatingDb = false;
          _loggedIn = loggedIn;
          _authChecked = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUpdatingDb = false;
        });
      }
      await _showDbSyncMessageThenContinue(
        "Telefondaki veritabanı güncellenemedi",
        loggedIn: loggedIn,
      );
    }
  }

  Future<void> _showDbSyncMessageThenContinue(
    String message, {
    required bool loggedIn,
  }) async {
    if (mounted) {
      setState(() {
        _dbSyncMessage = message;
      });
    }
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _dbSyncMessage = null;
        _loggedIn = loggedIn;
        _authChecked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR App',
      theme: ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => const QrScanPage(),
      },
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_dbSyncMessage != null) {
      return _DbSyncStatusScreen(message: _dbSyncMessage!, showSpinner: false);
    }
    if (_isUpdatingDb) {
      return const _DbSyncStatusScreen(
        message:
            "Telefondaki veritabanı güncelleniyor. Güncelleme işlemi birazdan bitecek.",
        showSpinner: true,
      );
    }
    if (!_authChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _loggedIn ? const QrScanPage() : const LoginPage();
  }
}

class _DbSyncStatusScreen extends StatelessWidget {
  const _DbSyncStatusScreen({required this.message, required this.showSpinner});

  final String message;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSpinner) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
              ],
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}