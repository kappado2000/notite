import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/secret_item.dart';
import '../utils/format.dart';
import 'note_pdf.dart';

/// Codurile de rezervă 2FA ale tuturor conturilor: lista mereu la zi din
/// aplicație și exportul pe hârtie (PDF).
class RecoveryCodes {
  RecoveryCodes._();

  /// Conturile cu 2FA (cheie sau coduri de rezervă), alfabetic.
  static List<SecretItem> accounts(Iterable<SecretItem> all) =>
      [
        for (final i in all)
          if (i.type == SecretType.login &&
              (i.totp.trim().isNotEmpty || i.recoveryCodes.trim().isNotEmpty))
            i,
      ]..sort(
        (a, b) => a.displayTitle.toLowerCase().compareTo(
          b.displayTitle.toLowerCase(),
        ),
      );

  /// Codurile, câte unul pe rând (fără rândurile goale).
  static List<String> lines(String codes) => [
    for (final l in codes.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];

  /// Amprenta listei (ce conturi și ce coduri): diferită = s-a schimbat
  /// ceva de la ultimul export.
  static String fingerprint(Iterable<SecretItem> accounts) {
    final parts = [
      for (final i in accounts)
        '${i.id}|${i.displayTitle}|${i.recoveryCodes.trim()}',
    ]..sort();
    return sha256.convert(utf8.encode(parts.join('\n'))).toString();
  }

  static final _code = RegExp(
    r'^\s*(?:\d{1,2}[.)]\s*)?([A-Za-z0-9]{3,10}(?:[ -][A-Za-z0-9]{3,10}){0,2})\s*$',
  );
  static final _header = RegExp(
    r'cod|code|rezerv|recuper|backup|recovery',
    caseSensitive: false,
  );

  static bool _isCode(String l) {
    final m = _code.firstMatch(l);
    if (m == null) return false;
    final v = m[1]!;
    final digits = v.replaceAll(RegExp(r'[^0-9]'), '').length;
    final len = v.replaceAll(RegExp(r'[ -]'), '').length;
    return digits >= 3 && len >= 6 && len <= 20;
  }

  /// Codurile de rezervă scrise în notițele contului: cel mai lung șir de
  /// cel puțin 3 rânduri-cod consecutive (cu titlul de deasupra, dacă e
  /// „Coduri de rezervă…”). Null = nu am găsit.
  static ({String codes, String notes})? fromNotes(String notes) {
    final ls = notes.split('\n');
    var bestStart = -1, bestLen = 0;
    var i = 0;
    while (i < ls.length) {
      if (!_isCode(ls[i])) {
        i++;
        continue;
      }
      var j = i;
      while (j < ls.length && _isCode(ls[j])) {
        j++;
      }
      if (j - i > bestLen) {
        bestStart = i;
        bestLen = j - i;
      }
      i = j;
    }
    if (bestLen < 3) return null;
    var from = bestStart;
    if (from > 0 &&
        _header.hasMatch(ls[from - 1]) &&
        ls[from - 1].length < 80) {
      from--;
    }
    final codes = [
      for (final l in ls.sublist(bestStart, bestStart + bestLen)) l.trim(),
    ].join('\n');
    final rest = [
      ...ls.sublist(0, from),
      ...ls.sublist(bestStart + bestLen),
    ].join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return (codes: codes, notes: rest);
  }

  /// Același conținut ca foaia PDF, ca text simplu (.txt).
  static String text(List<SecretItem> accounts) {
    final b = StringBuffer()
      ..writeln('CODURI DE REZERVĂ 2FA')
      ..writeln('Din Notițe · ${formatDateTime(DateTime.now())}')
      ..writeln()
      ..writeln(
        'Păstrează fișierul într-un loc sigur (e necriptat). Fiecare cod '
        'merge o singură dată.',
      )
      ..writeln('=' * 60);
    final without = <SecretItem>[];
    for (final i in accounts) {
      final codes = lines(i.recoveryCodes);
      if (codes.isEmpty) {
        without.add(i);
        continue;
      }
      b
        ..writeln()
        ..writeln(i.displayTitle);
      final sub = [
        if (i.username.isNotEmpty) i.username,
        if (i.url.isNotEmpty) i.url,
      ].join(' · ');
      if (sub.isNotEmpty) b.writeln(sub);
      for (final c in codes) {
        b.writeln('  [ ] $c');
      }
    }
    if (without.isNotEmpty) {
      b
        ..writeln()
        ..writeln('=' * 60)
        ..writeln('Conturi cu 2FA fără coduri de rezervă salvate:');
      for (final i in without) {
        b.writeln(
          '  - ${i.displayTitle}${i.username.isEmpty ? '' : ' (${i.username})'}',
        );
      }
    }
    return b.toString();
  }

  /// Foaia de printat: fiecare cont cu codurile lui; la final conturile cu
  /// 2FA fără coduri salvate.
  static Future<Uint8List> pdf(List<SecretItem> accounts) async {
    final theme = await pdfTheme();
    final mono = pw.Font.courier();
    final monoBold = pw.Font.courierBold();
    final withCodes = [
      for (final i in accounts)
        if (i.recoveryCodes.trim().isNotEmpty) i,
    ];
    final without = [
      for (final i in accounts)
        if (i.recoveryCodes.trim().isEmpty) i,
    ];
    final doc = pw.Document(
      title: 'Coduri de rezervă 2FA',
      creator: 'Notițe',
      theme: theme,
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Pagina ${ctx.pageNumber} din ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (_) => [
          pw.Text(
            'Coduri de rezervă 2FA',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Din Notițe · ${formatDateTime(DateTime.now())} · '
            '${withCodes.length == 1 ? '1 cont' : '${withCodes.length} conturi'} '
            'cu coduri',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey500),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              'Păstrează foaia într-un loc sigur. Fiecare cod merge o singură '
              'dată, când nu ai acces la codul 2FA. Bifează codurile folosite. '
              'Dacă ai generat coduri noi pe un site, cele vechi nu mai merg: '
              'printează din nou foaia.',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
          pw.SizedBox(height: 14),
          for (final i in withCodes)
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    i.displayTitle,
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    [
                      if (i.username.isNotEmpty) i.username,
                      if (i.url.isNotEmpty) i.url,
                    ].join(' · '),
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Wrap(
                    spacing: 18,
                    runSpacing: 4,
                    children: [
                      for (final c in lines(i.recoveryCodes))
                        pw.Text(
                          '[ ]  $c',
                          style: pw.TextStyle(
                            font: c.contains(RegExp(r'[^\x00-\x7F]'))
                                ? null
                                : monoBold,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          if (without.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Conturi cu 2FA fără coduri de rezervă salvate',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            for (final i in without)
              pw.Text(
                '•  ${i.displayTitle}'
                '${i.username.isEmpty ? '' : ' (${i.username})'}',
                style: pw.TextStyle(font: null, fontSize: 10),
              ),
          ],
          if (withCodes.isEmpty && without.isEmpty)
            pw.Text('Niciun cont cu 2FA.', style: pw.TextStyle(font: mono)),
        ],
      ),
    );
    return doc.save();
  }
}
