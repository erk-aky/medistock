import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ItsCredentials {
  final String gln;
  final String password;

  const ItsCredentials({required this.gln, required this.password});

  bool get isComplete => gln.isNotEmpty && password.isNotEmpty;
}

class ItsCredentialStore {
  static final ItsCredentialStore instance = ItsCredentialStore();

  final FlutterSecureStorage _storage;

  ItsCredentialStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static String _glnKey(String userId) => 'its_gln_$userId';
  static String _passwordKey(String userId) => 'its_password_$userId';
  static String _legacyGlnKey(String userId) => 'local_gln_$userId';
  static String _legacyPasswordKey(String userId) => 'local_its_password_$userId';

  // Kullanıcının GLN ve ITS şifresini güvenli depodan okur, eski düz metin kayıtları varsa önce oraya taşır
  Future<ItsCredentials> read(String userId) async {
    return ItsCredentials(
      gln: await _readMigrating(_glnKey(userId), _legacyGlnKey(userId)),
      password: await _readMigrating(_passwordKey(userId), _legacyPasswordKey(userId)),
    );
  }

  // Kullanıcının GLN ve ITS şifresini birlikte güvenli depoya yazar, boş olanı siler
  Future<void> save(String userId, {required String gln, required String password}) async {
    await _writeOrDelete(_glnKey(userId), gln);
    await _writeOrDelete(_passwordKey(userId), password);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyGlnKey(userId));
    await prefs.remove(_legacyPasswordKey(userId));
  }

  // Değeri güvenli depodan okur, yoksa eski düz metin kaydı taşıyıp siler
  Future<String> _readMigrating(String key, String legacyKey) async {
    final stored = await _storage.read(key: key);
    if (stored != null) return stored;

    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(legacyKey);
    if (legacy == null) return '';

    await _storage.write(key: key, value: legacy);
    await prefs.remove(legacyKey);
    return legacy;
  }

  // Değer boşsa siler, doluysa güvenli depoya yazar
  Future<void> _writeOrDelete(String key, String value) async {
    if (value.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }
}
