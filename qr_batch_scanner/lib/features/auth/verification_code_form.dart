import 'dart:async';
import 'package:flutter/material.dart';

class VerificationCodeForm extends StatefulWidget {
  final Future<bool> Function(String code) onVerify;
  final Future<bool> Function() onResend;
  final bool isLoading;
  final int? attemptsLeft;
  final String verifyLabel;

  const VerificationCodeForm({
    super.key,
    required this.onVerify,
    required this.onResend,
    required this.isLoading,
    this.attemptsLeft,
    this.verifyLabel = 'Kodu Doğrula',
  });

  @override
  State<VerificationCodeForm> createState() => _VerificationCodeFormState();
}

class _VerificationCodeFormState extends State<VerificationCodeForm> {
  static const int _maxResends = 3;
  static const int _cooldownSeconds = 60;

  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  int _resendCount = 0;
  int _cooldownLeft = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _cooldownLeft = _cooldownSeconds;
    _startTimer();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  // Kod 6 haneliyse doğrulama için üst ekrana iletir
  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.onVerify(_codeController.text.trim());
  }

  // Yeni kod ister, başarılıysa bir hak düşer ve sayaç yeniden başlar
  Future<void> _resend() async {
    if (_resendCount >= _maxResends || _cooldownLeft > 0) return;
    final success = await widget.onResend();
    if (!mounted || !success) return;

    _codeController.clear();
    setState(() {
      _resendCount++;
      _cooldownLeft = _cooldownSeconds;
    });
    _startTimer();
  }

  // Tekrar gönder butonu için geri sayımı başlatır
  void _startTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldownLeft--);
      if (_cooldownLeft <= 0) timer.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final codeUsedUp = widget.attemptsLeft == 0;

    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _codeController,
            enabled: !codeUsedUp,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
            decoration: InputDecoration(
              hintText: '000000',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: Color(0xFFFFCDD2)),
              ),
            ),
            keyboardType: TextInputType.number,
            maxLength: 6,
            validator: (v) => v!.length < 6 ? '6 haneli kodu girin' : null,
          ),
          if (codeUsedUp)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Kod 3 kez yanlış girildi, lütfen yeni kod isteyin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 3,
              ),
              onPressed: (widget.isLoading || codeUsedUp) ? null : _verify,
              child: widget.isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(widget.verifyLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 16),
          _buildResendButton(),
        ],
      ),
    );
  }

  // Kalan hakka ve geri sayıma göre tekrar gönder butonunu çizer
  Widget _buildResendButton() {
    if (_resendCount >= _maxResends) {
      return const Text(
        'Başka hakkınız bulunmamaktadır.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
      );
    }

    final remaining = _maxResends - _resendCount;
    final text = _cooldownLeft > 0
        ? 'Kodu tekrar gönder ($_cooldownLeft sn)'
        : 'Kodu tekrar gönder (kalan hak: $remaining)';

    return TextButton(
      onPressed: (widget.isLoading || _cooldownLeft > 0) ? null : _resend,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
