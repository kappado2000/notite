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

/// Extrage numărul (validat Luhn), data expirării și titularul din textul
/// recunoscut (OCR) de pe un card.
CardData parseCardText(String text) {
  final d = CardData();
  final upper = text.toUpperCase();

  // Numărul: 13–19 cifre, eventual în grupuri; OCR-ul confundă O/0, I/1.
  final groups = RegExp(r'(?:[0-9OIL]{4}[ \-]?){3}[0-9OIL]{1,7}');
  for (final m in groups.allMatches(upper)) {
    final digits = m[0]!
        .replaceAll(RegExp('[ -]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    if (digits.length >= 13 && digits.length <= 19 && luhnValid(digits)) {
      d.number = [
        for (var i = 0; i < digits.length; i += 4)
          digits.substring(i, i + 4 > digits.length ? digits.length : i + 4),
      ].join(' ');
      break;
    }
  }

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
    d.holder = candidates.last.replaceAll(RegExp(r'\s+'), ' ');
  }
  return d;
}
