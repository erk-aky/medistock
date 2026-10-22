import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ 1. EKLEME: Ekran kilitleme için gerekli
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import yollarını kendi proje yapına göre kontrol et:
import 'features/auth/login_page.dart';
import 'features/qr_scan/qr_scan_page.dart';
import 'features/qr_scan/qr_scan_view_model.dart';
import 'features/auth/auth_view_model.dart';
import 'core/network/api_client.dart';
import 'core/network/token_store.dart';
import 'core/services/auth_service.dart';
import 'features/db_sync/db_sync_page.dart';

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
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();

  bool _authChecked = false;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    ApiClient.onSessionExpired = _handleSessionExpired;
    _bootstrap();
  }

  // Oturum yenilenemezse kullanıcıyı bilgilendirip giriş ekranına döndürür
  Future<void> _handleSessionExpired() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.context.read<AuthViewModel>().logout();
    navigator.pushNamedAndRemoveUntil('/login', (route) => false);
    _messengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text(ApiClient.sessionExpiredMessage)),
    );
  }

  Future<bool> _checkLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();

    // --- TERMINAL LOGLARI ---
    final loggedIn = await TokenStore.instance.hasSession();
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

  // Giriş yapılmışsa önce veritabanı senkronuna, yapılmamışsa giriş ekranına yönlendirir
  Future<void> _bootstrap() async {
    final loggedIn = await _checkLoggedIn();
    if (mounted) {
      setState(() {
        _loggedIn = loggedIn;
        _authChecked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR App',
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
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
    if (!_authChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _loggedIn ? const DbSyncPage() : const LoginPage();
  }
}
