import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/notes_store.dart';
import '../models/secret_item.dart';
import 'secret_helpers.dart';

/// Completarea automată în iOS: ține la zi, pentru extensia AutoFill,
/// conturile cu parolă (criptate în partea nativă, cu cheia protejată de
/// Face ID). Doar pe iPhone / iPad.
class IosAutofill {
  IosAutofill._();
  static final instance = IosAutofill._();

  static const _channel = MethodChannel('notite/autofill');

  NotesStore? _store;
  Timer? _debounce;
  String _lastSig = '';

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Conturile care pot fi completate (cu parolă), în forma pentru extensie.
  static List<Map<String, String>> loginsFor(Iterable<SecretItem> items) => [
    for (final i in items)
      if ((i.type == SecretType.login || i.type == SecretType.subscription) &&
          i.password.isNotEmpty)
        {
          'id': i.id,
          'title': i.displayTitle,
          'url': i.url,
          'host': _host(i),
          'user': i.username,
          'password': i.password,
        },
  ];

  static String _host(SecretItem i) {
    final h = hostOf(i.url);
    if (h.isNotEmpty) return h;
    return recognizeSite(i.title)?.domain ?? '';
  }

  void attach(NotesStore store) {
    if (!supported) return;
    _store?.removeListener(_changed);
    _store = store;
    store.addListener(_changed);
    _changed();
  }

  void detach() {
    _store?.removeListener(_changed);
    _store = null;
    _debounce?.cancel();
  }

  /// La deconectare: nimic nu mai rămâne pentru extensie.
  Future<void> clear() async {
    detach();
    _lastSig = '';
    if (!supported) return;
    try {
      await _channel.invokeMethod('clear');
    } catch (e) {
      debugPrint('IosAutofill.clear: $e');
    }
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _push);
  }

  Future<void> _push() async {
    final store = _store;
    if (store == null) return;
    final logins = loginsFor(store.allSecrets);
    // Nu rescriem dacă nimic din ce contează nu s-a schimbat.
    final sig = Object.hashAll([
      for (final l in logins) Object.hashAll(l.values),
    ]).toString();
    if (sig == _lastSig) return;
    try {
      await _channel.invokeMethod('sync', logins);
      _lastSig = sig;
    } catch (e) {
      debugPrint('IosAutofill.sync: $e');
    }
  }
}
