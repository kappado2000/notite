import 'package:flutter_test/flutter_test.dart';
import 'package:notite/models/note.dart';
import 'package:notite/services/receipt_totals.dart';

Note _bon(String id, String title, String text, {List<String>? tags}) => Note(
  id: id,
  notebookId: 'nb',
  title: title,
  plainText: text,
  tags: tags ?? ['bonuri'],
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
);

void main() {
  final a = _bon(
    'a',
    'Bon · Restaurant Exemplu · 05.11.2026',
    'Restaurant Exemplu · 05.11.2026\n'
        'Eu: 45,50 lei\n'
        '  1 × Pizza — 35,00 lei\n'
        '  1 × Apă — 10,50 lei\n\n'
        'Ana: 1.020,00 lei\n'
        '  1 × Vin — 1.020,00 lei\n\n'
        'Nealocat: 4,50 lei\n\n'
        'Total bon: 1.070,00 lei',
  );
  final b = _bon(
    'b',
    'Bon · Magazin · 20.11.2026',
    'eu: 10,00 lei\n  1 × Pâine — 10,00 lei\n\nTotal bon: 10,00 lei',
  );
  final c = _bon(
    'c',
    'Bon · Cafenea · 02.10.2026',
    'Ana: 12,00 lei\n\nTotal bon: 12,00 lei',
  );

  test('citește bonul: participanți, nealocat, total, magazin, dată', () {
    final e = parseReceiptNote(a)!;
    expect(e.persons, {'Eu': 45.5, 'Ana': 1020.0});
    expect(e.unassigned, 4.5);
    expect(e.total, 1070.0);
    expect(e.merchant, 'Restaurant Exemplu');
    expect(e.date, DateTime(2026, 11, 5));
  });

  test('adună pe participanți (fără diferență de litere) și total', () {
    final t = ReceiptTotals(receiptsIn([a, b, c]));
    expect(t.total, 1092.0);
    expect(t.entries.length, 3);
    expect(t.persons['eu']!.sum, 55.5);
    expect(t.persons['eu']!.entries.length, 2);
    expect(t.persons['ana']!.sum, 1032.0);
    expect(t.ranked.first.name, 'Ana');
  });

  test('perioada: doar bonurile dintre date', () {
    final nov = receiptsIn(
      [a, b, c],
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 11, 30),
    );
    expect(nov.map((e) => e.note.id), ['b', 'a']);
    final t = ReceiptTotals(nov);
    expect(t.total, 1080.0);
    expect(t.persons.containsKey('ana'), isTrue);
  });

  test('notițele fără eticheta „bonuri” sau fără sume nu intră', () {
    final other = _bon('x', 'Notă', 'Eu: 5,00 lei', tags: ['altceva']);
    final empty = _bon('y', 'Bon gol', 'nimic aici');
    expect(receiptsIn([other, empty]), isEmpty);
  });
}
