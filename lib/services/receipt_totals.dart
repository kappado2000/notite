import '../data/notes_store.dart';
import '../models/note.dart';

/// Un bon salvat (notiță cu eticheta „bonuri”), citit din textul lui:
/// „Ana: 45,50 lei”, „Nealocat: …”, „Total bon: … lei”. Dacă ai corectat de
/// mână o sumă în notiță, se ia în calcul valoarea corectată.
class ReceiptEntry {
  ReceiptEntry({
    required this.note,
    required this.date,
    required this.merchant,
    required this.total,
    required this.unassigned,
    required this.persons,
  });

  final Note note;
  final DateTime date;
  final String merchant;
  final double total;
  final double unassigned;

  /// Numele așa cum apare în bon → suma lui.
  final Map<String, double> persons;
}

/// Suma unui participant pe perioadă și bonurile din care vine.
class PersonTotal {
  PersonTotal(this.name);
  final String name;
  double sum = 0;
  final List<(ReceiptEntry, double)> entries = [];
}

class ReceiptTotals {
  ReceiptTotals(this.entries) {
    for (final e in entries) {
      total += e.total;
      unassigned += e.unassigned;
      e.persons.forEach((name, v) {
        final p = persons.putIfAbsent(
          name.trim().toLowerCase(),
          () => PersonTotal(name.trim()),
        );
        p.sum += v;
        p.entries.add((e, v));
      });
    }
    for (final p in persons.values) {
      p.sum = _round2(p.sum);
      p.entries.sort((a, b) => b.$1.date.compareTo(a.$1.date));
    }
    total = _round2(total);
    unassigned = _round2(unassigned);
  }

  final List<ReceiptEntry> entries;
  double total = 0;
  double unassigned = 0;

  /// Cheie = numele fără diferență între litere mari și mici.
  final Map<String, PersonTotal> persons = {};

  /// Participanții, de la cel cu suma cea mai mare.
  List<PersonTotal> get ranked =>
      persons.values.toList()..sort((a, b) => b.sum.compareTo(a.sum));
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

final _line = RegExp(r'^\s*(.+?):\s*(-?[\d.\s]+,\d{2})\s*lei\s*$');

/// „1.234,56” → 1234.56.
double? parseLei(String s) =>
    double.tryParse(s.replaceAll(RegExp(r'[.\s]'), '').replaceAll(',', '.'));

/// Bonul din notiță; null dacă textul nu are nicio sumă de bon.
ReceiptEntry? parseReceiptNote(Note n) {
  final persons = <String, double>{};
  double? total;
  var unassigned = 0.0;
  for (final raw in n.plainText.split('\n')) {
    final m = _line.firstMatch(raw);
    if (m == null) continue;
    final name = m[1]!.trim();
    final v = parseLei(m[2]!);
    if (v == null) continue;
    final key = name.toLowerCase();
    if (key == 'total bon') {
      total = v;
    } else if (key == 'nealocat') {
      unassigned = v;
    } else {
      persons[name] = _round2((persons[name] ?? 0) + v);
    }
  }
  if (total == null && persons.isEmpty) return null;
  final parts = n.title.split('·').map((s) => s.trim()).toList();
  final merchant = parts.length >= 3 && parts.first.toLowerCase() == 'bon'
      ? parts[1]
      : (parts.length == 2 && parts.first.toLowerCase() == 'bon'
            ? ''
            : n.displayTitle);
  return ReceiptEntry(
    note: n,
    date: NotesStore.docDate(n),
    merchant: merchant,
    total: total ?? _round2(persons.values.fold(0.0, (s, v) => s + v)),
    unassigned: unassigned,
    persons: persons,
  );
}

/// Bonurile dintre [from] și [to] (inclusiv; null = fără limită), cele mai
/// noi primele.
List<ReceiptEntry> receiptsIn(
  Iterable<Note> notes, {
  DateTime? from,
  DateTime? to,
}) {
  final out = <ReceiptEntry>[];
  for (final n in notes) {
    if (!n.tags.contains('bonuri')) continue;
    final e = parseReceiptNote(n);
    if (e == null) continue;
    final d = DateTime(e.date.year, e.date.month, e.date.day);
    if (from != null && d.isBefore(from)) continue;
    if (to != null && d.isAfter(to)) continue;
    out.add(e);
  }
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}
