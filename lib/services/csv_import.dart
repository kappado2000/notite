import '../models/secret_item.dart';
import 'secret_helpers.dart';

/// Parser CSV (RFC 4180): ghilimele, virgule și rânduri noi în câmpuri.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = 0;
  if (text.startsWith('﻿')) i = 1; // BOM
  // Separatorul: virgulă sau punct și virgulă (Excel în română).
  final firstLine = text.split('\n').first;
  final sep =
      ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length
      ? ';'
      : ',';
  for (; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == sep) {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      if (row.any((f) => f.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    if (row.any((f) => f.isNotEmpty)) rows.add(row);
  }
  return rows;
}

/// Din ce aplicație pare să provină fișierul (după antet).
String csvSourceName(List<String> header) {
  final h = header.map((e) => e.trim().toLowerCase()).toSet();
  if (h.contains('login_uri') || h.contains('login_totp')) return 'Bitwarden';
  if (h.contains('grouping') || h.contains('extra')) return 'LastPass';
  if (h.contains('otpauth') || h.contains('title') && h.contains('url')) {
    return 'Parole iCloud';
  }
  if (h.contains('name') && h.contains('url') && h.contains('password')) {
    return 'Chrome';
  }
  return 'CSV';
}

/// Coloanele cunoscute (Chrome, Parole iCloud/Safari, Bitwarden, LastPass,
/// 1Password, Firefox) → câmpurile noastre.
const _columns = {
  'title': ['name', 'title', 'nume'],
  'url': ['url', 'login_uri', 'website', 'site', 'origin', 'hostname'],
  'username': ['username', 'login_username', 'user', 'email', 'utilizator'],
  'password': ['password', 'login_password', 'parola', 'parolă'],
  'totp': ['otpauth', 'login_totp', 'totp', 'one-time password'],
  'notes': ['note', 'notes', 'extra', 'notițe', 'notite'],
  'type': ['type'],
  'folder': ['grouping', 'folder'],
  'favorite': ['fav', 'favorite'],
};

/// Transformă rândurile CSV în intrări. Conturile devin „Cont”; din
/// LastPass, notele securizate ajung fiecare în secțiunea lor (card, cont
/// bancar, Wi-Fi, act, notă). Rândurile goale sunt ignorate; cele deja
/// existente sunt sărite.
({List<SecretItem> items, int skipped, String source}) secretsFromCsv(
  String text, {
  required Iterable<SecretItem> existing,
  required SecretItem Function([SecretType type]) create,
}) {
  final rows = parseCsv(text);
  if (rows.length < 2) {
    throw const FormatException('Fișierul nu conține parole.');
  }
  final header = [for (final h in rows.first) h.trim().toLowerCase()];
  int col(String key) => header.indexWhere((h) => _columns[key]!.contains(h));
  final idx = {for (final k in _columns.keys) k: col(k)};
  if (idx['password']! < 0) {
    throw const FormatException(
      'Nu găsesc coloana „password”. Exportă din Chrome, Parole iCloud, '
      'Bitwarden sau LastPass în format CSV.',
    );
  }
  String key(String url, String user, String pass) =>
      '${hostOf(url)}|${user.toLowerCase()}|$pass';
  final seen = {
    for (final i in existing)
      if (i.type == SecretType.login)
        key(i.url, i.username, i.password)
      else
        _noteKey(i),
  };
  final out = <SecretItem>[];
  var skipped = 0;
  for (final r in rows.skip(1)) {
    String v(String k) {
      final i = idx[k]!;
      return i >= 0 && i < r.length ? r[i].trim() : '';
    }

    // LastPass: notele securizate au adresa „http://sn” și câmpurile în
    // „extra” (NoteType:Credit Card, Number:…, Expiration Date:…).
    final extra = v('notes');
    if (v('url') == 'http://sn' || extra.startsWith('NoteType:')) {
      final item = _lastPassNote(v('title'), extra, create);
      final dupKey = item == null
          ? null
          : item.type == SecretType.login
          ? key(item.url, item.username, item.password)
          : _noteKey(item);
      if (item == null || !seen.add(dupKey!)) {
        skipped++;
        continue;
      }
      item.favorite = v('favorite') == '1';
      _addFolder(item, v('folder'));
      out.add(item);
      continue;
    }
    final type = v('type').toLowerCase();
    // Bitwarden: exportă și carduri / note; păstrăm doar conturile.
    if (type.isNotEmpty && type != 'login') {
      skipped++;
      continue;
    }
    final user = v('username');
    final pass = idx['password']! < r.length ? r[idx['password']!] : '';
    final url = v('url');
    if (user.isEmpty && pass.isEmpty) {
      skipped++;
      continue;
    }
    if (!seen.add(key(url, user, pass))) {
      skipped++;
      continue;
    }
    var title = v('title');
    // Chrome pune domeniul ca nume; îl înlocuim cu numele serviciului.
    final site = recognizeSite(url.isNotEmpty ? url : title);
    if (site != null && (title.isEmpty || title == hostOf(url))) {
      title = site.name;
    }
    if (title.isEmpty) title = hostOf(url);
    final item = create()
      ..title = title
      ..url = url
      ..username = user
      ..password = pass
      ..totp = v('totp')
      ..notes = v('notes')
      ..favorite = v('favorite') == '1';
    _addFolder(item, v('folder'));
    out.add(item);
  }
  return (items: out, skipped: skipped, source: csvSourceName(rows.first));
}

/// Dosarul din LastPass, păstrat ca un câmp al intrării.
void _addFolder(SecretItem item, String folder) {
  if (folder.isEmpty) return;
  item.custom.add(CustomField(label: 'Dosar (LastPass)', value: folder));
}

/// Cheia pentru „există deja” la intrările care nu sunt conturi.
String _noteKey(SecretItem i) => [
  i.type.name,
  i.title.trim().toLowerCase(),
  i.cardDigits,
  i.ibanCompact,
  i.username,
  i.docNumber,
  i.notes.trim(),
].join('|');

/// Câmpurile unei note LastPass: „Cheie:Valoare” pe rânduri; „Notes:” ține
/// până la sfârșit (poate avea mai multe rânduri).
({String type, Map<String, String> fields, String notes}) parseLastPassExtra(
  String extra,
) {
  final fields = <String, String>{};
  var type = '';
  var notes = '';
  final lines = extra.replaceAll('\r', '').split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final c = line.indexOf(':');
    if (c <= 0) continue;
    final k = line.substring(0, c).trim();
    final v = line.substring(c + 1).trim();
    if (k == 'NoteType') {
      type = v;
    } else if (k == 'Notes') {
      notes = [line.substring(c + 1), ...lines.skip(i + 1)].join('\n').trim();
      break;
    } else if (k != 'Language' && v.isNotEmpty) {
      fields[k] = v;
    }
  }
  return (type: type, fields: fields, notes: notes);
}

const _months = {
  'january': 1,
  'february': 2,
  'march': 3,
  'april': 4,
  'may': 5,
  'june': 6,
  'july': 7,
  'august': 8,
  'september': 9,
  'october': 10,
  'november': 11,
  'december': 12,
};

/// Datele LastPass: „May,05,2028”, „January,2027” sau „2028-05-05”.
DateTime? _lpDate(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final iso = DateTime.tryParse(s.trim());
  if (iso != null) return iso;
  final p = s.split(RegExp(r'[,\s/]+')).where((e) => e.isNotEmpty).toList();
  final m = p.isEmpty ? null : _months[p.first.toLowerCase()];
  if (m == null) return null;
  final nums = p.skip(1).map(int.tryParse).whereType<int>().toList();
  if (nums.isEmpty) return null;
  final year = nums.last < 100 ? 2000 + nums.last : nums.last;
  final day = nums.length >= 2 ? nums.first : 1;
  return DateTime(year, m, day);
}

/// O notă securizată LastPass → intrarea potrivită din Notițe.
SecretItem? _lastPassNote(
  String name,
  String extra,
  SecretItem Function([SecretType type]) create,
) {
  final p = parseLastPassExtra(extra);
  final f = Map.of(p.fields);
  String take(List<String> keys) {
    for (final k in keys) {
      final v = f.remove(k);
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  // Ce n-a avut loc în câmpurile noastre rămâne ca un câmp suplimentar
  // (ascuns, dacă pare secret).
  void rest(SecretItem i) {
    for (final e in f.entries) {
      i.custom.add(
        CustomField(
          label: e.key,
          value: e.value,
          hidden: RegExp(
            r'pin|password|parol|code|cod|secret|key',
            caseSensitive: false,
          ).hasMatch(e.key),
        ),
      );
    }
    i.notes = p.notes;
  }

  final kind = p.type.toLowerCase();
  if (kind == 'credit card') {
    final i = create(SecretType.card)..title = name;
    i.cardHolder = take(['Name on Card']);
    i.cardNumber = take(['Number']);
    i.cardCvv = take(['Security Code']);
    final exp = _lpDate(take(['Expiration Date']));
    if (exp != null) {
      final mm = exp.month.toString().padLeft(2, '0');
      final yy = (exp.year % 100).toString().padLeft(2, '0');
      i.cardExpiry = '$mm/$yy';
    }
    f.remove('Type');
    rest(i);
    return i;
  }
  if (kind == 'bank account') {
    final i = create(SecretType.bank)..title = name;
    i.bankName = take(['Bank Name']);
    final iban = take(['IBAN Number']);
    final acc = take(['Account Number']);
    i.iban = iban.isNotEmpty ? iban : acc;
    if (iban.isNotEmpty && acc.isNotEmpty) {
      i.custom.add(CustomField(label: 'Număr cont', value: acc));
    }
    i.swift = take(['SWIFT Code']);
    rest(i);
    return i;
  }
  if (kind == 'wi-fi password') {
    final i = create(SecretType.wifi)..title = name;
    i.username = take(['SSID']);
    if (i.username.isEmpty) i.username = name;
    i.password = take(['Password']);
    final auth = '${take(['Authentication'])} ${f['Encryption'] ?? ''}'
        .toLowerCase();
    i.wifiSecurity = auth.contains('wep')
        ? 'WEP'
        : (auth.contains('open') || auth.contains('none')) && i.password.isEmpty
        ? 'nopass'
        : 'WPA';
    rest(i);
    return i;
  }
  if (kind == 'passport' || kind == 'driver\'s license') {
    final i = create(SecretType.identity)..title = name;
    i.docKind = kind == 'passport' ? DocKind.passport : DocKind.license;
    i.lastName = take(['Name']);
    i.docNumber = take(['Number']);
    i.issueDate = _lpDate(take(['Issued Date']));
    i.expiryDate = _lpDate(take(['Expiration Date']));
    i.address = [
      take(['Address']),
      take(['City / Town']),
      take(['ZIP / Postal Code']),
      take(['State']),
    ].where((e) => e.isNotEmpty).join(', ');
    f.remove('Type');
    rest(i);
    return i;
  }
  // Note cu utilizator și parolă (email, server, bază de date…) → cont
  final user = f['Username'] ?? f['Email Address'] ?? '';
  final pass = f['Password'] ?? '';
  if (user.isNotEmpty && pass.isNotEmpty) {
    final i = create(SecretType.login)..title = name;
    i.username = take(['Username', 'Email Address']);
    i.password = take(['Password']);
    i.url = take(['Hostname', 'Server', 'URL', 'Website']);
    rest(i);
    if (p.type.isNotEmpty) {
      i.custom.insert(0, CustomField(label: 'Tip (LastPass)', value: p.type));
    }
    return i;
  }
  // Orice altceva: notă securizată, cu toate câmpurile păstrate
  if (f.isEmpty && p.notes.isEmpty && name.isEmpty) return null;
  final i = create(SecretType.note)..title = name.isEmpty ? p.type : name;
  rest(i);
  return i;
}
