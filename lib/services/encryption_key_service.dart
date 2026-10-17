import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Cheia AES-256 cu care sunt criptate notițele pe dispozitiv.
/// Generată o singură dată per cont și păstrată în seiful sistemului
/// (Keychain pe iOS, Keystore pe Android, DPAPI pe Windows).
class EncryptionKeyService {
  static const _storage = FlutterSecureStorage();

  static Future<HiveAesCipher> cipherFor(String uid) async {
    final name = 'notite_key_$uid';
    var encoded = await _storage.read(key: name);
    if (encoded == null) {
      encoded = base64UrlEncode(Hive.generateSecureKey());
      await _storage.write(key: name, value: encoded);
    }
    return HiveAesCipher(base64Url.decode(encoded));
  }

  static Future<void> deleteFor(String uid) =>
      _storage.delete(key: 'notite_key_$uid');
}
