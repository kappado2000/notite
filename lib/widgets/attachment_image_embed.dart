import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../screens/image_viewer_screen.dart';

/// Tipul de embed Quill pentru o imagine atașată; `data` = id atașament.
const kAttachmentImageEmbed = 'attimg';

BlockEmbed attachmentImageEmbed(String attachmentId) =>
    BlockEmbed(kAttachmentImageEmbed, attachmentId);

/// Afișează în editor o imagine păstrată în stocarea locală.
class AttachmentImageEmbedBuilder extends EmbedBuilder {
  const AttachmentImageEmbedBuilder();

  @override
  String get key => kAttachmentImageEmbed;

  @override
  String toPlainText(Embed node) => '￼';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final id = embedContext.node.value.data as String;
    final store = context.read<NotesStore>();
    final att = store.attachment(id);
    final bytes = store.bytesOf(id);
    if (att == null || bytes == null) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Row(
          children: [
            Icon(Icons.broken_image_outlined),
            SizedBox(width: 8),
            Text('Imagine indisponibilă'),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ImageViewerScreen(attachmentId: id),
          ),
        ),
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            if (att.ocrText.isNotEmpty)
              Positioned(
                right: 6,
                top: 6,
                child: Tooltip(
                  message: 'Copiază textul recunoscut',
                  child: Material(
                    color: Colors.black54,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: att.ocrText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Text copiat')),
                        );
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.document_scanner_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                            SizedBox(width: 4),
                            Text('Text', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
