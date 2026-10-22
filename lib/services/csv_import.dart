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
};

/// Transformă rândurile CSV în intrări „Cont”. Rândurile fără parolă și
/// fără utilizator sunt ignorate; cele deja existente (același site,
/// utilizator și parolă) sunt sărite.
({List<SecretItem> items, int skipped, String source}) secretsFromCsv(
  String text, {
  required Iterable<SecretItem> existing,
  required SecretItem Function() create,
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
      if (i.type == SecretType.login) key(i.url, i.username, i.password),
  };
  final out = <SecretItem>[];
  var skipped = 0;
  for (final r in rows.skip(1)) {
    String v(String k) {
      final i = idx[k]!;
      return i >= 0 && i < r.length ? r[i].trim() : '';
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
    out.add(
      create()
        ..title = title
        ..url = url
        ..username = user
        ..password = pass
        ..totp = v('totp')
        ..notes = v('notes'),
    );
  }
  return (items: out, skipped: skipped, source: csvSourceName(rows.first));
}
