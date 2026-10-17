import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../models/notebook.dart';

/// Creare / redenumire carnet. Întoarce carnetul creat sau actualizat.
Future<Notebook?> editNotebook(BuildContext context, {Notebook? notebook}) {
  return showModalBottomSheet<Notebook>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<NotesStore>(),
      child: _NotebookEditor(notebook: notebook),
    ),
  );
}

class _NotebookEditor extends StatefulWidget {
  const _NotebookEditor({this.notebook});
  final Notebook? notebook;

  @override
  State<_NotebookEditor> createState() => _NotebookEditorState();
}

class _NotebookEditorState extends State<_NotebookEditor> {
  late final _name = TextEditingController(text: widget.notebook?.name ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final store = context.read<NotesStore>();
    final nav = Navigator.of(context);
    final existing = widget.notebook;
    if (existing == null) {
      nav.pop(await store.createNotebook(name));
    } else {
      await store.updateNotebook(
        existing,
        name: name,
        emoji: existing.emoji,
        color: existing.color,
      );
      nav.pop(existing);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.notebook == null ? 'Carnet nou' : 'Redenumește carnetul',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Nume carnet',
              prefixIcon: Icon(Icons.book_outlined),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              child: Text(
                widget.notebook == null ? 'Creează carnetul' : 'Salvează',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Iconița unui carnet — uniformă, în culoarea de accent.
class NotebookBadge extends StatelessWidget {
  const NotebookBadge({super.key, required this.notebook, this.size = 36});

  final Notebook notebook;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        Icons.book_outlined,
        size: size * 0.55,
        color: scheme.onPrimaryContainer,
      ),
    );
  }
}
