import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../models/note.dart';
import '../widgets/note_tile.dart';
import '../widgets/pickers.dart';
import 'note_editor_screen.dart';

/// Ce listă de notițe e afișată.
sealed class NoteView {
  const NoteView();
}

class AllNotesView extends NoteView {
  const AllNotesView();
}

class PinnedView extends NoteView {
  const PinnedView();
}

class RemindersView extends NoteView {
  const RemindersView();
}

class TrashView extends NoteView {
  const TrashView();
}

class NotebookView extends NoteView {
  const NotebookView(this.id);
  final String id;
}

class TagView extends NoteView {
  const TagView(this.tag);
  final String tag;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  NoteView _view = const AllNotesView();
  final _search = TextEditingController();
  String _query = '';

  static const _wideBreakpoint = 840.0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _title(NotesStore store) => switch (_view) {
    AllNotesView() => 'Toate notițele',
    PinnedView() => 'Fixate',
    RemindersView() => 'Mementouri',
    TrashView() => 'Coș',
    NotebookView(:final id) => store.notebook(id)?.name ?? 'Carnet',
    TagView(:final tag) => '#$tag',
  };

  List<Note> _notes(NotesStore store) {
    final base = switch (_view) {
      AllNotesView() => store.activeNotes,
      PinnedView() => store.pinnedNotes,
      RemindersView() => store.reminderNotes,
      TrashView() => store.trashedNotes,
      NotebookView(:final id) => store.notesInNotebook(id),
      TagView(:final tag) => store.notesWithTag(tag),
    };
    return store.search(_query, base);
  }

  void _select(NoteView v, {bool closeDrawer = true}) {
    setState(() {
      _view = v;
      _search.clear();
      _query = '';
    });
    if (closeDrawer && MediaQuery.of(context).size.width < _wideBreakpoint) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _open(Note note) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: note.id)));

  Future<void> _newNote() async {
    final store = context.read<NotesStore>();
    final note = await store.createNote(
      notebookId: _view is NotebookView ? (_view as NotebookView).id : null,
      tag: _view is TagView ? (_view as TagView).tag : null,
    );
    if (_view is PinnedView) await store.togglePin(note);
    await _open(note);
  }

  void _noteActions(Note note) {
    final store = context.read<NotesStore>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
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
                    title: Text(
                      note.pinned ? 'Anulează fixarea' : 'Fixează sus',
                    ),
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
                      ScaffoldMessenger.of(context).showSnackBar(
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

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final wide = MediaQuery.of(context).size.width >= _wideBreakpoint;
    final notes = _notes(store);
    final sidebar = _Sidebar(current: _view, onSelect: _select);

    final scaffold = Scaffold(
      drawer: wide ? null : Drawer(child: sidebar),
      appBar: AppBar(
        title: Text(_title(store)),
        actions: [
          if (_view is TrashView && store.trashedNotes.isNotEmpty)
            TextButton(
              onPressed: () async {
                if (await confirm(
                  context,
                  'Golești coșul? Notițele vor fi șterse definitiv.',
                  action: 'Golește',
                )) {
                  store.emptyTrash();
                }
              },
              child: const Text('Golește'),
            ),
          if (_view is! RemindersView && _view is! TrashView)
            PopupMenuButton<NoteSort>(
              tooltip: 'Sortare',
              icon: const Icon(Icons.sort),
              initialValue: store.sort,
              onSelected: (s) => store.sort = s,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: NoteSort.updated,
                  child: Text('Data modificării'),
                ),
                PopupMenuItem(
                  value: NoteSort.created,
                  child: Text('Data creării'),
                ),
                PopupMenuItem(value: NoteSort.title, child: Text('Titlu')),
              ],
            ),
        ],
      ),
      floatingActionButton: _view is TrashView
          ? null
          : FloatingActionButton.extended(
              onPressed: _newNote,
              icon: const Icon(Icons.edit_note),
              label: const Text('Notiță nouă'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: SearchBar(
              controller: _search,
              hintText: 'Caută în notițe, etichete, text scanat…',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              trailing: [
                if (_query.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  ),
              ],
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: notes.isEmpty
                ? _Empty(view: _view, searching: _query.isNotEmpty)
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: notes.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (_, i) {
                      final n = notes[i];
                      final tile = NoteTile(
                        note: n,
                        showNotebook: _view is! NotebookView,
                        onTap: () => _open(n),
                        onLongPress: () => _noteActions(n),
                      );
                      if (_view is! RemindersView) return tile;
                      return Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Checkbox(
                              value: n.reminderDone,
                              onChanged: (_) => store.toggleReminderDone(n),
                            ),
                          ),
                          Expanded(child: tile),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );

    if (!wide) return scaffold;
    return Row(
      children: [
        SizedBox(width: 290, child: Material(child: sidebar)),
        const VerticalDivider(width: 1),
        Expanded(child: scaffold),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.view, required this.searching});
  final NoteView view;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = searching
        ? (Icons.search_off, 'Niciun rezultat')
        : switch (view) {
            TrashView() => (Icons.delete_outline, 'Coșul e gol'),
            RemindersView() => (
              Icons.alarm,
              'Niciun memento.\nAdaugă unul din editorul unei notițe.',
            ),
            PinnedView() => (
              Icons.push_pin_outlined,
              'Nicio notiță fixată.\nȚine apăsat pe o notiță ca s-o fixezi.',
            ),
            _ => (Icons.note_alt_outlined, 'Nicio notiță încă'),
          };
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: color),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: color),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, required this.onSelect});

  final NoteView current;
  final void Function(NoteView) onSelect;

  bool _is(NoteView v) => switch ((current, v)) {
    (NotebookView a, NotebookView b) => a.id == b.id,
    (TagView a, TagView b) => a.tag == b.tag,
    _ => current.runtimeType == v.runtimeType,
  };

  Widget _item(
    BuildContext context,
    NoteView v,
    IconData icon,
    String label, {
    int? count,
    VoidCallback? onLongPress,
  }) {
    return ListTile(
      dense: true,
      selected: _is(v),
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      shape: const StadiumBorder(),
      leading: Icon(icon),
      title: Text(label, overflow: TextOverflow.ellipsis),
      trailing: count == null || count == 0 ? null : Text('$count'),
      onTap: () => onSelect(v),
      onLongPress: onLongPress,
    );
  }

  Widget _header(BuildContext context, String text, {VoidCallback? onAdd}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 1.1,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (onAdd != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add, size: 20),
              onPressed: onAdd,
            ),
        ],
      ),
    );
  }

  void _notebookMenu(BuildContext context, String id) {
    final store = context.read<NotesStore>();
    final nb = store.notebook(id)!;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Redenumește'),
              onTap: () async {
                Navigator.pop(ctx);
                final name = await promptText(
                  context,
                  title: 'Redenumește carnetul',
                  initial: nb.name,
                );
                if (name != null) store.renameNotebook(nb, name);
              },
            ),
            ListTile(
              leading: Icon(
                store.defaultNotebookId == id ? Icons.star : Icons.star_outline,
              ),
              title: const Text('Carnet implicit pentru notițe noi'),
              onTap: () {
                Navigator.pop(ctx);
                store.defaultNotebookId = id;
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
                final ok = await store.deleteNotebook(nb);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Trebuie să rămână cel puțin un carnet'),
                    ),
                  );
                } else if (current is NotebookView &&
                    (current as NotebookView).id == id) {
                  onSelect(const AllNotesView());
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _tagMenu(BuildContext context, String tag) {
    final store = context.read<NotesStore>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
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
                  if (current is TagView) onSelect(TagView(name));
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
                  if (current is TagView) onSelect(const AllNotesView());
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _settings(BuildContext context) {
    final store = context.read<NotesStore>();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Temă',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              StatefulBuilder(
                builder: (ctx, setState) => SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('Automat'),
                      icon: Icon(Icons.brightness_auto),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Luminos'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Întunecat'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {store.themeMode},
                  onSelectionChanged: (s) {
                    store.themeMode = s.first;
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  child: const Icon(Icons.edit_note),
                ),
                const SizedBox(width: 12),
                Text(
                  'Notițe',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          _item(
            context,
            const AllNotesView(),
            Icons.notes,
            'Toate notițele',
            count: store.activeNotes.length,
          ),
          _item(
            context,
            const PinnedView(),
            Icons.push_pin_outlined,
            'Fixate',
            count: store.pinnedNotes.length,
          ),
          _item(
            context,
            const RemindersView(),
            Icons.alarm,
            'Mementouri',
            count: store.reminderNotes.where((n) => !n.reminderDone).length,
          ),
          _header(
            context,
            'Carnete',
            onAdd: () async {
              final name = await promptText(
                context,
                title: 'Carnet nou',
                hint: 'Nume carnet',
                action: 'Creează',
              );
              if (name != null) {
                final nb = await store.createNotebook(name);
                onSelect(NotebookView(nb.id));
              }
            },
          ),
          for (final nb in store.notebooks)
            _item(
              context,
              NotebookView(nb.id),
              store.defaultNotebookId == nb.id
                  ? Icons.book
                  : Icons.book_outlined,
              nb.name,
              count: store.notebookCount(nb.id),
              onLongPress: () => _notebookMenu(context, nb.id),
            ),
          if (store.allTags.isNotEmpty) ...[
            _header(context, 'Etichete'),
            for (final t in store.allTags)
              _item(
                context,
                TagView(t),
                Icons.sell_outlined,
                t,
                count: store.tagCount(t),
                onLongPress: () => _tagMenu(context, t),
              ),
          ],
          const Divider(height: 24),
          _item(
            context,
            const TrashView(),
            Icons.delete_outline,
            'Coș',
            count: store.trashedNotes.length,
          ),
          ListTile(
            dense: true,
            shape: const StadiumBorder(),
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Setări'),
            onTap: () => _settings(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Ține apăsat pe un carnet sau o etichetă pentru opțiuni.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
