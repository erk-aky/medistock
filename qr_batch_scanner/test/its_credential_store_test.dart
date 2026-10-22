import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_batch_scanner/core/services/its_credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('GLN ve şifre birlikte kaydedilip geri okunur, düz metin kayıt tutulmaz', () async {
    final store = ItsCredentialStore();
    await store.save('7', gln: '8680000000001', password: 'gizli-sifre');

    final credentials = await store.read('7');
    expect(credentials.gln, '8680000000001');
    expect(credentials.password, 'gizli-sifre');
    expect(credentials.isComplete, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  test('eski düz metin GLN ve şifre ilk okumada güvenli depoya taşınır ve silinir', () async {
    SharedPreferences.setMockInitialValues({
      'local_gln_7': '8680000000001',
      'local_its_password_7': 'eski-sifre',
    });

    final credentials = await ItsCredentialStore().read('7');
    expect(credentials.gln, '8680000000001');
    expect(credentials.password, 'eski-sifre');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
    expect(await const FlutterSecureStorage().read(key: 'its_password_7'), 'eski-sifre');
  });

  test('kullanıcıların bilgileri birbirine karışmaz', () async {
    final store = ItsCredentialStore();
    await store.save('7', gln: '1111111111111', password: 'ali-sifre');
    await store.save('8', gln: '2222222222222', password: 'ayse-sifre');

    expect((await store.read('7')).password, 'ali-sifre');
    expect((await store.read('8')).gln, '2222222222222');
  });

  test('boş kaydedilen alan silinir, eksik bilgi tamamlanmamış sayılır', () async {
    final store = ItsCredentialStore();
    await store.save('7', gln: '8680000000001', password: 'gizli-sifre');
    await store.save('7', gln: '8680000000001', password: '');

    final credentials = await store.read('7');
    expect(credentials.password, '');
    expect(credentials.isComplete, isFalse);
  });

  test('hiç kayıt yoksa iki alan da boş döner', () async {
    final credentials = await ItsCredentialStore().read('7');
    expect(credentials.gln, '');
    expect(credentials.password, '');
  });
}
