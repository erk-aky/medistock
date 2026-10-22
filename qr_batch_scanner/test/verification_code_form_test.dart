import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_batch_scanner/features/auth/verification_code_form.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('6 haneden kısa kod gönderilmez, 6 haneli kod iletilir', (tester) async {
    final verified = <String>[];
    await tester.pumpWidget(_wrap(VerificationCodeForm(
      onVerify: (code) async {
        verified.add(code);
        return true;
      },
      onResend: () async => true,
      isLoading: false,
    )));

    await tester.enterText(find.byType(TextFormField), '123');
    await tester.tap(find.text('Kodu Doğrula'));
    await tester.pump();
    expect(find.text('6 haneli kodu girin'), findsOneWidget);
    expect(verified, isEmpty);

    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('Kodu Doğrula'));
    await tester.pump();
    expect(verified, ['123456']);

    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('tekrar gönder 60 saniye bekler, 3 haktan sonra kapanır', (tester) async {
    var resendCount = 0;
    await tester.pumpWidget(_wrap(VerificationCodeForm(
      onVerify: (_) async => true,
      onResend: () async {
        resendCount++;
        return true;
      },
      isLoading: false,
    )));

    expect(find.text('Kodu tekrar gönder (60 sn)'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 60));
      await tester.tap(find.textContaining('kalan hak'));
      await tester.pump();
    }

    expect(resendCount, 3);
    await tester.pump(const Duration(seconds: 60));
    expect(find.text('Başka hakkınız bulunmamaktadır.'), findsOneWidget);
  });

  testWidgets('kod gönderilemezse hak düşmez', (tester) async {
    await tester.pumpWidget(_wrap(VerificationCodeForm(
      onVerify: (_) async => true,
      onResend: () async => false,
      isLoading: false,
    )));

    await tester.pump(const Duration(seconds: 60));
    await tester.tap(find.text('Kodu tekrar gönder (kalan hak: 3)'));
    await tester.pump();
    expect(find.text('Kodu tekrar gönder (kalan hak: 3)'), findsOneWidget);
  });

  testWidgets('kodun hakkı bitince alan ve doğrula butonu kapanır', (tester) async {
    var verifyCalled = false;
    await tester.pumpWidget(_wrap(VerificationCodeForm(
      onVerify: (_) async {
        verifyCalled = true;
        return false;
      },
      onResend: () async => true,
      isLoading: false,
      attemptsLeft: 0,
      verifyLabel: 'Şifreyi Güncelle',
    )));

    expect(find.text('Kod 3 kez yanlış girildi, lütfen yeni kod isteyin.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.text('Şifreyi Güncelle'));
    await tester.pump();
    expect(verifyCalled, isFalse);

    await tester.pump(const Duration(seconds: 60));
  });
}
