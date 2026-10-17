import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Setări ale aplicației, independente de cont (ex. tema).
class AppSettings extends ChangeNotifier {
  AppSettings(this._box);

  final Box _box;

  ThemeMode get themeMode =>
      ThemeMode.values[(_box.get('themeMode') as int?) ?? 0];
  set themeMode(ThemeMode v) {
    _box.put('themeMode', v.index);
    notifyListeners();
  }

  /// Ultimul email folosit la logare, precompletat data viitoare.
  String get lastEmail => (_box.get('lastEmail') as String?) ?? '';
  set lastEmail(String v) => _box.put('lastEmail', v);
}
