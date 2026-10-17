import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> open(String name, String mime, Uint8List bytes) =>
    SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: name, mimeType: mime)],
        fileNameOverrides: [name],
      ),
    );
