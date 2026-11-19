import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('notite/backup');

bool get supported => Platform.isIOS || Platform.isAndroid;

/// iPhone: folderul „Notițe” din iCloud Drive (dacă iCloud e activ și
/// aplicația are dreptul), altfel folderul local al aplicației.
Future<(Directory, bool)> _dir() async {
  if (Platform.isIOS) {
    try {
      final path = await _channel.invokeMethod<String>('cloudDir');
      if (path != null && path.isNotEmpty) {
        final d = Directory(path);
        await d.create(recursive: true);
        return (d, true);
      }
    } catch (e) {
      debugPrint('backup iCloud: $e');
    }
  }
  final base = await getApplicationSupportDirectory();
  final d = Directory('${base.path}/Backup');
  await d.create(recursive: true);
  return (d, false);
}

Future<String?> write(String name, Uint8List bytes, {required int keep}) async {
  final (dir, cloud) = await _dir();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  // păstrăm doar ultimele [keep] (numele încep cu data, deci se sortează)
  final old =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.notite'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
  for (final f in old.skip(keep)) {
    try {
      await f.delete();
    } catch (_) {}
  }
  return cloud ? 'iCloud Drive → Notițe' : 'pe telefon (doar în aplicație)';
}

Future<String?> location() async {
  final (_, cloud) = await _dir();
  return cloud ? 'iCloud Drive → Notițe' : 'pe telefon (doar în aplicație)';
}
