import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiClient {
  static const Duration defaultTimeout = Duration(seconds: 10);
  static const Map<String, String> _baseHeaders = {'ngrok-skip-browser-warning': 'true'};
  static const Map<String, String> _jsonHeaders = {..._baseHeaders, 'Content-Type': 'application/json'};

  final http.Client _http;
  final String _baseUrl;

  ApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConstants.baseUrl;

  // Verilen yolu sunucu adresiyle birleştirip tam adresi döner
  Uri uri(String path) => Uri.parse('$_baseUrl$path');

  Future<Map<String, dynamic>> get(String path, {Duration timeout = defaultTimeout}) {
    return _send(() => _http.get(uri(path), headers: _jsonHeaders), timeout);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {Duration timeout = defaultTimeout}) {
    return _send(() => _http.post(uri(path), headers: _jsonHeaders, body: jsonEncode(body)), timeout);
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body, {Duration timeout = defaultTimeout}) {
    return _send(() => _http.put(uri(path), headers: _jsonHeaders, body: jsonEncode(body)), timeout);
  }

  // Dosyayı form verisi olarak gönderir ve cevabı çözülmüş olarak döner
  Future<Map<String, dynamic>> postFile(String path, String field, String filePath, {Duration timeout = defaultTimeout}) {
    return _send(() async {
      final request = http.MultipartRequest('POST', uri(path))
        ..headers.addAll(_baseHeaders)
        ..files.add(await http.MultipartFile.fromPath(field, filePath));
      return http.Response.fromStream(await _http.send(request));
    }, timeout);
  }

  // İsteği gönderir, bağlantı ve zaman aşımı hatalarını anlaşılır mesaja çevirir
  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request, Duration timeout) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw const ApiException('Sunucu zamanında cevap vermedi, lütfen tekrar deneyin.');
    } on SocketException {
      throw const ApiException('Sunucuya ulaşılamadı. Bağlantınızı kontrol edin.');
    } on http.ClientException {
      throw const ApiException('Sunucuya ulaşılamadı. Bağlantınızı kontrol edin.');
    }
    return _decode(response);
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
      throw ApiException(errorMessage(decoded, 'Sunucu hatası (${response.statusCode}).'), statusCode: response.statusCode);
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
