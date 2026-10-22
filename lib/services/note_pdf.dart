import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/notes_store.dart';
import '../models/note.dart';
import '../utils/format.dart';
import '../widgets/attachment_image_embed.dart';

/// Fonturile Noto Sans (cu diacritice românești) pentru PDF.
Future<pw.ThemeData> _pdfTheme() async {
  Future<pw.Font> font(String v) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-$v.ttf'));
  return pw.ThemeData.withFont(
    base: await font('Regular'),
    bold: await font('Bold'),
    italic: await font('Italic'),
    boldItalic: await font('BoldItalic'),
  );
}

/// Exportă una sau mai multe notițe într-un PDF (fiecare de la pagină nouă),
/// păstrând formatarea: titluri, aldin/cursiv/subliniat/tăiat, liste,
/// liste de bifat, citate și imaginile din text.
/// Notițele blocate apar doar cu titlul dacă [includeLocked] e fals.
Future<Uint8List> notesToPdf(
  List<Note> notes,
  NotesStore store, {
  required String title,
  bool includeLocked = true,
}) async {
  final doc = pw.Document(title: title, creator: 'Notițe');
  final theme = await _pdfTheme();
  for (final note in notes) {
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 56),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (_) => noteWidgets(note, store, includeLocked: includeLocked),
      ),
    );
  }
  return doc.save();
}

/// Conținutul unei notițe ca elemente PDF.
@visibleForTesting
List<pw.Widget> noteWidgets(
  Note note,
  NotesStore store, {
  bool includeLocked = true,
}) {
  final out = <pw.Widget>[
    pw.Text(
      note.displayTitle,
      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 4),
    pw.Text(
      [
        store.notebook(note.notebookId)?.name ?? '',
        'Modificată ${DateFormat('d MMMM y, HH:mm', 'ro').format(note.updatedAt)}',
        if (note.tags.isNotEmpty) note.tags.map((t) => '#$t').join(' '),
      ].where((s) => s.isNotEmpty).join('  ·  '),
      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
    ),
    pw.Divider(color: PdfColors.grey400, height: 20),
  ];
  if (note.locked && !includeLocked) {
    out.add(
      pw.Text(
        'Notiță blocată — conținutul nu a fost exportat.',
        style: pw.TextStyle(fontStyle: pw.FontStyle.italic),
      ),
    );
    return out;
  }

  List<dynamic> ops;
  try {
    ops = jsonDecode(note.contentJson) as List<dynamic>;
  } catch (_) {
    ops = [
      {'insert': '${note.plainText}\n'},
    ];
  }

  var spans = <pw.InlineSpan>[];
  var ordered = 0;
  for (final op in ops) {
    final insert = (op as Map)['insert'];
    final attrs = (op['attributes'] as Map?) ?? const {};
    if (insert is Map) {
      // imagine din text
      final id = insert[kAttachmentImageEmbed];
      final bytes = id is String ? store.bytesOf(id) : null;
      if (bytes != null) {
        if (spans.isNotEmpty) {
          out.add(_paragraph(spans, const {}, 0));
          spans = [];
        }
        out.add(
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: pw.Image(
              pw.MemoryImage(bytes),
              height: 320,
              fit: pw.BoxFit.contain,
            ),
          ),
        );
      }
      continue;
    }
    final text = insert as String;
    final parts = text.split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) spans.add(_span(parts[i], attrs));
      if (i < parts.length - 1) {
        // Sfârșit de rând: în formatul Quill, atributele rândului (titlu,
        // listă, citat) stau pe caracterul „\n” al acestei operații.
        ordered = attrs['list'] == 'ordered' ? ordered + 1 : 0;
        out.add(_paragraph(spans, attrs, ordered));
        spans = [];
      }
    }
  }
  if (spans.isNotEmpty) out.add(_paragraph(spans, const {}, 0));

  final files = store.attachmentsOf(note.id).where((a) => !a.isImage).toList();
  if (files.isNotEmpty) {
    out
      ..add(pw.SizedBox(height: 16))
      ..add(
        pw.Text(
          'Atașamente',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
      );
    for (final a in files) {
      out.add(pw.Bullet(text: '${a.name}  (${formatSize(a.size)})'));
    }
  }
  return out;
}

pw.TextSpan _span(String text, Map attrs) => pw.TextSpan(
  text: text,
  style: pw.TextStyle(
    fontWeight: attrs['bold'] == true ? pw.FontWeight.bold : null,
    fontStyle: attrs['italic'] == true ? pw.FontStyle.italic : null,
    decoration: pw.TextDecoration.combine([
      if (attrs['underline'] == true) pw.TextDecoration.underline,
      if (attrs['strike'] == true) pw.TextDecoration.lineThrough,
    ]),
    color: attrs['link'] != null ? PdfColors.blue700 : null,
  ),
);

pw.Widget _paragraph(List<pw.InlineSpan> spans, Map attrs, int ordered) {
  final header = attrs['header'];
  final size = switch (header) {
    1 => 20.0,
    2 => 16.0,
    3 => 13.5,
    _ => 11.5,
  };
  final style = pw.TextStyle(
    fontSize: size,
    lineSpacing: 2,
    fontWeight: header != null ? pw.FontWeight.bold : null,
  );
  final body = pw.RichText(
    text: pw.TextSpan(
      style: style,
      children: spans.isEmpty ? [const pw.TextSpan(text: ' ')] : spans,
    ),
  );
  final list = attrs['list'];
  pw.Widget line = switch (list) {
    'bullet' => _withMarker(pw.Text('•', style: style), body),
    'ordered' => _withMarker(pw.Text('$ordered.', style: style), body),
    'checked' || 'unchecked' => _withMarker(_checkbox(list == 'checked'), body),
    _ => body,
  };
  if (attrs['blockquote'] == true) {
    line = pw.Container(
      padding: const pw.EdgeInsets.only(left: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(color: PdfColors.grey500, width: 2),
        ),
      ),
      child: line,
    );
  }
  return pw.Padding(
    padding: pw.EdgeInsets.only(top: header != null ? 10 : 2, bottom: 2),
    child: line,
  );
}

pw.Widget _withMarker(pw.Widget marker, pw.Widget body) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    // Align: marcajul își păstrează mărimea (altfel pătrățelul de bifat
    // se întinde pe toată lățimea rezervată).
    pw.SizedBox(
      width: 18,
      child: pw.Align(alignment: pw.Alignment.topLeft, child: marker),
    ),
    pw.Expanded(child: body),
  ],
);

pw.Widget _checkbox(bool checked) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 2.5),
  child: pw.Container(
    width: 9,
    height: 9,
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey800, width: 1),
      color: checked ? PdfColors.grey800 : null,
    ),
  ),
);
