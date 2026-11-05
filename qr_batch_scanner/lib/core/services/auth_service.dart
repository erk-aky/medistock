import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../models/user_model.dart';
import '../network/api_client.dart';
import '../network/token_store.dart';

class AuthService {
  final ApiClient _api;
  final TokenStore _tokens;

  AuthService({ApiClient? apiClient, TokenStore? tokenStore})
      : _api = apiClient ?? ApiClient(tokenStore: tokenStore),
        _tokens = tokenStore ?? TokenStore.instance;

  /// ✅ YENİ: E-posta Doğrulama Kodunu Backend'e Gönderir
  /// POST /api/v1/auth/verify-email
  Future<Map<String, dynamic>> verifyEmail(String ticket, String code) async {
    return _api.post(
      ApiConstants.verifyEmail,
      {'ticket': ticket, 'code': code},
      timeout: const Duration(seconds: 15),
    );
  }

  // Kullanıcı adını sunucuda günceller
  Future<Map<String, dynamic>> updateProfile({required String newUsername}) async {
    final decoded = await _api.put(ApiConstants.updateProfile, {'newUsername': newUsername});

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', newUsername);

    return decoded;
  }

  // Yeni e-posta adresine onay kodu gönderilmesini ister
  Future<Map<String, dynamic>> requestEmailChange(String newEmail) async {
    return _api.post(ApiConstants.changeEmailRequest, {'newEmail': newEmail}, timeout: const Duration(seconds: 15));
  }

  // Onay koduyla e-posta değişikliğini tamamlar
  Future<Map<String, dynamic>> confirmEmailChange(String ticket, String code) async {
    return _api.post(ApiConstants.changeEmailConfirm, {'ticket': ticket, 'code': code}, timeout: const Duration(seconds: 15));
  }

  /// ✅ Backend'den Güncel Profil Bilgilerini Çeker
  Future<Map<String, dynamic>> getUserProfile() async {
    final decoded = await _api.get(ApiConstants.me);

    final prefs = await SharedPreferences.getInstance();
    if (decoded['email'] != null) await prefs.setString('email', decoded['email']);
    if (decoded['subscriptionStatus'] != null) await prefs.setString('subscriptionStatus', decoded['subscriptionStatus']);
    if (decoded['trialEndDate'] != null) await prefs.setString('trialEndDate', decoded['trialEndDate']);
    if (decoded['subscriptionEndDate'] != null) await prefs.setString('subscriptionEndDate', decoded['subscriptionEndDate']);
    if (decoded['id'] != null) await prefs.setInt('userId', decoded['id']);

    return decoded;
  }

  /// POST /api/v1/auth/login
  Future<Map<String, dynamic>> login(String username, String password) async {
    final decoded = await _api.post(ApiConstants.login, {'usernameOrEmail': username, 'password': password});

    await _tokens.save(decoded['accessToken'].toString(), decoded['refreshToken'].toString());

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', decoded['username'] ?? username);
    await prefs.setString('email', decoded['email'] ?? '');
    if (decoded['id'] != null) await prefs.setInt('userId', decoded['id']);

    await prefs.setString('subscriptionStatus', decoded['subscriptionStatus'] ?? 'None');
    if (decoded['trialEndDate'] != null) await prefs.setString('trialEndDate', decoded['trialEndDate']);
    if (decoded['subscriptionEndDate'] != null) await prefs.setString('subscriptionEndDate', decoded['subscriptionEndDate']);

    return decoded;
  }

  /// POST /api/v1/auth/register
  Future<Map<String, dynamic>> register(String username, String email, String password) async {
    return _api.post(ApiConstants.register, {
      'username': username,
      'email': email,
      'password': password,
    });
  }

  /// 1. Adım: Şifremi Unuttum
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    return _api.post(
      ApiConstants.forgotPassword,
      {'email': email},
      timeout: const Duration(seconds: 15),
    );
  }

  /// 2. Adım: Yeni Şifreyi Kaydet
  Future<Map<String, dynamic>> resetPassword(String email, String code, String newPassword) async {
    return _api.post(
      ApiConstants.resetPassword,
      {'email': email, 'code': code, 'newPassword': newPassword},
      timeout: const Duration(seconds: 15),
    );
  }

  // Telefonda geçerli bir oturum olup olmadığını döner
  Future<bool> hasSession() => _tokens.hasSession();

  // Sunucudaki oturumu kapatmayı dener, sonuç ne olursa olsun telefondaki oturumu siler
  Future<void> logout() async {
    final refreshToken = await _tokens.refreshToken;
    if (refreshToken != null) {
      try {
        await _api.post(ApiConstants.logout, {'refreshToken': refreshToken}, timeout: const Duration(seconds: 10));
      } on ApiException catch (e) {
        debugPrint('Sunucudaki oturum kapatılamadı: $e');
      }
    }
    await clearSession();
  }

  /// Oturumu kapatır
  Future<void> clearSession() async {
    await _tokens.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('username');
    await prefs.remove('email');
    await prefs.remove('userId');
    await prefs.remove('authToken');
    await prefs.remove('token');
    await prefs.remove('subscriptionStatus');
    await prefs.remove('trialEndDate');
    await prefs.remove('subscriptionEndDate');
  }

  /// Yerel hafızadaki bilgileri modele dönüştürür
  Future<UserModel?> getSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    if (username == null) return null;

    return UserModel(
      username: username,
      email: prefs.getString('email') ?? '',
      subscriptionStatus: prefs.getString('subscriptionStatus') ?? 'None',
      trialEndDate: prefs.getString('trialEndDate') != null
          ? DateTime.tryParse(prefs.getString('trialEndDate')!)
          : null,
      subscriptionEndDate: prefs.getString('subscriptionEndDate') != null
          ? DateTime.tryParse(prefs.getString('subscriptionEndDate')!)
          : null,
    );
  }

  Future<String?> getLoggedInUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username');
  }

  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('userId');
  }
}