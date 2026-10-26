import 'ro_names.dart';
import 'password_tools.dart';

/// Datele citite de pe fața unui card bancar.
class CardData {
  String number = '';
  String expiry = '';
  String holder = '';

  int get found => [number, expiry, holder].where((s) => s.isNotEmpty).length;
}

/// Cuvinte care apar pe carduri, dar nu sunt numele titularului.
const _notName = {
  'VISA',
  'MASTERCARD',
  'MAESTRO',
  'DEBIT',
  'CREDIT',
  'BANK',
  'BANCA',
  'VALID',
  'THRU',
  'FROM',
  'MONTH',
  'YEAR',
  'GOOD',
  'EXPIRES',
  'END',
  'ELECTRONIC',
  'BUSINESS',
  'PLATINUM',
  'GOLD',
  'CLASSIC',
  'STANDARD',
  'WORLD',
  'ELITE',
  'PREMIUM',
  'INFINITE',
  'SIGNATURE',
  'CONTACTLESS',
  'TRANSILVANIA',
  'BCR',
  'BRD',
  'ING',
  'RAIFFEISEN',
  'REVOLUT',
  'CEC',
  'UNICREDIT',
  'GARANTI',
  'BBVA',
  'OTP',
  'LIBRA',
  'ALPHA',
  'EXIM',
  'INTESA',
  'FIRST',
  'PATRIA',
  'SALT',
  'STAR',
  'CARD',
  'CARTE',
  'GROUPE',
  'SOCIETE',
  'GENERALE',
  'GEORGE',
  'NEO',
  'PAY',
  'APPLE',
  'GOOGLE',
};

/// Litere citite în locul cifrelor de fontul în relief.
const _digitLike = {
  'O': '0', 'D': '0', 'Q': '0', 'U': '0', //
  'I': '1', 'L': '1', '|': '1', 'T': '1', //
  'Z': '2', 'S': '5', 'G': '6', 'B': '8',
};

/// Un grup „de cifre” citit (ex. „4I11”, „S55O”): măcar jumătate cifre.
String? _digitGroup(String token) {
  if (token.length < 2 || token.length > 19) return null;
  final digits = RegExp(r'\d').allMatches(token).length;
  if (digits * 2 < token.length) return null;
  final out = StringBuffer();
  for (final ch in token.split('')) {
    if (RegExp(r'\d').hasMatch(ch)) {
      out.write(ch);
    } else if (_digitLike[ch] case final d?) {
      out.write(d);
    } else {
      return null;
    }
  }
  return out.toString();
}

/// Numărul cardului: grupurile de cifre pot veni pe rânduri sau blocuri
/// separate (așa le întoarce OCR-ul de pe telefon), deci le lipim în ordine
/// și păstrăm prima combinație de 13–19 cifre care trece de Luhn.
String _findCardNumber(String upper) {
  final groups = [
    for (final t in upper.split(RegExp(r'[\s\-–.,]+'))) ?_digitGroup(t),
  ];
  for (var i = 0; i < groups.length; i++) {
    // Un număr începe cu 2–6 (Mastercard, Visa, Amex, Maestro…).
    if (!RegExp('^[2-6]').hasMatch(groups[i])) continue;
    var joined = '';
    for (var j = i; j < groups.length && j < i + 5; j++) {
      joined += groups[j];
      if (joined.length > 19) break;
      // Grupurile de la mijloc au 4–6 cifre; doar ultimul poate fi scurt.
      final lastShort = groups[j].length < 4;
      if (joined.length >= 13 && luhnValid(joined)) {
        return [
          for (var k = 0; k < joined.length; k += 4)
            joined.substring(k, k + 4 > joined.length ? joined.length : k + 4),
        ].join(' ');
      }
      if (lastShort) break;
    }
  }
  return '';
}

/// Extrage numărul (validat Luhn), data expirării și titularul din textul
/// recunoscut (OCR) de pe un card.
CardData parseCardText(String text) {
  final d = CardData();
  final upper = text.toUpperCase();

  d.number = _findCardNumber(upper);

  // Expirarea: cea mai târzie dată LL/AA (unele carduri au și „valid from”).
  DateTime? latest;
  for (final m in RegExp(
    r'(?<!\d)(0[1-9]|1[0-2])\s*[/\\-]\s*(\d{4}|\d{2})(?!\d)',
  ).allMatches(upper)) {
    var y = int.parse(m[2]!);
    if (y < 100) y += 2000;
    if (y < 2000 || y > 2100) continue;
    final date = DateTime(y, int.parse(m[1]!));
    if (latest == null || date.isAfter(latest)) {
      latest = date;
      d.expiry = '${m[1]}/${(y % 100).toString().padLeft(2, '0')}';
    }
  }

  // Titularul: rând doar cu litere mari, 2–4 cuvinte, fără cuvinte de card.
  final candidates =
      [
        for (final line in upper.split(RegExp(r'[\r\n]+')))
          if (RegExp(r"^[A-ZĂÂÎȘŞȚŢ][A-ZĂÂÎȘŞȚŢ.\-' ]{3,}$")
              .hasMatch(line.trim()))
            line.trim(),
      ].where((l) {
        final words = l.split(RegExp(r'\s+'));
        return words.length >= 2 &&
            words.length <= 4 &&
            !words.any((w) => _notName.contains(w.replaceAll('.', '')));
      }).toList();
  // Numele e de obicei sub număr, deci ultimul candidat.
  if (candidates.isNotEmpty) {
    d.holder = fixNameOcr(candidates.last.replaceAll(RegExp(r'\s+'), ' '));
  }
  return d;
}
