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
          IconButton(
            tooltip: settings.notesGrid ? 'Afișare listă' : 'Afișare grilă',
            icon: Icon(
              settings.notesGrid
                  ? Icons.view_agenda_outlined
                  : Icons.grid_view_outlined,
            ),
            onPressed: () => settings.notesGrid = !settings.notesGrid,
          ),
          if (_view is! RemindersView && _view is! TrashView)
            PopupMenuButton<NoteSort>(
              tooltip: 'Sortare',
              icon: const Icon(Icons.swap_vert),
              initialValue: store.sort,
              onSelected: (s) => store.sort = s,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: NoteSort.updated,
                  child: Text('Modificate recent'),
                ),
                PopupMenuItem(
                  value: NoteSort.created,
                  child: Text('Create recent'),
                ),
                PopupMenuItem(value: NoteSort.title, child: Text('După titlu')),
              ],
            ),
          if (nbView != null)
            IconButton(
              tooltip: 'Opțiuni carnet',
              icon: const Icon(Icons.more_vert),
              onPressed: () => showNotebookMenu(
                context,
                nbView,
                onDeleted: () => _select(const AllNotesView()),
              ),
            ),
          if (_view is TagView)
            IconButton(
              tooltip: 'Opțiuni etichetă',
              icon: const Icon(Icons.more_vert),
              onPressed: () => showTagMenu(
                context,
                (_view as TagView).tag,
                onRenamed: (n) => _select(TagView(n)),
                onDeleted: () => _select(const AllNotesView()),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: aboveNavBar(
        context,
        _view is TrashView
            ? null
            : FloatingActionButton.extended(
                onPressed: _newNote,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Notiță nouă'),
              ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchBar(
              controller: _search,
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
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final (v, label, icon) in <(NoteView, String, IconData?)>[
                  (const AllNotesView(), 'Toate', null),
                  (const PinnedView(), 'Fixate', Icons.push_pin_outlined),
                  (const RemindersView(), 'Mementouri', Icons.alarm),
                ])
                  _chip(
                    label,
                    sameView(v, _view),
                    () => _select(v),
                    icon: icon,
                  ),
                for (final nb in store.notebooks)
                  _chip(
                    nb.name,
                    sameView(NotebookView(nb.id), _view),
                    () => _select(NotebookView(nb.id)),
                    icon: Icons.book_outlined,
                  ),
                _chip(
                  'Coș',
                  _view is TrashView,
                  () => _select(const TrashView()),
                  icon: Icons.delete_outline,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: notes.isEmpty
                ? _Empty(view: _view, searching: _query.isNotEmpty)
                : settings.notesGrid
                ? _grid(notes)
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      bottomSpace(context),
                    ),
                    itemCount: notes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _card(notes[i], scheme),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(Note n, ColorScheme scheme, {bool compact = false}) => NoteCard(
    note: n,
    compact: compact,
    showNotebook: _view is! NotebookView,
    onTap: () => openNote(context, n),
    onLongPress: () => showNoteActions(context, n),
    leading: _view is RemindersView
        ? Center(
            child: Checkbox(
              value: n.reminderDone,
              onChanged: (_) =>
                  context.read<NotesStore>().toggleReminderDone(n),
            ),
          )
        : null,
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

  Widget _chip(
    String label,
    bool selected,
    VoidCallback onTap, {
    IconData? icon,
  }) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Center(
      child: ChoiceChip(
        avatar: icon == null ? null : Icon(icon, size: 16),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    ),
  );
}

class _ViewPicker extends StatelessWidget {
  const _ViewPicker({required this.current, required this.onSelect});

  final NoteView current;
  final ValueChanged<NoteView> onSelect;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final scheme = Theme.of(context).colorScheme;
    Widget item(NoteView v, Widget leading, String label, int count) =>
        ListTile(
          selected: sameView(v, current),
          selectedTileColor: scheme.primaryContainer,
          selectedColor: scheme.onPrimaryContainer,
          leading: leading,
          title: Text(label),
          trailing: count > 0 ? Text('$count') : null,
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
