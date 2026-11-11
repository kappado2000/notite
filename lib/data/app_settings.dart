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

  /// Notițele afișate în grilă (true) sau în listă.
  bool get notesGrid => (_box.get('notesGrid') as bool?) ?? false;
  set notesGrid(bool v) {
    _box.put('notesGrid', v);
    notifyListeners();
  }

  /// Text îngroșat în aplicație. Implicit oprit (scris normal, ca în
  /// Evernote), indiferent de „Text aldin” din setările telefonului.
  bool get boldText => (_box.get('boldText') as bool?) ?? false;
  set boldText(bool v) {
    _box.put('boldText', v);
    notifyListeners();
  }

  /// Mărimea textului în aplicație, peste cea din setările telefonului
  /// (1.0 = 100%).
  double get textScale => (_box.get('textScale') as double?) ?? 1.0;
  set textScale(double v) {
    v = (v * 20).round() / 20; // pași de 5%, fără zecimale „murdare”
    _box.put('textScale', v);
    notifyListeners();
  }

  /// Conținutul ascuns în comutatorul de aplicații (implicit pornit).
  bool get hideInSwitcher => (_box.get('hideInSwitcher') as bool?) ?? true;
  set hideInSwitcher(bool v) {
    _box.put('hideInSwitcher', v);
    notifyListeners();
  }

  /// Nuanța aleasă pentru un tip de parole: (culoare, intensitate, scris)
  /// sau null = cea implicită a tipului.
  (int, int, int)? secretTypeTint(String type) {
    final v = _box.get('secretTint.$type');
    if (v is List && v.length == 3) {
      return (v[0] as int, v[1] as int, v[2] as int);
    }
    return null;
  }

  void setSecretTypeTint(String type, (int, int, int)? v) {
    if (v == null) {
      _box.delete('secretTint.$type');
    } else {
      _box.put('secretTint.$type', [v.$1, v.$2, v.$3]);
    }
    notifyListeners();
  }

  /// După câte minute fără folosire se blochează singură secțiunea Parole
  /// (0 = doar manual / la ieșirea din aplicație).
  int get secretsAutoLockMinutes =>
      (_box.get('secretsAutoLockMinutes') as int?) ?? 5;
  set secretsAutoLockMinutes(int v) {
    _box.put('secretsAutoLockMinutes', v);
    notifyListeners();
  }

  /// Ultimul email folosit la logare, precompletat data viitoare.
  String get lastEmail => (_box.get('lastEmail') as String?) ?? '';
  set lastEmail(String v) => _box.put('lastEmail', v);
}
