import 'dart:io';
import 'dart:typed_data';

/// Citește fișierul primit și îl șterge din folderul temporar.
Future<({String name, Uint8List bytes})?> readAndDelete(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final bytes = await file.readAsBytes();
  final name = path.split(Platform.pathSeparator).last;
  try {
    await file.parent.delete(recursive: true);
  } catch (_) {}
  return (name: name, bytes: bytes);
}
