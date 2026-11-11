import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/app_settings.dart';
import '../../data/notes_store.dart';
import '../../models/attachment.dart';
import '../../models/secret_item.dart';
import '../../services/file_opener.dart';
import '../../services/password_tools.dart';
import '../../services/secret_helpers.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/pickers.dart';
import '../../widgets/tint_picker.dart';
import '../image_viewer_screen.dart';

/// Culoarea implicită a fiecărui tip (index în `GroupTint.all`).
int defaultSecretTint(SecretType t) => switch (t) {
  SecretType.login => 2, // albastru
  SecretType.card => 4, // mov
  SecretType.bank => 5, // turcoaz
  SecretType.identity => 1, // coral
  SecretType.subscription => 6, // roz
  SecretType.wifi => 0, // salvie
  SecretType.note => 3, // miere
};

/// Nuanța unui tip de intrare (Conturi, Carduri, Acte…): cea aleasă de
/// user în setări sau cea implicită.
GroupTint secretTint(BuildContext context, SecretType t) {
  AppSettings? settings;
  try {
    settings = context.read<AppSettings>();
  } catch (_) {}
  final v = settings?.secretTypeTint(t.name);
  if (v == null) return GroupTint.at(defaultSecretTint(t));
  return GroupTint.at(v.$1)
      .styled(level: v.$2, text: TintText.values[v.$3 % 3]);
}

/// Iconița din listă: culoarea și inițiala serviciului recunoscut
/// (eMAG, Netflix, BT…) sau iconița tipului.
class SecretAvatar extends StatelessWidget {
  const SecretAvatar({super.key, required this.item, this.radius = 20});

  final SecretItem item;
  final double radius;

  @override
  Widget build(BuildContext context) {
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
    final tint = secretTint(context, item.type);
    return CircleAvatar(
      radius: radius,
      backgroundColor: tint.container(context),
      foregroundColor: tint.onContainer(context),
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
  // Semn imediat (vibrație scurtă + mesaj), apoi copierea propriu-zisă.
  HapticFeedback.selectionClick();
  final messenger = ScaffoldMessenger.of(context);
  messenger
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
  if (secret) {
    await SecureClipboard.copy(value);
  } else {
    await Clipboard.setData(ClipboardData(text: value));
  }
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

/// Alegerea nuanței unui tip de parole (culoare, intensitate, scris).
Future<void> editSecretTypeTint(BuildContext context, SecretType type) {
  final settings = context.read<AppSettings>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => ChangeNotifierProvider.value(
      value: settings,
      child: _SecretTintSheet(type: type),
    ),
  );
}

class _SecretTintSheet extends StatefulWidget {
  const _SecretTintSheet({required this.type});
  final SecretType type;

  @override
  State<_SecretTintSheet> createState() => _SecretTintSheetState();
}

class _SecretTintSheetState extends State<_SecretTintSheet> {
  late int _color;
  late int _level;
  late TintText _text;

  @override
  void initState() {
    super.initState();
    final v = context.read<AppSettings>().secretTypeTint(widget.type.name);
    _color = v?.$1 ?? defaultSecretTint(widget.type);
    _level = v?.$2 ?? 1;
    _text = TintText.values[(v?.$3 ?? 0) % 3];
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<AppSettings>();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nuanța: ${widget.type.label}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TintPicker(
              color: _color,
              level: _level,
              text: _text,
              sampleTitle: widget.type.label,
              sampleIcon: widget.type.icon,
              onChanged: (c, l, t) => setState(() {
                _color = c;
                _level = l;
                _text = t;
              }),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    settings.setSecretTypeTint(widget.type.name, null);
                    Navigator.pop(context);
                  },
                  child: const Text('Implicit'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    settings.setSecretTypeTint(widget.type.name, (
                      _color,
                      _level,
                      _text.index,
                    ));
                    Navigator.pop(context);
                  },
                  child: const Text('Salvează'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
