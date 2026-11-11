import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../models/notebook.dart';
import '../theme.dart';
import 'tint_picker.dart';

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

  /// Nuanța aleasă: culoarea (index în [GroupTint.all]), intensitatea,
  /// culoarea scrisului.
  late int _color;
  late int _level;
  late TintText _text;

  @override
  void initState() {
    super.initState();
    final store = context.read<NotesStore>();
    final nb = widget.notebook;
    _color = nb == null ? store.freeTint() : store.tintOf(nb);
    _level = nb?.intensity ?? 1;
    _text = TintText.values[(nb?.textMode ?? 0) % 3];
  }

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
      final nb = await store.createNotebook(name, color: _color + 1);
      await store.updateNotebook(
        nb,
        name: name,
        emoji: nb.emoji,
        color: nb.color,
        intensity: _level,
        textMode: _text.index,
      );
      nav.pop(nb);
    } else {
      await store.updateNotebook(
        existing,
        name: name,
        emoji: existing.emoji,
        color: _color + 1,
        intensity: _level,
        textMode: _text.index,
      );
      nav.pop(existing);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.notebook == null ? 'Carnet nou' : 'Editează carnetul',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: widget.notebook == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Nume carnet',
              prefixIcon: Icon(Icons.book_outlined),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          TintPicker(
            color: _color,
            level: _level,
            text: _text,
            sampleTitle: _name.text.trim().isEmpty
                ? 'Carnet'
                : _name.text.trim(),
            onChanged: (c, l, t) => setState(() {
              _color = c;
              _level = l;
              _text = t;
            }),
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

/// Iconița unui carnet, în nuanța lui.
class NotebookBadge extends StatelessWidget {
  const NotebookBadge({super.key, required this.notebook, this.size = 36});

  final Notebook notebook;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = context.read<NotesStore>().notebookTint(notebook);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.container(context),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        Icons.book_outlined,
        size: size * 0.55,
        color: tint.onContainer(context),
      ),
    );
  }
}
