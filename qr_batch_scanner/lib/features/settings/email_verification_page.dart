import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_view_model.dart';
import '../auth/verification_code_form.dart';

class EmailVerificationPage extends StatelessWidget {
  final String newEmail;

  const EmailVerificationPage({super.key, required this.newEmail});

  // Kod doğruysa sayfayı başarıyla kapatır, değilse hatayı gösterir
  Future<bool> _verify(BuildContext context, String code) async {
    final authVm = context.read<AuthViewModel>();
    final success = await authVm.confirmEmailChange(newEmail, code);
    if (!context.mounted) return success;

    if (success) {
      Navigator.pop(context, true);
    } else {
      _showMessage(context, authVm.error ?? 'Kod hatalı veya süresi dolmuş', Colors.redAccent);
    }
    return success;
  }

  // Aynı adrese yeni kod ister, önceki kod geçersiz olur
  Future<bool> _resend(BuildContext context) async {
    final authVm = context.read<AuthViewModel>();
    final success = await authVm.requestEmailChange(newEmail);
    if (!context.mounted) return success;

    if (success) {
      _showMessage(context, 'Yeni kod gönderildi, önceki kod artık geçersiz.', Colors.green);
    } else {
      _showMessage(context, authVm.error ?? 'Kod gönderilemedi', Colors.redAccent);
    }
    return success;
  }

  void _showMessage(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authVm = context.watch<AuthViewModel>();

    return Scaffold(
      appBar: AppBar(title: const Text('E-posta Doğrulama')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            const Icon(Icons.mark_email_read_outlined, size: 60, color: Color(0xFFE53935)),
            const SizedBox(height: 24),
            Text(
              '$newEmail adresine gönderilen 6 haneli kodu giriniz.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            VerificationCodeForm(
              onVerify: (code) => _verify(context, code),
              onResend: () => _resend(context),
              isLoading: authVm.isLoading,
              attemptsLeft: authVm.codeAttemptsLeft,
            ),
          ],
        ),
      ),
    );
  }
}
