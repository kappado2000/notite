import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:notite/widgets/signature_pad.dart';

void main() {
  test('semnătura: PNG transparent, decupat la contur, cu cerneală', () async {
    final strokes = [
      [const Offset(40, 60), const Offset(80, 30), const Offset(120, 70)],
      [const Offset(130, 50), const Offset(200, 52)],
    ];
    final png = await signaturePng(strokes, const Size(300, 140));
    final image = img.decodePng(png)!;
    // conturul: (40..200)×(30..70) + margine 8, la scară 3
    expect(image.width, closeTo((200 - 40 + 16) * 3, 3));
    expect(image.height, closeTo((70 - 30 + 16) * 3, 3));
    // colțul e transparent, linia are culoare
    expect(image.getPixel(0, 0).a, 0);
    final inked = [
      for (var y = 0; y < image.height; y++)
        for (var x = 0; x < image.width; x++)
          if (image.getPixel(x, y).a > 200) 1,
    ];
    expect(inked.length, greaterThan(200));
  });
}
