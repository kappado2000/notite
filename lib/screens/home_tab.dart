import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../models/note.dart';
import '../services/scan_service.dart';
import '../session.dart';
import '../utils/format.dart';
import '../widgets/note_actions.dart';
import '../widgets/note_card.dart';
import '../widgets/notebook_editor.dart';
import 'note_editor_screen.dart';
import 'notes_tab.dart';
import 'shell.dart';

/// Pagina de start: acțiuni rapide, recente, mementouri, carnete.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return 'Noapte bună';
    if (h < 12) return 'Bună dimineața';
    if (h < 18) return 'Bună ziua';
    return 'Bună seara';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final session = context.read<Session>();
    final shell = context.read<ShellController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final searching = _query.trim().isNotEmpty;
    final results = searching ? store.search(_query, store.activeNotes) : [];
    final recent = [...store.activeNotes]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final upcoming = store.reminderNotes
        .where((n) => !n.reminderDone)
        .take(3)
        .toList();
    final initial = session.email.isEmpty
        ? '🙂'
        : session.email.substring(0, 1).toUpperCase();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _greeting,
                            style: text.headlineMedium?.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _capitalize(
                              DateFormat(
                                'EEEE, d MMMM',
                                'ro',
                              ).format(DateTime.now()),
                            ),
                            style: text.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => shell.go(3),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: scheme.primaryContainer,
                        foregroundColor: scheme.onPrimaryContainer,
                        child: Text(
                          initial,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              sliver: SliverToBoxAdapter(
                child: SearchBar(
                  controller: _search,
                  hintText: 'Caută în toate notițele…',
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (searching)
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
            ),
            if (searching)
              ..._searchResults(results.cast<Note>())
            else ...[
              _section(
                null,
                SliverToBoxAdapter(child: _QuickActions(shell: shell)),
              ),
              if (upcoming.isNotEmpty)
                _section(
                  _Header(
                    'Mementouri',
                    action: 'Toate',
                    onAction: () => shell.openNotes(const RemindersView()),
                  ),
                  SliverToBoxAdapter(
                    child: Card(
                      child: Column(
                        children: [
                          for (final n in upcoming)
                            ListTile(
                              leading: Icon(
                                Icons.alarm,
                                color: n.reminderAt!.isBefore(DateTime.now())
                                    ? scheme.error
                                    : scheme.secondary,
                              ),
                              title: Text(
                                n.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(formatDateTime(n.reminderAt!)),
                              trailing: IconButton(
                                tooltip: 'Marchează ca făcut',
                                icon: const Icon(Icons.check_circle_outline),
                                onPressed: () => store.toggleReminderDone(n),
                              ),
                              onTap: () => openNote(context, n),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (recent.isNotEmpty)
                _section(
                  _Header(
                    'Recente',
                    action: 'Toate',
                    onAction: () => shell.openNotes(),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 196,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        itemCount: recent.length.clamp(0, 10),
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => SizedBox(
                          width: 210,
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: NoteCard(
                              note: recent[i],
                              compact: true,
                              onTap: () => openNote(context, recent[i]),
                              onLongPress: () =>
                                  showNoteActions(context, recent[i]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              _section(
                _Header(
                  'Carnete',
                  action: 'Nou',
                  onAction: () => editNotebook(context),
                ),
                SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisExtent: 104,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  delegate: SliverChildListDelegate([
                    for (final nb in store.notebooks)
                      _NotebookTile(
                        name: nb.name,
                        count: store.notebookCount(nb.id),
                        onTap: () => shell.openNotes(NotebookView(nb.id)),
                        onLongPress: () => showNotebookMenu(context, nb),
                      ),
                    _NewNotebookTile(onTap: () => editNotebook(context)),
                  ]),
                ),
              ),
              if (store.allTags.isNotEmpty)
                _section(
                  const _Header('Etichete'),
                  SliverToBoxAdapter(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in store.allTags)
                          ActionChip(
                            avatar: const Icon(Icons.tag, size: 16),
                            label: Text('$t  ${store.tagCount(t)}'),
                            onPressed: () => shell.openNotes(TagView(t)),
                          ),
                      ],
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(height: bottomSpace(context, fab: false) + 70),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _searchResults(List<Note> results) => [
    if (results.isEmpty)
      const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text('Niciun rezultat')),
      )
    else
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomSpace(context)),
        sliver: SliverList.separated(
          itemCount: results.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => NoteCard(
            note: results[i],
            onTap: () => openNote(context, results[i]),
            onLongPress: () => showNoteActions(context, results[i]),
          ),
        ),
      ),
  ];

  Widget _section(Widget? header, Widget sliver) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
    sliver: SliverMainAxisGroup(
      slivers: [
        if (header != null) SliverToBoxAdapter(child: header),
        sliver,
      ],
    ),
  );

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Header extends StatelessWidget {
  const _Header(this.title, {this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.shell});
  final ShellController shell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final neutral = Theme.of(context).cardTheme.color ?? scheme.surface;
    final actions = <(IconData, String, Color, Color, VoidCallback)>[
      (
        Icons.edit_outlined,
        'Notiță',
        scheme.primary,
        scheme.onPrimary,
        () => createAndOpenNote(context),
      ),
      (
        Icons.checklist,
        'Listă',
        neutral,
        scheme.primary,
        () => createAndOpenNote(context, checklist: true),
      ),
      if (ScanService.scanSupported)
        (
          Icons.document_scanner_outlined,
          'Scanează',
          neutral,
          scheme.primary,
          () => _scan(context),
        )
      else
        (
          Icons.push_pin_outlined,
          'Fixate',
          neutral,
          scheme.primary,
          () => shell.openNotes(const PinnedView()),
        ),
      (
        Icons.key_outlined,
        'Parole',
        neutral,
        scheme.primary,
        () => shell.go(2),
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: actions[i].$3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: i == 0
                    ? BorderSide.none
                    : BorderSide(color: scheme.outlineVariant),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: actions[i].$5,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Icon(actions[i].$1, color: actions[i].$4, size: 26),
                      const SizedBox(height: 6),
                      Text(
                        actions[i].$2,
                        style: TextStyle(
                          color: actions[i].$4,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _scan(BuildContext context) async {
    final store = context.read<NotesStore>();
    final note = await store.createNote();
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(noteId: note.id, startWithScan: true),
      ),
    );
  }
}

class _NotebookTile extends StatelessWidget {
  const _NotebookTile({
    required this.name,
    required this.count,
    required this.onTap,
    required this.onLongPress,
  });

  final String name;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.book_outlined,
                  size: 19,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const Spacer(),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                count == 1 ? '1 notiță' : '$count notițe',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewNotebookTile extends StatelessWidget {
  const _NewNotebookTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant, width: 1.5),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, color: scheme.onSurfaceVariant),
              const SizedBox(height: 4),
              Text(
                'Carnet nou',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
