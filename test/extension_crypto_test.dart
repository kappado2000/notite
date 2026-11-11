import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notite/services/vault.dart';

/// Extensia de browser (extension/lib/crypto.js) trebuie să citească și să
/// scrie exact ce scrie aplicația. Rulează codul extensiei în Node.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'extensia citește și scrie la fel ca aplicația',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const password = 'Parola-Test#2026 ăîșț';
      final created = await Vault.create(password);
      final item = {
        'id': 'test-1',
        'type': 'login',
        'title': 'eMAG',
        'url': 'https://www.emag.ro',
        'username': 'exemplu@test.ro',
        'password': 'K7#pQ2!vX9',
        'updatedAt': 1762000000000,
      };
      final enc = await created.vault.encryptMap(item, 'secrets/test-1');

      final p = await Process.start('node', [
        'extension/test/compat.mjs',
      ], runInShell: true);
      p.stdin.write(
        jsonEncode({
          'password': password,
          'keysDoc': created.keysDoc,
          'enc': enc,
          'path': 'secrets/test-1',
        }),
      );
      await p.stdin.close();
      final out = await p.stdout.transform(utf8.decoder).join();
      final err = await p.stderr.transform(utf8.decoder).join();
      expect(await p.exitCode, 0, reason: err);

      final r = jsonDecode(out) as Map<String, dynamic>;
      expect(r['wrongIsNull'], isTrue);
      expect(r['decoded'], item);
      final back = await created.vault.decryptMap(
        r['reenc'] as String,
        'secrets/din-extensie',
      );
      expect(back['password'], 'din-extensie');
      expect(back['username'], 'exemplu@test.ro');
      // calea greșită nu se decriptează (documentul nu poate fi mutat)
      expect(
        () => created.vault.decryptMap(r['reenc'] as String, 'secrets/alta'),
        throwsA(anything),
      );
    },
    skip: Process.runSync('node', ['--version'], runInShell: true).exitCode == 0
        ? false
        : 'node lipsește',
  );
}
