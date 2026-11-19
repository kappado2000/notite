import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../models/secret_item.dart';
import 'password_tools.dart';
import 'secret_helpers.dart';

/// Site-urile care permit verificarea în doi pași cu cod din aplicație
/// (TOTP), după lista publică 2fa.directory. Lista se descarcă rar (o dată
/// la 14 zile) și se păstrează pe dispozitiv; nu trimitem nimic despre
/// conturile tale — se descarcă lista întreagă și comparația se face local.
class TwoFactorSites extends ChangeNotifier {
  TwoFactorSites._();
  static final instance = TwoFactorSites._();

  static const _url = 'https://api.2fa.directory/v3/totp.json';
  static const _cacheKey = 'tfaDirectory';
  static const _cacheAtKey = 'tfaDirectoryAt';
  static const _dismissedKey = 'tfaDismissed';
  static const _maxAge = Duration(days: 14);

  /// domeniu → pagina cu instrucțiuni (poate fi '').
  Map<String, String>? _sites;
  Future<void>? _loading;

  Box get _box => Hive.box('settings');

  bool get loaded => _sites != null;

  /// Încarcă lista (din cache sau de pe internet). Fără internet rămâne
  /// lista veche; dacă nu există nicio listă, [loaded] rămâne false.
  Future<void> load() =>
      _loading ??= _load().whenComplete(() => _loading = null);

  Future<void> _load() async {
    final cached = _box.get(_cacheKey) as String?;
    final at = _box.get(_cacheAtKey) as int?;
    if (cached != null && _sites == null) {
      _sites = Map<String, String>.from(jsonDecode(cached) as Map);
      notifyListeners();
    }
    final fresh =
        at != null &&
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at)) <
            _maxAge;
    if (cached != null && fresh) return;
    try {
      final r = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return;
      final sites = parseDirectory(r.body);
      if (sites.isEmpty) return;
      _sites = sites;
      await _box.put(_cacheKey, jsonEncode(sites));
      await _box.put(_cacheAtKey, DateTime.now().millisecondsSinceEpoch);
      notifyListeners();
    } catch (e) {
      debugPrint('2fa.directory: $e');
    }
  }

  /// Formatul 2fa.directory v3: `[[nume, {domain, additional-domains,
  /// documentation, tfa}], …]`.
  @visibleForTesting
  static Map<String, String> parseDirectory(String body) {
    final out = <String, String>{};
    final list = jsonDecode(body);
    if (list is! List) return out;
    for (final e in list) {
      if (e is! List || e.length < 2 || e[1] is! Map) continue;
      final m = e[1] as Map;
      final doc =
          (m['documentation'] as String?) ?? (m['url'] as String?) ?? '';
      for (final d in [m['domain'], ...?(m['additional-domains'] as List?)]) {
        if (d is String && d.isNotEmpty) {
          out.putIfAbsent(d.toLowerCase(), () => doc);
        }
      }
    }
    return out;
  }

  /// Conturile pentru care ai ascuns sugestia („nu vreau 2FA aici”).
  Set<String> get dismissed =>
      ((_box.get(_dismissedKey) as List?) ?? const []).cast<String>().toSet();

  Future<void> dismiss(String id) async {
    await _box.put(_dismissedKey, [...dismissed, id]);
    notifyListeners();
  }

  Future<void> undismiss(String id) async {
    await _box.put(_dismissedKey, [...dismissed..remove(id)]);
    notifyListeners();
  }

  /// Pagina cu instrucțiuni pentru site-ul contului, dacă site-ul are 2FA
  /// prin aplicație ('' = are, dar fără pagină); null = nu are / necunoscut.
  String? docFor(SecretItem i) {
    final sites = _sites;
    if (sites == null) return null;
    return matchHost(sites, _hostOf(i));
  }

  /// Caută domeniul și apoi părinții lui (`login.yahoo.com` → `yahoo.com`).
  @visibleForTesting
  static String? matchHost(Map<String, String> sites, String host) {
    var h = host.toLowerCase();
    if (h.startsWith('www.')) h = h.substring(4);
    while (h.contains('.')) {
      final doc = sites[h];
      if (doc != null) return doc;
      h = h.substring(h.indexOf('.') + 1);
    }
    return null;
  }

  static String _hostOf(SecretItem i) {
    final h = hostOf(i.url);
    if (h.isNotEmpty) return h;
    return recognizeSite(i.title)?.domain ?? '';
  }

  /// Conturile (cu parolă, fără cod 2FA salvat) de pe site-uri care permit
  /// 2FA prin aplicație — fără cele ignorate sau ascunse.
  List<(SecretItem, String)> missing(Iterable<SecretItem> items) {
    if (_sites == null) return const [];
    final hidden = dismissed;
    final seen = <String>{};
    final out = <(SecretItem, String)>[];
    final sorted = [...items]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final i in sorted) {
      if (i.type != SecretType.login || i.password.isEmpty) continue;
      if (i.totp.trim().isNotEmpty || i.ignoreHealth) continue;
      if (hidden.contains(i.id) || isLocalAccount(i)) continue;
      final doc = docFor(i);
      if (doc == null) continue;
      // același site + utilizator o singură dată (dublurile)
      if (!seen.add('${siteBase(i)}|${i.username.toLowerCase()}')) continue;
      out.add((i, doc));
    }
    out.sort(
      (a, b) => a.$1.displayTitle.toLowerCase().compareTo(
        b.$1.displayTitle.toLowerCase(),
      ),
    );
    return out;
  }
}
