import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import '../models/secret_item.dart';

/// Generator de parole cu `Random.secure()`.
class PasswordGenerator {
  static const _lower = 'abcdefghijkmnopqrstuvwxyz';
  static const _upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const _digits = '23456789';
  static const _symbols = r'!@#$%^&*()-_=+[]{};:,.?';
  // Variantele „ambigue” (l, I, O, 0, 1) sunt excluse implicit.
  static const _ambiguous = 'lIO01';

  static String generate({
    int length = 20,
    bool upper = true,
    bool digits = true,
    bool symbols = true,
    bool avoidAmbiguous = true,
  }) {
    final groups = <String>[
      _lower + (avoidAmbiguous ? '' : 'l'),
      if (upper) _upper + (avoidAmbiguous ? '' : 'IO'),
      if (digits) _digits + (avoidAmbiguous ? '' : '01'),
      if (symbols) _symbols,
    ];
    final all = groups.join();
    final r = Random.secure();
    // Câte un caracter din fiecare grup ales, restul la întâmplare.
    final chars = [
      for (final g in groups) g[r.nextInt(g.length)],
      for (var i = groups.length; i < length; i++) all[r.nextInt(all.length)],
    ]..shuffle(r);
    assert(!avoidAmbiguous || !chars.any(_ambiguous.contains));
    return chars.take(length).join();
  }
}

enum Strength {
  weak('Slabă', 0xFFD32F2F),
  fair('Acceptabilă', 0xFFF57C00),
  good('Bună', 0xFF388E3C),
  strong('Foarte bună', 0xFF1B5E20);

  const Strength(this.label, this.color);
  final String label;
  final int color;
}

/// Estimare simplă a puterii: lungime, varietate, tipare evidente.
Strength passwordStrength(String p) {
  if (p.isEmpty) return Strength.weak;
  var classes = 0;
  if (RegExp('[a-z]').hasMatch(p)) classes++;
  if (RegExp('[A-Z]').hasMatch(p)) classes++;
  if (RegExp(r'\d').hasMatch(p)) classes++;
  if (RegExp(r'[^a-zA-Z\d]').hasMatch(p)) classes++;
  final lower = p.toLowerCase();
  const common = [
    'parola',
    'password',
    'qwerty',
    'azerty',
    '123456',
    'abc123',
    'iloveyou',
    'admin',
    'welcome',
    'romania',
  ];
  final obvious =
      common.any(lower.contains) ||
      RegExp(r'(.)\1{3,}').hasMatch(p) ||
      RegExp(r'^\d+$').hasMatch(p);
  if (p.length < 8 || obvious) return Strength.weak;
  if (p.length < 11 || classes <= 2) return Strength.fair;
  if (p.length < 15 || classes == 3) return Strength.good;
  return Strength.strong;
}

/// Rezultatul verificării de securitate a parolelor.
class PasswordReport {
  PasswordReport(this.weak, this.reused, this.old);

  final List<SecretItem> weak;

  /// Grupuri de intrări care folosesc aceeași parolă.
  final List<List<SecretItem>> reused;
  final List<SecretItem> old;

  int get problems => weak.length + reused.length + old.length;

  static PasswordReport of(Iterable<SecretItem> items) {
    final logins = items
        .where(
          (i) =>
              (i.type == SecretType.login ||
                  i.type == SecretType.subscription) &&
              i.password.isNotEmpty,
        )
        .toList();
    final byPassword = <String, List<SecretItem>>{};
    for (final i in logins) {
      byPassword.putIfAbsent(i.password, () => []).add(i);
    }
    final yearAgo = DateTime.now().subtract(const Duration(days: 365));
    return PasswordReport(
      logins
          .where((i) => passwordStrength(i.password) == Strength.weak)
          .toList(),
      byPassword.values.where((g) => g.length > 1).toList(),
      logins.where((i) => i.passwordChangedAt.isBefore(yearAgo)).toList(),
    );
  }
}

/// Copiere în clipboard cu ștergere automată după 30 de secunde.
class SecureClipboard {
  static Timer? _timer;
  static const clearAfter = Duration(seconds: 30);

  static Future<void> copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _timer?.cancel();
    _timer = Timer(clearAfter, () async {
      try {
        // Ștergem doar dacă între timp nu s-a copiat altceva.
        final now = await Clipboard.getData(Clipboard.kTextPlain);
        if (now?.text == value) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      } catch (_) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
  }
}

/// Validare număr de card (algoritmul Luhn).
bool luhnValid(String digits) {
  if (digits.length < 12) return false;
  var sum = 0;
  var alt = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var n = int.parse(digits[i]);
    if (alt) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    alt = !alt;
  }
  return sum % 10 == 0;
}

String cardBrand(String digits) {
  if (digits.startsWith('4')) return 'Visa';
  if (RegExp(r'^(5[1-5]|2[2-7])').hasMatch(digits)) return 'Mastercard';
  if (RegExp(r'^3[47]').hasMatch(digits)) return 'American Express';
  if (RegExp(r'^(50|5[6-9]|6)').hasMatch(digits)) return 'Maestro';
  return '';
}

/// Textul codului QR de conectare la Wi-Fi (scanabil de camera telefonului).
String wifiQrPayload(SecretItem w) {
  String esc(String s) =>
      s.replaceAllMapped(RegExp(r'([\\;,:"])'), (m) => '\\${m[1]}');
  return 'WIFI:T:${w.wifiSecurity};S:${esc(w.username)};'
      'P:${esc(w.password)};${w.wifiHidden ? 'H:true;' : ''};';
}
