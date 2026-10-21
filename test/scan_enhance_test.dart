import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:notite/services/scan_enhance.dart';

/// Foaie cu umbră (luminozitate 255 → 110 de la stânga la dreapta) și
/// rânduri de „text” la 30% din luminozitatea hârtiei din jur.
(Uint8List, int, int) _shadowedPage() {
  const w = 400, h = 300;
  final rgb = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final paper = 255 - 145 * x / (w - 1);
      final isText = (y % 30) < 6 && x % 40 < 30;
      final v = (isText ? paper * 0.3 : paper).round();
      final p = (y * w + x) * 3;
      rgb[p] = v;
      rgb[p + 1] = v;
      rgb[p + 2] = (v * 0.92).round(); // hârtie ușor gălbuie
    }
  }
  return (rgb, w, h);
}

int _lum(Uint8List out, int w, int x, int y) {
  final p = (y * w + x) * 3;
  return (out[p] * 77 + out[p + 1] * 150 + out[p + 2] * 29) >> 8;
}

void main() {
  for (final filter in [ScanFilter.document, ScanFilter.blackWhite]) {
    test('${filter.label}: umbra dispare, hârtia devine albă', () {
      final (rgb, w, h) = _shadowedPage();
      final out = scanFilterRgb(rgb, w, h, filter);
      // hârtie (rând fără text): stânga luminoasă și dreapta umbrită → albe
      expect(_lum(out, w, 50, 15), greaterThan(235));
      expect(_lum(out, w, 350, 15), greaterThan(235));
      // text: închis și în zona luminoasă, și în cea umbrită
      expect(_lum(out, w, 50, 62), lessThan(70));
      expect(_lum(out, w, 365, 62), lessThan(70));
    });
  }

  test('enhanceScan: JPEG micșorat la latura maximă', () async {
    final big = img.Image(width: 3000, height: 2000)
      ..clear(img.ColorRgb8(240, 238, 230));
    final jpg = await enhanceScan(
      Uint8List.fromList(img.encodeJpg(big)),
      ScanFilter.document,
    );
    final back = img.decodeJpg(jpg)!;
    expect(back.width, kScanMaxSide);
    expect(back.height, (2000 * kScanMaxSide / 3000).round());
  });
}
