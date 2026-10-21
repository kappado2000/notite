import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notite/services/pdf_builder.dart';

void main() {
  // Un PNG de 1×1 pixeli (o „pagină scanată” minimă).
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  test('PDF valid, câte o pagină pentru fiecare imagine', () async {
    final bytes = await buildPdfFromImages([png, png], title: 'Test');
    final text = latin1.decode(bytes);
    expect(text.startsWith('%PDF-'), isTrue);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 2);
  });
}
