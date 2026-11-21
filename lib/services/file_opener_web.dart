import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Pe web: descărcare directă (în Descărcări), fără fereastra de
/// partajare a sistemului.
Future<void> open(String name, String mime, Uint8List bytes) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  // adresa temporară se eliberează după ce browserul a preluat fișierul
  Future<void>.delayed(
    const Duration(seconds: 30),
    () => web.URL.revokeObjectURL(url),
  );
}
