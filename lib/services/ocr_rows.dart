/// Un rând de text recunoscut, cu poziția lui pe imagine (pixeli).
class OcrLine {
  const OcrLine(
    this.text,
    this.left,
    this.top,
    this.right,
    this.bottom, {
    this.slope = 0,
  });
  final String text;
  final double left, top, right, bottom;

  /// Înclinarea rândului (dy/dx), dacă cititorul o dă.
  final double slope;

  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
}

/// Reface rândurile unui document tipărit (bon, factură) din liniile OCR.
/// Cititorul de pe telefon întoarce adesea coloana de prețuri ca bloc
/// separat de denumiri; aici liniile aflate la aceeași înălțime sunt
/// lipite înapoi, de la stânga la dreapta, ca pe hârtie. Poza ținută
/// strâmb e îndreptată: înălțimea fiecărei linii e măsurată de-a lungul
/// înclinării bonului, ca prețul din dreapta să rămână lângă denumirea lui.
///
/// [skew]: înclinarea folosită (dy/dx); implicit cea raportată de cititor.
List<String> rowsFromLines(List<OcrLine> lines, {double? skew}) {
  if (lines.isEmpty) return const [];
  final k = skew ?? reportedSkew(lines);
  double y(OcrLine l) => l.centerY - k * l.centerX;
  final sorted = [...lines]..sort((a, b) => y(a).compareTo(y(b)));
  final rows = <List<OcrLine>>[];
  for (final l in sorted) {
    final row = rows.isEmpty ? null : rows.last;
    if (row != null) {
      final rowY = row.map(y).reduce((a, b) => a + b) / row.length;
      final h = row.map((e) => e.height).reduce((a, b) => a + b) / row.length;
      // două texte unul sub altul (aceeași coloană) nu pot fi pe același
      // rând, oricât de aproape ar părea
      final stacked = row.any((e) => _overlapX(e, l));
      if (!stacked &&
          (y(l) - rowY).abs() < (h < l.height ? h : l.height) * 0.6) {
        row.add(l);
        continue;
      }
    }
    rows.add([l]);
  }
  return [
    for (final r in rows)
      (r..sort((a, b) => a.left.compareTo(b.left)))
          .map((l) => l.text.trim())
          .where((t) => t.isNotEmpty)
          .join('  '),
  ];
}

/// Înclinarea bonului: mediana înclinărilor liniilor lungi (cele scurte,
/// de 1–2 caractere, au colțuri imprecise).
double reportedSkew(List<OcrLine> lines) {
  final s = [
    for (final l in lines)
      if (l.right - l.left > 2 * l.height && l.slope.abs() < 0.5) l.slope,
  ]..sort();
  if (s.isEmpty) return 0;
  return s[s.length ~/ 2];
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

/// Se suprapun pe orizontală mai mult de o treime din cel mai îngust.
bool _overlapX(OcrLine a, OcrLine b) {
  final o =
      (a.right < b.right ? a.right : b.right) -
      (a.left > b.left ? a.left : b.left);
  final w = (a.right - a.left) < (b.right - b.left)
      ? a.right - a.left
      : b.right - b.left;
  return w > 0 && o > w / 3;
}
