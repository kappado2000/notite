import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Coduri 2FA (TOTP, RFC 6238) — compatibile cu Google Authenticator.
class Totp {
  Totp({
    required this.secret,
    this.digits = 6,
    this.period = 30,
    this.algorithm = 'SHA1',
  });

  final Uint8List secret;
  final int digits;
  final int period;
  final String algorithm;

  /// Acceptă cheia Base32 („JBSW Y3DP …”) sau un link
  /// `otpauth://totp/…?secret=…&digits=…&period=…&algorithm=…`.
  /// Întoarce `null` dacă textul nu e valid.
  static Totp? parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    if (text.toLowerCase().startsWith('otpauth://')) {
      final uri = Uri.tryParse(text);
      if (uri == null || uri.host.toLowerCase() != 'totp') return null;
      final q = uri.queryParameters;
      final key = _base32Decode(q['secret'] ?? '');
      if (key == null) return null;
      return Totp(
        secret: key,
        digits: int.tryParse(q['digits'] ?? '') ?? 6,
        period: int.tryParse(q['period'] ?? '') ?? 30,
        algorithm: (q['algorithm'] ?? 'SHA1').toUpperCase(),
      );
    }
    final key = _base32Decode(text);
    return key == null ? null : Totp(secret: key);
  }

  /// Codul pentru momentul [at] (implicit acum).
  String code([DateTime? at]) {
    final t = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    final counter = t ~/ period;
    final msg = ByteData(8)..setUint64(0, counter);
    final hash = switch (algorithm) {
      'SHA256' => sha256,
      'SHA512' => sha512,
      _ => sha1,
    };
    final h = Hmac(hash, secret).convert(msg.buffer.asUint8List()).bytes;
    final offset = h.last & 0x0f;
    final bin =
        ((h[offset] & 0x7f) << 24) |
        (h[offset + 1] << 16) |
        (h[offset + 2] << 8) |
        h[offset + 3];
    var mod = 1;
    for (var i = 0; i < digits; i++) {
      mod *= 10;
    }
    return (bin % mod).toString().padLeft(digits, '0');
  }

  /// Secunde până la schimbarea codului.
  int secondsLeft([DateTime? at]) {
    final t = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return period - (t % period);
  }

  static Uint8List? _base32Decode(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final s = input.toUpperCase().replaceAll(RegExp(r'[\s=-]'), '');
    if (s.isEmpty) return null;
    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final ch in s.split('')) {
      final v = alphabet.indexOf(ch);
      if (v < 0) return null;
      buffer = (buffer << 5) | v;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
    }
    return out.isEmpty ? null : Uint8List.fromList(out);
  }
}
