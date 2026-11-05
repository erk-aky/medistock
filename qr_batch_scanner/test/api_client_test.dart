import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_batch_scanner/core/constants/api_constants.dart';
import 'package:qr_batch_scanner/core/network/api_client.dart';
import 'package:qr_batch_scanner/core/network/token_store.dart';

ApiClient _client(Future<http.Response> Function(http.Request request) handler, {TokenStore? tokens}) {
  return ApiClient(httpClient: MockClient(handler), baseUrl: 'https://test.local', tokenStore: tokens ?? TokenStore());
}

Future<TokenStore> _loggedInStore() async {
  final store = TokenStore();
  await store.save('eski-giris', 'eski-yenileme');
  return store;
}

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.onSessionExpired = null;
  });

  test('adres sunucu adresi ve api önekiyle birleşir, ortak headerlar eklenir', () async {
    late http.Request sent;
    final api = _client((request) async {
      sent = request;
      return _json({'success': true}, 200);
    });

    await api.post(ApiConstants.login, {'usernameOrEmail': 'ali'});

    expect(sent.url.toString(), 'https://test.local/api/v1/auth/login');
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

  test('korunan adrese token başlığı eklenir, giriş adresine eklenmez', () async {
    final sent = <http.Request>[];
    final api = _client((request) async {
      sent.add(request);
      return _json({'success': true}, 200);
    }, tokens: await _loggedInStore());

    await api.get(ApiConstants.dbVersion);
    await api.post(ApiConstants.login, {});

    expect(sent[0].headers['Authorization'], 'Bearer eski-giris');
    expect(sent[1].headers.containsKey('Authorization'), isFalse);
  });

  test('401 gelince token yenilenir ve istek yeni token ile tekrarlanır', () async {
    final tokens = await _loggedInStore();
    final sent = <http.Request>[];
    final api = _client((request) async {
      sent.add(request);
      if (request.url.path == ApiConstants.refresh) {
        expect(jsonDecode(request.body), {'refreshToken': 'eski-yenileme'});
        return _json({'success': true, 'accessToken': 'yeni-giris', 'refreshToken': 'yeni-yenileme'}, 200);
      }
      if (request.headers['Authorization'] == 'Bearer yeni-giris') return _json({'success': true, 'version': 3}, 200);
      return _json({'success': false, 'message': ApiClient.sessionExpiredMessage}, 401);
    }, tokens: tokens);

    final result = await api.get(ApiConstants.dbVersion);

    expect(result['version'], 3);
    expect(sent.length, 3);
    expect(await tokens.accessToken, 'yeni-giris');
    expect(await tokens.refreshToken, 'yeni-yenileme');
  });

  test('aynı anda gelen 401 lerde token sadece bir kez yenilenir', () async {
    final tokens = await _loggedInStore();
    var refreshCount = 0;
    final api = _client((request) async {
      if (request.url.path == ApiConstants.refresh) {
        refreshCount++;
        await Future.delayed(const Duration(milliseconds: 20));
        return _json({'success': true, 'accessToken': 'yeni-giris', 'refreshToken': 'yeni-yenileme'}, 200);
      }
      if (request.headers['Authorization'] == 'Bearer yeni-giris') return _json({'success': true}, 200);
      return _json({'success': false}, 401);
    }, tokens: tokens);

    await Future.wait([api.get(ApiConstants.dbVersion), api.get(ApiConstants.dbExport), api.post(ApiConstants.itsResolveCode, {})]);

    expect(refreshCount, 1);
  });

  test('yenileme reddedilirse oturum silinir ve giriş ekranına haber verilir', () async {
    final tokens = await _loggedInStore();
    var expiredCalled = false;
    ApiClient.onSessionExpired = () => expiredCalled = true;
    final api = _client((_) async => _json({'success': false, 'message': ApiClient.sessionExpiredMessage}, 401), tokens: tokens);

    await expectLater(
      api.get(ApiConstants.dbVersion),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', ApiClient.sessionExpiredMessage)
          .having((e) => e.statusCode, 'statusCode', 401)),
    );
    expect(expiredCalled, isTrue);
    expect(await tokens.hasSession(), isFalse);
  });

  test('yenileme sırasında internet yoksa oturum silinmez', () async {
    final tokens = await _loggedInStore();
    var expiredCalled = false;
    ApiClient.onSessionExpired = () => expiredCalled = true;
    final api = _client((request) async {
      if (request.url.path == ApiConstants.refresh) throw const SocketException('bağlantı yok');
      return _json({'success': false}, 401);
    }, tokens: tokens);

    await expectLater(
      api.get(ApiConstants.dbVersion),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('ulaşılamadı'))),
    );
    expect(expiredCalled, isFalse);
    expect(await tokens.refreshToken, 'eski-yenileme');
  });

  test('yanlış şifrede token yenilenmeye çalışılmaz', () async {
    var requestCount = 0;
    final api = _client((_) async {
      requestCount++;
      return _json({'success': false, 'message': 'Kullanıcı adı veya şifre hatalı'}, 401);
    }, tokens: await _loggedInStore());

    await expectLater(api.post(ApiConstants.login, {}), throwsA(isA<ApiException>()));
    expect(requestCount, 1);
  });

  test('token kaydedilince güvenli depodan geri okunur', () async {
    await TokenStore().save('giris', 'yenileme');
    final reopened = TokenStore();
    expect(await reopened.accessToken, 'giris');
    expect(await reopened.hasSession(), isTrue);
    await reopened.clear();
    expect(await TokenStore().hasSession(), isFalse);
  });

  test('geliştirme modunda teknik detay mesajın altına eklenir', () {
    final message = ApiClient.errorMessage({'message': 'Beklenmeyen bir hata oluştu.', 'detail': 'NpgsqlException'}, 'yedek');
    expect(message, 'Beklenmeyen bir hata oluştu.\nNpgsqlException');
  });
}
