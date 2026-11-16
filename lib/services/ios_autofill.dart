import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/notes_store.dart';
import '../models/secret_item.dart';
import 'password_tools.dart';
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
  /// Cel mai nou primul: la dubluri (același site și utilizator), iOS
  /// primește doar versiunea cea mai recentă.
  static List<Map<String, String>> loginsFor(Iterable<SecretItem> items) => [
    for (final i in [
      ...items,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
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
    importSaves();
    _lifecycle ??= AppLifecycleListener(onResume: importSaves);
  }

  AppLifecycleListener? _lifecycle;

  /// Anunțat după ce au fost salvate parole primite de la iOS (câte).
  void Function(int count)? onImported;

  /// Parolele pe care iOS (26.2+) le-a dat extensiei spre salvare („Salvez
  /// parola în Notițe?” după conectarea într-o aplicație sau pe un site):
  /// le pune în cont — actualizează contul existent (parola veche intră în
  /// istoric) sau creează unul nou.
  Future<int> importSaves() async {
    final store = _store;
    if (!supported || store == null) return 0;
    List<dynamic> raw;
    try {
      raw = await _channel.invokeMethod<List<dynamic>>('takeSaves') ?? [];
    } catch (e) {
      debugPrint('IosAutofill.takeSaves: $e');
      return 0;
    }
    var count = 0;
    for (final m in raw.whereType<Map<dynamic, dynamic>>()) {
      final user = (m['user'] as String?)?.trim() ?? '';
      final pass = (m['password'] as String?) ?? '';
      if (pass.isEmpty) continue;
      final id = (m['identifier'] as String?) ?? '';
      final name = (m['name'] as String?)?.trim() ?? '';
      final title = (m['title'] as String?)?.trim() ?? '';
      final candidate = store.newSecret(SecretType.login)
        ..username = user
        ..password = pass;
      if (m['type'] == 'app') {
        candidate
          ..title = name.isNotEmpty ? name : id
          ..notes =
              'Salvat din aplicația iOS „${name.isNotEmpty ? name : id}”.';
      } else {
        final url = m['type'] == 'url' ? id : 'https://$id';
        candidate
          ..url = url
          ..title = title.isNotEmpty ? title : hostOf(url)
          ..notes = 'Salvat de completarea automată iOS.';
      }
      final existing = findSameAccount(store.allSecrets, candidate);
      if (existing != null) {
        if (existing.password == pass) continue;
        await store.saveSecret(existing.copy()..password = pass);
      } else {
        await store.saveSecret(candidate);
      }
      count++;
    }
    if (count > 0) onImported?.call(count);
    return count;
  }

  void detach() {
    _store?.removeListener(_changed);
    _store = null;
    _debounce?.cancel();
    _lifecycle?.dispose();
    _lifecycle = null;
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

  /// Jurnalul de diagnostic (aplicație + extensie), fără date secrete.
  static Future<String> log() async {
    if (!supported) return 'Doar pe iPhone / iPad.';
    try {
      return (await _channel.invokeMethod<String>('log')) ?? '';
    } catch (e) {
      return 'Eroare: $e';
    }
  }

  static Future<void> clearLog() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('clearLog');
    } catch (_) {}
  }

  /// Rescrie acum lista pentru extensie (chiar dacă nu s-a schimbat nimic).
  Future<void> resync() async {
    _lastSig = '';
    await _push();
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
