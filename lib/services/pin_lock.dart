import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Rezultatul unei încercări de cod.
enum PinResult { ok, wrong, lockedOut }

/// Codul de 6 cifre pentru secțiunea „Parole”, separat pe fiecare dispozitiv.
/// Se păstrează doar amprenta lui (PBKDF2 cu sare aleatoare), în seiful
/// securizat al sistemului. După [maxAttempts] coduri greșite la rând,
/// codul e blocat până la deblocarea cu parola contului.
class PinLock {
  PinLock(this.uid, {FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final String uid;
  final FlutterSecureStorage _storage;

  static const length = 6;
  static const maxAttempts = 5;
  static const _iterations = 60000;

  String get _hashKey => 'pin_hash_$uid';
  String get _failKey => 'pin_fail_$uid';

  static bool isValidFormat(String pin) =>
      RegExp('^\\d{$length}\$').hasMatch(pin);

  Future<bool> isSet() async => (await _storage.read(key: _hashKey)) != null;

  Future<int> failedAttempts() async =>
      int.tryParse(await _storage.read(key: _failKey) ?? '') ?? 0;

  Future<bool> isLockedOut() async => await failedAttempts() >= maxAttempts;

  Future<void> set(String pin) async {
    if (!isValidFormat(pin)) {
      throw ArgumentError('Codul trebuie să aibă $length cifre.');
    }
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final hash = await _derive(pin, salt);
    await _storage.write(
      key: _hashKey,
      value: '${base64Encode(salt)}:${base64Encode(hash)}',
    );
    await _storage.delete(key: _failKey);
  }

  Future<void> clear() async {
    await _storage.delete(key: _hashKey);
    await _storage.delete(key: _failKey);
  }

  /// După deblocarea cu parola contului, codul poate fi folosit din nou.
  Future<void> resetAttempts() => _storage.delete(key: _failKey);

  Future<PinResult> verify(String pin) async {
    if (await isLockedOut()) return PinResult.lockedOut;
    final stored = await _storage.read(key: _hashKey);
    if (stored == null) return PinResult.wrong;
    final parts = stored.split(':');
    final salt = base64Decode(parts[0]);
    final expected = base64Decode(parts[1]);
    final actual = await _derive(pin, salt);
    if (_equal(actual, expected)) {
      await _storage.delete(key: _failKey);
      return PinResult.ok;
    }
    final fails = await failedAttempts() + 1;
    await _storage.write(key: _failKey, value: '$fails');
    return fails >= maxAttempts ? PinResult.lockedOut : PinResult.wrong;
  }

  static Future<List<int>> _derive(String pin, List<int> salt) async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: 256,
    ).deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }

  /// Comparație în timp constant.
  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
