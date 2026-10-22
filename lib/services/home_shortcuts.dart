import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';

import 'scan_service.dart';

/// Acțiunile rapide de pe iconița aplicației (apăsare lungă pe iconiță).
enum HomeShortcut {
  note('Notiță nouă'),
  list('Listă de bifat'),
  scan('Scanează document'),
  qr('Citește cod QR');

  const HomeShortcut(this.title);
  final String title;
}

class HomeShortcuts {
  static const _actions = QuickActions();

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Înregistrează acțiunile; [onSelected] e apelat și când aplicația a fost
  /// pornită dintr-o acțiune rapidă.
  static Future<void> init(void Function(HomeShortcut) onSelected) async {
    if (!supported) return;
    try {
      await _actions.initialize((type) {
        for (final s in HomeShortcut.values) {
          if (s.name == type) onSelected(s);
        }
      });
      await _actions.setShortcutItems([
        for (final s in HomeShortcut.values)
          if (s != HomeShortcut.scan || ScanService.scanSupported)
            ShortcutItem(type: s.name, localizedTitle: s.title),
      ]);
    } catch (e) {
      debugPrint('HomeShortcuts: $e');
    }
  }
}
