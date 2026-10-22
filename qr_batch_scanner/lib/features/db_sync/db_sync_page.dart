import 'package:flutter/material.dart';
import '../../core/network/token_store.dart';
import '../../core/services/db_sync_service.dart';
import '../auth/login_page.dart';
import '../qr_scan/qr_scan_page.dart';

class DbSyncPage extends StatefulWidget {
  const DbSyncPage({super.key});

  @override
  State<DbSyncPage> createState() => _DbSyncPageState();
}

class _DbSyncPageState extends State<DbSyncPage> {
  final DbSyncService _syncService = DbSyncService();

  bool _isUpdating = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _syncThenContinue();
  }

  // Sunucudaki ilaç listesi daha yeniyse telefondaki veritabanını günceller, sonra ana ekrana geçer
  Future<void> _syncThenContinue() async {
    final remoteVersion = await _syncService.getRemoteVersionOrNull();

    if (remoteVersion == null) {
      await _showMessage("Telefondaki veritabanı güncellenemedi");
    } else if (remoteVersion > await _syncService.getLocalVersion()) {
      if (mounted) setState(() => _isUpdating = true);
      try {
        await _syncService.downloadAndApplyUpdate(remoteVersion).timeout(const Duration(seconds: 60));
      } catch (e) {
        await _showMessage("Telefondaki veritabanı güncellenemedi");
      }
    }

    final loggedIn = await TokenStore.instance.hasSession();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => loggedIn ? const QrScanPage() : const LoginPage()),
    );
  }

  // Senkron sonucunu kullanıcıya iki saniye gösterir
  Future<void> _showMessage(String message) async {
    if (!mounted) return;
    setState(() {
      _isUpdating = false;
      _message = message;
    });
    await Future.delayed(const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    final message = _message ??
        (_isUpdating ? "Telefondaki veritabanı güncelleniyor. Güncelleme işlemi birazdan bitecek." : null);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_message == null) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
              ],
              if (message != null)
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
