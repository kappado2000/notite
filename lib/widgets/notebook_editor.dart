import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../models/notebook.dart';
import '../theme.dart';

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

  /// Nuanța aleasă (index în [GroupTint.all]); null = încă neatinsă.
  int? _tint;

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
      nav.pop(
        await store.createNotebook(name, color: _tint == null ? 0 : _tint! + 1),
      );
    } else {
      await store.updateNotebook(
        existing,
        name: name,
        emoji: existing.emoji,
        color: _tint == null ? existing.color : _tint! + 1,
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
            widget.notebook == null ? 'Carnet nou' : 'Editează carnetul',
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
          const SizedBox(height: 16),
          Text('Nuanță', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _TintPicker(
            selected:
                _tint ??
                (widget.notebook == null
                    ? null
                    : context.read<NotesStore>().tintOf(widget.notebook!)),
            onSelected: (i) => setState(() => _tint = i),
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

/// Rândul de cercuri colorate pentru alegerea nuanței.
class _TintPicker extends StatelessWidget {
  const _TintPicker({required this.selected, required this.onSelected});
  final int? selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (var i = 0; i < GroupTint.all.length; i++)
        Tooltip(
          message: GroupTint.all[i].name,
          child: InkResponse(
            onTap: () => onSelected(i),
            radius: 24,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: GroupTint.all[i].container(context),
                shape: BoxShape.circle,
                border: Border.all(
                  color: GroupTint.all[i].onContainer(context),
                  width: selected == i ? 3 : 1,
                ),
              ),
              child: selected == i
                  ? Icon(
                      Icons.check,
                      size: 20,
                      color: GroupTint.all[i].onContainer(context),
                    )
                  : null,
            ),
          ),
        ),
    ],
  );
}

/// Iconița unui carnet, în nuanța lui.
class NotebookBadge extends StatelessWidget {
  const NotebookBadge({super.key, required this.notebook, this.size = 36});

  final Notebook notebook;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = GroupTint.at(context.read<NotesStore>().tintOf(notebook));
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
