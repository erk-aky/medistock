import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'token_store.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? body;

  const ApiException(this.message, {this.statusCode, this.body});

  // Sunucunun bildirdiği kalan kod deneme hakkını döner, yoksa null döner
  int? get remainingAttempts => body?['remainingAttempts'] as int?;

  @override
  String toString() => message;
}

class ApiClient {
  static const Duration defaultTimeout = Duration(seconds: 10);
  static const String sessionExpiredMessage = 'Oturumunuzun süresi doldu, lütfen tekrar giriş yapın.';
  static const Map<String, String> _baseHeaders = {'ngrok-skip-browser-warning': 'true'};
  static const Map<String, String> _jsonHeaders = {..._baseHeaders, 'Content-Type': 'application/json'};

  static void Function()? onSessionExpired;

  final http.Client _http;
  final String _baseUrl;
  final TokenStore _tokens;

  ApiClient({http.Client? httpClient, String? baseUrl, TokenStore? tokenStore})
      : _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConstants.baseUrl,
        _tokens = tokenStore ?? TokenStore.instance;

  // Verilen yolu sunucu adresiyle birleştirip tam adresi döner
  Uri uri(String path) => Uri.parse('$_baseUrl$path');

  Future<Map<String, dynamic>> get(String path, {Duration timeout = defaultTimeout}) {
    return _send(path, (auth) => _http.get(uri(path), headers: {..._jsonHeaders, ...auth}), timeout);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {Duration timeout = defaultTimeout}) {
    return _send(path, (auth) => _http.post(uri(path), headers: {..._jsonHeaders, ...auth}, body: jsonEncode(body)), timeout);
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body, {Duration timeout = defaultTimeout}) {
    return _send(path, (auth) => _http.put(uri(path), headers: {..._jsonHeaders, ...auth}, body: jsonEncode(body)), timeout);
  }

  // Dosyayı form verisi olarak gönderir ve cevabı çözülmüş olarak döner
  Future<Map<String, dynamic>> postFile(String path, String field, String filePath, {Duration timeout = defaultTimeout}) {
    return _send(path, (auth) async {
      final request = http.MultipartRequest('POST', uri(path))
        ..headers.addAll({..._baseHeaders, ...auth})
        ..files.add(await http.MultipartFile.fromPath(field, filePath));
      return http.Response.fromStream(await _http.send(request));
    }, timeout);
  }

  // İsteği token ile gönderir, token süresi dolmuşsa bir kez yenileyip isteği tekrarlar
  Future<Map<String, dynamic>> _send(
    String path,
    Future<http.Response> Function(Map<String, String> auth) request,
    Duration timeout,
  ) async {
    if (ApiConstants.publicPaths.contains(path)) return _decode(await _execute(() => request(const {}), timeout));

    final sentToken = await _tokens.accessToken;
    var response = await _execute(() => request(_authHeader(sentToken)), timeout);

    if (response.statusCode == 401 && sentToken != null) {
      if (sentToken == await _tokens.accessToken && !await _tokens.refreshOnce(() => _refreshTokens(timeout))) {
        throw const ApiException(sessionExpiredMessage, statusCode: 401);
      }
      final newToken = await _tokens.accessToken;
      response = await _execute(() => request(_authHeader(newToken)), timeout);
    }
    return _decode(response);
  }

  static Map<String, String> _authHeader(String? token) => token == null ? const {} : {'Authorization': 'Bearer $token'};

  // Yenileme token'ıyla yeni token çifti alır, sunucu reddederse oturumu kapatır
  Future<bool> _refreshTokens(Duration timeout) async {
    final refreshToken = await _tokens.refreshToken;
    if (refreshToken != null) {
      final response = await _execute(
        () => _http.post(uri(ApiConstants.refresh), headers: _jsonHeaders, body: jsonEncode({'refreshToken': refreshToken})),
        timeout,
      );
      if (response.statusCode == 200) {
        final decoded = _decode(response);
        await _tokens.save(decoded['accessToken'].toString(), decoded['refreshToken'].toString());
        return true;
      }
      if (response.statusCode != 401) _decode(response);
    }
    await _tokens.clear();
    onSessionExpired?.call();
    return false;
  }

  // İsteği gönderir, bağlantı ve zaman aşımı hatalarını anlaşılır mesaja çevirir
  Future<http.Response> _execute(Future<http.Response> Function() request, Duration timeout) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw const ApiException('Sunucu zamanında cevap vermedi, lütfen tekrar deneyin.');
    } on SocketException {
      throw const ApiException('Sunucuya ulaşılamadı. Bağlantınızı kontrol edin.');
    } on http.ClientException {
      throw const ApiException('Sunucuya ulaşılamadı. Bağlantınızı kontrol edin.');
    }
  }

  // Cevabı JSON olarak çözer, başarısızsa sunucunun mesajıyla hata fırlatır
  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> decoded;
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) throw const FormatException();
      decoded = body;
    } on FormatException {
      throw ApiException('Sunucudan geçersiz cevap alındı (${response.statusCode}).', statusCode: response.statusCode);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(errorMessage(decoded, 'Sunucu hatası (${response.statusCode}).'), statusCode: response.statusCode, body: decoded);
    }
    return decoded;
  }

  // Sunucunun hata mesajını döner, geliştirme modunda varsa teknik detayı da altına ekler
  static String errorMessage(Map<String, dynamic> decoded, String fallback) {
    final message = decoded['message']?.toString() ?? fallback;
    final detail = decoded['detail']?.toString();
    if (kDebugMode && detail != null) return '$message\n$detail';
    return message;
  }
}
