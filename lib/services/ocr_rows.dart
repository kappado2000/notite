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

/// Rezultatul lipirii mai multor poze ale aceluiași document.
class MergedRows {
  const MergedRows(this.rows, this.skipped);
  final List<String> rows;

  /// Rânduri sărite pentru că apăreau în ambele poze (suprapunere).
  final int skipped;
}

/// Lipește pozele unui bon lung, făcute pe bucăți de sus în jos. Partea
/// comună dintre două poze consecutive (sfârșitul uneia = începutul
/// următoarei) e păstrată o singură dată, ca produsele să nu se dubleze.
/// La marginea fiecărei poze poate fi un rând tăiat (citit greșit): e
/// ignorat, iar rândul apare întreg din cealaltă poză. Rândurile identice
/// din aceeași poză (2 produse la fel) rămân neatinse.
MergedRows mergeRowParts(List<List<String>> parts) {
  final out = <String>[];
  var skipped = 0;
  for (final part in parts) {
    final next = [
      for (final r in part)
        if (r.trim().isNotEmpty) r.trim(),
    ];
    final o = out.isEmpty ? null : _findOverlap(out, next);
    if (o == null) {
      out.addAll(next);
      continue;
    }
    // rândul tăiat de la sfârșitul pozei anterioare iese; din poza nouă
    // sărim rândul ei tăiat de sus și rândurile comune
    out.removeRange(out.length - o.dropPrev, out.length);
    out.addAll(next.skip(o.dropNext + o.length));
    skipped += o.dropNext + o.length;
  }
  return MergedRows(out, skipped);
}

class _Overlap {
  const _Overlap(this.length, this.dropPrev, this.dropNext);

  /// Câte rânduri comune.
  final int length;

  /// Rând tăiat ignorat: la sfârșitul pozei anterioare / începutul următoarei.
  final int dropPrev, dropNext;
}

/// Cea mai lungă potrivire între sfârșitul lui [prev] și începutul lui
/// [next], ignorând cel mult un rând tăiat la fiecare margine.
_Overlap? _findOverlap(List<String> prev, List<String> next) {
  const maxRows = 25;
  _Overlap? best;
  var bestScore = 0.0;
  for (var dropPrev = 0; dropPrev <= 1; dropPrev++) {
    for (var dropNext = 0; dropNext <= 1; dropNext++) {
      // cu rânduri tăiate ignorate cerem măcar 2 rânduri comune, ca să nu
      // lipim greșit două bucăți fără legătură
      final minK = dropPrev + dropNext == 0 ? 1 : 2;
      final maxK = [
        prev.length - dropPrev,
        next.length - dropNext,
        maxRows,
      ].reduce((a, b) => a < b ? a : b);
      for (var k = maxK; k >= minK; k--) {
        var same = 0;
        for (var j = 0; j < k; j++) {
          if (_similar(
            prev[prev.length - dropPrev - k + j],
            next[dropNext + j],
          )) {
            same++;
          }
        }
        // toate rândurile comune seamănă (la 4+ rânduri, unul poate fi
        // citit diferit)
        if (k >= 4 ? same < k - 1 : same < k) continue;
        // cea mai lungă potrivire; la egalitate, fără rânduri ignorate
        final score = k - 0.1 * (dropPrev + dropNext);
        if (score > bestScore) {
          bestScore = score;
          best = _Overlap(k, dropPrev, dropNext);
        }
        break;
      }
    }
  }
  return best;
}

String _norm(String s) => s
    .toUpperCase()
    .replaceAll(',', '.')
    .replaceAll(RegExp(r'[^A-Z0-9.ĂÂÎȘŞȚŢ]'), '');

bool _similar(String a, String b) {
  final x = _norm(a), y = _norm(b);
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  final longer = x.length > y.length ? x.length : y.length;
  return 1 - _distance(x, y) / longer >= 0.8;
}

/// Distanța Levenshtein.
int _distance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + cost,
      ].reduce((p, q) => p < q ? p : q);
    }
    prev = cur;
  }
  return prev[b.length];
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
