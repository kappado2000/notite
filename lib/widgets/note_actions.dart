import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../screens/note_editor_screen.dart';
import 'notebook_editor.dart';
import 'pickers.dart';

Future<void> openNote(BuildContext context, Note note) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: note.id)));

Future<void> createAndOpenNote(
  BuildContext context, {
  String? notebookId,
  String? tag,
  bool pinned = false,
  bool checklist = false,
}) async {
  final store = context.read<NotesStore>();
  final note = await store.createNote(notebookId: notebookId, tag: tag);
  if (pinned) await store.togglePin(note);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          NoteEditorScreen(noteId: note.id, startWithChecklist: checklist),
    ),
  );
}

/// Meniul unei notițe (apăsare lungă).
void showNoteActions(BuildContext context, Note note) {
  final store = context.read<NotesStore>();
  final messenger = ScaffoldMessenger.of(context);
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: note.isTrashed
            ? [
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Restaurează'),
                  onTap: () {
                    Navigator.pop(ctx);
                    store.restore(note);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined),
                  title: const Text('Șterge definitiv'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (await confirm(
                      context,
                      'Ștergi definitiv „${note.displayTitle}”?',
                    )) {
                      store.deleteForever(note);
                    }
                  },
                ),
              ]
            : [
                ListTile(
                  leading: Icon(
                    note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  ),
                  title: Text(note.pinned ? 'Anulează fixarea' : 'Fixează sus'),
                  onTap: () {
                    Navigator.pop(ctx);
                    store.togglePin(note);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.drive_file_move_outline),
                  title: const Text('Mută în alt carnet'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final id = await pickNotebook(
                      context,
                      current: note.notebookId,
                    );
                    if (id != null) {
                      note.notebookId = id;
                      store.saveNote(note);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.sell_outlined),
                  title: const Text('Etichete'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final tags = await editTags(context, note.tags);
                    if (tags != null) {
                      note.tags = tags;
                      store.saveNote(note);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Mută în coș'),
                  onTap: () {
                    Navigator.pop(ctx);
                    store.trash(note);
                    messenger.showSnackBar(
                      SnackBar(
                        content: const Text('Notița a fost mutată în coș'),
                        action: SnackBarAction(
                          label: 'Anulează',
                          onPressed: () => store.restore(note),
                        ),
                      ),
                    );
                  },
                ),
              ],
      ),
    ),
  );
}

/// Opțiunile unui carnet. [onDeleted] e apelat după ștergere.
void showNotebookMenu(
  BuildContext context,
  Notebook nb, {
  VoidCallback? onDeleted,
}) {
  final store = context.read<NotesStore>();
  final messenger = ScaffoldMessenger.of(context);
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: NotebookBadge(notebook: nb, size: 40),
            title: Text(
              nb.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('${store.notebookCount(nb.id)} notițe'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Editează (nume, culoare, emoji)'),
            onTap: () {
              Navigator.pop(ctx);
              editNotebook(context, notebook: nb);
            },
          ),
          ListTile(
            leading: Icon(
              store.defaultNotebookId == nb.id
                  ? Icons.star
                  : Icons.star_outline,
            ),
            title: const Text('Carnet implicit pentru notițe noi'),
            onTap: () {
              Navigator.pop(ctx);
              store.defaultNotebookId = nb.id;
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Șterge carnetul'),
            subtitle: const Text('Notițele lui ajung în coș'),
            onTap: () async {
              Navigator.pop(ctx);
              if (!await confirm(context, 'Ștergi carnetul „${nb.name}”?')) {
                return;
              }
              if (await store.deleteNotebook(nb)) {
                onDeleted?.call();
              } else {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Trebuie să rămână cel puțin un carnet'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    ),
  );
}

/// Opțiunile unei etichete.
void showTagMenu(
  BuildContext context,
  String tag, {
  void Function(String newName)? onRenamed,
  VoidCallback? onDeleted,
}) {
  final store = context.read<NotesStore>();
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Redenumește eticheta'),
            onTap: () async {
              Navigator.pop(ctx);
              final name = await promptText(
                context,
                title: 'Redenumește eticheta',
                initial: tag,
              );
              if (name != null) {
                await store.renameTag(tag, name);
                onRenamed?.call(name);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Șterge eticheta'),
            subtitle: const Text('Notițele rămân, doar eticheta dispare'),
            onTap: () async {
              Navigator.pop(ctx);
              if (await confirm(context, 'Ștergi eticheta „$tag”?')) {
                await store.deleteTag(tag);
                onDeleted?.call();
              }
            },
          ),
        ],
      ),
    ),
  );
}
