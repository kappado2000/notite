import '../models/secret_item.dart';
import 'csv_import.dart';
import 'password_tools.dart';
import 'secret_helpers.dart';

/// Un cont din fișierul Google care există și în Notițe, dar cu altă parolă.
class PasswordDiff {
  PasswordDiff(this.local, this.other, {required this.olderInNotite});

  final SecretItem local;
  final SecretItem other;

  /// Parola din Google e una veche a contului (e în „Parole anterioare”):
  /// ai schimbat-o deja în Notițe, Google a rămas în urmă.
  final bool olderInNotite;
}

/// Rezultatul comparării parolelor din Notițe cu un export Google / Chrome.
class PasswordCompare {
  PasswordCompare({
    required this.missing,
    required this.different,
    required this.same,
    required this.source,
  });

  /// În fișier, dar nu în Notițe (ca la AFM).
  final List<SecretItem> missing;
  final List<PasswordDiff> different;
  final int same;
  final String source;
}

/// Compară după site + utilizator (ca la dubluri), ținând cont și de
/// „Alte site-uri” ale conturilor din Notițe.
PasswordCompare compareWithCsv(
  String text, {
  required Iterable<SecretItem> existing,
  required SecretItem Function([SecretType type]) create,
}) {
  final parsed = secretsFromCsv(text, existing: const [], create: create);
  final byKey = <String, List<SecretItem>>{};
  for (final i in existing) {
    if (i.type != SecretType.login) continue;
    for (final k in accountKeys(i)) {
      byKey.putIfAbsent(k, () => []).add(i);
    }
  }
  final missing = <SecretItem>[];
  final different = <PasswordDiff>[];
  var same = 0;
  for (final c in parsed.items) {
    if (c.type != SecretType.login) continue;
    final locals = {for (final k in accountKeys(c)) ...?byKey[k]};
    if (locals.isEmpty) {
      missing.add(c);
    } else if (locals.any((l) => l.password == c.password)) {
      same++;
    } else {
      final l = locals.first;
      different.add(
        PasswordDiff(
          l,
          c,
          olderInNotite: l.passwordHistory.any((p) => p.password == c.password),
        ),
      );
    }
  }
  missing.sort(
    (a, b) =>
        a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()),
  );
  return PasswordCompare(
    missing: missing,
    different: different,
    same: same,
    source: parsed.source,
  );
}

/// Export în formatul acceptat de Google Password Manager / Chrome
/// (name,url,username,password,note). Câte un rând pentru fiecare site al
/// contului (adresa lui + „Alte site-uri”). Conturile fără site recunoscut
/// nu pot fi importate de Google: le numărăm în [skipped].
({String csv, int rows, int skipped}) googleCsv(Iterable<SecretItem> items) {
  String cell(String v) =>
      v.contains(RegExp(r'[",\n\r]')) ? '"${v.replaceAll('"', '""')}"' : v;
  String? urlOf(String u) {
    final h = hostOf(u);
    if (h.isEmpty) return null;
    final t = u.trim();
    return RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(t)
        ? t
        : 'https://$t';
  }

  final out = <String>['name,url,username,password,note'];
  var skipped = 0;
  for (final i in items) {
    if (i.type != SecretType.login || i.password.isEmpty || i.isTrashed) {
      continue;
    }
    final known = recognizeSite(i.title)?.domain;
    final urls = <String>{?urlOf(i.url), for (final s in i.sites) ?urlOf(s)};
    if (urls.isEmpty && known != null) urls.add('https://$known');
    if (urls.isEmpty) {
      skipped++;
      continue;
    }
    for (final u in urls) {
      out.add(
        [i.displayTitle, u, i.username, i.password, ''].map(cell).join(','),
      );
    }
  }
  return (csv: '${out.join('\n')}\n', rows: out.length - 1, skipped: skipped);
}
