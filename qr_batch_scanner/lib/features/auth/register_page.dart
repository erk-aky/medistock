import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/validation_constants.dart';
import 'auth_view_model.dart';
import 'verification_code_form.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // Controllerlar
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  // Sayfa Durumu: false ise Kayıt, true ise Onay ekranı
  bool _showVerifyStep = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 1. ADIM: Kayıt İşlemi
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final viewModel = context.read<AuthViewModel>();
    final success = await viewModel.register(
      _usernameController.text.trim(),
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );

    if (mounted) {
      if (success) {
        setState(() => _showVerifyStep = true); // Onay ekranına geç
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Onay kodu e-postanıza gönderildi.'),
            backgroundColor: const Color(0xFFEF5350),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        _showError(viewModel.error ?? 'Kayıt hatası');
      }
    }
  }

  /// 2. ADIM: E-posta Doğrulama İşlemi
  Future<bool> _handleVerify(String code) async {
    final viewModel = context.read<AuthViewModel>();
    final success = await viewModel.verifyCode(code);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('E-posta başarıyla doğrulandı! Giriş yapabilirsiniz.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context); // Her şey bitti, Login'e dön
      } else {
        _showError(viewModel.error ?? 'Kod hatalı veya süresi dolmuş');
      }
    }
    return success;
  }

  // Aynı bilgilerle yeni kod ister, önceki kod geçersiz olur
  Future<bool> _handleResend() async {
    final viewModel = context.read<AuthViewModel>();
    final success = await viewModel.register(
      _usernameController.text.trim(),
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );

    if (!mounted) return success;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yeni kod gönderildi, önceki kod artık geçersiz.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      _showError(viewModel.error ?? 'Kod gönderilemedi');
    }
    return success;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              // Eğer kayıt başarılıysa Verify ekranını, değilse Register ekranını göster
              child: _showVerifyStep ? _buildVerifyUI() : _buildRegisterUI(),
            ),
          ),
        ),
      ),
    );
  }

  /// --- KAYIT ARAYÜZÜ (ADIM 1) ---
  Widget _buildRegisterUI() {
    final viewModel = context.watch<AuthViewModel>();
    return Column(
      key: const ValueKey("RegisterUI"),
      children: [
        _buildHeader(Icons.person_add_outlined, 'Yeni Hesap Oluştur', 'Sağlık yolculuğunuza bugün başlayın'),
        const SizedBox(height: 32),
        Form(
          key: _formKey,
          child: Column(
            children: [
              _customTextField(_usernameController, 'Kullanıcı Adı', Icons.person_outline, isUsername: true),
              const SizedBox(height: 16),
              _customTextField(_emailController, 'E-posta Adresi', Icons.email_outlined, isEmail: true),
              const SizedBox(height: 16),
              _customTextField(_passwordController, 'Şifre', Icons.lock_outline, isPassword: true),
              const SizedBox(height: 40),
              _buildMainButton(
                onPressed: viewModel.isLoading ? null : _handleRegister,
                text: 'Kayıt Ol',
                isLoading: viewModel.isLoading,
              ),
              const SizedBox(height: 24),
              _buildFooterLink("Zaten hesabınız var mı?", "Giriş Yapın", () => Navigator.pop(context)),
            ],
          ),
        ),
      ],
    );
  }

  /// --- DOĞRULAMA ARAYÜZÜ (ADIM 2) ---
  Widget _buildVerifyUI() {
    final viewModel = context.watch<AuthViewModel>();
    return Column(
      key: const ValueKey("VerifyUI"),
      children: [
        _buildHeader(Icons.mark_email_read_outlined, 'E-posta Doğrulama', '${_emailController.text} adresine gönderilen 6 haneli kodu giriniz.'),
        const SizedBox(height: 32),
        VerificationCodeForm(
          onVerify: _handleVerify,
          onResend: _handleResend,
          isLoading: viewModel.isLoading,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _showVerifyStep = false),
          child: const Text("Bilgileri Düzenle / Geri Dön", style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }

  /// --- ORTAK WIDGETLAR ---

  Widget _buildHeader(IconData icon, String title, String subtitle) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Color(0xFFE53935)),
            onPressed: () {
              if (_showVerifyStep) {
                setState(() => _showVerifyStep = false);
              } else {
                Navigator.pop(context);
              }
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0xFFE53935).withOpacity(0.1), spreadRadius: 5, blurRadius: 10)],
          ),
          child: Icon(icon, size: 60, color: const Color(0xFFE53935)),
        ),
        const SizedBox(height: 24),
        Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }

  Widget _customTextField(TextEditingController controller, String label, IconData icon, {bool isEmail = false, bool isPassword = false, bool isUsername = false}) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
      inputFormatters: isUsername ? [UsernameSpaceFormatter()] : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: const Color(0xFFFFCDD2)),
        ),
      ),
      validator: (v) {
        if (v!.isEmpty) return '$label gerekli';
        if (isUsername) return validateUsername(v);
        if (isEmail) return validateEmail(v);
        if (isPassword && v.length < minPasswordLength) return 'Şifre en az $minPasswordLength karakter olmalıdır';
        return null;
      },
    );
  }

  Widget _buildMainButton({required VoidCallback? onPressed, required String text, required bool isLoading}) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD32F2F),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 3,
        ),
        onPressed: onPressed,
        child: isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildFooterLink(String text, String linkText, VoidCallback onTap) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(text),
        TextButton(onPressed: onTap, child: Text(linkText, style: const TextStyle(fontWeight: FontWeight.bold))),
      ],
    );
  }
}