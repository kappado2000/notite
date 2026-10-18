import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../models/note.dart';
import '../utils/format.dart';

/// Cardul unei notițe: titlu, fragment, imagine, carnet, etichete.
/// [compact] = varianta pentru grilă și pentru „Recente”.
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    this.onLongPress,
    this.compact = false,
    this.showNotebook = true,
    this.leading,
    this.showImage = true,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool compact;
  final bool showNotebook;

  /// Ex. bifa de la mementouri.
  final Widget? leading;

  /// Fals pentru rândurile cu înălțime fixă (ex. „Recente”).
  final bool showImage;

  @override
  Widget build(BuildContext context) {
    final store = context.read<NotesStore>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final nb = store.notebook(note.notebookId);
    final thumb = store.firstImageOf(note.id);
    final thumbBytes = thumb == null || !showImage
        ? null
        : store.bytesOf(thumb.id);
    final attCount = store.attachmentsOf(note.id).length;
    final body = snippet(note.plainText, max: compact ? 120 : 180);
    final muted = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    final meta = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (showNotebook && nb != null)
          _Pill(
            color: scheme.primaryContainer,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.book_outlined,
                  size: 12,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    nb.name,
                    style: text.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimaryContainer,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (!compact)
          for (final t in note.tags.take(3))
            _Pill(
              color: scheme.surfaceContainerHigh,
              child: Text('#$t', style: text.labelSmall),
            ),
        if (note.hasReminder)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                note.reminderDone ? Icons.check_circle : Icons.alarm,
                size: 14,
                color: note.reminderDone ? scheme.primary : scheme.secondary,
              ),
              const SizedBox(width: 3),
              Text(formatDate(note.reminderAt!), style: muted),
            ],
          ),
        if (attCount > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.attach_file, size: 14, color: muted?.color),
              Text('$attCount', style: muted),
            ],
          ),
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compact && thumbBytes != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              thumbBytes,
              height: 96,
              width: double.infinity,
              fit: BoxFit.cover,
              cacheWidth: 480,
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                note.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: scheme.onSurface,
                ),
              ),
            ),
            if (note.pinned)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 2),
                child: Icon(Icons.push_pin, size: 16, color: scheme.primary),
              ),
          ],
        ),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            body,
            maxLines: compact ? 4 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: meta),
            const SizedBox(width: 8),
            Text(formatDate(note.updatedAt), style: muted),
          ],
        ),
      ],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: leading,
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    child: content,
                  ),
                ),
                if (!compact && thumbBytes != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 14, 14, 14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        thumbBytes,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        cacheWidth: 216,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.child});
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 160),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

/// Rândul unei notițe în listă, în stilul Evernote: titlu mare și gros,
/// 3 rânduri de text subțire, data jos, miniatura imaginii în dreapta.
class NoteRow extends StatelessWidget {
  const NoteRow({
    super.key,
    required this.note,
    required this.onTap,
    this.onLongPress,
    this.showNotebook = true,
    this.leading,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showNotebook;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final store = context.read<NotesStore>();
    final scheme = Theme.of(context).colorScheme;
    final thumb = store.firstImageOf(note.id);
    final thumbBytes = thumb == null ? null : store.bytesOf(thumb.id);
    final attCount = store.attachmentsOf(note.id).length;
    final body = snippet(note.plainText, max: 260);
    final nb = showNotebook ? store.notebook(note.notebookId) : null;
    final small = TextStyle(fontSize: 13, color: scheme.onSurfaceVariant);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null)
              Padding(padding: const EdgeInsets.only(right: 8), child: leading),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(formatShortDate(note.updatedAt), style: small),
                      if (nb != null) ...[
                        Text('  ·  ', style: small),
                        Flexible(
                          child: Text(
                            nb.name,
                            style: small,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      if (note.pinned) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.push_pin, size: 14, color: scheme.primary),
                      ],
                      if (note.hasReminder) ...[
                        const SizedBox(width: 8),
                        Icon(
                          note.reminderDone ? Icons.check_circle : Icons.alarm,
                          size: 14,
                          color: small.color,
                        ),
                      ],
                      if (attCount > 0) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.attach_file, size: 14, color: small.color),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (thumbBytes != null) ...[
              const SizedBox(width: 14),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.memory(
                    thumbBytes,
                    width: 104,
                    height: 104,
                    fit: BoxFit.cover,
                    cacheWidth: 312,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
