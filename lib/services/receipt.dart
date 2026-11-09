import 'dart:math';

/// Un produs de pe bon: „BERE URSUS  2 x 15,00 = 30,00”.
class ReceiptItem {
  ReceiptItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
    double? total,
  }) : total = total ?? round2(qty * unitPrice);

  String name;
  double qty;
  double unitPrice;
  double total;

  /// Bucăți care se pot împărți între persoane. Produsele cântărite
  /// (0,456 kg) sau cu cantități mari se împart ca un singur întreg.
  int get units =>
      (qty == qty.roundToDouble() && qty >= 1 && qty <= 99) ? qty.round() : 1;

  /// Prețul unei bucăți (pentru o bucată aleasă de o persoană).
  double get unitShare => units == 0 ? 0 : total / units;

  Map<String, dynamic> toJson() => {
    'name': name,
    'qty': qty,
    'unitPrice': unitPrice,
    'total': total,
  };

  factory ReceiptItem.fromJson(Map<String, dynamic> m) => ReceiptItem(
    name: m['name'] as String,
    qty: (m['qty'] as num).toDouble(),
    unitPrice: (m['unitPrice'] as num).toDouble(),
    total: (m['total'] as num).toDouble(),
  );
}

class Receipt {
  Receipt({
    this.merchant = '',
    this.date,
    List<ReceiptItem>? items,
    this.printedTotal,
  }) : items = items ?? [];

  String merchant;
  DateTime? date;
  final List<ReceiptItem> items;

  /// TOTAL-ul tipărit pe bon (pentru verificare), dacă a fost găsit.
  double? printedTotal;

  double get itemsTotal => round2(items.fold(0.0, (s, i) => s + i.total));

  /// Diferența față de totalul tipărit (0 = toate produsele găsite).
  double? get missing =>
      printedTotal == null ? null : round2(printedTotal! - itemsTotal);
}

double round2(double v) => (v * 100).roundToDouble() / 100;

/// „30,00” / „1.234,50” / „30.00” → 30.0
double? parseAmount(String s) {
  var t = s.trim().replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return null;
  // separatorul zecimal = ultimul „,” sau „.” urmat de exact 2 cifre
  final m = RegExp(r'^(-?[\d.,]*?)[.,](\d{2})$').firstMatch(t);
  if (m != null) {
    final whole = m[1]!.replaceAll(RegExp('[.,]'), '');
    return double.tryParse('${whole.isEmpty ? '0' : whole}.${m[2]}');
  }
  return double.tryParse(t.replaceAll(',', '.'));
}

String formatLei(double v) {
  final neg = v < 0;
  final cents = (v.abs() * 100).round();
  final lei = cents ~/ 100;
  final rest = (cents % 100).toString().padLeft(2, '0');
  final s = lei.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return '${neg ? '-' : ''}$s,$rest';
}

// ------------------------------------------------------------- citire bon

final _amountAtEnd = RegExp(
  r'(-?\d{1,3}(?:[.,\s]\d{3})*[.,]\d{2}|-?\d+[.,]\d{2})\s*(?:[A-G]|LEI|RON)?\s*$',
  caseSensitive: false,
);

/// „2.000 BUC x 15.00”, „2 x 15,00”, „1,000 X 4.5”, „0.456 KG x 12.99”.
final _qtyTimesPrice = RegExp(
  r'(\d+(?:[.,]\d{1,3})?)\s*(?:BUC\.?|BUC|KG|L|BC|PCS|ST)?\s*[xX×\*]\s*'
  // fără literă lipită după preț: „6x0.5L” e ambalaj, nu 6 × 0,5 lei
  r'(\d+(?:[.,]\d{1,2})?)(?![\d.,]*[A-Za-z%])',
  caseSensitive: false,
);

/// Rânduri care nu sunt produse (antet, taxe, plată).
final _notItem = RegExp(
  r'^\s*(sub\s*total|total|tva|t\.v\.a|cif|c\.i\.f|cod fiscal|nr\.?\s*(inm|reg|bon)|'
  r'bon fiscal|card|numerar|cash|rest|plata|achitat|casier|operator|data|ora|'
  r'z:|id unic|fiscal|vat|tip plata|cota|baza|bon nr|nota nr|masa|ospatar|'
  r'chelner|va multumim|multumim|reg\.? com|j\d|tel|adresa|str\.|jud\.|'
  r'mun\.|loc\.|www\.|e-?mail|valoare tva)',
  caseSensitive: false,
);

final _totalRow = RegExp(r'^\s*total\b', caseSensitive: false);

/// „x 4.000” / „x4” / „× 2 BUC” (cantitatea după „x”, fără preț).
final _xQty = RegExp(
  r'^[xX×\*]\s*(\d+(?:[.,]\d{1,3})?)\s*(?:BUC\.?|KG|L)?$',
  caseSensitive: false,
);

/// Cantitate: „4.000” / „4,000” = 4 (casele fiscale scriu 3 zecimale);
/// „0.456” = 0,456 kg. Întoarce null pentru 0 sau valori absurde.
double? _qty(String s) {
  final v = double.tryParse(s.replaceAll(',', '.'));
  if (v == null || v <= 0 || v > 999) return null;
  return v;
}

bool _hasLetters(String s) => RegExp(r'[A-Za-zĂÂÎȘŞȚŢăâîșşțţ]{2,}').hasMatch(s);

/// Denumirea dintr-un rând: textul fără cantitate, preț și litera TVA.
String _cleanName(String row) {
  var s = row.replaceAll(_qtyTimesPrice, ' ');
  s = s.replaceAll(_amountAtEnd, ' ');
  s = s.replaceAll(RegExp(r'\s*=\s*'), ' ');
  s = s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  return s.replaceAll(RegExp(r'^[\-\*\.\s]+|[\-\*\.=\s]+$'), '');
}

/// Citește un bon (fiscal sau notă de plată de restaurant) din rândurile
/// recunoscute. Formatele acceptate:
///  - „2.000 BUC x 15.00” urmat de „BERE URSUS   30.00 B” (case fiscale);
///  - „BERE URSUS” urmat de „2 x 15,00   30,00”;
///  - „Bere Ursus   2 x 15,00   30,00” sau „Bere Ursus  2  15,00  30,00”;
///  - „PAINE   4,50 A” (cantitate 1).
/// Se oprește la TOTAL. Totul se poate corecta apoi manual.
Receipt parseReceipt(List<String> rows) {
  final r = Receipt();
  final lines = [
    for (final l in rows)
      if (l.trim().isNotEmpty) l.trim(),
  ];

  // Comerciantul: primul rând cu litere, înainte de produse.
  for (final l in lines.take(6)) {
    if (_hasLetters(l) && !_amountAtEnd.hasMatch(l)) {
      r.merchant = l.replaceAll(RegExp(r'\s{2,}'), ' ');
      break;
    }
  }
  // Data bonului.
  for (final l in lines) {
    final m = RegExp(r'(\d{2})[./-](\d{2})[./-](\d{4}|\d{2})\b').firstMatch(l);
    if (m != null) {
      var y = int.parse(m[3]!);
      if (y < 100) y += 2000;
      final mo = int.parse(m[2]!), d = int.parse(m[1]!);
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
        r.date = DateTime(y, mo, d);
        break;
      }
    }
  }

  String? pendingName; // „BERE URSUS” fără preț, înaintea cantității
  for (var i = 0; i < lines.length; i++) {
    final row = lines[i];
    if (_totalRow.hasMatch(row) &&
        !RegExp(r'^\s*total\s*tva', caseSensitive: false).hasMatch(row)) {
      final a = _amountAtEnd.firstMatch(row);
      if (a != null) r.printedTotal = parseAmount(a[1]!);
      break;
    }
    if (_notItem.hasMatch(row)) {
      pendingName = null;
      continue;
    }

    final qtyMatch = _qtyTimesPrice.firstMatch(row);
    final amountMatch = _amountAtEnd.firstMatch(row);

    if (qtyMatch != null) {
      final qty =
          parseAmount(qtyMatch[1]!.replaceAll(',', '.')) ??
          double.tryParse(qtyMatch[1]!.replaceAll(',', '.'));
      final unit =
          parseAmount(qtyMatch[2]!) ??
          double.tryParse(qtyMatch[2]!.replaceAll(',', '.'));
      if (qty == null || unit == null || qty <= 0) continue;
      final expected = round2(qty * unit);
      var name = _cleanName(row);
      double? total;
      // totalul pe același rând, după „x preț”
      if (amountMatch != null && amountMatch.start >= qtyMatch.end - 1) {
        final t = parseAmount(amountMatch[1]!);
        if (t != null && (t - expected).abs() <= max(0.05, expected * 0.02)) {
          total = t;
        }
      }
      if (name.isEmpty || !_hasLetters(name)) {
        // Casa fiscală: cantitatea pe un rând, denumirea + totalul pe
        // următorul; altfel denumirea a fost pe rândul anterior.
        final next = i + 1 < lines.length ? lines[i + 1] : null;
        final nextAmount = next == null ? null : _amountAtEnd.firstMatch(next);
        final nextTotal = nextAmount == null
            ? null
            : parseAmount(nextAmount[1]!);
        if (next != null &&
            _hasLetters(next) &&
            !_notItem.hasMatch(next) &&
            !_totalRow.hasMatch(next) &&
            _qtyTimesPrice.firstMatch(next) == null &&
            (nextTotal == null ||
                (nextTotal - expected).abs() <= max(0.05, expected * 0.02))) {
          name = _cleanName(next);
          total ??= nextTotal;
          i++;
        } else if (pendingName != null) {
          name = pendingName;
        }
      }
      pendingName = null;
      if (name.isEmpty) name = 'Produs';
      r.items.add(
        ReceiptItem(
          name: name,
          qty: qty,
          unitPrice: unit,
          total: total ?? expected,
        ),
      );
      continue;
    }

    // „x 4.000   48.00” pe rândul de sub denumire (fără preț unitar).
    if (amountMatch != null && !_hasLetters(row) && pendingName != null) {
      final m = _xQty.firstMatch(row.substring(0, amountMatch.start).trim());
      final total = parseAmount(amountMatch[1]!);
      final qty = m == null ? null : _qty(m[1]!);
      if (qty != null && total != null) {
        r.items.add(
          ReceiptItem(
            name: pendingName,
            qty: qty,
            unitPrice: round2(total / qty),
            total: total,
          ),
        );
        pendingName = null;
        continue;
      }
    }

    if (amountMatch != null && _hasLetters(row)) {
      final total = parseAmount(amountMatch[1]!);
      if (total == null) continue;
      final before = row.substring(0, amountMatch.start).trim();
      // „Peroni Draft x 4.000   48.00” sau „4 x Peroni Draft   48.00”:
      // cantitatea și valoarea totală, fără prețul unitar.
      final nameX = RegExp(
        // înainte de „x” nu e cifră: „Fanta 6x0.5L” rămâne denumire
        r'^(.*?[A-Za-zĂÂÎȘŞȚŢăâîșşțţ].*?[^\d\s.,])\s*[xX×\*]\s*(\d+(?:[.,]\d{1,3})?)\s*(?:BUC\.?|KG|L)?$',
        caseSensitive: false,
      ).firstMatch(before);
      final xName = RegExp(
        r'^(\d+(?:[.,]\d{1,3})?)\s*(?:BUC\.?|KG|L)?\s*[xX×\*]\s*(.*[A-Za-zĂÂÎȘŞȚŢăâîșşțţ].*)$',
        caseSensitive: false,
      ).firstMatch(before);
      final qtyFirst = xName != null;
      final qty = nameX != null
          ? _qty(nameX[2]!)
          : qtyFirst
          ? _qty(xName[1]!)
          : null;
      if (qty != null) {
        final name = _cleanName(qtyFirst ? xName[2]! : nameX![1]!);
        r.items.add(
          ReceiptItem(
            name: name.isEmpty ? 'Produs' : name,
            qty: qty,
            unitPrice: round2(total / qty),
            total: total,
          ),
        );
        pendingName = null;
        continue;
      }
      // „Bere Ursus  2  15,00  30,00”: cantitate și preț fără „x”
      final cols = RegExp(
        r'^(.*?[A-Za-zĂÂÎȘŞȚŢăâîșşțţ].*?)\s+(\d+(?:[.,]\d{1,3})?)\s+(\d+[.,]\d{2})$',
      ).firstMatch(before);
      if (cols != null) {
        final qty = double.tryParse(cols[2]!.replaceAll(',', '.'));
        final unit = parseAmount(cols[3]!);
        if (qty != null &&
            unit != null &&
            qty > 0 &&
            (round2(qty * unit) - total).abs() <= max(0.05, total * 0.02)) {
          r.items.add(
            ReceiptItem(
              name: _cleanName(cols[1]!),
              qty: qty,
              unitPrice: unit,
              total: total,
            ),
          );
          pendingName = null;
          continue;
        }
      }
      final name = _cleanName(row);
      if (name.isEmpty) continue;
      r.items.add(
        ReceiptItem(name: name, qty: 1, unitPrice: total, total: total),
      );
      pendingName = null;
      continue;
    }

    // Rând doar cu text: poate fi denumirea produsului de pe rândul următor.
    pendingName = _hasLetters(row) ? _cleanName(row) : null;
  }
  return r;
}

// --------------------------------------------------------- împărțire

/// Cine ce a consumat: pentru fiecare persoană, câte bucăți din fiecare
/// produs. O bucată nu poate fi aleasă de două persoane.
class ReceiptSplit {
  ReceiptSplit(this.receipt, {List<String>? persons})
    : persons = persons ?? ['Eu'];

  final Receipt receipt;
  final List<String> persons;

  /// persoană → (index produs → bucăți)
  final Map<String, Map<int, int>> _take = {};

  int taken(String person, int item) => _take[person]?[item] ?? 0;

  int assigned(int item) => _take.values.fold(0, (s, m) => s + (m[item] ?? 0));

  int remaining(int item) => receipt.items[item].units - assigned(item);

  /// Setează bucățile alese de [person] (limitat la ce a rămas liber).
  void set(String person, int item, int units) {
    final others = assigned(item) - taken(person, item);
    final maxUnits = receipt.items[item].units - others;
    final v = units.clamp(0, maxUnits);
    (_take[person] ??= {})[item] = v;
  }

  double personTotal(String person) => round2(
    (_take[person] ?? const {}).entries.fold(
      0.0,
      (s, e) => s + e.value * receipt.items[e.key].unitShare,
    ),
  );

  /// Valoarea produselor nealese de nimeni.
  double get unassignedTotal => round2(
    receipt.itemsTotal - persons.fold(0.0, (s, p) => s + personTotal(p)),
  );

  void addPerson(String name) {
    if (!persons.contains(name)) persons.add(name);
  }

  void removePerson(String name) {
    persons.remove(name);
    _take.remove(name);
  }

  /// La ștergerea unui produs, indicii de după el se mută cu o poziție.
  void removeItem(int item) {
    receipt.items.removeAt(item);
    for (final m in _take.values) {
      final shifted = <int, int>{
        for (final e in m.entries)
          if (e.key < item)
            e.key: e.value
          else if (e.key > item)
            e.key - 1: e.value,
      };
      m
        ..clear()
        ..addAll(shifted);
    }
  }

  /// După schimbarea cantității unui produs, alegerile peste noul total
  /// sunt reduse.
  void clampItem(int item) {
    for (final p in persons) {
      set(p, item, taken(p, item));
    }
  }

  /// Același bon, recitit (ex. după o poză de continuare): persoanele și
  /// alegerile rămân pentru produsele care nu s-au schimbat.
  ReceiptSplit withReceipt(Receipt r) {
    final s = ReceiptSplit(r, persons: [...persons]);
    for (var i = 0; i < r.items.length && i < receipt.items.length; i++) {
      final a = receipt.items[i], b = r.items[i];
      if (a.name != b.name || a.total != b.total) continue;
      for (final p in persons) {
        if (taken(p, i) > 0) s.set(p, i, taken(p, i));
      }
    }
    return s;
  }

  /// Rezumat text: ce a ales fiecare și cât are de plătit.
  String summary() {
    final b = StringBuffer();
    final title = [
      if (receipt.merchant.isNotEmpty) receipt.merchant,
      if (receipt.date != null)
        '${receipt.date!.day.toString().padLeft(2, '0')}.'
            '${receipt.date!.month.toString().padLeft(2, '0')}.'
            '${receipt.date!.year}',
    ].join(' · ');
    if (title.isNotEmpty) b.writeln(title);
    for (final p in persons) {
      final lines = [
        for (var i = 0; i < receipt.items.length; i++)
          if (taken(p, i) > 0)
            '  ${taken(p, i)} × ${receipt.items[i].name} — '
                '${formatLei(round2(taken(p, i) * receipt.items[i].unitShare))} lei',
      ];
      if (lines.isEmpty) continue;
      if (b.isNotEmpty) b.writeln();
      b.writeln('$p: ${formatLei(personTotal(p))} lei');
      lines.forEach(b.writeln);
    }
    final rest = unassignedTotal;
    if (rest.abs() >= 0.01) {
      b.writeln();
      b.writeln('Nealocat: ${formatLei(rest)} lei');
    }
    b.writeln();
    b.write('Total bon: ${formatLei(receipt.itemsTotal)} lei');
    return b.toString();
  }
}
