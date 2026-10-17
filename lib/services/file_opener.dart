import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import 'file_opener_stub.dart'
    if (dart.library.io) 'file_opener_io.dart'
    as impl;

class FileOpener {
  /// Deschide atașamentul cu aplicația implicită a sistemului.
  /// Pe web îl oferă spre descărcare.
  static Future<void> open(String name, String mime, Uint8List bytes) =>
      impl.open(name, mime, bytes);

  static Future<void> share(String name, String mime, Uint8List bytes) =>
      SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: name, mimeType: mime)],
          fileNameOverrides: [name],
        ),
      );
}
