import 'package:flutter_test/flutter_test.dart';
import 'package:notite/models/secret_item.dart';
import 'package:notite/services/breach_check.dart';
import 'package:notite/services/card_parser.dart';
import 'package:notite/services/csv_import.dart';
import 'package:notite/services/id_card_parser.dart';
import 'package:notite/services/reminder_service.dart';
import 'package:notite/services/ro_names.dart';
import 'package:notite/services/secret_helpers.dart';

var _n = 0;
SecretItem _new([SecretType t = SecretType.login]) {
  final now = DateTime(2026, 1, 1);
  return SecretItem(id: 'id${_n++}', type: t, createdAt: now, updatedAt: now);
}

void main() {
  test('IBAN: validare, formatare, banca', () {
    expect(ibanValid('RO49 AAAA 1B31 0075 9384 0000'), isTrue);
    expect(ibanValid('RO49AAAA1B31007593840001'), isFalse);
    expect(ibanValid('GB82 WEST 1234 5698 7654 32'), isTrue);
    expect(ibanValid('RO49AAAA1B3100759384'), isFalse); // lungime
    expect(
      formatIban('ro49aaaa1b31007593840000'),
      'RO49 AAAA 1B31 0075 9384 0000',
    );
    expect(
      bankFromIban('RO66 BTRL 0000 0000 0000 0000')?.name,
      'Banca Transilvania',
    );
    expect(bankFromIban('RO66 RNCB 0000')?.swift, 'RNCBROBU');
    expect(bankFromIban('DE89370400440532013000'), isNull);
  });

  test('CNP: cifră de control și data nașterii', () {
    expect(cnpValid('1800101123456'), isFalse);
    // 1800101 + 12345 → cifra de control calculată.
    const k = '279146358279';
    String withCheck(String s12) {
      var sum = 0;
      for (var i = 0; i < 12; i++) {
        sum += int.parse(s12[i]) * int.parse(k[i]);
      }
      final c = sum % 11 == 10 ? 1 : sum % 11;
      return '$s12$c';
    }

    final cnp = withCheck('180010112345');
    expect(cnpValid(cnp), isTrue);
    expect(cnpBirthDate(cnp), DateTime(1980, 1, 1));
    expect(cnpValid(withCheck('180023012345')), isFalse); // 30 februarie
    expect(cnpBirthDate(withCheck('503121512345')), DateTime(2003, 12, 15));
  });

  test('frază-parolă', () {
    expect(passphraseWords.toSet().length, passphraseWords.length);
    expect(passphraseWords.length, greaterThan(400));
    final p = generatePassphrase();
    expect(p.split('-').length, 5);
    expect(RegExp(r'\d').hasMatch(p), isTrue);
    expect(RegExp('[A-Z]').hasMatch(p), isTrue);
    expect(
      generatePassphrase(words: 4, addNumber: false, capitalize: false),
      matches(RegExp(r'^[a-z]+(-[a-z]+){3}$')),
    );
  });

  test('recunoaștere site', () {
    expect(recognizeSite('emag')?.name, 'eMAG');
    expect(recognizeSite('https://www.emag.ro/cart')?.name, 'eMAG');
    expect(recognizeSite('Cărturești')?.domain, 'carturesti.ro');
    expect(recognizeSite('george')?.name, 'BCR');
    expect(recognizeSite('ceva necunoscut'), isNull);
    expect(suggestSites('ne').map((s) => s.name), contains('Netflix'));
    expect(hostOf('HTTPS://www.Netflix.com/login'), 'netflix.com');
  });

  test('sugestii utilizator / email', () {
    final items = [
      _new()..username = 'ion@gmail.com',
      _new()..username = 'ion@gmail.com',
      _new()..username = 'ion.popescu',
    ];
    expect(usernameSuggestions('io', items).first, 'ion@gmail.com');
    expect(usernameSuggestions('maria@ya', items), [
      'maria@yahoo.com',
      'maria@yahoo.ro',
    ]);
  });

  test('clipboard', () {
    expect(classifyClip('otpauth://totp/X?secret=JBSWY3DP'), ClipKind.otpauth);
    expect(classifyClip('RO49AAAA1B31007593840000'), ClipKind.iban);
    expect(classifyClip('4111 1111 1111 1111'), ClipKind.card);
    expect(classifyClip('a@b.ro'), ClipKind.email);
    expect(classifyClip('https://emag.ro'), ClipKind.url);
    expect(classifyClip('K7#pQ2!vX9'), ClipKind.password);
    expect(classifyClip('un text oarecare'), ClipKind.text);
  });

  test('otpauth: emitent și cont', () {
    final r = otpauthLabel(
      'otpauth://totp/GitHub:ion%40gmail.com?secret=JBSWY3DP&issuer=GitHub',
    );
    expect(r?.issuer, 'GitHub');
    expect(r?.account, 'ion@gmail.com');
  });

  test('CSV: Chrome, Bitwarden, dubluri, ghilimele', () {
    const chrome =
        'name,url,username,password,note\n'
        'emag.ro,https://www.emag.ro/,ion@gmail.com,"pa,ss""1",\n'
        'site.ro,https://site.ro/,ion,secret2,"rând1\nrând2"\n'
        'emag.ro,https://www.emag.ro/,ion@gmail.com,"pa,ss""1",\n';
    final existing = [
      _new()
        ..url = 'site.ro'
        ..username = 'ion'
        ..password = 'secret2',
    ];
    final r = secretsFromCsv(chrome, existing: existing, create: _new);
    expect(r.source, 'Chrome');
    expect(r.items.length, 1);
    expect(r.skipped, 2);
    expect(r.items.first.title, 'eMAG');
    expect(r.items.first.password, 'pa,ss"1');

    const bw =
        'folder,favorite,type,name,notes,fields,reprompt,login_uri,'
        'login_username,login_password,login_totp\n'
        ',,login,Netflix,,,0,https://netflix.com,a@b.ro,p1,\n'
        ',,card,Card,,,0,,,,\n';
    final b = secretsFromCsv(bw, existing: const [], create: _new);
    expect(b.source, 'Bitwarden');
    expect(b.items.single.title, 'Netflix');
    expect(b.skipped, 1);

    expect(
      () => secretsFromCsv('a,b\n1,2', existing: const [], create: _new),
      throwsFormatException,
    );
    expect(parseCsv('a;b\n1;2'), [
      ['a', 'b'],
      ['1', '2'],
    ]);
  });

  test('HIBP: amprentă și răspuns cu umplutură', () {
    expect(
      BreachCheck.sha1Hex('password'),
      '5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8',
    );
    final m = BreachCheck.parseRange(
      '1E4C9B93F3F0682250B6CF8331B7EE68FD8:3861493\r\nABCDEF:0\r\n',
    );
    expect(m['1E4C9B93F3F0682250B6CF8331B7EE68FD8'], 3861493);
    expect(m.containsKey('ABCDEF'), isFalse);
  });

  test('model: tipuri noi, expirare, cost lunar, compatibilitate', () {
    final card = _new(SecretType.card)..cardExpiry = '02/28';
    expect(card.expiresOn, DateTime(2028, 2, 29));
    final sub = _new(SecretType.subscription)
      ..price = '120'
      ..period = BillingPeriod.yearly
      ..renewalDate = DateTime(2026, 5, 1);
    expect(sub.monthlyCost, 10);
    final id = _new(SecretType.identity)
      ..lastName = 'Popescu'
      ..firstName = 'Ion'
      ..cnp = '123'
      ..expiryDate = DateTime(2030, 1, 1)
      ..passwordHistory = [PasswordVersion('vechi', DateTime(2025))];
    final back = SecretItem.fromMap(id.toMap());
    expect(back.type, SecretType.identity);
    expect(back.fullName, 'Popescu Ion');
    expect(back.expiryDate, DateTime(2030, 1, 1));
    expect(back.passwordHistory.single.password, 'vechi');
    expect(back.searchText.contains('123'), isFalse);
    // Date vechi, fără câmpurile noi.
    final old = SecretItem.fromMap({
      'id': 'x',
      'type': 'login',
      'createdAt': 0,
      'updatedAt': 0,
    });
    expect(old.passwordHistory, isEmpty);
    expect(old.period, BillingPeriod.monthly);
  });

  test('memento expirare: cu 30 de zile înainte sau în ziua expirării', () {
    final id = _new(SecretType.identity)..expiryDate = DateTime(2026, 12, 31);
    expect(
      ReminderService.secretReminderAt(id, now: DateTime(2026, 10, 22)),
      DateTime(2026, 12, 1, 10),
    );
    expect(
      ReminderService.secretReminderAt(id, now: DateTime(2026, 12, 20)),
      DateTime(2026, 12, 31, 10),
    );
    expect(
      ReminderService.secretReminderAt(id, now: DateTime(2027, 1, 2)),
      isNull,
    );
  });

  test('buletin vechi: etichete + MRZ', () {
    const k = '279146358279';
    var sum = 0;
    const s12 = '180010112345';
    for (var i = 0; i < 12; i++) {
      sum += int.parse(s12[i]) * int.parse(k[i]);
    }
    final cnp = '$s12${sum % 11 == 10 ? 1 : sum % 11}';
    final text =
        'ROMANIA ROUMANIE ROMANIA\n'
        'CARTE DE IDENTITATE\n'
        'IDENTITY CARD\n'
        'SERIA RX NR 123456\n'
        'CNP $cnp\n'
        'Nume/Nom/Last name\n'
        'POPESCU\n'
        'Prenume/Prenom/First name\n'
        'ION-MIHAI\n'
        'Cetățenie/Nationalité/Nationality\n'
        'Română / ROU\n'
        'Loc naștere/Lieu de naissance/Place of birth\n'
        'Jud.CJ Mun.Cluj-Napoca\n'
        'Domiciliu/Adresse/Address\n'
        'Jud.CJ Mun.Cluj-Napoca\n'
        'Str.Memorandumului nr.28 ap.3\n'
        'Emisă de/Délivrée par/Issued by\n'
        'SPCLEP Cluj-Napoca\n'
        'Valabilitate/Validité/Validity\n'
        '12.03.15-01.01.2025\n'
        'IDROUPOPESCU<<ION<MIHAI<<<<<<<<<<<<<\n'
        'RX123456<4ROU8001015M250101912345674\n';
    final d = parseRomanianId(text);
    expect(d.lastName, 'POPESCU');
    expect(d.firstName, 'ION-MIHAI');
    expect(d.cnp, cnp);
    expect(d.series, 'RX');
    expect(d.number, '123456');
    expect(d.address, 'Jud.CJ Mun.Cluj-Napoca, Str.Memorandumului nr.28 ap.3');
    expect(d.issuedBy, 'SPCLEP Cluj-Napoca');
    expect(d.issueDate, DateTime(2015, 3, 12));
    expect(d.expiryDate, DateTime(2025, 1, 1));
    expect(d.found, 9);
  });

  test('buletin: doar MRZ citit corect', () {
    final d = parseRomanianId(
      'ceva zgomot\n'
      'IDROUIONESCU<<MARIA<ELENA<<<<<<<<<<<<\n'
      'KX654321<5ROU9002024F300101823456789\n',
    );
    expect(d.lastName, 'IONESCU');
    expect(d.firstName, 'MARIA-ELENA');
    expect(d.series, 'KX');
    expect(d.number, '654321');
    expect(d.expiryDate, DateTime(2030, 1, 1));
  });

  test('corectarea numelor citite greșit (K în loc de M/N)', () {
    expect(fixNameOcr('POP KARIA'), 'POP MARIA');
    expect(fixNameOcr('POP SIMION ADRIAK'), 'POP SIMION ADRIAN');
    expect(fixNameOcr('SIMION-ADRIAK'), 'SIMION-ADRIAN');
    expect(fixNameOcr('MARIAKKKK'), 'MARIA');
    expect(fixNameOcr('Pop Karia'), 'Pop Maria');
    // Numele corecte și cele necunoscute rămân neatinse.
    expect(fixNameOcr('DARIA POPESCU'), 'DARIA POPESCU');
    expect(fixNameOcr('KARINA'), 'KARINA');
    expect(fixNameOcr('ȘTEFĂNESCU ZENOBIA'), 'ȘTEFĂNESCU ZENOBIA');
    expect(fixNameOcr('POPESKU'), 'POPESKU'); // diferență neconfundabilă
    // Pe card și pe buletin, corectura se aplică automat.
    expect(
      parseCardText('4111 1111 1111 1111\n12/29\nPOP SIMION ADRIAK').holder,
      'POP SIMION ADRIAN',
    );
    expect(
      parseRomanianId(
        'Nume/Nom/Last name\nPOP\nPrenume/Prenom/First name\n'
        'KARIA\n',
      ).firstName,
      'MARIA',
    );
  });

  test('card: număr despărțit pe rânduri / blocuri, litere în loc de cifre', () {
    // Așa întoarce adesea ML Kit: fiecare grup pe rândul lui.
    final d = parseCardText(
      'BT\nVISA\n4111\n1111\n1111\n1111\nVALID THRU\n12/29\nPOP SIMION ADRIAK',
    );
    expect(d.number, '4111 1111 1111 1111');
    expect(d.expiry, '12/29');
    expect(d.holder, 'POP SIMION ADRIAN');
    // S citit în loc de 5, O în loc de 0; grupuri pe două rânduri.
    expect(parseCardText('S555 5555\n5555 4444').number, '5555 5555 5555 4444');
    expect(parseCardText('4111 1111 1111 111O').number, isEmpty); // Luhn
    // Alte numere de pe card (telefon, cod) nu sunt luate drept număr.
    expect(parseCardText('0800 801 228\n12/29').number, isEmpty);
  });

  test('card din fotografie', () {
    final d = parseCardText(
      'Banca Transilvania\n'
      'VISA DEBIT\n'
      '4111 1111 1111 1111\n'
      'VALID FROM 03/22 VALID THRU 03/27\n'
      'ION POPESCU\n'
      'VISA\n',
    );
    expect(d.number, '4111 1111 1111 1111');
    expect(d.expiry, '03/27');
    expect(d.holder, 'ION POPESCU');
    expect(d.found, 3);
    // Un număr care nu trece de Luhn e ignorat; „O” citit în loc de 0.
    final e = parseCardText(
      '1234 5678 9012 3456\n5555 5555 5555 4444\n12/2030\nVALID THRU',
    );
    expect(parseCardText('4111 1111 1111 11I1').number, '4111 1111 1111 1111');
    expect(e.number, '5555 5555 5555 4444');
    expect(e.expiry, '12/30');
    expect(e.holder, '');
  });
}
