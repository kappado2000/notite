import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/notes_store.dart';
import '../models/note.dart';

/// Rezultatul unei scanări de cod.
class ScannedCode {
  const ScannedCode(this.value, this.kind);
  final String value;

  /// „Cod QR”, „Cod de bare” etc.
  final String kind;

  /// Linkul web din cod, dacă e cazul.
  Uri? get url {
    final v = value.trim();
    if (!RegExp(r'^(https?://|www\.)', caseSensitive: false).hasMatch(v)) {
      return null;
    }
    return Uri.tryParse(v.startsWith('www.') ? 'https://$v' : v);
  }
}

/// Deschide camera și întoarce primul cod citit (sau null).
Future<ScannedCode?> scanCode(BuildContext context) => Navigator.of(context)
    .push<ScannedCode>(MaterialPageRoute(builder: (_) => const QrScanScreen()));

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final value = b.rawValue ?? b.displayValue;
      if (value == null || value.isEmpty) continue;
      _done = true;
      HapticFeedback.mediumImpact();
      final kind = b.format == BarcodeFormat.qrCode ? 'Cod QR' : 'Cod de bare';
      Navigator.pop(context, ScannedCode(value, kind));
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Citește cod QR / de bare'),
        actions: [
          IconButton(
            tooltip: 'Lanternă',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: _controller.toggleTorch,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera nu poate fi folosită: ${error.errorCode.name}.\n'
                  'Verifică permisiunea pentru cameră în Setări.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          // cadru de țintire
          IgnorePointer(
            child: Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Text(
              'Încadrează codul în chenar',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

/// Conținutul unei notițe create dintr-un cod: valoarea, ca link dacă e URL.
String codeNoteContent(ScannedCode code) {
  final url = code.url;
  return jsonEncode([
    if (url != null)
      {
        'insert': code.value,
        'attributes': {'link': url.toString()},
      }
    else
      {'insert': code.value},
    {'insert': '\n'},
  ]);
}

/// Scanează și arată rezultatul: salvare ca notiță, copiere, deschidere.
/// Întoarce notița creată (dacă s-a ales „Salvează”).
Future<Note?> scanCodeFlow(BuildContext context) async {
  final code = await scanCode(context);
  if (code == null || !context.mounted) return null;
  final store = context.read<NotesStore>();
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.qr_code_2),
            title: Text(code.kind),
            subtitle: SelectableText(code.value, maxLines: 6),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.note_add_outlined),
            title: const Text('Salvează ca notiță'),
            onTap: () => Navigator.pop(ctx, 'save'),
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copiază'),
            onTap: () => Navigator.pop(ctx, 'copy'),
          ),
          if (code.url != null)
            ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text('Deschide linkul'),
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
        ],
      ),
    ),
  );
  switch (action) {
    case 'save':
      final note = await store.createNote();
      note
        ..title = code.kind
        ..contentJson = codeNoteContent(code)
        ..plainText = code.value;
      await store.saveNote(note);
      return note;
    case 'copy':
      await Clipboard.setData(ClipboardData(text: code.value));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Copiat')));
      }
    case 'open':
      await launchUrl(code.url!, mode: LaunchMode.externalApplication);
  }
  return null;
}
