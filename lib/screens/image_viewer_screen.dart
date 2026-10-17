import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../services/file_opener.dart';

/// Imagine pe tot ecranul, cu zoom, și textul recunoscut (OCR) dedesubt.
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.attachmentId});

  final String attachmentId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final att = store.attachment(attachmentId);
    final bytes = store.bytesOf(attachmentId);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(att?.name ?? ''),
        actions: [
          if (att != null && bytes != null)
            IconButton(
              tooltip: 'Partajează',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => FileOpener.share(att.name, att.mime, bytes),
            ),
        ],
      ),
      body: bytes == null
          ? const Center(
              child: Text(
                'Imagine indisponibilă',
                style: TextStyle(color: Colors.white),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: InteractiveViewer(
                    maxScale: 6,
                    child: Center(child: Image.memory(bytes)),
                  ),
                ),
                if (att != null && att.ocrText.isNotEmpty)
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 220),
                    color: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.document_scanner_outlined),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Text recunoscut',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Copiază'),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: att.ocrText),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Text copiat')),
                                );
                              },
                            ),
                          ],
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            child: SelectableText(att.ocrText),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
