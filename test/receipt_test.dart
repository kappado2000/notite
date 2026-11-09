import 'package:flutter_test/flutter_test.dart';
import 'package:notite/services/ocr_rows.dart';
import 'package:notite/services/receipt.dart';

void main() {
  test('sume: virgulă, punct, mii', () {
    expect(parseAmount('30,00'), 30.0);
    expect(parseAmount('30.00'), 30.0);
    expect(parseAmount('1.234,50'), 1234.5);
    expect(parseAmount('1,234.50'), 1234.5);
    expect(formatLei(1234.5), '1.234,50');
    expect(formatLei(15), '15,00');
  });

  test(
    'bon fiscal: cantitatea pe un rând, denumirea + totalul pe următorul',
    () {
      final r = parseReceipt([
        'S.C. TERASA DUNARII S.R.L.',
        'CIF: RO12345678',
        'TULCEA, STR. PORTULUI 1',
        '2.000 BUC x 15.00',
        'BERE URSUS 0.5L          30.00 B',
        '1.000 BUC x 25.50',
        'CIORBA DE BURTA          25.50 B',
        'SUBTOTAL                 55.50',
        'TOTAL                    55.50',
        'CARD                     55.50',
        'DATA: 08.11.2026 ORA: 21:14',
      ]);
      expect(r.merchant, 'S.C. TERASA DUNARII S.R.L.');
      expect(r.items.length, 2);
      expect(r.items[0].name, 'BERE URSUS 0.5L');
      expect(r.items[0].qty, 2);
      expect(r.items[0].unitPrice, 15);
      expect(r.items[0].total, 30);
      expect(r.items[1].name, 'CIORBA DE BURTA');
      expect(r.printedTotal, 55.5);
      expect(r.missing, 0);
      expect(r.date, DateTime(2026, 11, 8));
    },
  );

  test('notă de restaurant: denumire, cantitate, preț, valoare pe un rând', () {
    final r = parseReceipt([
      'Restaurant La Pescari',
      'Masa 4   Ospatar Ion',
      'Bere Ursus  2 x 15,00  30,00',
      'Pizza Diavola  1  32,00  32,00',
      'Apa plata 0.5  2  7,50  15,00',
      'TOTAL  77,00 LEI',
    ]);
    expect(r.items.map((i) => i.name).toList(), [
      'Bere Ursus',
      'Pizza Diavola',
      'Apa plata 0.5',
    ]);
    expect(r.items.map((i) => i.total).toList(), [30, 32, 15]);
    expect(r.items[2].qty, 2);
    expect(r.printedTotal, 77);
    expect(r.missing, 0);
  });

  test('produse cu cantitate 1 și denumire pe rândul de dinainte', () {
    final r = parseReceipt([
      'MAGAZIN MIXT',
      'PAINE ALBA          4,50 A',
      'LAPTE 3.5%          7,99 A',
      'COCA COLA 0.5L',
      '3 x 6,00            18,00 B',
      'TOTAL              30,49',
    ]);
    expect(r.items.length, 3);
    expect(r.items[0].name, 'PAINE ALBA');
    expect(r.items[0].qty, 1);
    expect(r.items[1].total, 7.99);
    expect(r.items[2].name, 'COCA COLA 0.5L');
    expect(r.items[2].units, 3);
    expect(r.missing, 0);
  });

  test('„denumire x cantitate valoare”, fără preț unitar (4 beri Peroni)', () {
    final r = parseReceipt([
      'BISTRO CENTRAL',
      'Peroni Draft  x 4.000  48.00',
      '2 x Pizza Margherita  64,00',
      'Limonada 0.4L',
      'x 3  36,00',
      'Fanta 6x0.5L  30,00',
      'TOTAL  178,00',
    ]);
    expect(r.items.map((i) => i.name).toList(), [
      'Peroni Draft',
      'Pizza Margherita',
      'Limonada 0.4L',
      'Fanta 6x0.5L',
    ]);
    final peroni = r.items[0];
    expect(peroni.qty, 4);
    expect(peroni.units, 4);
    expect(peroni.unitPrice, 12);
    expect(peroni.total, 48);
    expect(r.items[1].qty, 2);
    expect(r.items[1].unitPrice, 32);
    expect(r.items[2].qty, 3);
    expect(r.items[2].unitPrice, 12);
    expect(r.items[3].qty, 1); // „6x0.5L” e parte din denumire
    expect(r.missing, 0);
    // o persoană alege o singură bere din cele 4
    final s = ReceiptSplit(r)..set('Eu', 0, 1);
    expect(s.personTotal('Eu'), 12);
  });

  test('rânduri refăcute: prețurile venite ca bloc separat', () {
    // ML Kit: coloana de denumiri și coloana de prețuri, blocuri diferite.
    final rows = rowsFromLines(const [
      OcrLine('2 x 15,00', 10, 100, 120, 118),
      OcrLine('Bere Ursus', 10, 120, 140, 138),
      OcrLine('Pizza Diavola', 10, 140, 160, 158),
      OcrLine('30,00', 300, 121, 360, 139),
      OcrLine('32,00', 300, 141, 360, 159),
    ]);
    expect(rows, ['2 x 15,00', 'Bere Ursus  30,00', 'Pizza Diavola  32,00']);
    final r = parseReceipt(rows);
    expect(r.items.length, 2);
    expect(r.items[0].name, 'Bere Ursus');
    expect(r.items[0].qty, 2);
    expect(r.items[1].total, 32);
  });

  test('poză nedecupată, ținută strâmb: notă de plată cu bacșiș', () {
    // ce întoarce cititorul: denumire, „X cantitate” și valoare, ca linii
    // separate; bonul e înclinat ~3°, deci prețul din dreapta stă cu
    // aproape un rând mai jos decât denumirea lui
    const slope = 0.05;
    final lines = <OcrLine>[];
    void row(double y, List<(String, double, double)> cells) {
      for (final (text, l, r) in cells) {
        final dy = slope * (l + r) / 2;
        lines.add(OcrLine(text, l, y + dy, r, y + dy + 40, slope: slope));
      }
    }

    row(650, [('NOTA DE PLATA', 360, 760)]);
    row(760, [('Nr.:N.partiala din 09.11.2026 22:21', 95, 750)]);
    const items = [
      ('Peroni Draft', 'X 8.000', '96.00'),
      ('Apa minerala 750ml', 'X 2.000', '30.00'),
      ('Pahar Vin Rosu-Purca', 'X 3.000', '51.00'),
      ('Borzaska de porc', 'X 2.000', '76.00'),
      ('Ceafa traditionala de', 'X 2.000', '76.00'),
      ('Cartofi rustici', 'X 3.000', '45.00'),
      ('Legume Grill', 'X 2.000', '40.00'),
      ('Muraturi asortate', 'X 2.000', '24.00'),
      ('Tandem Alb', 'X 1.000', '65.00'),
    ];
    for (var i = 0; i < items.length; i++) {
      final (name, qty, price) = items[i];
      row(900 + 50.0 * i, [
        (name, 90, 470),
        (qty, 585, 725),
        (price, 880, 1000),
      ]);
    }
    row(1440, [('Total de plata: 503.00', 545, 960)]);
    row(1485, [('din care TVA: 65.62', 635, 960)]);
    row(1570, [('Alegeti valoarea bacsisului', 135, 565)]);
    row(1700, [('( ) 5% - 25.00 LEI', 140, 460)]);
    row(1745, [('( ) 10% - 50.00 LEI', 140, 470)]);

    final r = parseReceipt(rowsFromLines(lines));
    expect(r.items.map((i) => i.name).toList(), [
      for (final (name, _, _) in items) name,
    ]);
    expect(r.items.map((i) => i.qty).toList(), [8, 2, 3, 2, 2, 3, 2, 2, 1]);
    expect(r.items[0].unitPrice, 12);
    expect(r.printedTotal, 503);
    expect(r.missing, 0);
    expect(r.date, DateTime(2026, 11, 9));
    expect(r.merchant, ''); // „NOTA DE PLATA” nu e numele localului
  });

  test('o urmă de fundal după preț nu strică rândul', () {
    final r = parseReceipt(['Peroni Draft  X 8.000  96.00  |', 'TOTAL 96.00']);
    expect(r.items.single.qty, 8);
    expect(r.missing, 0);
  });

  group('bon lung, din mai multe poze', () {
    test('partea comună dintre poze apare o singură dată', () {
      final m = mergeRowParts([
        [
          'RESTAURANT X',
          'Bere  2 x 15,00  30,00',
          'Pizza  32,00',
          'Supa  18,00',
        ],
        ['Pizza  32,00', 'Supa  18,00', 'Desert  21,00', 'TOTAL  101,00'],
      ]);
      expect(m.rows, [
        'RESTAURANT X',
        'Bere  2 x 15,00  30,00',
        'Pizza  32,00',
        'Supa  18,00',
        'Desert  21,00',
        'TOTAL  101,00',
      ]);
      expect(m.skipped, 2);
      final r = parseReceipt(m.rows);
      expect(r.items.length, 4);
      expect(r.missing, 0); // nimic dublat: suma bate cu TOTAL-ul
    });

    test('tolerează diferențe de citire între poze („30,00” / „30.00”)', () {
      final m = mergeRowParts([
        ['Bere Ursus  30,00 B', 'Pizza Diavola  32,00 B'],
        ['Pizza Diavo1a  32.00 B', 'Apa  7,50 B'],
      ]);
      expect(m.rows.length, 3);
      expect(m.rows.last, 'Apa  7,50 B');
    });

    test('rândurile tăiate la marginea pozelor sunt ignorate', () {
      final m = mergeRowParts([
        ['Bere  30,00', 'Pizza  32,00', 'Supa  18,00', 'Ceai  6,00', 'Ds~rt 2'],
        ['iza 3', 'Supa  18,00', 'Ceai  6,00', 'Desert  21,00', 'Cafea  9,00'],
      ]);
      // „Ds~rt 2” (jos, tăiat) și „iza 3” (sus, tăiat) dispar
      expect(m.rows, [
        'Bere  30,00',
        'Pizza  32,00',
        'Supa  18,00',
        'Ceai  6,00',
        'Desert  21,00',
        'Cafea  9,00',
      ]);
    });

    test('fără parte comună: pozele se pun una după alta', () {
      final m = mergeRowParts([
        ['Bere  30,00', 'Pizza  32,00'],
        ['Supa  18,00', 'Desert  21,00'],
      ]);
      expect(m.rows.length, 4);
      expect(m.skipped, 0);
    });

    test('produse identice în aceeași poză rămân amândouă', () {
      final m = mergeRowParts([
        ['Bere  15,00', 'Bere  15,00', 'Pizza  32,00'],
      ]);
      expect(m.rows.length, 3);
      expect(parseReceipt(m.rows).itemsTotal, 62);
    });

    test('trei poze', () {
      final m = mergeRowParts([
        ['Apa  1,00', 'Bere  2,00', 'Cafea  3,00'],
        ['Bere  2,00', 'Cafea  3,00', 'Dulce  4,00', 'Ecler  5,00'],
        ['Ecler  5,00', 'Fanta  6,00', 'TOTAL  21,00'],
      ]);
      final r = parseReceipt(m.rows);
      expect(r.items.map((i) => i.name).toList(), [
        'Apa',
        'Bere',
        'Cafea',
        'Dulce',
        'Ecler',
        'Fanta',
      ]);
      expect(r.missing, 0);
    });
  });

  test('continuare: alegerile făcute deja rămân după poza nouă', () {
    final first = parseReceipt(['Bere  2 x 15,00  30,00', 'Pizza  32,00']);
    final s = ReceiptSplit(first, persons: ['Eu', 'Ion'])
      ..set('Eu', 0, 1)
      ..set('Ion', 1, 1);
    final merged = mergeRowParts([
      ['Bere  2 x 15,00  30,00', 'Pizza  32,00'],
      ['Pizza  32,00', 'Supa  18,00', 'TOTAL  80,00'],
    ]);
    final s2 = s.withReceipt(parseReceipt(merged.rows));
    expect(s2.receipt.items.length, 3);
    expect(s2.persons, ['Eu', 'Ion']);
    expect(s2.taken('Eu', 0), 1);
    expect(s2.taken('Ion', 1), 1);
    expect(s2.receipt.missing, 0);
    expect(s2.unassignedTotal, 33); // berea rămasă + supa
  });

  test('împărțire: fiecare își alege bucățile, fără dubluri', () {
    final r = Receipt(
      items: [
        ReceiptItem(name: 'Bere', qty: 2, unitPrice: 15),
        ReceiptItem(name: 'Pizza', qty: 1, unitPrice: 32),
        ReceiptItem(name: 'Brânză', qty: 0.456, unitPrice: 40, total: 18.24),
      ],
    );
    final s = ReceiptSplit(r, persons: ['Eu', 'Ion']);
    s.set('Eu', 0, 1); // o bere din două
    expect(s.personTotal('Eu'), 15);
    s.set('Ion', 0, 5); // vrea 5, dar a mai rămas una
    expect(s.taken('Ion', 0), 1);
    expect(s.remaining(0), 0);
    s.set('Ion', 1, 1);
    expect(s.personTotal('Ion'), 47);
    // produs cântărit = un singur întreg
    expect(r.items[2].units, 1);
    s.set('Eu', 2, 1);
    expect(s.personTotal('Eu'), 33.24);
    expect(s.unassignedTotal, 0);
    final text = s.summary();
    expect(text, contains('Eu: 33,24 lei'));
    expect(text, contains('1 × Bere — 15,00 lei'));
    expect(text, contains('Total bon: 80,24 lei'));
    // ștergerea unui produs mută corect alegerile
    s.removeItem(0);
    expect(s.taken('Ion', 0), 1); // pizza a devenit primul produs
    expect(s.personTotal('Ion'), 32);
  });
}
