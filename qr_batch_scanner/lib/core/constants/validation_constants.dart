import 'package:flutter/services.dart';

const int minPasswordLength = 6;
const int minUsernameLength = 3;
const int maxUsernameLength = 50;

final RegExp _usernameAllowed = RegExp(r'^[\p{L}\p{Nd}._-]+$', unicode: true);
final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

// Kullanıcı adı kurala uymuyorsa hata mesajını, uyuyorsa null döner
String? validateUsername(String? value) {
  final username = (value ?? '').trim();
  if (username.length < minUsernameLength || username.length > maxUsernameLength) {
    return 'Kullanıcı adı $minUsernameLength ile $maxUsernameLength karakter arasında olmalıdır';
  }
  if (!_usernameAllowed.hasMatch(username)) {
    return 'Kullanıcı adı yalnızca harf, rakam, nokta, alt çizgi ve tire içerebilir';
  }
  return null;
}

// E-posta biçimi geçersizse hata mesajını, geçerliyse null döner
String? validateEmail(String? value) {
  final email = (value ?? '').trim();
  if (email.isEmpty || !_emailPattern.hasMatch(email)) {
    return 'Geçerli bir e-posta adresi giriniz';
  }
  return null;
}

class UsernameSpaceFormatter extends TextInputFormatter {
  // Yazarken baştaki boşlukları siler, aradaki boşlukları tek alt çizgiye çevirir
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceFirst(RegExp(r'^\s+'), '').replaceAll(RegExp(r'_?\s+'), '_');
    if (text == newValue.text) return newValue;

    final removed = newValue.text.length - text.length;
    final offset = (newValue.selection.end - removed).clamp(0, text.length);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: offset));
  }
}
