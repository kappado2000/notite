import 'package:flutter_test/flutter_test.dart';
import 'package:notite/models/secret_item.dart';
import 'package:notite/services/secret_helpers.dart';

/// Recunoașterea categoriei pentru ~450 de conturi trebuie să fie rapidă
/// (o face ecranul „Repară parolele”).
void main() {
  test('categoriile pentru 450 de conturi, sub 200 ms', () {
    final now = DateTime(2026);
    final items = [
      for (var i = 0; i < 450; i++)
        SecretItem(
          id: 'id$i',
          type: SecretType.login,
          title: 'Site necunoscut $i',
          url: 'https://www.exemplu$i.ro/login',
          createdAt: now,
          updatedAt: now,
        ),
    ];
    // prima trecere încălzește codul (în aplicație rulează compilat)
    for (final i in items.take(50)) {
      loginCategory(i);
    }
    final sw = Stopwatch()..start();
    for (final i in items) {
      loginCategory(i);
    }
    sw.stop();
    // ignore: avoid_print
    print('450 categorii: ${sw.elapsedMilliseconds} ms');
    expect(sw.elapsedMilliseconds, lessThan(200));
  });
}
