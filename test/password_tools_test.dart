import 'package:flutter_test/flutter_test.dart';
import 'package:notite/models/secret_item.dart';
import 'package:notite/services/password_tools.dart';
import 'package:notite/services/totp.dart';

void main() {
  group('TOTP (vectorii oficiali RFC 6238, SHA1)', () {
    // Cheia ASCII „12345678901234567890” în Base32.
    const key = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
    final t = Totp.parse(
      'otpauth://totp/Test?secret=$key&digits=8&algorithm=SHA1',
    )!;
    final cases = {
      59: '94287082',
      1111111109: '07081804',
      1111111111: '14050471',
      1234567890: '89005924',
      2000000000: '69279037',
    };
    cases.forEach((seconds, expected) {
      test('t=$seconds → $expected', () {
        expect(
          t.code(DateTime.fromMillisecondsSinceEpoch(seconds * 1000)),
          expected,
        );
      });
    });

    test('cheie Base32 simplă, cu spații și litere mici', () {
      final simple = Totp.parse('gezd gnbv gy3t qojq gezd gnbv gy3t qojq')!;
      expect(simple.digits, 6);
      expect(simple.code(DateTime.fromMillisecondsSinceEpoch(59000)), '287082');
    });

    test('cheie invalidă', () {
      expect(Totp.parse('nu e cheie!'), isNull);
      expect(Totp.parse(''), isNull);
    });
  });

  group('generator', () {
    test('lungime și toate tipurile de caractere', () {
      for (var i = 0; i < 200; i++) {
        final p = PasswordGenerator.generate(length: 16);
        expect(p.length, 16);
        expect(p, matches(RegExp('[a-z]')));
        expect(p, matches(RegExp('[A-Z]')));
        expect(p, matches(RegExp(r'\d')));
        expect(p, matches(RegExp(r'[^a-zA-Z\d]')));
        expect(p, isNot(matches(RegExp('[lIO01]'))));
      }
    });

    test('doar litere mici când restul sunt oprite', () {
      final p = PasswordGenerator.generate(
        length: 30,
        upper: false,
        digits: false,
        symbols: false,
      );
      expect(p, matches(RegExp(r'^[a-z]{30}$')));
    });

    test('parolele generate sunt evaluate „Foarte bună”', () {
      expect(
        passwordStrength(PasswordGenerator.generate(length: 20)),
        Strength.strong,
      );
    });
  });

  test('puterea parolelor', () {
    expect(passwordStrength('parola123'), Strength.weak);
    expect(passwordStrength('12345678901'), Strength.weak);
    expect(passwordStrength('abc'), Strength.weak);
    expect(passwordStrength('casaverde12'), Strength.fair);
    expect(passwordStrength('CasaVerde12!'), Strength.good);
  });

  test('validare card (Luhn) și emitent', () {
    expect(luhnValid('4111111111111111'), isTrue);
    expect(luhnValid('4111111111111112'), isFalse);
    expect(cardBrand('4111111111111111'), 'Visa');
    expect(cardBrand('5500000000000004'), 'Mastercard');
  });

  test('cod QR Wi-Fi cu caractere speciale', () {
    final now = DateTime.now();
    final w = SecretItem(
      id: '1',
      type: SecretType.wifi,
      username: 'Acasa;5G',
      password: r'a"b\c',
      createdAt: now,
      updatedAt: now,
    );
    expect(wifiQrPayload(w), r'WIFI:T:WPA;S:Acasa\;5G;P:a\"b\\c;;');
  });

  test('raport: parole slabe și repetate', () {
    final now = DateTime.now();
    SecretItem login(String id, String pw) => SecretItem(
      id: id,
      type: SecretType.login,
      password: pw,
      createdAt: now,
      updatedAt: now,
    );
    final r = PasswordReport.of([
      login('a', 'parola123'),
      login('b', 'X9!vT4#qL8@wZ2m'),
      login('c', 'X9!vT4#qL8@wZ2m'),
    ]);
    expect(r.weak.map((i) => i.id), ['a']);
    expect(r.reused.single.map((i) => i.id), ['b', 'c']);
  });
}
