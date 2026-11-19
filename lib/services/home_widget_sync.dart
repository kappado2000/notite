import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import '../data/notes_store.dart';
import '../models/note.dart';

/// Widgeturile de pe ecranul iPhone-ului (WidgetKit):
/// - „Notițe rapide”: notiță nouă, listă, scanare, bon (deschid aplicația);
/// - „Listă Notițe”: o listă de bifat (cea aleasă cu „Arată pe widget” sau,
///   implicit, cea mai recentă listă cu lucruri nebifate).
///
/// Aplicația scrie în grupul comun doar titlul și rândurile acelei liste
/// (niciodată notițe blocate sau parole). Atingerile din widget ajung
/// înapoi ca legături `notite://widget/...` ([onLink]).
class HomeWidgetSync {
  HomeWidgetSync._();
  static final instance = HomeWidgetSync._();

  static const _channel = MethodChannel('notite/widget');
  static const _chosenKey = 'widgetNoteId';
  static const maxItems = 12;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  NotesStore? _store;
  Timer? _debounce;
  String _last = '';

  /// Ce s-a atins în widget: `new/note`, `new/list`, `new/scan`, `new/bon`,
  /// `note/<id>`.
  void Function(String link)? onLink;

  Box get _settings => Hive.box('settings');

  void attach(NotesStore store) {
    if (!supported) return;
    _store?.removeListener(_changed);
    _store = store;
    store.addListener(_changed);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'link' && call.arguments is String) {
        onLink?.call(call.arguments as String);
      }
    });
    _push();
    // legătura cu care a fost pornită aplicația (din widget)
    _channel
        .invokeMethod<String>('takeLink')
        .then((l) {
          if (l != null && l.isNotEmpty) onLink?.call(l);
        })
        .catchError((_) {});
  }

  Future<void> detach() async {
    _store?.removeListener(_changed);
    _store = null;
    if (!supported) return;
    _last = '';
    try {
      await _channel.invokeMethod('update', '{}');
    } catch (_) {}
  }

  Future<void> choose(String noteId) async {
    await _settings.put(_chosenKey, noteId);
    _push();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _push);
  }

  Future<void> _push() async {
    final store = _store;
    if (store == null) return;
    final payload = jsonEncode(
      payloadFor(store.activeNotes, _settings.get(_chosenKey) as String?),
    );
    if (payload == _last) return;
    _last = payload;
    try {
      await _channel.invokeMethod('update', payload);
    } catch (e) {
      debugPrint('widget: $e');
    }
  }

  /// Datele pentru widget: lista aleasă (dacă mai există și nu e blocată)
  /// sau cea mai recent modificată listă cu rânduri nebifate.
  @visibleForTesting
  static Map<String, Object?> payloadFor(List<Note> notes, String? chosenId) {
    Note? pick;
    for (final n in notes) {
      if (n.id == chosenId && !n.locked && !n.isTrashed) pick = n;
    }
    if (pick == null) {
      final candidates =
          notes
              .where(
                (n) =>
                    !n.locked &&
                    !n.isTrashed &&
                    checklistOf(n).any((i) => !i.done),
              )
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      pick = candidates.firstOrNull;
    }
    if (pick == null) return {'list': null};
    final items = checklistOf(pick);
    // nebifatele întâi (ca în lista de cumpărături), apoi cele bifate
    final ordered = [
      ...items.where((i) => !i.done),
      ...items.where((i) => i.done),
    ];
    return {
      'list': {
        'id': pick.id,
        'title': pick.displayTitle,
        'open': items.where((i) => !i.done).length,
        'total': items.length,
        'items': [
          for (final i in ordered.take(maxItems)) {'t': i.text, 'd': i.done},
        ],
      },
    };
  }

  /// Rândurile de tip „listă de bifat” din conținutul notiței (Delta Quill:
  /// atributul `list` stă pe caracterul „\n” de la finalul rândului).
  @visibleForTesting
  static List<({String text, bool done})> checklistOf(Note n) {
    final out = <({String text, bool done})>[];
    List ops;
    try {
      ops = jsonDecode(n.contentJson) as List;
    } catch (_) {
      return out;
    }
    final line = StringBuffer();
    for (final op in ops) {
      if (op is! Map) continue;
      final insert = op['insert'];
      if (insert is! String) continue; // imagini, atașamente
      final list = (op['attributes'] as Map?)?['list'];
      final parts = insert.split('\n');
      for (var k = 0; k < parts.length; k++) {
        line.write(parts[k]);
        if (k == parts.length - 1) break; // fără „\n” după ultima bucată
        final text = line.toString().trim();
        line.clear();
        if ((list == 'checked' || list == 'unchecked') && text.isNotEmpty) {
          out.add((text: text, done: list == 'checked'));
        }
      }
    }
    return out;
  }
}
