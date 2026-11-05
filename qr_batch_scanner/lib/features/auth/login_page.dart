import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ 1. SharedPreferences ekledik
import '../../core/services/auth_service.dart';
import 'auth_view_model.dart';
import 'register_page.dart';
import 'forgot_password_page.dart';
import '../db_sync/db_sync_page.dart';
import '../qr_scan/qr_scan_view_model.dart'; // ✅ 2. QrScanViewModel import edildi

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    // ChangeNotifierProvider kaldırıldı, direkt _LoginView döndür
    return const _LoginView();
    }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFFFFEBEE), Colors.white],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 60.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/giris-icon.png',
                      width: 130,
                      height: 130,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Tekrar Hoş Geldiniz',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Lütfen hesabınıza giriş yapın',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 40),

                    TextFormField(
                      controller: _usernameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Kullanıcı Adı veya E-posta',
                        prefixIcon: const Icon(Icons.person_outline),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(color: const Color(0xFFFFCDD2)),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Kullanıcı adı veya e-posta gerekli' : null,
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Şifre',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: const Color(0xFFEF9A9A),
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(color: const Color(0xFFFFCDD2)),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Şifre gerekli' : null,
                    ),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
                          );
                        },
                        child: const Text('Şifremi Unuttum?', style: TextStyle(color: const Color(0xFFE53935))),
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (vm.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Text(vm.error!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                      ),

                    vm.isLoading
                        ? const CircularProgressIndicator()
                        : SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD32F2F),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                elevation: 2,
                              ),
                              onPressed: () async {
                                if (!_formKey.currentState!.validate()) return;
                                final username = _usernameCtrl.text.trim();
                                final password = _passwordCtrl.text;

                                final ok = await vm.login(username, password);
                                if (ok && mounted) {
                                  final prefs = await SharedPreferences.getInstance();

                                  // --- 1. userId, username, email kaydet ---
                                  if (vm.userId != null) await prefs.setInt('userId', vm.userId!);
                                  if (vm.username != null) await prefs.setString('username', vm.username!);
                                  if (vm.email != null) await prefs.setString('email', vm.email!);

                                  // --- 2. trial / subscription bilgileri ---
                                  if (vm.trialEndDate != null) {
                                    await prefs.setString('trialEndDate', vm.trialEndDate!);
                                    await prefs.setString('subscriptionStatus', 'Trialing');
                                  }

                                  // --- 3. QrScanViewModel’i tazeleyelim ---
                                  if (!context.mounted) return;
                                  context.read<QrScanViewModel>().loadSavedResults();

                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(builder: (_) => const DbSyncPage()),
                                  );
                                }
                              },
                              child: const Text('Giriş Yap', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ),
                          ),

                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Hesabınız yok mu?"),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const RegisterPage()),
                            );
                          },
                          child: const Text('Şimdi Kayıt Olun', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}