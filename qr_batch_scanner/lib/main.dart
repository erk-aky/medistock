import 'dart:async';

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
import 'core/local/db_helper.dart';

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

  // 🔹 OFFLINE SQLITE INIT
  await DBHelper.init();

  // 🔹 İlaç veritabanını arka planda kontrol et/güncelle (uygulamayı bloklamaz)
  unawaited(DbSyncService().checkAndUpdateIfNeeded());

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      home: FutureBuilder<bool>(
        future: _checkLoggedIn(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          final loggedIn = snapshot.data ?? false;
          return loggedIn ? const QrScanPage() : const LoginPage();
        },
      ),
    );
  }
}