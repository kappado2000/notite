import 'ro_names.dart';
import 'secret_helpers.dart';

/// Datele citite de pe o carte de identitate românească.
class IdCardData {
  String lastName = '';
  String firstName = '';
  String cnp = '';
  String address = '';
  String series = '';
  String number = '';
  String issuedBy = '';
  DateTime? issueDate;
  DateTime? expiryDate;

  /// Câte câmpuri au fost găsite (pentru mesajul de confirmare).
  int get found =>
      [
        lastName,
        firstName,
        cnp,
        address,
        series,
        number,
        issuedBy,
      ].where((s) => s.isNotEmpty).length +
      (issueDate == null ? 0 : 1) +
      (expiryDate == null ? 0 : 1);
}

String _fold(String s) {
  const from = 'ăâîșşțţĂÂÎȘŞȚŢ';
  const to = 'aaissttAAISSTT';
  var r = s;
  for (var i = 0; i < from.length; i++) {
    r = r.replaceAll(from[i], to[i]);
  }
  return r.toLowerCase();
}

/// Rândurile-etichetă trilingve („Nume/Nom/Last name”).
final _labelRe = RegExp(
  r'(^nume|prenume|cetatenie|nationalit|^sex|loc na|lieu de|domiciliu|'
  r'adresse|emis|delivr|issued|valabil|validit|data na|date of|'
  r'data emiter|data expir|autoritate|semnatur|carte de|identity card|'
  r"carte d'id|^romania)",
);

bool _isLabel(String line) => _labelRe.hasMatch(_fold(line).trim());

bool _isMrz(String line) =>
    RegExp(r'^[A-Z0-9<]{25,}$').hasMatch(line.replaceAll(' ', ''));

/// Extrage datele din textul recunoscut (OCR) de pe fața buletinului.
/// Funcționează pe cartea veche (cu adresă) și pe cea electronică.
IdCardData parseRomanianId(String text) {
  final d = IdCardData();
  final lines = [
    for (final l in text.split(RegExp(r'[\r\n]+')))
      if (l.trim().isNotEmpty) l.trim().replaceAll('«', '<<'),
  ];

  /// Valorile de după eticheta care se potrivește cu [key].
  List<String> after(RegExp key, {int max = 1}) {
    for (var i = 0; i < lines.length; i++) {
      final f = _fold(lines[i]);
      if (!key.hasMatch(f)) continue;
      // Uneori valoarea e pe același rând, după ultima etichetă.
      final inline = lines[i].split(RegExp(r'\s{2,}|:\s*')).skip(1).join(' ');
      final out = <String>[if (inline.trim().isNotEmpty) inline.trim()];
      for (var j = i + 1; j < lines.length && out.length < max; j++) {
        if (_isLabel(lines[j]) || _isMrz(lines[j])) break;
        out.add(lines[j]);
      }
      if (out.isNotEmpty) return out;
    }
    return const [];
  }

  // ---- zona citibilă automat (MRZ), rezervă sigură pentru nume/serie.
  final mrz = [
    for (final l in lines)
      if (_isMrz(l)) l.replaceAll(' ', ''),
  ];
  for (final m in mrz) {
    if (m.startsWith('IDROU') || m.startsWith('I<ROU')) {
      final parts = m.substring(5).split('<<');
      if (parts.isNotEmpty) {
        d.lastName = parts.first.replaceAll('<', '-');
      }
      if (parts.length > 1) {
        d.firstName = parts[1].replaceAll('<', '-');
      }
    } else if (RegExp(r'^[A-Z]{2}\d{6}').hasMatch(m)) {
      d.series = m.substring(0, 2);
      d.number = m.substring(2, 8);
      // După serie: cifra de control, „ROU”, nașterea (6+1), sexul,
      // apoi expirarea (AAMMZZ).
      final rou = m.indexOf('ROU', 9);
      if (rou > 0 && m.length >= rou + 17) {
        final e = m.substring(rou + 11, rou + 17);
        if (RegExp(r'^\d{6}$').hasMatch(e)) {
          d.expiryDate = _yyMMdd(e, future: true);
        }
      }
    }
  }

  // ---- numele de pe fața cărții (au diacritice, deci au prioritate).
  final last = after(RegExp(r'^nume|last name'));
  if (last.isNotEmpty && _looksLikeName(last.first)) {
    d.lastName = _clean(last.first);
  }
  final first = after(RegExp(r'prenume|first name|given name'));
  if (first.isNotEmpty && _looksLikeName(first.first)) {
    d.firstName = _clean(first.first);
  }

  // ---- seria și numărul („SERIA RX NR 123456”).
  final sn = RegExp(r'SERIA\s*([A-Z]{2})\s*N[RO0]\.?\s*([0-9O]{6})')
      .firstMatch(text.toUpperCase());
  if (sn != null) {
    d.series = sn[1]!;
    d.number = sn[2]!.replaceAll('O', '0');
  }

  // ---- CNP: primul număr de 13 cifre valid.
  final cnpLabel = RegExp(r'CNP\s*[:.]?\s*([0-9O ]{13,16})');
  final candidates = [
    for (final m in cnpLabel.allMatches(text.toUpperCase()))
      m[1]!.replaceAll(' ', '').replaceAll('O', '0'),
    for (final m in RegExp(r'(?<!\d)\d{13}(?!\d)').allMatches(text)) m[0]!,
  ];
  for (final c in candidates) {
    if (c.length >= 13 && cnpValid(c.substring(0, 13))) {
      d.cnp = c.substring(0, 13);
      break;
    }
  }

  // ---- adresa (doar pe cartea veche).
  final addr = after(RegExp(r'domiciliu|adresse|address'), max: 3);
  if (addr.isNotEmpty) d.address = addr.map(_clean).join(', ');

  // ---- emitentul.
  final by = after(RegExp(r'emis|delivr|issued|autoritate'));
  if (by.isNotEmpty) {
    d.issuedBy = _clean(by.first);
  } else {
    final m = RegExp(
      r'\b(S\.?P\.?C\.?L\.?E\.?P\.?|S\.?P\.?C\.?E\.?P\.?|DEPABD|SEIP)\b.*',
    ).firstMatch(text);
    if (m != null) d.issuedBy = _clean(m[0]!);
  }

  // ---- valabilitatea: „12.03.15-01.01.2025” = eliberare – expirare.
  final range = RegExp(
    r'(\d{2})[.,](\d{2})[.,](\d{2,4})\s*[-–]\s*(\d{2})[.,](\d{2})[.,](\d{4})',
  ).firstMatch(text);
  if (range != null) {
    d.issueDate = _date(range[1]!, range[2]!, range[3]!);
    d.expiryDate = _date(range[4]!, range[5]!, range[6]!) ?? d.expiryDate;
  } else {
    // Cartea electronică: „Data emiterii” și „Data expirării” separate.
    DateTime? dateAfter(RegExp key) {
      for (final v in after(key, max: 2)) {
        final m = RegExp(r'(\d{2})[.,/ ](\d{2})[.,/ ](\d{4})').firstMatch(v);
        if (m != null) return _date(m[1]!, m[2]!, m[3]!);
      }
      return null;
    }

    d.issueDate = dateAfter(RegExp(r'data emiter|date of issue'));
    d.expiryDate =
        dateAfter(RegExp(r'data expir|date of expiry')) ?? d.expiryDate;
  }
  d
    ..lastName = fixNameOcr(d.lastName)
    ..firstName = fixNameOcr(d.firstName);
  return d;
}

bool _looksLikeName(String s) =>
    RegExp(r"^[A-Za-zĂÂÎȘŞȚŢăâîșşțţ\- ']{2,}$").hasMatch(s.trim());

String _clean(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'^[,.;:\s]+'), '');

DateTime? _date(String dd, String mm, String yy) {
  final day = int.parse(dd), month = int.parse(mm);
  var year = int.parse(yy);
  if (yy.length == 2) year += 2000;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final r = DateTime(year, month, day);
  return r.month == month ? r : null;
}

DateTime? _yyMMdd(String s, {bool future = false}) {
  final yy = int.parse(s.substring(0, 2));
  return _date(
    s.substring(4, 6),
    s.substring(2, 4),
    '${future ? 2000 + yy : (yy > DateTime.now().year % 100 ? 1900 + yy : 2000 + yy)}',
  );
}
