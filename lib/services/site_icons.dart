import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/notes_store.dart';
import '../models/secret_item.dart';
import 'secret_helpers.dart';

/// Iconițele site-urilor conturilor. Întâi direct de pe site (nimeni
/// altcineva nu află lista site-urilor tale), apoi, doar ca rezervă,
/// serviciul de iconițe Google. Pe telefon iconița se cere o singură dată
/// și se păstrează criptată pe dispozitiv; pe web se ocupă browserul.
class SiteIcons {
  SiteIcons._();

  /// Găzduiri comune: fiecare subdomeniu e alt site (ex. x.web.app).
  static const _shared = {
    'web.app',
    'firebaseapp.com',
    'github.io',
    'azurewebsites.net',
    'b2clogin.com',
    'herokuapp.com',
    'vercel.app',
    'netlify.app',
    'pages.dev',
    'blogspot.com',
  };

  /// Domeniul al cărui iconiță o cerem (null = fără iconiță: fără site,
  /// adresă IP, rețeaua de acasă).
  static String? domainOf(SecretItem i) {
    var h = hostOf(i.url).split(':').first;
    if (h.isEmpty) return siteOf(i)?.domain;
    if (!h.contains('.') ||
        RegExp(r'^[\d.]+$').hasMatch(h) ||
        h.endsWith('.local') ||
        h.endsWith('.lan')) {
      return null;
    }
    final p = h.split('.');
    if (p.length <= 2) return h;
    final two = p.sublist(p.length - 2).join('.');
    final keep3 =
        _shared.contains(two) ||
        RegExp(r'^(co|com|org|net|gov|ac)\.[a-z]{2}$').hasMatch(two);
    h = p.sublist(p.length - (keep3 ? 3 : 2)).join('.');
    return h;
  }

  /// Adresele încercate, în ordine.
  static List<String> sources(String domain) => [
    'https://$domain/apple-touch-icon.png',
    'https://$domain/favicon.ico',
    'https://www.google.com/s2/favicons?domain=$domain&sz=128',
  ];

  static final Map<String, Future<Uint8List?>> _inFlight = {};
  static int _running = 0;
  static final List<Completer<void>> _queue = [];

  /// Pe telefon / desktop: iconița din memoria criptată sau descărcată
  /// acum (o singură dată). Null = nu există.
  static Future<Uint8List?> load(NotesStore store, String domain) {
    final cached = store.siteIcon(domain);
    if (cached != null) {
      return SynchronousFuture(cached.isEmpty ? null : cached);
    }
    return _inFlight[domain] ??= _fetch(
      store,
      domain,
    ).whenComplete(() => _inFlight.remove(domain));
  }

  static Future<Uint8List?> _fetch(NotesStore store, String domain) async {
    // câte 4 deodată: o listă cu sute de conturi nu pornește sute de cereri
    if (_running >= 4) {
      final c = Completer<void>();
      _queue.add(c);
      await c.future;
    }
    _running++;
    try {
      for (final url in sources(domain)) {
        final bytes = await _get(url);
        if (bytes != null) {
          await store.putSiteIcon(domain, bytes);
          return bytes;
        }
      }
      await store.putSiteIcon(domain, Uint8List(0));
      return null;
    } finally {
      _running--;
      if (_queue.isNotEmpty) _queue.removeAt(0).complete();
    }
  }

  /// Imaginea de la adresă, dacă e o imagine validă.
  static Future<Uint8List?> _get(String url) async {
    try {
      final r = await http
          .get(Uri.parse(url), headers: const {'Accept': 'image/*'})
          .timeout(const Duration(seconds: 8));
      final type = r.headers['content-type'] ?? '';
      if (r.statusCode != 200 ||
          r.bodyBytes.length < 64 ||
          !(type.startsWith('image/') || type.isEmpty)) {
        return null;
      }
      // unele site-uri întorc o pagină HTML în loc de iconiță
      final codec = await ui.instantiateImageCodec(r.bodyBytes);
      codec.dispose();
      return r.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}
