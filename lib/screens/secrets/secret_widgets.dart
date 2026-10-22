import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/notes_store.dart';
import '../../models/attachment.dart';
import '../../models/secret_item.dart';
import '../../services/file_opener.dart';
import '../../services/password_tools.dart';
import '../../services/secret_helpers.dart';
import '../../utils/format.dart';
import '../../widgets/pickers.dart';
import '../image_viewer_screen.dart';

/// Iconița din listă: culoarea și inițiala serviciului recunoscut
/// (eMAG, Netflix, BT…) sau iconița tipului.
class SecretAvatar extends StatelessWidget {
  const SecretAvatar({super.key, required this.item, this.radius = 20});

  final SecretItem item;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final site =
        item.type == SecretType.login || item.type == SecretType.subscription
        ? siteOf(item)
        : null;
    if (site != null) {
      final bg = Color(site.color);
      final fg = bg.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        foregroundColor: fg,
        child: Text(
          site.initial,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: radius * 0.85,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      child: item.type == SecretType.login && item.displayTitle.isNotEmpty
          ? Text(item.displayTitle.substring(0, 1).toUpperCase())
          : Icon(item.type.icon, size: radius),
    );
  }
}

/// Copiere cu mesaj. Datele secrete (parole, CVV, PIN, CNP) se șterg din
/// clipboard după 30 s; restul rămân, ca să poată fi lipite oricând.
Future<void> copyValue(
  BuildContext context,
  String value, {
  required bool secret,
  String? what,
}) async {
  if (secret) {
    await SecureClipboard.copy(value);
  } else {
    await Clipboard.setData(ClipboardData(text: value));
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          secret
              ? '${what ?? 'Copiat'} — se șterge din clipboard în 30 s'
              : '${what ?? 'Copiat'} în clipboard',
        ),
      ),
    );
}

/// Atașamentele unei intrări din „Parole” (poze cu actul, contracte…),
/// păstrate criptat ca și restul datelor. Pe [onAdded] edit-ul ține
/// evidența celor adăugate, ca să le poată elimina la „Renunță”.
class SecretAttachments extends StatelessWidget {
  const SecretAttachments({
    super.key,
    required this.ownerId,
    this.editable = false,
    this.onAdded,
  });

  final String ownerId;
  final bool editable;
  final void Function(Attachment a)? onAdded;

  Future<void> _add(BuildContext context) async {
    final store = context.read<NotesStore>();
    try {
      final files = await FilePicker.pickFiles();
      for (final f in files) {
        final a = await store.addAttachment(
          noteId: ownerId,
          name: f.name,
          bytes: await f.readAsBytes(),
          mime: Attachment.mimeFromName(f.name),
        );
        onAdded?.call(a);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nu am putut atașa fișierul: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final files = store.attachmentsOf(ownerId);
    if (files.isEmpty && !editable) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Atașamente',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final a in files)
          ListTile(
            leading: Icon(
              a.isImage
                  ? Icons.image_outlined
                  : a.mime == 'application/pdf'
                  ? Icons.picture_as_pdf_outlined
                  : Icons.insert_drive_file_outlined,
            ),
            title: Text(a.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(formatSize(a.size)),
            onTap: () {
              if (a.isImage) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ImageViewerScreen(attachmentId: a.id),
                  ),
                );
                return;
              }
              final bytes = store.bytesOf(a.id);
              if (bytes != null) FileOpener.open(a.name, a.mime, bytes);
            },
            trailing: IconButton(
              tooltip: 'Elimină',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'Elimini „${a.name}”?')) {
                  await store.removeAttachment(a);
                }
              },
            ),
          ),
        if (editable || files.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton.icon(
              icon: const Icon(Icons.attach_file),
              label: const Text('Atașează fișier sau poză'),
              onPressed: () => _add(context),
            ),
          ),
      ],
    );
  }
}
