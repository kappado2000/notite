import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Cum arată paginile scanate în PDF / în notiță.
enum ScanFilter {
  /// Fundal alb uniform, fără umbre; culorile (ștampile, pix albastru)
  /// rămân. Ca o copie color de la scaner.
  document('Document'),

  /// Alb-negru curat, ca o fotocopie.
  blackWhite('Alb-negru'),

  /// Imaginea exact cum a ieșit din cameră.
  original('Original');

  const ScanFilter(this.label);
  final String label;
}

/// Latura lungă a paginii finale: ~200 dpi pe A4, ca la un scaner.
const kScanMaxSide = 2200;

/// Aplică filtrul de scaner și întoarce un JPEG. Rulează pe un fir separat.
Future<Uint8List> enhanceScan(
  Uint8List bytes,
  ScanFilter filter, {
  int maxSide = kScanMaxSide,
}) => compute(_enhanceEntry, (bytes, filter.index, maxSide));

Uint8List _enhanceEntry((Uint8List, int, int) args) {
  final (bytes, filterIndex, maxSide) = args;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  var image = img.bakeOrientation(decoded);
  final longSide = math.max(image.width, image.height);
  if (longSide > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: maxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: maxSide,
            interpolation: img.Interpolation.average,
          );
  }
  final filter = ScanFilter.values[filterIndex];
  if (filter != ScanFilter.original) {
    final rgb = image.getBytes(order: img.ChannelOrder.rgb);
    final out = scanFilterRgb(rgb, image.width, image.height, filter);
    image = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: out.buffer,
      numChannels: 3,
    );
  }
  return img.encodeJpg(image, quality: 88);
}

/// Filtrul propriu-zis, pe pixeli RGB (3 octeți / pixel).
///
/// 1. Luminozitatea fiecărui pixel.
/// 2. „Hârtia goală”: pe o imagine micșorată de 4 ori păstrăm doar zonele
///    cele mai luminoase dintr-o vecinătate (filtru de maxim) — textul
///    dispare, rămân hârtia și umbrele ei — apoi netezim.
/// 3. Împărțim fiecare pixel la hârtie: umbrele și iluminarea neuniformă
///    (tipice pozelor făcute din unghi) dispar, fundalul devine alb.
/// 4. Contrast: textul devine închis și clar.
@visibleForTesting
Uint8List scanFilterRgb(Uint8List rgb, int w, int h, ScanFilter filter) {
  final n = w * h;
  final lum = Uint8List(n);
  for (var i = 0, p = 0; i < n; i++, p += 3) {
    lum[i] = (rgb[p] * 77 + rgb[p + 1] * 150 + rgb[p + 2] * 29) >> 8;
  }

  // ---- fundalul (hârtia), pe o grilă de 4×4 pixeli
  const f = 4;
  final sw = (w + f - 1) ~/ f, sh = (h + f - 1) ~/ f;
  var small = Uint8List(sw * sh);
  for (var y = 0; y < h; y++) {
    final row = (y ~/ f) * sw;
    for (var x = 0; x < w; x++) {
      final j = row + x ~/ f;
      final v = lum[y * w + x];
      if (v > small[j]) small[j] = v;
    }
  }
  final radius = math.max(3, math.max(sw, sh) ~/ 60);
  small = _maxFilter(small, sw, sh, radius);
  small = _boxBlur(small, sw, sh, radius);
  small = _boxBlur(small, sw, sh, radius);

  final out = Uint8List(n * 3);
  for (var y = 0; y < h; y++) {
    // interpolare biliniară a fundalului
    final gy = ((y + 0.5) / f - 0.5).clamp(0, sh - 1.0);
    final y0 = gy.floor(), y1 = math.min(y0 + 1, sh - 1);
    final fy = gy - y0;
    for (var x = 0; x < w; x++) {
      final gx = ((x + 0.5) / f - 0.5).clamp(0, sw - 1.0);
      final x0 = gx.floor(), x1 = math.min(x0 + 1, sw - 1);
      final fx = gx - x0;
      final top = small[y0 * sw + x0] * (1 - fx) + small[y0 * sw + x1] * fx;
      final bottom = small[y1 * sw + x0] * (1 - fx) + small[y1 * sw + x1] * fx;
      final bg = math.max(top * (1 - fy) + bottom * fy, 24.0);

      final i = y * w + x, p = i * 3;
      if (filter == ScanFilter.blackWhite) {
        final norm = lum[i] * 255 / bg;
        var t = ((norm - 100) / (215 - 100)).clamp(0.0, 1.0);
        t = t * t * (3 - 2 * t); // tranziție lină, fără margini zimțate
        final v = (t * 255).round();
        out[p] = v;
        out[p + 1] = v;
        out[p + 2] = v;
      } else {
        for (var c = 0; c < 3; c++) {
          final norm = rgb[p + c] * 255 / bg;
          // ce e aproape de alb devine alb; textul se închide
          out[p + c] = ((norm - 30) * 255 / (222 - 30)).round().clamp(0, 255);
        }
      }
    }
  }
  return out;
}

/// Maxim pe o fereastră (2r+1)×(2r+1), separabil (rânduri, apoi coloane).
Uint8List _maxFilter(Uint8List src, int w, int h, int r) {
  final tmp = Uint8List(w * h), dst = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var m = 0;
      final a = math.max(0, x - r), b = math.min(w - 1, x + r);
      for (var k = a; k <= b; k++) {
        final v = src[y * w + k];
        if (v > m) m = v;
      }
      tmp[y * w + x] = m;
    }
  }
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      var m = 0;
      final a = math.max(0, y - r), b = math.min(h - 1, y + r);
      for (var k = a; k <= b; k++) {
        final v = tmp[k * w + x];
        if (v > m) m = v;
      }
      dst[y * w + x] = m;
    }
  }
  return dst;
}

/// Medie pe o fereastră (2r+1)×(2r+1), cu sume glisante.
Uint8List _boxBlur(Uint8List src, int w, int h, int r) {
  final tmp = Uint8List(w * h), dst = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var sum = 0, cnt = 0;
      for (var k = math.max(0, x - r); k <= math.min(w - 1, x + r); k++) {
        sum += src[y * w + k];
        cnt++;
      }
      tmp[y * w + x] = sum ~/ cnt;
    }
  }
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      var sum = 0, cnt = 0;
      for (var k = math.max(0, y - r); k <= math.min(h - 1, y + r); k++) {
        sum += tmp[k * w + x];
        cnt++;
      }
      dst[y * w + x] = sum ~/ cnt;
    }
  }
  return dst;
}
