import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../models/user_model.dart'; 

class AuthService {
  final String baseUrl = ApiConstants.baseUrl;

  /// ✅ YENİ: E-posta Doğrulama Kodunu Backend'e Gönderir
  /// POST /api/auth/verify-email
  Future<Map<String, dynamic>> verifyEmail(String ticket, String code) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}/api/auth/verify-email');

    final bodyJson = jsonEncode({
      'ticket': ticket,
      'code': code,
    });

    final resp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: bodyJson,
    ).timeout(const Duration(seconds: 15));

    final Map<String, dynamic> decoded = jsonDecode(resp.body);

    if (resp.statusCode == 200) {
      return decoded;
    } else {
      throw Exception(decoded['message'] ?? 'Doğrulama kodu hatalı');
    }
  }

  /// ✅ Profil Bilgilerini Veritabanında Günceller
  Future<Map<String, dynamic>> updateProfile({
    required int userId,
    required String newUsername,
    required String newEmail,
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}/api/auth/update-profile');
    
    final bodyJson = jsonEncode({
      'userId': userId,
      'newUsername': newUsername,
      'newEmail': newEmail,
    });

    final resp = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: bodyJson,
    ).timeout(const Duration(seconds: 10));

    final Map<String, dynamic> decoded = jsonDecode(resp.body);

    if (resp.statusCode == 200) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', newUsername);
      await prefs.setString('email', newEmail);
      
      return decoded;
    } else {
      throw Exception(decoded['message'] ?? 'Profil güncellenemedi');
    }
  }

  /// ✅ Backend'den Güncel Profil Bilgilerini Çeker
  Future<Map<String, dynamic>> getUserProfile(String username) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}/api/auth/profile/$username');

    final resp = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
    ).timeout(const Duration(seconds: 10));

    if (resp.statusCode == 200) {
      final Map<String, dynamic> decoded = jsonDecode(resp.body);
      
      final prefs = await SharedPreferences.getInstance();
      if (decoded['email'] != null) await prefs.setString('email', decoded['email']);
      if (decoded['subscriptionStatus'] != null) await prefs.setString('subscriptionStatus', decoded['subscriptionStatus']);
      if (decoded['trialEndDate'] != null) await prefs.setString('trialEndDate', decoded['trialEndDate']);
      if (decoded['subscriptionEndDate'] != null) await prefs.setString('subscriptionEndDate', decoded['subscriptionEndDate']);
      if (decoded['id'] != null) await prefs.setInt('userId', decoded['id']);
      
      return decoded;
    } else {
      throw Exception('Profil bilgileri alınamadı');
    }
  }

  /// POST /api/auth/login
  Future<Map<String, dynamic>> login(String username, String password) async {
    final uri = Uri.parse(ApiConstants.login);
    final bodyJson = jsonEncode({'usernameOrEmail': username, 'password': password});

    final resp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: bodyJson,
    ).timeout(const Duration(seconds: 10));

    final Map<String, dynamic> decoded = jsonDecode(resp.body);

    if (resp.statusCode == 200) {
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
    } else {
      // Backend'den gelen spesifik hata mesajını (örneğin: "Email onaylanmadı") fırlatır
      throw Exception(decoded['message'] ?? 'Giriş başarısız');
    }
  }

  /// POST /api/auth/register
  Future<Map<String, dynamic>> register(String username, String email, String password) async {
    final uri = Uri.parse(ApiConstants.register);
    final bodyJson = jsonEncode({
      'username': username,
      'email': email,
      'password': password,
    });

    final resp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: bodyJson,
    ).timeout(const Duration(seconds: 10));
    
    final Map<String, dynamic> decoded = jsonDecode(resp.body);
    if (resp.statusCode == 200) {
      return decoded;
    } else {
      throw Exception(decoded['message'] ?? 'Kayıt başarısız');
    }
  }

  /// 1. Adım: Şifremi Unuttum
  Future<Map<String, dynamic>> forgotPassword(String email) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}/api/auth/forgot-password');
    final bodyJson = jsonEncode({'email': email});

    final resp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: bodyJson,
    ).timeout(const Duration(seconds: 15));

    final Map<String, dynamic> decoded = jsonDecode(resp.body);
    if (resp.statusCode == 200) {
      return decoded;
    } else {
      throw Exception(decoded['message'] ?? 'Kod gönderilemedi');
    }
  }

  /// 2. Adım: Yeni Şifreyi Kaydet
  Future<Map<String, dynamic>> resetPassword(String email, String code, String newPassword) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}/api/auth/reset-password');
    final bodyJson = jsonEncode({
      'email': email,
      'code': code,
      'newPassword': newPassword,
    });

    final resp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
      body: bodyJson,
    ).timeout(const Duration(seconds: 15));

    final Map<String, dynamic> decoded = jsonDecode(resp.body);
    if (resp.statusCode == 200) {
      return decoded;
    } else {
      throw Exception(decoded['message'] ?? 'Şifre güncellenemedi');
    }
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