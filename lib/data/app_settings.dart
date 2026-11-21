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

  /// O listă personalizată (carduri Acasă, unelte, șabloane): id-urile
  /// alese, în ordinea aleasă; null = cea implicită.
  List<String>? customList(String key) {
    var ids = (_box.get('custom_$key') as List?)?.cast<String>();
    if (key != 'homeCards' || ids == null) return ids;
    // o singură dată: cardul „Notiță” de pe Acasă (dublat de butonul din
    // dreapta-jos) devine „Auth”
    if (_box.get('homeAuthSwap') != true) {
      _box.put('homeAuthSwap', true);
      if (ids.contains('note') && !ids.contains('auth')) {
        ids = [for (final i in ids) i == 'note' ? 'auth' : i];
        _box.put('custom_$key', ids);
      }
    }
    // o singură dată: „Auth” primul în rând (apoi ordinea e a ta)
    if (_box.get('homeAuthFirst') != true) {
      _box.put('homeAuthFirst', true);
      if (ids.contains('auth') && ids.first != 'auth') {
        ids = ['auth', ...ids.where((i) => i != 'auth')];
        _box.put('custom_$key', ids);
      }
    }
    return ids;
  }

  void setCustomList(String key, List<String>? ids) {
    if (ids == null) {
      _box.delete('custom_$key');
    } else {
      _box.put('custom_$key', ids);
    }
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

  /// Cardurile de sus din Parole (tipuri, avertizări) ascunse, ca lista să
  /// aibă tot ecranul. Ținut minte între porniri.
  bool get secretsHeaderHidden =>
      (_box.get('secretsHeaderHidden') as bool?) ?? false;
  set secretsHeaderHidden(bool v) {
    _box.put('secretsHeaderHidden', v);
    notifyListeners();
  }

  /// Ordinea conturilor în Autentificator: 'alpha' (A–Z), 'recent'
  /// (codul copiat cel mai de curând primul) sau 'manual' (trase de tine).
  String get authOrder => (_box.get('authOrder') as String?) ?? 'alpha';
  set authOrder(String v) {
    _box.put('authOrder', v);
    notifyListeners();
  }

  /// Ordinea manuală: id-urile conturilor, de sus în jos.
  List<String> get authManual =>
      ((_box.get('authManual') as List?) ?? const []).cast<String>();
  set authManual(List<String> v) {
    _box.put('authManual', v);
    notifyListeners();
  }

  /// Când ai copiat ultima dată codul fiecărui cont (id → ms).
  Map<String, int> get authUsed =>
      ((_box.get('authUsed') as Map?) ?? const {}).cast<String, int>();
  void markAuthUsed(String id) {
    _box.put('authUsed', {
      ...authUsed,
      id: DateTime.now().millisecondsSinceEpoch,
    });
    if (authOrder == 'recent') notifyListeners();
  }

  /// Ultimul export al codurilor de rezervă (amprenta listei și când), ca
  /// să știi când trebuie printată din nou foaia.
  String get recoveryExportHash =>
      (_box.get('recoveryExportHash') as String?) ?? '';
  DateTime? get recoveryExportAt {
    final ms = _box.get('recoveryExportAt') as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void markRecoveryExport(String hash) {
    _box.put('recoveryExportHash', hash);
    _box.put('recoveryExportAt', DateTime.now().millisecondsSinceEpoch);
    notifyListeners();
  }

  /// Ultimul email folosit la logare, precompletat data viitoare.
  String get lastEmail => (_box.get('lastEmail') as String?) ?? '';
  set lastEmail(String v) => _box.put('lastEmail', v);
}
