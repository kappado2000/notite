import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notite/services/vault.dart';

void main() {
  test('cheia se deblochează cu parola corectă, nu cu una greșită', () async {
    final r = await Vault.create('parola-mea-123');
    final doc = jsonDecode(jsonEncode(r.keysDoc)) as Map<String, dynamic>;

    final ok = await Vault.unlockWithPassword(doc, 'parola-mea-123');
    expect(ok, isNotNull);
    expect(await Vault.unlockWithPassword(doc, 'gresita'), isNull);

    // Cheia deblocată descifrează ce a cifrat cea originală.
    final enc = await r.vault.encryptMap({'title': 'Secret'}, 'notes/1');
    expect(await ok!.decryptMap(enc, 'notes/1'), {'title': 'Secret'});
  });

  test('codul de recuperare merge și scris neglijent', () async {
    final r = await Vault.create('p');
    final doc = jsonDecode(jsonEncode(r.keysDoc)) as Map<String, dynamic>;
    expect(r.recoveryCode, matches(RegExp(r'^([0-9A-Z]{4}-){7}[0-9A-Z]{4}$')));

    final messy = '  ${r.recoveryCode.toLowerCase().replaceAll('-', ' ')} ';
    expect(await Vault.unlockWithRecoveryCode(doc, messy), isNotNull);
    expect(
      await Vault.unlockWithRecoveryCode(doc, Vault.newRecoveryCode()),
      isNull,
    );
  });

  test('după resetarea parolei: recuperare + reîmpachetare', () async {
    final r = await Vault.create('veche');
    final doc = jsonDecode(jsonEncode(r.keysDoc)) as Map<String, dynamic>;
    final enc = await r.vault.encryptMap({'x': 1}, 'notes/a');

    final recovered = await Vault.unlockWithRecoveryCode(doc, r.recoveryCode);
    doc['password'] = await recovered!.wrapForPassword('noua');

    expect(await Vault.unlockWithPassword(doc, 'veche'), isNull);
    final v = await Vault.unlockWithPassword(doc, 'noua');
    expect(await v!.decryptMap(enc, 'notes/a'), {'x': 1});
  });

  test('textul criptat nu poate fi mutat pe alt document', () async {
    final r = await Vault.create('p');
    final enc = await r.vault.encryptMap({'x': 1}, 'notes/a');
    expect(
      () => r.vault.decryptMap(enc, 'notes/b'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('atașamente binare: dus-întors, fără text în clar', () async {
    final r = await Vault.create('p');
    final rnd = Random(1);
    final data = Uint8List.fromList(
      List.generate(2 * 1024 * 1024, (_) => rnd.nextInt(256)),
    );
    final enc = await r.vault.encryptBytes(data, 'blobs/a_0');
    expect(enc.length, data.length + 12 + 16); // nonce + MAC
    expect(await r.vault.decryptBytes(enc, 'blobs/a_0'), data);

    final plain = utf8.encode('Lista de cumparaturi');
    final encText = await r.vault.encryptBytes(plain, 'notes/z');
    expect(String.fromCharCodes(encText).contains('cumparaturi'), isFalse);
  });
}
