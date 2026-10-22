import 'package:flutter/material.dart';
import '../../../core/constants/validation_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/auth_service.dart';
import 'verification_code_form.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _isCodeSent = false;
  bool _isLoading = false;
  int? _attemptsLeft;

  @override
  void dispose() {
    _emailController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  void _showMsg(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Aşama 1: Mail Gönder
  Future<void> _sendCode() async {
    if (_emailController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await _authService.forgotPassword(_emailController.text.trim());
      setState(() => _isCodeSent = true);
      _showMsg('6 haneli kod mail adresinize gönderildi.');
    } catch (e) {
      _showMsg(e.toString(), isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Aşama 2: Kodu ve Yeni Şifreyi Onayla
  Future<bool> _resetPassword(String code) async {
    if (_newPasswordController.text.trim().length < minPasswordLength) {
      _showMsg('Şifre en az $minPasswordLength karakter olmalıdır', isError: true);
      return false;
    }
    setState(() => _isLoading = true);
    try {
      await _authService.resetPassword(
        _emailController.text.trim(),
        code,
        _newPasswordController.text.trim(),
      );
      if (!mounted) return true;
      _showMsg('Şifreniz başarıyla güncellendi.');
      Navigator.pop(context); // Giriş ekranına geri dön
      return true;
    } catch (e) {
      if (e is ApiException && mounted) setState(() => _attemptsLeft = e.remainingAttempts);
      if (mounted) _showMsg(e.toString(), isError: true);
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Aynı adrese yeni kod ister, başarılıysa kod deneme hakkı yenilenir
  Future<bool> _resendCode() async {
    setState(() => _isLoading = true);
    try {
      await _authService.forgotPassword(_emailController.text.trim());
      if (!mounted) return true;
      setState(() => _attemptsLeft = null);
      _showMsg('Yeni kod gönderildi, önceki kod artık geçersiz.');
      return true;
    } catch (e) {
      if (mounted) _showMsg(e.toString(), isError: true);
      return false;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: SafeArea(
            child: Column(
              children: [
                // Geri Butonu
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Color(0xFFE53935)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                
                // Üst İkon (Anahtar Simgesi)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE53935).withOpacity(0.1),
                        spreadRadius: 5,
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isCodeSent ? Icons.lock_reset : Icons.mail_outline,
                    size: 60,
                    color: const Color(0xFFE53935),
                  ),
                ),
                const SizedBox(height: 24),
                
                Text(
                  _isCodeSent ? 'Şifrenizi Belirleyin' : 'Şifremi Unuttum',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _isCodeSent 
                    ? 'E-postanıza gelen kodu ve yeni şifrenizi girin.' 
                    : 'Kayıtlı e-posta adresinizi girerek şifre sıfırlama kodu isteyin.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                ),
                const SizedBox(height: 40),

                // E-posta Alanı
                TextField(
                  controller: _emailController,
                  enabled: !_isCodeSent,
                  decoration: InputDecoration(
                    labelText: 'E-posta Adresiniz',
                    prefixIcon: const Icon(Icons.email_outlined),
                    filled: true,
                    fillColor: _isCodeSent ? Colors.grey.shade100 : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(color: const Color(0xFFFFCDD2)),
                    ),
                  ),
                ),

                if (_isCodeSent) ...[
                  const SizedBox(height: 16),
                  // Yeni Şifre Alanı
                  TextField(
                    controller: _newPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Yeni Şifreniz',
                      prefixIcon: const Icon(Icons.lock_outline),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: const Color(0xFFEF9A9A)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  VerificationCodeForm(
                    onVerify: _resetPassword,
                    onResend: _resendCode,
                    isLoading: _isLoading,
                    attemptsLeft: _attemptsLeft,
                    verifyLabel: 'Şifreyi Güncelle',
                  ),
                ] else ...[
                  const SizedBox(height: 40),

                  // İşlem Butonu
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 3,
                      ),
                      onPressed: _isLoading ? null : _sendCode,
                      child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Doğrulama Kodu Gönder',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}