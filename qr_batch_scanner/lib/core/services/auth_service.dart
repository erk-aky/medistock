import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../models/user_model.dart';
import '../network/api_client.dart';

class AuthService {
  final ApiClient _api;

  AuthService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  /// ✅ YENİ: E-posta Doğrulama Kodunu Backend'e Gönderir
  /// POST /api/auth/verify-email
  Future<Map<String, dynamic>> verifyEmail(String ticket, String code) async {
    return _api.post(
      ApiConstants.verifyEmail,
      {'ticket': ticket, 'code': code},
      timeout: const Duration(seconds: 15),
    );
  }

  /// ✅ Profil Bilgilerini Veritabanında Günceller
  Future<Map<String, dynamic>> updateProfile({
    required int userId,
    required String newUsername,
    required String newEmail,
  }) async {
    final decoded = await _api.put(ApiConstants.updateProfile, {
      'userId': userId,
      'newUsername': newUsername,
      'newEmail': newEmail,
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', newUsername);
    await prefs.setString('email', newEmail);

    return decoded;
  }

  /// ✅ Backend'den Güncel Profil Bilgilerini Çeker
  Future<Map<String, dynamic>> getUserProfile(String username) async {
    final decoded = await _api.get(ApiConstants.profile(username));

    final prefs = await SharedPreferences.getInstance();
    if (decoded['email'] != null) await prefs.setString('email', decoded['email']);
    if (decoded['subscriptionStatus'] != null) await prefs.setString('subscriptionStatus', decoded['subscriptionStatus']);
    if (decoded['trialEndDate'] != null) await prefs.setString('trialEndDate', decoded['trialEndDate']);
    if (decoded['subscriptionEndDate'] != null) await prefs.setString('subscriptionEndDate', decoded['subscriptionEndDate']);
    if (decoded['id'] != null) await prefs.setInt('userId', decoded['id']);

    return decoded;
  }

  /// POST /api/auth/login
  Future<Map<String, dynamic>> login(String username, String password) async {
    final decoded = await _api.post(ApiConstants.login, {'usernameOrEmail': username, 'password': password});

    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('username', decoded['username'] ?? username);
    await prefs.setString('email', decoded['email'] ?? '');
    if (decoded['id'] != null) await prefs.setInt('userId', decoded['id']);

    await prefs.setString('subscriptionStatus', decoded['subscriptionStatus'] ?? 'None');
    if (decoded['trialEndDate'] != null) await prefs.setString('trialEndDate', decoded['trialEndDate']);
    if (decoded['subscriptionEndDate'] != null) await prefs.setString('subscriptionEndDate', decoded['subscriptionEndDate']);

    final token = (decoded['token'] ?? decoded['authToken'])?.toString();
    if (token != null) {
      await prefs.setString('authToken', token);
      await prefs.setString('token', token);
    }

    return decoded;
  }

  /// POST /api/auth/register
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

  /// Oturumu kapatır
  Future<void> clearSession() async {
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