import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'scan_service.dart';

bool get scanSupported => Platform.isAndroid || Platform.isIOS;

Future<List<ScannedPage>> scan() async {
  if (!scanSupported) return const [];
  final paths = await CunningDocumentScanner.getPictures(
    scannerSource: ScannerSource.cameraAndGallery,
  );
  if (paths == null || paths.isEmpty) return const [];
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final pages = <ScannedPage>[];
  for (var i = 0; i < paths.length; i++) {
    final file = File(paths[i]);
    pages.add(
      ScannedPage(
        name: 'Scanare_${stamp}_${i + 1}.jpg',
        bytes: await file.readAsBytes(),
        text: await _recognizeFile(file.path),
      ),
    );
  }
  return pages;
}

Future<String> recognize(Uint8List bytes) async {
  if (!scanSupported) return '';
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  await file.writeAsBytes(bytes);
  try {
    return await _recognizeFile(file.path);
  } finally {
    if (await file.exists()) await file.delete();
  }
}

Future<String> _recognizeFile(String path) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(path));
    return result.text.trim();
  } catch (e) {
    debugPrint('OCR: $e');
    return '';
  } finally {
    await recognizer.close();
  }
}
