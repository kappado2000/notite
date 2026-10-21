import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_settings.dart';
import '../data/notes_store.dart';
import '../models/note.dart';
import '../widgets/note_actions.dart';
import '../widgets/note_card.dart';
import '../widgets/notebook_editor.dart';
import '../widgets/pickers.dart';
import 'shell.dart';

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

bool sameView(NoteView a, NoteView b) => switch ((a, b)) {
  (NotebookView x, NotebookView y) => x.id == y.id,
  (TagView x, TagView y) => x.tag == y.tag,
  _ => a.runtimeType == b.runtimeType,
};

class NotesTab extends StatefulWidget {
  const NotesTab({super.key});

  @override
  State<NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<NotesTab> {
  NoteView _view = const AllNotesView();
  final _search = TextEditingController();
  String _query = '';
  bool _searching = false;
  ShellController? _shell;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = context.read<ShellController>();
    if (shell != _shell) {
      _shell?.removeListener(_onShell);
      _shell = shell..addListener(_onShell);
      _onShell();
    }
  }

  /// „Acasă” poate cere deschiderea unui carnet sau a unei vederi.
  void _onShell() {
    final v = _shell?.pendingView;
    if (v == null) return;
    _shell!.pendingView = null;
    _select(v);
  }

  @override
  void dispose() {
    _shell?.removeListener(_onShell);
    _search.dispose();
    super.dispose();
  }

  void _select(NoteView v) => setState(() {
    _view = v;
    _search.clear();
    _query = '';
    _searching = false;
  });

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

  void _newNote() => createAndOpenNote(
    context,
    notebookId: _view is NotebookView ? (_view as NotebookView).id : null,
    tag: _view is TagView ? (_view as TagView).tag : null,
    pinned: _view is PinnedView,
  );

  /// Alegerea carnetului / etichetei / vederii — se deschide din titlu.
  void _openPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: context.read<NotesStore>(),
        child: _ViewPicker(
          current: _view,
          onSelect: (v) {
            Navigator.pop(ctx);
            _select(v);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final settings = context.watch<AppSettings>();
    final scheme = Theme.of(context).colorScheme;
    final notes = _notes(store);
    final nbView = _view is NotebookView
        ? store.notebook((_view as NotebookView).id)
        : null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _openPicker,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (nbView != null) ...[
                  NotebookBadge(notebook: nbView, size: 30),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    _title(store),
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.expand_more),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Caută',
            icon: Icon(_searching ? Icons.search_off : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _search.clear();
                _query = '';
              }
            }),
          ),
          IconButton(
            tooltip: 'Filtrează: carnete, etichete, fixate…',
            icon: const Icon(Icons.filter_list),
            onPressed: _openPicker,
          ),
          PopupMenuButton<String>(
            tooltip: 'Mai multe',
            icon: const Icon(Icons.more_horiz),
            onSelected: (v) async {
              switch (v) {
                case 'layout':
                  settings.notesGrid = !settings.notesGrid;
                case 'sort-updated':
                  store.sort = NoteSort.updated;
                case 'sort-created':
                  store.sort = NoteSort.created;
                case 'sort-title':
                  store.sort = NoteSort.title;
                case 'notebook':
                  showNotebookMenu(
                    context,
                    nbView!,
                    onDeleted: () => _select(const AllNotesView()),
                  );
                case 'tag':
                  showTagMenu(
                    context,
                    (_view as TagView).tag,
                    onRenamed: (n) => _select(TagView(n)),
                    onDeleted: () => _select(const AllNotesView()),
                  );
                case 'empty-trash':
                  if (await confirm(
                    context,
                    'Golești coșul? Notițele vor fi șterse definitiv.',
                    action: 'Golește',
                  )) {
                    store.emptyTrash();
                  }
              }
            },
            itemBuilder: (_) {
              PopupMenuItem<String> item(
                String value,
                IconData icon,
                String label, {
                bool checked = false,
              }) => PopupMenuItem(
                value: value,
                child: Row(
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label)),
                    if (checked) const Icon(Icons.check, size: 18),
                  ],
                ),
              );
              final sortable = _view is! RemindersView && _view is! TrashView;
              return [
                item(
                  'layout',
                  settings.notesGrid
                      ? Icons.view_agenda_outlined
                      : Icons.grid_view_outlined,
                  settings.notesGrid ? 'Afișare listă' : 'Afișare grilă',
                ),
                if (sortable) ...[
                  const PopupMenuDivider(),
                  item(
                    'sort-updated',
                    Icons.update,
                    'Modificate recent',
                    checked: store.sort == NoteSort.updated,
                  ),
                  item(
                    'sort-created',
                    Icons.schedule,
                    'Create recent',
                    checked: store.sort == NoteSort.created,
                  ),
                  item(
                    'sort-title',
                    Icons.sort_by_alpha,
                    'După titlu',
                    checked: store.sort == NoteSort.title,
                  ),
                ],
                if (nbView != null) ...[
                  const PopupMenuDivider(),
                  item('notebook', Icons.edit_outlined, 'Redenumește carnetul'),
                ],
                if (_view is TagView) ...[
                  const PopupMenuDivider(),
                  item('tag', Icons.sell_outlined, 'Opțiuni etichetă'),
                ],
                if (_view is TrashView && store.trashedNotes.isNotEmpty) ...[
                  const PopupMenuDivider(),
                  item(
                    'empty-trash',
                    Icons.delete_sweep_outlined,
                    'Golește coșul',
                  ),
                ],
              ];
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: aboveNavBar(
        context,
        _view is TrashView
            ? null
            : FloatingActionButton(
                tooltip: 'Notiță nouă',
                onPressed: _newNote,
                child: const Icon(Icons.edit_note, size: 28),
              ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SearchBar(
                controller: _search,
                autoFocus: true,
                hintText: 'Caută în notițe, etichete, text scanat…',
                leading: const Icon(Icons.search),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: Text(
              notes.length == 1 ? '1 NOTIȚĂ' : '${notes.length} NOTIȚE',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: notes.isEmpty
                ? _Empty(view: _view, searching: _query.isNotEmpty)
                : settings.notesGrid
                ? _grid(notes)
                : ListView.separated(
                    padding: EdgeInsets.only(bottom: bottomSpace(context)),
                    itemCount: notes.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => SwipeToDelete.note(
                      note: notes[i],
                      reminderOnly: _view is RemindersView,
                      child: NoteRow(
                        note: notes[i],
                        showNotebook: _view is! NotebookView,
                        onTap: () => openNote(context, notes[i]),
                        onLongPress: () => showNoteActions(context, notes[i]),
                        leading: _reminderCheck(notes[i]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget? _reminderCheck(Note n) => _view is RemindersView
      ? Checkbox(
          value: n.reminderDone,
          onChanged: (_) => context.read<NotesStore>().toggleReminderDone(n),
        )
      : null;

  Widget _card(Note n, ColorScheme scheme, {bool compact = false}) => NoteCard(
    note: n,
    compact: compact,
    showNotebook: _view is! NotebookView,
    onTap: () => openNote(context, n),
    onLongPress: () => showNoteActions(context, n),
    leading: _reminderCheck(n),
  );

  /// Grilă „zidărie”: două (sau mai multe) coloane de înălțimi diferite.
  Widget _grid(List<Note> notes) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / 260).floor().clamp(2, 4);
        final columns = List.generate(cols, (_) => <Widget>[]);
        for (var i = 0; i < notes.length; i++) {
          columns[i % cols].add(
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _card(notes[i], scheme, compact: true),
            ),
          );
        }
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottomSpace(context)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var k = 0; k < cols; k++) ...[
                if (k > 0) const SizedBox(width: 10),
                Expanded(child: Column(children: columns[k])),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ViewPicker extends StatelessWidget {
  const _ViewPicker({required this.current, required this.onSelect});

  final NoteView current;
  final ValueChanged<NoteView> onSelect;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final scheme = Theme.of(context).colorScheme;
    Widget item(
      NoteView v,
      Widget leading,
      String label,
      int count, {
      VoidCallback? onEdit,
    }) => ListTile(
      selected: sameView(v, current),
      selectedTileColor: scheme.primaryContainer,
      selectedColor: scheme.onPrimaryContainer,
      leading: leading,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count > 0) Text('$count'),
          if (onEdit != null)
            IconButton(
              tooltip: 'Redenumește',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: onEdit,
            ),
        ],
      ),
      onTap: () => onSelect(v),
    );
    Widget header(String t, {VoidCallback? onAdd}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              t,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (onAdd != null)
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nou'),
            ),
        ],
      ),
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
        children: [
          item(
            const AllNotesView(),
            const Icon(Icons.notes),
            'Toate notițele',
            store.activeNotes.length,
          ),
          item(
            const PinnedView(),
            const Icon(Icons.push_pin_outlined),
            'Fixate',
            store.pinnedNotes.length,
          ),
          item(
            const RemindersView(),
            const Icon(Icons.alarm),
            'Mementouri',
            store.reminderNotes.where((n) => !n.reminderDone).length,
          ),
          header(
            'CARNETE',
            onAdd: () async {
              final nb = await editNotebook(context);
              if (nb != null) onSelect(NotebookView(nb.id));
            },
          ),
          for (final nb in store.notebooks)
            item(
              NotebookView(nb.id),
              NotebookBadge(notebook: nb, size: 32),
              nb.name,
              store.notebookCount(nb.id),
              onEdit: () => editNotebook(context, notebook: nb),
            ),
          if (store.allTags.isNotEmpty) ...[
            header('ETICHETE'),
            for (final t in store.allTags)
              item(
                TagView(t),
                const Icon(Icons.sell_outlined),
                t,
                store.tagCount(t),
              ),
          ],
          const Divider(height: 24),
          item(
            const TrashView(),
            const Icon(Icons.delete_outline),
            'Coș',
            store.trashedNotes.length,
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.view, required this.searching});
  final NoteView view;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final (icon, title, text) = searching
        ? (Icons.search_off, 'Niciun rezultat', 'Încearcă alte cuvinte.')
        : switch (view) {
            TrashView() => (
              Icons.delete_outline,
              'Coșul e gol',
              'Notițele șterse stau aici 30 de zile.',
            ),
            RemindersView() => (
              Icons.alarm,
              'Niciun memento',
              'Adaugă unul din editorul unei notițe (⏰).',
            ),
            PinnedView() => (
              Icons.push_pin_outlined,
              'Nicio notiță fixată',
              'Ține apăsat pe o notiță ca s-o fixezi sus.',
            ),
            _ => (
              Icons.edit_note,
              'Nicio notiță încă',
              'Apasă „Notiță nouă” ca să începi.',
            ),
          };
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
