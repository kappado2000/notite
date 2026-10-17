import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Criptare end-to-end a datelor din cloud.
///
/// Fiecare cont are o **cheie de date** aleatorie (AES-256-GCM) cu care
/// sunt criptate notițele înainte să plece de pe dispozitiv. În cloud
/// cheia de date există doar „împachetată” (criptată) de două ori:
/// - cu o cheie derivată din **parolă** (PBKDF2-SHA256, 600.000 iterații);
/// - cu o cheie derivată din **codul de recuperare** (dat utilizatorului
///   o singură dată), pentru cazul în care își uită parola.
/// Fără una din ele, datele din cloud nu pot fi citite de nimeni.
class Vault {
  Vault._(this._key, this._keyBytes);

  final SecretKey _key;
  final List<int> _keyBytes;

  static final _aes = AesGcm.with256bits();
  static const _storage = FlutterSecureStorage();
  static const _passwordIterations = 600000;
  // Codul de recuperare are 160 de biți aleatori; nu are nevoie de multe
  // iterații ca să fie greu de ghicit.
  static const _recoveryIterations = 10000;

  // ---------------------------------------------- criptarea documentelor

  /// [path] (ex. `notes/<id>`) leagă textul criptat de locul lui, ca un
  /// document să nu poată fi mutat peste altul fără să fie detectat.
  Future<String> encryptMap(Map<String, dynamic> data, String path) async {
    final bytes = await encryptBytes(utf8.encode(jsonEncode(data)), path);
    return base64Encode(bytes);
  }

  Future<Map<String, dynamic>> decryptMap(String enc, String path) async {
    final bytes = await decryptBytes(base64Decode(enc), path);
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<Uint8List> encryptBytes(List<int> clear, String path) async {
    final box = await _aes.encrypt(
      clear,
      secretKey: _key,
      aad: utf8.encode(path),
    );
    return box.concatenation();
  }

  Future<Uint8List> decryptBytes(List<int> data, String path) async {
    final box = SecretBox.fromConcatenation(
      data,
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
      copy: false,
    );
    final clear = await _aes.decrypt(
      box,
      secretKey: _key,
      aad: utf8.encode(path),
    );
    return Uint8List.fromList(clear);
  }

  // --------------------------------------------- păstrare pe dispozitiv

  static String _localName(String uid) => 'notite_dek_$uid';

  static Future<Vault?> loadLocal(String uid) async {
    final s = await _storage.read(key: _localName(uid));
    if (s == null) return null;
    final bytes = base64Decode(s);
    return Vault._(SecretKey(bytes), bytes);
  }

  Future<void> saveLocal(String uid) =>
      _storage.write(key: _localName(uid), value: base64Encode(_keyBytes));

  static Future<void> deleteLocal(String uid) =>
      _storage.delete(key: _localName(uid));

  // ------------------------------------------ împachetarea cheii de date

  /// Cont nou: cheie de date nouă, împachetată cu parola și cu un cod de
  /// recuperare. Întoarce documentul de salvat în cloud și codul.
  static Future<
    ({Vault vault, Map<String, dynamic> keysDoc, String recoveryCode})
  >
  create(String password) async {
    final bytes = _randomBytes(32);
    final vault = Vault._(SecretKey(bytes), bytes);
    final code = newRecoveryCode();
    final keysDoc = {
      'v': 1,
      'password': await _wrap(bytes, password, _passwordIterations),
      'recovery': await _wrap(
        bytes,
        normalizeRecoveryCode(code),
        _recoveryIterations,
      ),
    };
    return (vault: vault, keysDoc: keysDoc, recoveryCode: code);
  }

  /// Despachetare cu parola; `null` dacă parola nu se potrivește
  /// (ex. a fost resetată prin email).
  static Future<Vault?> unlockWithPassword(
    Map<String, dynamic> keysDoc,
    String password,
  ) => _unwrap(keysDoc['password'], password);

  static Future<Vault?> unlockWithRecoveryCode(
    Map<String, dynamic> keysDoc,
    String code,
  ) => _unwrap(keysDoc['recovery'], normalizeRecoveryCode(code));

  /// Reîmpachetează cheia cu o parolă nouă (după resetarea parolei).
  Future<Map<String, dynamic>> wrapForPassword(String password) =>
      _wrap(_keyBytes, password, _passwordIterations);

  /// Cod de recuperare nou; întoarce codul și împachetarea lui.
  Future<({String code, Map<String, dynamic> wrapped})> newRecovery() async {
    final code = newRecoveryCode();
    return (
      code: code,
      wrapped: await _wrap(
        _keyBytes,
        normalizeRecoveryCode(code),
        _recoveryIterations,
      ),
    );
  }

  static Future<Map<String, dynamic>> _wrap(
    List<int> keyBytes,
    String secret,
    int iterations,
  ) async {
    final salt = _randomBytes(16);
    final kek = await _derive(secret, salt, iterations);
    final box = await _aes.encrypt(keyBytes, secretKey: kek);
    return {
      'salt': base64Encode(salt),
      'iterations': iterations,
      'box': base64Encode(box.concatenation()),
    };
  }

  static Future<Vault?> _unwrap(Object? wrapped, String secret) async {
    if (wrapped is! Map) return null;
    final kek = await _derive(
      secret,
      base64Decode(wrapped['salt'] as String),
      wrapped['iterations'] as int,
    );
    try {
      final box = SecretBox.fromConcatenation(
        base64Decode(wrapped['box'] as String),
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      final bytes = await _aes.decrypt(box, secretKey: kek);
      return Vault._(SecretKey(bytes), bytes);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  static Future<SecretKey> _derive(
    String secret,
    List<int> salt,
    int iterations,
  ) => Pbkdf2.hmacSha256(
    iterations: iterations,
    bits: 256,
  ).deriveKeyFromPassword(password: secret, nonce: salt);

  // -------------------------------------------------- codul de recuperare

  // Alfabet fără caractere ușor de confundat (0/O, 1/I/L, U).
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static List<int> _randomBytes(int n) {
    final r = Random.secure();
    return List.generate(n, (_) => r.nextInt(256));
  }

  /// 32 de caractere (160 de biți), afișate în grupe: `ABCD-EFGH-…`.
  static String newRecoveryCode() {
    final r = Random.secure();
    final chars = List.generate(32, (_) => _alphabet[r.nextInt(32)]);
    final groups = <String>[];
    for (var i = 0; i < chars.length; i += 4) {
      groups.add(chars.sublist(i, i + 4).join());
    }
    return groups.join('-');
  }

  /// Acceptă codul scris oricum: litere mici, spații, O în loc de 0 etc.
  static String normalizeRecoveryCode(String code) => code
      .toUpperCase()
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1')
      .replaceAll(RegExp('[^0-9A-Z]'), '');
}
