import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notite/models/secret_item.dart';
import 'package:notite/services/full_backup.dart';
import 'package:notite/services/ios_autofill.dart';
import 'package:notite/services/two_factor_sites.dart';

void main() {
  test('backup criptat: se deschide doar cu parola corectă', () async {
    final data = {
      'format': 'notite-backup',
      'secrets': [
        {'id': 'a', 'password': 'exemplu-parola'},
      ],
    };
    final bytes = await FullBackup.encryptWithPassword(data, 'parola-backup-1');
    expect(FullBackup.isEncrypted(bytes), isTrue);
    // parola din backup nu apare în clar în fișier
    expect(latin1.decode(bytes).contains('exemplu-parola'), isFalse);
    final back = await FullBackup.decrypt(bytes, 'parola-backup-1');
    expect(back['secrets'][0]['password'], 'exemplu-parola');
    await expectLater(
      FullBackup.decrypt(bytes, 'gresita-123'),
      throwsA(isA<FormatException>()),
    );
    // fișier stricat
    final broken = Uint8List.fromList(bytes)..[bytes.length - 3] ^= 1;
    await expectLater(
      FullBackup.decrypt(broken, 'parola-backup-1'),
      throwsA(isA<FormatException>()),
    );
    expect(FullBackup.isEncrypted(utf8.encode('{"format":1}')), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('2fa.directory: domenii, domenii suplimentare, subdomenii', () {
    final sites = TwoFactorSites.parseDirectory(
      jsonEncode([
        [
          'Yahoo',
          {
            'domain': 'yahoo.com',
            'additional-domains': ['yahoo.ro'],
            'documentation': 'https://help.yahoo.com/2fa',
            'tfa': ['totp'],
          },
        ],
        [
          'Fără doc',
          {
            'domain': 'exemplu.ro',
            'tfa': ['totp'],
          },
        ],
        'gunoi',
      ]),
    );
    expect(
      TwoFactorSites.matchHost(sites, 'login.yahoo.com'),
      'https://help.yahoo.com/2fa',
    );
    expect(
      TwoFactorSites.matchHost(sites, 'www.yahoo.ro'),
      'https://help.yahoo.com/2fa',
    );
    expect(TwoFactorSites.matchHost(sites, 'exemplu.ro'), '');
    expect(TwoFactorSites.matchHost(sites, 'altceva.ro'), isNull);
    expect(TwoFactorSites.matchHost(sites, 'notyahoo.com'), isNull);
  });

  test('completarea automată iOS primește cheia 2FA', () {
    final now = DateTime(2026, 1, 1);
    final i =
        SecretItem(
            id: 'x',
            type: SecretType.login,
            createdAt: now,
            updatedAt: now,
          )
          ..title = 'Exemplu'
          ..url = 'https://exemplu.ro'
          ..username = 'eu'
          ..password = 'p'
          ..totp =
              'otpauth://totp/x?secret=JBSWY3DPEHPK3PXP&digits=8&period=60';
    final m = IosAutofill.loginsFor([i]).single;
    expect(base64Decode(m['otpKey']!), [
      ...ascii.encode('Hello!'),
      0xDE, 0xAD, 0xBE, 0xEF, //
    ]);
    expect(m['otpDigits'], '8');
    expect(m['otpPeriod'], '60');
    expect(m['otpAlg'], 'SHA1');
    final fara = IosAutofill.loginsFor([i..totp = '']).single;
    expect(fara.containsKey('otpKey'), isFalse);
  });
}
