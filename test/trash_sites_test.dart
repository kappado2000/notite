import 'package:flutter_test/flutter_test.dart';
import 'package:notite/models/secret_item.dart';
import 'package:notite/services/ios_autofill.dart';

SecretItem _login(String id, String url, String user, {List<String>? sites}) =>
    SecretItem(
      id: id,
      type: SecretType.login,
      title: 'AFM',
      url: url,
      username: user,
      password: 'exemplu-$id',
      sites: sites,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  test('coș: data, dispozitivul și motivul rămân după sincronizare', () {
    final i = _login('a', 'https://www.exemplu.ro', 'ana@exemplu.ro')
      ..deletedAt = DateTime(2026, 11, 20, 10, 30)
      ..deletedFrom = 'iPhone / iPad'
      ..deletedWhy = 'Unit cu „AFM” (dublură)';
    final back = SecretItem.fromMap(i.toMap());
    expect(back.isTrashed, isTrue);
    expect(back.deletedAt, DateTime(2026, 11, 20, 10, 30));
    expect(back.deletedFrom, 'iPhone / iPad');
    expect(back.deletedWhy, contains('dublură'));
    // recuperat: câmpurile coșului dispar din document
    back.deletedAt = null;
    expect(back.toMap().containsKey('deletedAt'), isFalse);
    expect(SecretItem.fromMap(back.toMap()).isTrashed, isFalse);
  });

  test('alte site-uri: se păstrează și ajung la completarea automată iOS', () {
    final i = _login(
      'b',
      'https://www.exemplu.ro',
      'ana@exemplu.ro',
      sites: ['https://login.exemplu-auth.com'],
    );
    final back = SecretItem.fromMap(i.toMap());
    expect(back.sites, ['https://login.exemplu-auth.com']);
    expect(back.searchText, contains('exemplu-auth'));
    final hosts = IosAutofill.loginsFor([back]).map((m) => m['host']).toSet();
    expect(hosts, containsAll(['exemplu.ro', 'login.exemplu-auth.com']));
    // același cont (același id) pe ambele site-uri
    expect(IosAutofill.loginsFor([back]).map((m) => m['id']).toSet(), {'b'});
  });
}
