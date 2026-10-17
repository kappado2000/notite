import 'dart:typed_data';

import 'scan_service_stub.dart'
    if (dart.library.io) 'scan_service_io.dart'
    as impl;

/// O pagină scanată: imaginea + textul recunoscut (OCR).
class ScannedPage {
  ScannedPage({required this.name, required this.bytes, required this.text});
  final String name;
  final Uint8List bytes;
  final String text;
}

/// Scanare documente cu detectare de margini + OCR (ML Kit).
/// Disponibil doar pe Android și iOS.
class ScanService {
  static bool get scanSupported => impl.scanSupported;

  /// Deschide scanerul; întoarce paginile scanate (listă goală la anulare).
  static Future<List<ScannedPage>> scan() => impl.scan();

  /// OCR pe o imagine existentă (ex. fotografie din galerie).
  static Future<String> recognize(Uint8List bytes) => impl.recognize(bytes);
}
