import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../models/note.dart';
import '../utils/format.dart';

class NoteTile extends StatelessWidget {
  const NoteTile({
    super.key,
    required this.note,
    required this.onTap,
    this.onLongPress,
    this.showNotebook = true,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showNotebook;

  @override
  Widget build(BuildContext context) {
    final store = context.read<NotesStore>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final thumb = store.firstImageOf(note.id);
    final thumbBytes = thumb == null ? null : store.bytesOf(thumb.id);
    final attCount = store.attachmentsOf(note.id).length;
    final body = snippet(note.plainText);
    final muted = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (note.pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.push_pin,
                            size: 16,
                            color: scheme.primary,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          note.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(formatDate(note.updatedAt), style: muted),
                      if (showNotebook)
                        _Meta(
                          icon: Icons.book_outlined,
                          label: store.notebook(note.notebookId)?.name ?? '',
                          style: muted,
                        ),
                      if (note.hasReminder)
                        _Meta(
                          icon: note.reminderDone
                              ? Icons.check_circle_outline
                              : Icons.alarm,
                          label: formatDate(note.reminderAt!),
                          style: muted,
                        ),
                      if (attCount > 0)
                        _Meta(
                          icon: Icons.attach_file,
                          label: '$attCount',
                          style: muted,
                        ),
                      for (final t in note.tags.take(3))
                        _Meta(
                          icon: Icons.sell_outlined,
                          label: t,
                          style: muted,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (thumbBytes != null) ...[
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  thumbBytes,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  cacheWidth: 192,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, this.style});
  final IconData icon;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: style?.color),
      const SizedBox(width: 3),
      Text(label, style: style),
    ],
  );
}
