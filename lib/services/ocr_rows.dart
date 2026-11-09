/// Un rând de text recunoscut, cu poziția lui pe imagine (pixeli).
class OcrLine {
  const OcrLine(this.text, this.left, this.top, this.right, this.bottom);
  final String text;
  final double left, top, right, bottom;

  double get height => bottom - top;
  double get centerY => (top + bottom) / 2;
}

/// Reface rândurile unui document tipărit (bon, factură) din liniile OCR.
/// Cititorul de pe telefon întoarce adesea coloana de prețuri ca bloc
/// separat de denumiri; aici liniile aflate la aceeași înălțime sunt
/// lipite înapoi, de la stânga la dreapta, ca pe hârtie.
List<String> rowsFromLines(List<OcrLine> lines) {
  if (lines.isEmpty) return const [];
  final sorted = [...lines]..sort((a, b) => a.centerY.compareTo(b.centerY));
  final rows = <List<OcrLine>>[];
  for (final l in sorted) {
    final row = rows.isEmpty ? null : rows.last;
    if (row != null && _sameRow(row, l)) {
      row.add(l);
    } else {
      rows.add([l]);
    }
  }
  return [
    for (final r in rows)
      (r..sort((a, b) => a.left.compareTo(b.left)))
          .map((l) => l.text.trim())
          .where((t) => t.isNotEmpty)
          .join('  '),
  ];
}

/// Pe același rând dacă centrul vertical e în banda rândului (cu toleranță
/// pentru poze ușor înclinate).
bool _sameRow(List<OcrLine> row, OcrLine l) {
  final top = row.map((e) => e.top).reduce((a, b) => a < b ? a : b);
  final bottom = row.map((e) => e.bottom).reduce((a, b) => a > b ? a : b);
  final h = row.map((e) => e.height).reduce((a, b) => a + b) / row.length;
  final center = (top + bottom) / 2;
  return (l.centerY - center).abs() < h * 0.55;
}
