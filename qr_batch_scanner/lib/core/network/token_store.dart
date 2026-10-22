import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  static final TokenStore instance = TokenStore();

  static const _keyAccess = 'accessToken';
  static const _keyRefresh = 'refreshToken';

  final FlutterSecureStorage _storage;
  String? _access;
  String? _refresh;
  bool _loaded = false;
  Future<bool>? _pendingRefresh;

  TokenStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  // Token'ları ilk kullanımda güvenli depodan okuyup bellekte tutar
  Future<void> _load() async {
    if (_loaded) return;
    _access = await _storage.read(key: _keyAccess);
    _refresh = await _storage.read(key: _keyRefresh);
    _loaded = true;
  }

  Future<String?> get accessToken async {
    await _load();
    return _access;
  }

  Future<String?> get refreshToken async {
    await _load();
    return _refresh;
  }

  // Yenileme token'ı varsa kullanıcı giriş yapmış sayılır
  Future<bool> hasSession() async => (await refreshToken) != null;

  // Sunucudan gelen yeni token çiftini kaydeder
  Future<void> save(String accessToken, String refreshToken) async {
    _access = accessToken;
    _refresh = refreshToken;
    _loaded = true;
    await _storage.write(key: _keyAccess, value: accessToken);
    await _storage.write(key: _keyRefresh, value: refreshToken);
  }

  // Çıkışta veya oturum düşünce token'ları siler
  Future<void> clear() async {
    _access = null;
    _refresh = null;
    _loaded = true;
    await _storage.delete(key: _keyAccess);
    await _storage.delete(key: _keyRefresh);
  }

  // Aynı anda gelen yenileme isteklerini tek bir yenilemede birleştirir
  Future<bool> refreshOnce(Future<bool> Function() refresh) {
    return _pendingRefresh ??= refresh().whenComplete(() => _pendingRefresh = null);
  }
}
