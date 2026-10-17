import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

Future<void> open(String name, String mime, Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File('${dir.path}${Platform.pathSeparator}$safe');
  await file.writeAsBytes(bytes, flush: true);
  await OpenFilex.open(file.path, type: mime);
}
