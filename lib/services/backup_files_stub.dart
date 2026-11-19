import 'dart:typed_data';

/// Pe web nu există backup automat (browserul nu poate scrie fișiere
/// singur); rămâne „Salvează backup acum”.
bool get supported => false;

Future<String?> write(
  String name,
  Uint8List bytes, {
  required int keep,
}) async => null;

Future<String?> location() async => null;
