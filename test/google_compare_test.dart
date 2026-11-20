import 'package:flutter_test/flutter_test.dart';
import 'package:notite/models/secret_item.dart';
import 'package:notite/services/csv_import.dart';
import 'package:notite/services/google_compare.dart';

var _n = 0;
SecretItem _new([SecretType t = SecretType.login]) => SecretItem(
  id: 'n${_n++}',
  type: t,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

SecretItem _login(
  String url,
  String user,
  String pass, {
  List<String>? sites,
  List<String> old = const [],
}) => _new()
  ..title = 'Exemplu'
  ..url = url
  ..username = user
  ..password = pass
  ..sites = sites ?? []
  ..passwordHistory = [for (final o in old) PasswordVersion(o, DateTime(2025))];

void main() {
  const csv =
      'name,url,username,password,note\n'
      'a,https://login.exemplu-auth.b2clogin.com/x,ana@exemplu.ro,p1,\n'
      'b,https://login.exemplu-auth.b2clogin.com/x,ion@exemplu.ro,p2,\n'
      'c,https://www.magazin.ro,ana@exemplu.ro,veche,\n'
      'd,https://www.magazin.ro,ion@exemplu.ro,alta,\n'
      'e,https://forum.ro,ana@exemplu.ro,p5,\n';

  test('compară: lipsă, parolă veche, parolă diferită, identic', () {
    final existing = [
      // același cont, legat de pagina de logare prin „Alte site-uri”
      _login(
        'https://www.exemplu.ro',
        'ana@exemplu.ro',
        'p1',
        sites: ['https://login.exemplu-auth.b2clogin.com'],
      ),
      _login('https://magazin.ro', 'ana@exemplu.ro', 'noua', old: ['veche']),
      _login('https://magazin.ro', 'ion@exemplu.ro', 'a-mea'),
    ];
    final r = compareWithCsv(csv, existing: existing, create: _new);
    expect(r.same, 1);
    expect(r.missing.map((i) => i.username).toList()..sort(), [
      'ana@exemplu.ro', // forum.ro
      'ion@exemplu.ro', // b2clogin
    ]);
    expect(r.different.length, 2);
    expect(
      r.different
          .firstWhere((d) => d.local.username == 'ana@exemplu.ro')
          .olderInNotite,
      isTrue,
    );
    expect(
      r.different
          .firstWhere((d) => d.local.username == 'ion@exemplu.ro')
          .olderInNotite,
      isFalse,
    );
  });

  test('o altă firmă pe b2clogin nu e același site', () {
    final existing = [
      _login('https://alta-firma.b2clogin.com', 'ana@exemplu.ro', 'p1'),
    ];
    final r = compareWithCsv(csv, existing: existing, create: _new);
    expect(r.missing.length, 5);
  });

  test(
    'export pentru Google: format Chrome, un rând pe site, se reimportă',
    () {
      final items = [
        _login(
          'https://www.exemplu.ro',
          'ana@exemplu.ro',
          'p,"1"',
          sites: ['login.exemplu-auth.b2clogin.com'],
        ),
        _new()
          ..title = 'Fără site cunoscut xyz'
          ..username = 'x'
          ..password = 'y',
      ];
      final r = googleCsv(items);
      expect(r.rows, 2);
      expect(r.skipped, 1);
      expect(r.csv.split('\n').first, 'name,url,username,password,note');
      final back = parseCsv(r.csv);
      expect(back[1][3], 'p,"1"');
      expect(back[2][1], 'https://login.exemplu-auth.b2clogin.com');
    },
  );
}
