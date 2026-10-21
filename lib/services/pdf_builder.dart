import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Un PDF cu câte o pagină A4 pentru fiecare imagine scanată
/// (imaginea încape întreagă în pagină, cu margini mici).
Future<Uint8List> buildPdfFromImages(
  List<Uint8List> images, {
  String title = 'Scanare',
}) async {
  final doc = pw.Document(title: title, creator: 'Notițe');
  for (final bytes in images) {
    final image = pw.MemoryImage(bytes);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ),
    );
  }
  return doc.save();
}
