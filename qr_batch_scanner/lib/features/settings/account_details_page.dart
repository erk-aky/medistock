import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../qr_scan/qr_scan_view_model.dart';
import '../auth/auth_view_model.dart';

class AccountDetailsPage extends StatefulWidget {
  final QrScanViewModel vm;
  const AccountDetailsPage({super.key, required this.vm});

  @override
  State<AccountDetailsPage> createState() => _AccountDetailsPageState();
}

class _AccountDetailsPageState extends State<AccountDetailsPage> {
  late TextEditingController _usernameController;
  late TextEditingController _emailController;
  late TextEditingController _pharmacyNameController;
  late TextEditingController _glnController;
  late TextEditingController _itsPasswordController;

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _isSaving = false;

  AuthViewModel? _authVm;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _emailController = TextEditingController();
    _pharmacyNameController = TextEditingController();
    _glnController = TextEditingController();
    _itsPasswordController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authVm = Provider.of<AuthViewModel>(context);
    if (_authVm != authVm) {
      _authVm?.removeListener(_onAuthVmChange);
      _authVm = authVm;
      _authVm!.addListener(_onAuthVmChange);

      if (_usernameController.text.isEmpty) {
        _usernameController.text = _authVm!.username ?? "";
      }
      if (_emailController.text.isEmpty) {
        _emailController.text = _authVm!.email ?? "";
      }
      _currentUserId = _authVm!.userId?.toString();
    }
  }

  void _onAuthVmChange() {
    if (!mounted || _isSaving || (_authVm?.isLoading ?? false)) return;

    final newUsername = _authVm?.username ?? "";
    final newEmail = _authVm?.email ?? "";

    // Eğer kullanıcı şu anda alanı düzenlemiyorsa controller'ı güncelle
    final usernameHasFocus = FocusScope.of(context).hasFocus && _usernameController.selection.isValid;
    if (_usernameController.text != newUsername && !usernameHasFocus) {
      _usernameController.text = newUsername;
    }

    final emailHasFocus = FocusScope.of(context).hasFocus && _emailController.selection.isValid;
    if (_emailController.text != newEmail && !emailHasFocus) {
      _emailController.text = newEmail;
    }
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    String userIdStr = authVm.userId?.toString() ?? "guest";

    final userNameKey = 'local_username_$userIdStr';
    final userEmailKey = 'local_email_$userIdStr';
    final userGlnKey = 'local_gln_$userIdStr';
    final userItsKey = 'local_its_password_$userIdStr';

    final savedUsername = prefs.getString(userNameKey);
    final savedEmail = prefs.getString(userEmailKey);

    if (!mounted) return;
    setState(() {
      _usernameController.text = savedUsername?.isNotEmpty == true ? savedUsername! : (authVm.username ?? "");
      _emailController.text = savedEmail?.isNotEmpty == true ? savedEmail! : (authVm.email ?? "");
      _glnController.text = prefs.getString(userGlnKey) ?? "";
      _itsPasswordController.text = prefs.getString(userItsKey) ?? "";
      _pharmacyNameController.text = "Güneş Eczanesi (Örnek)";
    });

    // opsiyonel: eğer prefs'te yoksa veya VM'deki username'in farklı olduğunu düşünüyorsanız,
    // authVm.fetchAndUpdateProfile(authVm.username ?? _usernameController.text);
  }

  // 🔥 KRİTİK GÜNCELLEME BURADA
  Future<void> _handleUpdate() async {
    if (_glnController.text.isNotEmpty && _glnController.text.length != 13) {
      _showSnackBar("GLN numarası tam 13 hane olmalıdır!", Colors.orange);
      return;
    }

    FocusScope.of(context).unfocus();
    final prefs = await SharedPreferences.getInstance();
    final authVm = Provider.of<AuthViewModel>(context, listen: false);

    final userIdStr = authVm.userId?.toString() ?? "guest";
    
    setState(() {
      _isLoading = true;
      _isSaving = true;
    });

    try {
      // 1. Önce SharedPreferences'a kaydet ve 'await' ile bittiğinden emin ol
      await prefs.setString('local_gln_$userIdStr', _glnController.text);
      await prefs.setString('local_its_password_$userIdStr', _itsPasswordController.text);

      print("✅ Yerel veriler kaydedildi: ${_usernameController.text}");

      // 2. DB Güncelleme İsteği
      final success = await authVm.updateUserInfo(
        newUsername: _usernameController.text,
        newEmail: _emailController.text,
      );

      if (success && mounted) {
        await prefs.setString('local_username_$userIdStr', _usernameController.text);
        await prefs.setString('local_email_$userIdStr', _emailController.text);

        // 3. ViewModel içindeki username'i manuel güncelle (404 hatasını önlemek için)
        // Eğer AuthViewModel içinde set metodu yoksa authVm.fetchAndUpdateProfile doğrudan çağrılır
        
        print("🚀 İstek atılıyor: ${_usernameController.text}");
        
        // Backend'den güncel veriyi çek
        await authVm.fetchAndUpdateProfile(_usernameController.text);
        
        _showSnackBar("Tüm bilgileriniz başarıyla güncellendi!", Colors.green);
      } else if (mounted && authVm.error != null) {
        _showSnackBar(authVm.error!, Colors.redAccent);
      }
    } catch (e) {
      print("❌ HATA: $e");
      _showSnackBar("İşlem sırasında bir hata oluştu.", Colors.redAccent);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSaving = false;
        });
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    _authVm?.removeListener(_onAuthVmChange);
    _usernameController.dispose();
    _emailController.dispose();
    _pharmacyNameController.dispose();
    _glnController.dispose();
    _itsPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color darkNavy = Color(0xFF1B262C);
    const Color medicalBlue = Color(0xFFB71C1C);

    return Scaffold(
      backgroundColor: darkNavy,
      appBar: AppBar(
        title: const Text("Profil Ayarları", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 2)),
                    child: const CircleAvatar(
                      radius: 45,
                      backgroundColor: medicalBlue,
                      child: Icon(Icons.medication_liquid_sharp, size: 40, color: Colors.white),
                    ),
                  ),
                  const CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.green,
                    child: Icon(Icons.check, size: 16, color: Colors.white),
                  )
                ],
              ),
            ),
            const SizedBox(height: 30),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 35),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(35), topRight: Radius.circular(35)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, -5))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader("HESAP BİLGİLERİ (DB)"),
                  _buildField(
                    controller: _usernameController,
                    label: "Kullanıcı Adı",
                    icon: Icons.alternate_email_rounded,
                    hint: "Kullanıcı adınızı seçin",
                  ),
                  const SizedBox(height: 20),
                  _buildField(
                    controller: _emailController,
                    label: "E-Posta Adresi",
                    icon: Icons.mail_outline_rounded,
                    hint: "E-postanızı girin",
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 25), child: Divider(color: Color(0xFFEEEEEE), thickness: 1.5)),
                  _buildSectionHeader("ITS BİLGİLERİ (YEREL)"),
                  _buildField(
                    controller: _glnController,
                    label: "GLN Numarası",
                    icon: Icons.numbers_rounded,
                    hint: "13 Haneli GLN giriniz",
                    keyboardType: TextInputType.number,
                    formatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(13),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildField(
                    controller: _itsPasswordController,
                    label: "İTS Şifresi",
                    icon: Icons.vpn_key_outlined,
                    hint: "İTS Portalı Şifreniz",
                    isPassword: true,
                    obscureText: !_isPasswordVisible,
                    onToggle: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                  ),
                  const SizedBox(height: 40),
                  _isLoading 
                    ? const Center(child: CircularProgressIndicator(color: medicalBlue))
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: medicalBlue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 58),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 4,
                          shadowColor: medicalBlue.withOpacity(0.4),
                        ),
                        onPressed: _handleUpdate,
                        child: const Text("DEĞİŞİKLİKLERİ KAYDET", style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                      ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    bool enabled = true,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggle,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? formatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
          inputFormatters: formatters,
          style: TextStyle(fontWeight: FontWeight.bold, color: enabled ? Colors.black87 : Colors.grey),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontWeight: FontWeight.normal, color: Colors.grey, fontSize: 14),
            prefixIcon: Icon(icon, color: const Color(0xFFB71C1C), size: 22),
            suffixIcon: isPassword 
              ? IconButton(
                  icon: Icon(_isPasswordVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: Colors.grey),
                  onPressed: onToggle,
                )
              : null,
            filled: true,
            fillColor: enabled ? const Color(0xFFF8FAFB) : Colors.grey.shade100,
            contentPadding: const EdgeInsets.all(18),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFB71C1C), width: 1.5)),
          ),
        ),
      ],
    );
  }
}