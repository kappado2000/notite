import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:notite/models/secret_item.dart';
import 'package:notite/services/recovery_codes.dart';

SecretItem _login(
  String id,
  String title, {
  String totp = '',
  String codes = '',
  String notes = '',
}) => SecretItem(
  id: id,
  type: SecretType.login,
  title: title,
  username: 'ana@exemplu.ro',
  password: 'exemplu-$id',
  totp: totp,
  recoveryCodes: codes,
  notes: notes,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ro'));

  test('codurile de rezervă se păstrează la sincronizare', () {
    final i = _login('a', 'Exemplu', codes: '1111 2222\n3333 4444');
    final back = SecretItem.fromMap(i.toMap());
    expect(back.recoveryCodes, '1111 2222\n3333 4444');
    // fără coduri, câmpul nu apare în document
    expect(_login('b', 'X').toMap().containsKey('recoveryCodes'), isFalse);
  });

  test('găsește codurile scrise în notițe și lasă restul', () {
    const notes =
        'Cont principal.\n\n'
        'Coduri de rezervă:\n'
        '1234 5678\n'
        '2345 6789\n'
        '3456 7890\n'
        '4567 8901\n\n'
        'Telefon recuperare pe numele Anei.';
    final r = RecoveryCodes.fromNotes(notes)!;
    expect(RecoveryCodes.lines(r.codes), [
      '1234 5678',
      '2345 6789',
      '3456 7890',
      '4567 8901',
    ]);
    expect(r.notes, contains('Cont principal.'));
    expect(r.notes, contains('Telefon recuperare'));
    expect(r.notes, isNot(contains('Coduri de rezervă')));
    expect(r.notes, isNot(contains('1234')));
  });

  test('coduri cu litere (ex. abcde-12345) și numerotate', () {
    final r = RecoveryCodes.fromNotes(
      '1. abcde-12345\n2. fghij-67890\n3. klmno-24680',
    )!;
    expect(RecoveryCodes.lines(r.codes).length, 3);
    expect(r.notes, isEmpty);
  });

  test('textul obișnuit nu e luat drept coduri', () {
    expect(
      RecoveryCodes.fromNotes('Cumpărat în 2024.\nGaranție 2 ani.'),
      isNull,
    );
    expect(RecoveryCodes.fromNotes('1111 2222\n3333 4444'), isNull); // sub 3
  });

  test('lista: doar conturile cu 2FA; amprenta se schimbă cu codurile', () {
    final a = _login('a', 'Alfa', totp: 'JBSWY3DPEHPK3PXP');
    final b = _login('b', 'Beta');
    final c = _login('c', 'Gama', codes: '1111 2222\n3333 4444\n5555 6666');
    final list = RecoveryCodes.accounts([b, c, a]);
    expect(list.map((i) => i.id), ['a', 'c']);
    final f1 = RecoveryCodes.fingerprint(list);
    a.recoveryCodes = '7777 8888\n9999 0000\n1212 3434';
    expect(RecoveryCodes.fingerprint(list), isNot(f1));
  });

  test('PDF-ul se face (cu diacritice)', () async {
    final bytes = await RecoveryCodes.pdf([
      _login(
        'a',
        'Rețea socială',
        totp: 'JBSWY3DPEHPK3PXP',
        codes: '1111 2222\n3333 4444\n5555 6666',
      ),
      _login('b', 'Fără coduri', totp: 'JBSWY3DPEHPK3PXP'),
    ]);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('exportul text: conturile cu coduri și cele fără', () {
    final t = RecoveryCodes.text([
      _login(
        'a',
        'Rețea',
        totp: 'JBSWY3DPEHPK3PXP',
        codes: '1111 2222\n3333 4444\n5555 6666',
      ),
      _login('b', 'Fără coduri', totp: 'JBSWY3DPEHPK3PXP'),
    ]);
    expect(t, contains('Rețea'));
    expect(t, contains('  [ ] 3333 4444'));
    expect(t, contains('fără coduri de rezervă salvate'));
    expect(t, contains('  - Fără coduri (ana@exemplu.ro)'));
  });
}
