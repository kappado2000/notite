import 'dart:io';
import 'dart:math';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'ocr_rows.dart';
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

/// Rândurile OCR cu poziția lor (pentru bonuri: prețurile aliniate la
/// dreapta vin altfel separat de denumiri).
Future<List<OcrLine>> recognizeLines(Uint8List bytes) async {
  if (!scanSupported) return const [];
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  await file.writeAsBytes(await compute(uprightForOcr, bytes));
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(
      InputImage.fromFilePath(file.path),
    );
    return [
      for (final block in result.blocks)
        for (final line in block.lines)
          OcrLine(
            line.text,
            line.boundingBox.left,
            line.boundingBox.top,
            line.boundingBox.right,
            line.boundingBox.bottom,
            slope: _slope(line.cornerPoints),
          ),
    ];
  } catch (e) {
    debugPrint('OCR: $e');
    return const [];
  } finally {
    await recognizer.close();
    if (await file.exists()) await file.delete();
  }
}

/// Înclinarea rândului (dy/dx pe marginea de sus), din colțurile lui.
double _slope(List<Point<int>> c) {
  if (c.length < 2) return 0;
  final dx = c[1].x - c[0].x;
  return dx <= 0 ? 0 : (c[1].y - c[0].y) / dx;
}

/// Poza „în picioare” pentru OCR. Camera iPhone salvează poza culcată, cu
/// o etichetă „rotește-o” (EXIF); cititorul vede atunci rândurile pe
/// verticală și denumirile nu se mai leagă de prețuri. Aici rotația e
/// aplicată efectiv, iar pozele foarte mari sunt micșorate (mai rapid,
/// fără pierderi la citire).
Uint8List uprightForOcr(Uint8List bytes) {
  const maxSide = 2600;
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final rotated =
        decoded.exif.imageIfd.hasOrientation &&
        (decoded.exif.imageIfd.orientation ?? 1) != 1;
    final big = max(decoded.width, decoded.height) > maxSide;
    if (!rotated && !big) return bytes;
    var im = img.bakeOrientation(decoded);
    if (big) {
      im = im.width >= im.height
          ? img.copyResize(im, width: maxSide)
          : img.copyResize(im, height: maxSide);
    }
    return img.encodeJpg(im, quality: 92);
  } catch (_) {
    return bytes;
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
