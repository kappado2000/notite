import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../data/notes_store.dart';
import 'backup_files_stub.dart'
    if (dart.library.io) 'backup_files_io.dart'
    as files;

/// Backup COMPLET (notițe, carnete, atașamente ȘI parole), criptat cu o
/// parolă de backup aleasă de tine (PBKDF2-SHA256 600 000 + AES-256-GCM).
/// Fișierul se poate restaura pe orice dispozitiv, chiar și dacă se pierde
/// contul din cloud — doar cu parola de backup.
///
/// Automat: o dată pe săptămână, la deschiderea aplicației, în iCloud Drive
/// → Notițe (pe iPhone, dacă iCloud e disponibil) sau în folderul local al
/// aplicației; se păstrează ultimele [keep] fișiere.
class FullBackup {
  static const magic = 'NOTITE-ENC1';
  static const keep = 6;
  static const _iterations = 600000;
  static const _storage = FlutterSecureStorage();
  static final _aes = AesGcm.with256bits();

  static String _keyName(String uid) => 'backup_key_$uid';
  static String _lastName(String uid) => 'lastAutoBackup_$uid';
  static Box get _settings => Hive.box('settings');

  /// Backup automat posibil pe acest dispozitiv (nu pe web).
  static bool get autoSupported => files.supported;

  // ------------------------------------------------------- parola de backup

  static Future<bool> configured(String uid) async =>
      (await _storage.read(key: _keyName(uid))) != null;

  /// Setează (sau schimbă) parola de backup. Cheia derivată rămâne pe
  /// dispozitiv (în Keychain), ca backup-ul automat să nu ceară parola.
  static Future<void> setPassword(String uid, String password) async {
    final salt = _random(16);
    final key = await _derive(password, salt);
    await _storage.write(
      key: _keyName(uid),
      value: jsonEncode({
        'salt': base64Encode(salt),
        'key': base64Encode(await key.extractBytes()),
      }),
    );
  }

  static Future<void> disable(String uid) async {
    await _storage.delete(key: _keyName(uid));
    await _settings.delete(_lastName(uid));
  }

  static DateTime? lastAuto(String uid) {
    final ms = _settings.get(_lastName(uid)) as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  // ------------------------------------------------------------ criptare

  /// Fișierul criptat cu cheia salvată (null = parola de backup nesetată).
  static Future<Uint8List?> build(NotesStore store, String uid) async {
    final saved = await _storage.read(key: _keyName(uid));
    if (saved == null) return null;
    final m = jsonDecode(saved) as Map;
    final data = utf8.encode(jsonEncode(store.exportBackup(withSecrets: true)));
    return encrypt(
      data,
      salt: base64Decode(m['salt'] as String),
      key: SecretKey(base64Decode(m['key'] as String)),
    );
  }

  /// Format: `NOTITE-ENC1\n{antet JSON}\n<text criptat + MAC>`.
  static Future<Uint8List> encrypt(
    List<int> clear, {
    required List<int> salt,
    required SecretKey key,
  }) async {
    final nonce = _random(12);
    final box = await _aes.encrypt(clear, secretKey: key, nonce: nonce);
    final header = jsonEncode({
      'kdf': 'pbkdf2-sha256',
      'iter': _iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'cipher': 'aes-256-gcm',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    final b = BytesBuilder(copy: false)
      ..add(utf8.encode('$magic\n$header\n'))
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return b.takeBytes();
  }

  static bool isEncrypted(List<int> bytes) =>
      bytes.length > magic.length &&
      utf8.decode(bytes.sublist(0, magic.length), allowMalformed: true) ==
          magic;

  /// Decriptează; aruncă [FormatException] la parolă greșită sau fișier
  /// stricat.
  static Future<Map<String, dynamic>> decrypt(
    Uint8List bytes,
    String password,
  ) async {
    final first = bytes.indexOf(10);
    final second = first < 0 ? -1 : bytes.indexOf(10, first + 1);
    if (!isEncrypted(bytes) || second < 0) {
      throw const FormatException('Fișierul nu este un backup Notițe criptat.');
    }
    final header =
        jsonDecode(utf8.decode(bytes.sublist(first + 1, second))) as Map;
    final key = await _derive(
      password,
      base64Decode(header['salt'] as String),
      (header['iter'] as int?) ?? _iterations,
    );
    final body = bytes.sublist(second + 1);
    if (body.length < 16) {
      throw const FormatException('Fișierul de backup e incomplet.');
    }
    try {
      final clear = await _aes.decrypt(
        SecretBox(
          body.sublist(0, body.length - 16),
          nonce: base64Decode(header['nonce'] as String),
          mac: Mac(body.sublist(body.length - 16)),
        ),
        secretKey: key,
      );
      return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    } on SecretBoxAuthenticationError {
      throw const FormatException('Parola de backup e greșită.');
    }
  }

  // ------------------------------------------------------------- automat

  static String fileName([DateTime? at]) =>
      'Notite-backup-${DateFormat('yyyy-MM-dd_HHmm').format(at ?? DateTime.now())}.notite';

  /// Backup automat dacă a trecut o săptămână de la ultimul. Întoarce
  /// locul unde s-a scris (sau null dacă nu era cazul / nu se poate).
  static Future<String?> autoIfDue(NotesStore store, String uid) async {
    if (!autoSupported || !await configured(uid)) return null;
    final last = lastAuto(uid);
    if (last != null && DateTime.now().difference(last).inDays < 7) {
      return null;
    }
    return runNow(store, uid);
  }

  /// Scrie acum un backup în locul automat (iCloud Drive / local).
  static Future<String?> runNow(NotesStore store, String uid) async {
    final bytes = await build(store, uid);
    if (bytes == null) return null;
    final where = await files.write(fileName(), bytes, keep: keep);
    if (where != null) {
      await _settings.put(
        _lastName(uid),
        DateTime.now().millisecondsSinceEpoch,
      );
    }
    return where;
  }

  /// Unde ajung backup-urile automate („iCloud Drive → Notițe” / cale).
  static Future<String?> location() => files.location();

  // ------------------------------------------------------------- utilitare

  static Future<SecretKey> _derive(
    String password,
    List<int> salt, [
    int iterations = _iterations,
  ]) => Pbkdf2.hmacSha256(
    iterations: iterations,
    bits: 256,
  ).deriveKeyFromPassword(password: password, nonce: salt);

  static List<int> _random(int n) {
    final r = Random.secure();
    return [for (var i = 0; i < n; i++) r.nextInt(256)];
  }

  @visibleForTesting
  static Future<Uint8List> encryptWithPassword(
    Map<String, dynamic> data,
    String password,
  ) async {
    final salt = _random(16);
    return encrypt(
      utf8.encode(jsonEncode(data)),
      salt: salt,
      key: await _derive(password, salt),
    );
  }
}
