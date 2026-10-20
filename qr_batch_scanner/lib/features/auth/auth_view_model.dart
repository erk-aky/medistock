import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/auth_service.dart';

class AuthViewModel extends ChangeNotifier {
  final AuthService _authService;

  AuthViewModel({AuthService? authService})
      : _authService = authService ?? AuthService() {
    loadSaved();
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;
  // Sınıfın üst kısmındaki değişkenlerin arasına ekle:
  int? userId;
  static const _keyUserId = 'userId';

  String? _username;
  String? get username => _username;

  void setUsername(String newUsername) {
    _username = newUsername;
    notifyListeners();
  }

  String? _email;
  String? get email => _email;

  String get currentUsername => _username ?? "Kullanıcı";
  String get currentUserEmail => _email ?? "";

  String? _trialEndDate;
  String? get trialEndDate => _trialEndDate;

  String? _registrationTicket;

  static const _keyLoggedIn = 'isLoggedIn';
  static const _keyUsername = 'username';
  static const _keyEmail = 'userEmail'; 
  static const _keyToken = 'authToken';

  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool(_keyLoggedIn) ?? false;
    userId = prefs.getInt(_keyUserId);
    _username = prefs.getString(_keyUsername);
    _email = prefs.getString(_keyEmail);
    userId = prefs.getInt(_keyUserId); // ID'yi de baştan oku

    // ✅ EKLEME: Yerelden ne okuduysak hemen UI'a bildir. 
    // Böylece "Kullanıcı" yerine hafızadaki ismi anında görürüz.
    notifyListeners(); 
    debugPrint("🔄 Veriler hafızadan yüklendi: ID: $userId, User: $_username");
    
    if (_isLoggedIn && _username != null) {
      await fetchAndUpdateProfile(_username!);
    }
  }

  /// ✅ YENİ: E-posta doğrulama kodunu gönderir
  Future<bool> verifyCode(String code) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final resp = await _authService.verifyEmail(_registrationTicket ?? '', code);
      _isLoading = false;
      if (resp['success'] == true) {
        _registrationTicket = null;
        notifyListeners();
        return true;
      } else {
        _error = resp['message'] ?? "Doğrulama başarısız";
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
      _error = e.toString().replaceAll("Exception:", "");
      notifyListeners();
      return false;
    }
  }

  /// ✅ PROFİL ÇEKERKEN ID YAKALAMA
  Future<void> fetchAndUpdateProfile(String username) async {
    try {
      final resp = await _authService.getUserProfile(username);

      if (resp['success'] == true) {
        // backend'den gelen değerler
        _username = resp['username']?.toString() ?? _username;
        _email = resp['email']?.toString();
        _trialEndDate = resp['trialEndDate']?.toString() ?? resp['trial_end_date']?.toString();
        userId = resp['id'] ?? resp['userId'] ?? userId;

        final prefs = await SharedPreferences.getInstance();

        // kritik: hostname/username key'lerini güncelle
        if (_username != null) {
          await prefs.setString(_keyUsername, _username!);
        }

        if (_email != null) {
          await prefs.setString(_keyEmail, _email!);
          await prefs.setString('email', _email!);
        }

        if (userId != null) {
          await prefs.setInt(_keyUserId, userId!);
          // Ayrıca local_username_{id} anahtarını da tutarlı tut:
          if (_username != null) {
            await prefs.setString('local_username_$userId', _username!);
          }
        }

        if (_trialEndDate != null) {
          await prefs.setString('trialEndDate', _trialEndDate!);
        }

        notifyListeners();
      }
    } catch (e) {
      print("--- [DEBUG] PROFİL TAZELEME HATASI: $e ---");
    }
  }

  /// ✅ LOGİN OLURKEN ID YAKALAMA
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final resp = await _authService.login(username, password);
      
      // --- 🕵️‍♂️ DEDEKTİF LOGLARI BAŞLADI ---
      print("==========================================");
      print("🚀 BACKEND'DEN GELEN TÜM CEVAP (RAW):");
      print(resp); // Tüm JSON yapısını terminale basar
      print("------------------------------------------");
      print("🔍 ANAHTAR KONTROLLERİ:");
      print("id var mı? -> ${resp['id']}");
      print("user objesi var mı? -> ${resp['user']}");
      if (resp['user'] != null) {
        print("user içindeki id -> ${resp['user']['id']}");
      }
      print("success durumu -> ${resp['success']}");
      print("ok durumu -> ${resp['ok']}");
      print("==========================================");
      // --- 🕵️‍♂️ DEDEKTİF LOGLARI BİTTİ ---

      final success = resp['success'] == true || resp['ok'] == true;

      if (success) {
        final token = resp['token']?.toString();
        _trialEndDate = resp['trialEndDate']?.toString(); 
        
        // ID yakalama (Gelen loglara göre burayı revize edebiliriz)
        userId = resp['id'] ?? (resp['user'] != null ? resp['user']['id'] : null);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_keyLoggedIn, true);
        await prefs.setString(_keyUsername, username);
        
        if (userId != null) {
          await prefs.setInt(_keyUserId, userId!);
          print("✅ ID HAFIZAYA KAYDEDİLDİ: $userId");
        } else {
          print("⚠️ UYARI: ID BULUNAMADI, HAFIZAYA YAZILAMADI!");
        }

        _email = resp['email']?.toString();
        if (_email == null && resp['user'] != null) {
          _email = resp['user']['email']?.toString();
        }

        if (_email != null) {
          await prefs.setString(_keyEmail, _email!);
        }

        if (_trialEndDate != null) {
          await prefs.setString('trialEndDate', _trialEndDate!);
        }

        if (token != null) {
          await prefs.setString(_keyToken, token);
        }

        _isLoggedIn = true;
        _username = username;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = resp['message']?.toString() ?? 'Giriş başarısız';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      print("❌ LOGIN HATASI: $e");
      _error = e.toString().replaceAll("Exception:", "");
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// ✅ GERÇEK DB GÜNCELLEMESİ (Hatasız ve Senkronize)
  Future<bool> updateUserInfo({String? newUsername, String? newEmail}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1️⃣ ID’yi garantiye al
      userId ??= prefs.getInt(_keyUserId);

      if (userId == null || userId == 0) {
        debugPrint("❌ HATA: Kullanıcı ID hala bulunamadı! Prefs Key: $_keyUserId");
        _error = "Kullanıcı kimliği bulunamadı. Lütfen tekrar giriş yapın.";
        _isLoading = false;
        notifyListeners();
        return false;
      }

      debugPrint("🚀 Güncelleme isteği gönderiliyor: ID: $userId");

      // 2️⃣ API isteği
      final resp = await _authService.updateProfile(
        userId: userId!,
        newUsername: newUsername ?? _username ?? "",
        newEmail: newEmail ?? _email ?? "",
      );

      if (resp['success'] == true || resp['ok'] == true) {
        final updatedUsername = resp['username']?.toString() ?? newUsername ?? _username ?? "";
        final updatedEmail = resp['email']?.toString() ?? newEmail ?? _email ?? "";

        _username = updatedUsername;
        _email = updatedEmail;

        // prefs güncelle
        await prefs.setString(_keyUsername, updatedUsername);
        await prefs.setString(_keyEmail, updatedEmail);

        // burada userId'nin prefs veya memory'de olduğundan emin ol
        userId ??= prefs.getInt(_keyUserId);
        if (userId != null) {
          await prefs.setString('local_username_$userId', updatedUsername); // <<< EKLENDİ
        }

        debugPrint("✅ Güncelleme başarılı (STATE + PREFS): $_username");
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = resp['message']?.toString() ?? "Güncelleme başarısız oldu.";
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint("⚠️ Güncelleme sırasında hata oluştu: $e");
      _error = e.toString().replaceAll("Exception:", "");
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String username, String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final resp = await _authService.register(username, email, password);
      if (resp['success'] == true) {
        _registrationTicket = resp['ticket']?.toString();
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = resp['message']?.toString() ?? 'Kayıt başarısız';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString().replaceAll("Exception:", "");
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();

    // Tüm bilinen anahtar varyantlarını temizle (tutarsızlık varsa kapsar)
    await prefs.remove(_keyLoggedIn);   // 'isLoggedIn'
    await prefs.remove(_keyUsername);   // 'username'
    await prefs.remove(_keyEmail);      // 'userEmail' (const)
    await prefs.remove('email');        // eğer başka yerde 'email' kullanıldıysa
    await prefs.remove(_keyToken);      // 'authToken'
    await prefs.remove('token');        // alternatif token anahtarı
    await prefs.remove(_keyUserId);     // 'userId'
    await prefs.remove('userId');       // güvenlik için tekrar
    await prefs.remove('trialEndDate');
    await prefs.remove('subscriptionStatus');
    await prefs.remove('subscriptionEndDate');
    await prefs.remove('hasShownExpiredForever');

    try {
      await _authService.clearSession();
    } catch (e) {
      print('Logout Hatası: $e');
    }

    // Bellekteki tüm kimlik bilgilerini temizle
    _isLoggedIn = false;
    _username = null;
    _email = null;
    _trialEndDate = null;
    userId = null;         // <<< MUTLAKA EKLENECEK
    _error = null;
    _isLoading = false;

    notifyListeners();
  }
}