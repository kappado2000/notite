import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import '../models/secret_item.dart';
import 'secret_helpers.dart';

/// Generator de parole cu `Random.secure()`.
class PasswordGenerator {
  static const _lower = 'abcdefghijkmnopqrstuvwxyz';
  static const _upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const _digits = '23456789';
  static const _symbols = '!*-_.';
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

  /// Câte conturi diferite au cel puțin o problemă.
  int get accounts => {
    for (final i in weak) i.id,
    for (final g in reused)
      for (final i in g) i.id,
    for (final i in old) i.id,
  }.length;

  static PasswordReport of(Iterable<SecretItem> items) {
    final logins = items
        .where(
          (i) =>
              (i.type == SecretType.login ||
                  i.type == SecretType.subscription) &&
              i.password.isNotEmpty &&
              !i.ignoreHealth &&
              !isLocalAccount(i),
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

/// Cont din rețeaua de acasă (router, NAS, imprimantă): nu e pe internet,
/// deci nu se numără la riscuri.
bool isLocalAccount(SecretItem i) {
  final h = hostOf(i.url.isNotEmpty ? i.url : i.title);
  if (h.isEmpty) return false;
  final ip = RegExp(r'^(\d+)\.(\d+)\.\d+\.\d+(:\d+)?$').firstMatch(h);
  if (ip != null) {
    final a = int.parse(ip[1]!), b = int.parse(ip[2]!);
    return a == 10 ||
        a == 127 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31);
  }
  return h == 'localhost' ||
      h.startsWith('localhost:') ||
      h.endsWith('.local') ||
      h.endsWith('.lan');
}

/// Numele „de bază” al unui site: login.yahoo.com, mail.yahoo.com,
/// yahoo.com, yahoo.co.uk → „yahoo”. Fără adresă: primul cuvânt din titlu
/// („Yahoo Mail” → „yahoo”).
String siteBase(SecretItem i) {
  final host = hostOf(i.url).split(':').first;
  if (host.isEmpty) {
    final words = i.title
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9ăâîșțşţ]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '';
    final w = words.first;
    // „www”, „https” din titluri ca „www.yahoo.com”
    return (w == 'www' || w == 'https' || w == 'http') && words.length > 1
        ? words[1]
        : w;
  }
  return _domainLabel(host);
}

String _domainLabel(String host) {
  if (RegExp(r'^[\d.]+$').hasMatch(host)) return host; // adresă IP
  final p = host.split('.');
  if (p.length < 2) return host;
  const second = {'com', 'co', 'org', 'net', 'gov', 'edu', 'ac', 'nom'};
  if (p.length >= 3 && p.last.length == 2 && second.contains(p[p.length - 2])) {
    return p[p.length - 3];
  }
  return p[p.length - 2];
}

/// Utilizatorul pentru comparare: „dr_monipop@yahoo.com” pe Yahoo e tot
/// „dr_monipop”.
String _userKey(String username, String site) {
  final u = username.trim().toLowerCase();
  final at = u.indexOf('@');
  if (at > 0 && _domainLabel(u.substring(at + 1)) == site) {
    return u.substring(0, at);
  }
  return u;
}

/// Cheia unui cont pentru dubluri: același site (de bază) și utilizator.
String _dupKey(SecretItem i) {
  final site = siteBase(i);
  final user = _userKey(i.username, site);
  // același site + același utilizator = același cont, chiar dacă parolele
  // diferă (o copie veche, ex. din import). Fără utilizator nu putem ști,
  // deci atunci doar parola identică le face dubluri.
  return user.isEmpty ? '$site||${i.password}' : '$site|$user';
}

/// Grupurile de conturi identice (de obicei din importuri repetate).
List<List<SecretItem>> duplicateGroups(Iterable<SecretItem> items) {
  final by = <String, List<SecretItem>>{};
  for (final i in items) {
    if (i.type != SecretType.login || i.password.isEmpty) continue;
    by.putIfAbsent(_dupKey(i), () => []).add(i);
  }
  return by.values.where((g) => g.length > 1).toList();
}

/// Unește un grup de dubluri în intrarea cea mai completă; întoarce
/// intrarea păstrată (cu datele adunate de la celelalte) și cele de șters.
({SecretItem keep, List<SecretItem> remove}) mergeDuplicates(
  List<SecretItem> group, {
  bool Function(SecretItem)? hasAttachments,
}) {
  int richness(SecretItem i) =>
      (hasAttachments?.call(i) == true ? 1000 : 0) +
      (i.favorite ? 50 : 0) +
      (i.totp.isNotEmpty ? 40 : 0) +
      i.custom.length * 10 +
      i.passwordHistory.length * 5 +
      (i.notes.isNotEmpty ? 5 : 0) +
      (i.url.isNotEmpty ? 3 : 0) +
      (i.title.isNotEmpty ? 2 : 0);
  final sorted = [...group]
    ..sort((a, b) {
      final r = richness(b).compareTo(richness(a));
      return r != 0 ? r : a.createdAt.compareTo(b.createdAt);
    });
  final keep = sorted.first.copy();
  for (final o in sorted.skip(1)) {
    keep.favorite = keep.favorite || o.favorite;
    if (keep.totp.isEmpty) keep.totp = o.totp;
    if (keep.url.isEmpty) keep.url = o.url;
    if (keep.title.isEmpty) keep.title = o.title;
    if (keep.category.isEmpty) keep.category = o.category;
    final n = o.notes.trim();
    if (n.isNotEmpty && !keep.notes.contains(n)) {
      keep.notes = keep.notes.trim().isEmpty ? n : '${keep.notes.trim()}\n\n$n';
    }
    for (final f in o.custom) {
      if (!keep.custom.any((k) => k.label == f.label && k.value == f.value)) {
        keep.custom.add(f);
      }
    }
    for (final p in o.passwordHistory) {
      if (!keep.passwordHistory.any((k) => k.password == p.password)) {
        keep.passwordHistory.add(p);
      }
    }
  }
  // parola valabilă = cea schimbată cel mai recent; celelalte → istoric
  final newest = [...group]
    ..sort((a, b) => b.passwordChangedAt.compareTo(a.passwordChangedAt));
  final current = newest.first;
  if (keep.password != current.password) {
    keep.password = current.password;
    keep.passwordChangedAt = current.passwordChangedAt;
  }
  for (final o in newest.skip(1)) {
    if (o.password != keep.password &&
        !keep.passwordHistory.any((k) => k.password == o.password)) {
      keep.passwordHistory.add(
        PasswordVersion(o.password, current.passwordChangedAt),
      );
    }
  }
  keep.passwordHistory
    ..removeWhere((p) => p.password == keep.password)
    ..sort((a, b) => b.until.compareTo(a.until));
  keep.passwordHistory = keep.passwordHistory.take(10).toList();
  return (keep: keep, remove: sorted.skip(1).toList());
}

/// Copiere în clipboard cu ștergere automată după 30 de secunde.
class SecureClipboard {
  static Timer? _timer;
  static const clearAfter = Duration(seconds: 30);

  static Future<void> copy(String value, {Duration? keepFor}) async {
    await Clipboard.setData(ClipboardData(text: value));
    _timer?.cancel();
    _timer = Timer(keepFor ?? clearAfter, () async {
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
