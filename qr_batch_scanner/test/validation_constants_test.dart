import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_batch_scanner/core/constants/validation_constants.dart';

String _type(String text) {
  final result = UsernameSpaceFormatter().formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)),
  );
  return result.text;
}

void main() {
  test('yazarken boşluk alt çizgiye döner', () {
    expect(_type('Ayşe Nur'), 'Ayşe_Nur');
    expect(_type('Ayşe   Nur'), 'Ayşe_Nur');
    expect(_type('Ayşe_ '), 'Ayşe_');
    expect(_type('  Ayşe'), 'Ayşe');
  });

  test('kullanıcı adı kuralı backend ile aynı', () {
    expect(validateUsername('Çağrı.Şen-1_'), isNull);
    expect(validateUsername('ali'), isNull);
    expect(validateUsername('ab'), isNotNull);
    expect(validateUsername('ali@veli'), isNotNull);
    expect(validateUsername('a' * 50), isNull);
    expect(validateUsername('a' * 51), isNotNull);
  });

  test('e-posta kuralı backend ile aynı', () {
    expect(validateEmail('ali@test.com'), isNull);
    expect(validateEmail('ali.veli@eczane.com.tr'), isNull);
    expect(validateEmail('abc'), isNotNull);
    expect(validateEmail('ali@test'), isNotNull);
    expect(validateEmail(''), isNotNull);
  });
}
