import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_batch_scanner/core/constants/api_constants.dart';
import 'package:qr_batch_scanner/core/network/api_client.dart';

ApiClient _client(Future<http.Response> Function(http.Request request) handler) {
  return ApiClient(httpClient: MockClient(handler), baseUrl: 'https://test.local');
}

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('adres sunucu adresi ve api önekiyle birleşir, ortak headerlar eklenir', () async {
    late http.Request sent;
    final api = _client((request) async {
      sent = request;
      return _json({'success': true}, 200);
    });

    await api.post(ApiConstants.login, {'usernameOrEmail': 'ali'});

    expect(sent.url.toString(), 'https://test.local/api/auth/login');
    expect(sent.method, 'POST');
    expect(sent.headers['ngrok-skip-browser-warning'], 'true');
    expect(sent.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(sent.body), {'usernameOrEmail': 'ali'});
  });

  test('başarılı cevap çözülmüş olarak döner', () async {
    final api = _client((_) async => _json({'success': true, 'version': 7}, 200));
    final result = await api.get(ApiConstants.dbVersion);
    expect(result['version'], 7);
  });

  test('hatalı cevapta sunucunun Türkçe mesajı ve durum kodu fırlatılır', () async {
    final api = _client((_) async => _json({'success': false, 'message': 'Kullanıcı adı veya şifre hatalı'}, 401));
    await expectLater(
      api.post(ApiConstants.login, {}),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', 'Kullanıcı adı veya şifre hatalı')
          .having((e) => e.statusCode, 'statusCode', 401)),
    );
  });

  test('JSON olmayan cevapta anlaşılır mesaj fırlatılır', () async {
    final api = _client((_) async => http.Response('<html>ngrok error page</html>', 502));
    await expectLater(
      api.get(ApiConstants.dbVersion),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('geçersiz cevap'))),
    );
  });

  test('sunucuya ulaşılamazsa anlaşılır mesaj fırlatılır', () async {
    final api = _client((_) async => throw const SocketException('bağlantı yok'));
    await expectLater(
      api.get(ApiConstants.dbVersion),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', contains('ulaşılamadı'))
          .having((e) => e.statusCode, 'statusCode', isNull)),
    );
  });

  test('zaman aşımında anlaşılır mesaj fırlatılır', () async {
    final api = _client((_) => Future.delayed(const Duration(seconds: 1), () => _json({}, 200)));
    await expectLater(
      api.get(ApiConstants.dbVersion, timeout: const Duration(milliseconds: 50)),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('zamanında'))),
    );
  });

  test('profil adresinde kullanıcı adı güvenli şekilde kodlanır', () {
    expect(ApiConstants.profile('Ayşe Nur'), '/api/auth/profile/Ay%C5%9Fe%20Nur');
  });

  test('geliştirme modunda teknik detay mesajın altına eklenir', () {
    final message = ApiClient.errorMessage({'message': 'Beklenmeyen bir hata oluştu.', 'detail': 'NpgsqlException'}, 'yedek');
    expect(message, 'Beklenmeyen bir hata oluştu.\nNpgsqlException');
  });
}
