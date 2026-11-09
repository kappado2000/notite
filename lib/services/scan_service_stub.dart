import 'dart:typed_data';

import 'ocr_rows.dart';
import 'scan_service.dart';

const bool scanSupported = false;

Future<List<ScannedPage>> scan() async => const [];

Future<String> recognize(Uint8List bytes) async => '';

Future<List<OcrLine>> recognizeLines(Uint8List bytes) async => const [];
