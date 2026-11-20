import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_settings.dart';
import '../data/notes_store.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../services/scan_service.dart';
import '../session.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/customize.dart';
import '../widgets/note_actions.dart';
import '../widgets/note_card.dart';
import '../widgets/notebook_editor.dart';
import '../services/on_device_ai.dart';
import 'ask_notes_screen.dart';
import 'note_editor_screen.dart';
import 'notes_tab.dart';
import 'secrets/secrets_screen.dart';
import 'qr_scan_screen.dart';
import 'receipt_split_screen.dart';
import 'shell.dart';

/// Pagina de start: acțiuni rapide, mementouri, apoi câte o secțiune
/// colorată pe fiecare carnet, cu ultimele lui notițe.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _search = TextEditingController();
  String _query = '';
  bool _searchOpen = false;

  /// „Întreabă notițele” (AI pe telefon) e disponibil.
  bool _aiOk = false;

  @override
  void initState() {
    super.initState();
    OnDeviceAI.available().then((ok) {
      if (mounted && ok) setState(() => _aiOk = true);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
    final upcoming = store.reminderNotes
        .where((n) => !n.reminderDone)
        .take(3)
        .toList();
    final initial = session.email.isEmpty
        ? '🙂'
        : session.email.substring(0, 1).toUpperCase();

    final receipts =
        store.activeNotes.where((n) => n.tags.contains('bonuri')).toList()
          ..sort(
            (a, b) => NotesStore.docDate(b).compareTo(NotesStore.docDate(a)),
          );
    return Scaffold(
      // notiță nouă direct de pe Acasă, ca în pagina Notițe
      floatingActionButton: searching
          ? null
          : aboveNavBar(
              context,
              FloatingActionButton(
                heroTag: 'acasa-notita-noua',
                tooltip: 'Notiță nouă',
                onPressed: () => createAndOpenNote(context),
                child: const Icon(Icons.edit_note, size: 28),
              ),
            ),
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
                            _capitalize(
                              DateFormat('EEEE', 'ro').format(DateTime.now()),
                            ),
                            style: text.headlineMedium?.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('d MMMM y', 'ro').format(DateTime.now()),
                            style: text.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_aiOk)
                      IconButton(
                        tooltip: 'Întreabă notițele',
                        icon: const Icon(Icons.auto_awesome_outlined),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AskNotesScreen(),
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: _searchOpen ? 'Închide căutarea' : 'Caută',
                      icon: Icon(_searchOpen ? Icons.close : Icons.search),
                      onPressed: () => setState(() {
                        _searchOpen = !_searchOpen;
                        if (!_searchOpen) {
                          _search.clear();
                          _query = '';
                        }
                      }),
                    ),
                    const SizedBox(width: 4),
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
            if (_searchOpen)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                sliver: SliverToBoxAdapter(
                  child: SearchBar(
                    controller: _search,
                    autoFocus: true,
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
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final n in upcoming)
                            SwipeToDelete.note(
                              note: n,
                              reminderOnly: true,
                              child: ListTile(
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
                            ),
                        ],
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
                // Câte o secțiune pe carnet, în nuanța lui, cu ultimele notițe.
                SliverList.separated(
                  itemCount: store.notebooks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final nb = store.notebooks[i];
                    return _NotebookSection(
                      notebook: nb,
                      tint: store.notebookTint(nb),
                      notes: _latest(store, nb.id),
                      count: store.notebookCount(nb.id),
                      onOpen: () => shell.openNotes(NotebookView(nb.id)),
                    );
                  },
                ),
              ),
              if (receipts.isNotEmpty)
                _section(
                  _Header(
                    'Bonuri',
                    action: 'Toate',
                    onAction: () => shell.openNotes(const TagView('bonuri')),
                  ),
                  SliverToBoxAdapter(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final n in receipts.take(3))
                            ListTile(
                              leading: Icon(
                                Icons.receipt_long_outlined,
                                color: scheme.primary,
                              ),
                              title: Text(
                                n.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => openNote(context, n),
                            ),
                        ],
                      ),
                    ),
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
          itemBuilder: (_, i) => ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SwipeToDelete.note(
              note: results[i],
              child: NoteCard(
                note: results[i],
                onTap: () => openNote(context, results[i]),
                onLongPress: () => showNoteActions(context, results[i]),
              ),
            ),
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

  /// Ultimele 3 notițe ale carnetului: întâi cele fixate, apoi cele mai noi.
  static List<Note> _latest(NotesStore store, String notebookId) =>
      (store.activeNotes.where((n) => n.notebookId == notebookId).toList()
            ..sort((a, b) {
              if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
              return b.updatedAt.compareTo(a.updatedAt);
            }))
          .take(3)
          .toList();

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

  VoidCallback? _action(BuildContext context, String id) => switch (id) {
    'list' => () => createAndOpenNote(context, checklist: true),
    'note' => () => createAndOpenNote(context),
    'auth' => () => openSecrets(context, authenticator: true),
    'scan' => ScanService.scanSupported ? () => _scan(context) : null,
    'pinned' => () => shell.openNotes(const PinnedView()),
    'qr' => () async {
      final note = await scanCodeFlow(context);
      if (note != null && context.mounted) openNote(context, note);
    },
    'bon' => () => openReceiptSplit(context),
    'reminders' => () => shell.openNotes(const RemindersView()),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final neutral = Theme.of(context).cardTheme.color ?? scheme.surface;
    // cardurile alese în Personalizare, în ordinea aleasă; toate în același
    // stil (fundal deschis, iconiță verde)
    final cards = [
      for (final d in CustomList.homeCards.chosen(context.watch<AppSettings>()))
        if (_action(context, d.id) case final onTap?) (d, onTap),
    ];
    void customize() => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CustomizeScreen(only: CustomList.homeCards),
      ),
    );
    if (cards.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.tune),
          label: const Text('Alege cardurile de aici'),
          onPressed: customize,
        ),
      );
    }
    // câte 5 pe rând (mai puține: ocupă tot rândul)
    final cols = cards.length < 5 ? cards.length : 5;
    final rows = [
      for (var i = 0; i < cards.length; i += 5)
        cards.sublist(i, (i + 5).clamp(0, cards.length)),
    ];
    return Column(
      children: [
        for (final (r, row) in rows.indexed) ...[
          if (r > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < cols; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: i >= row.length
                      ? const SizedBox()
                      : Material(
                          color: neutral,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(color: scheme.outlineVariant),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: row[i].$2,
                            // apăsare lungă: alegi cardurile și ordinea lor
                            onLongPress: customize,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(4, 16, 4, 16),
                              child: Column(
                                children: [
                                  Icon(
                                    row[i].$1.icon,
                                    color: scheme.primary,
                                    size: 26,
                                  ),
                                  const SizedBox(height: 6),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      row[i].$1.label,
                                      maxLines: 1,
                                      softWrap: false,
                                      style: TextStyle(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
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

/// Un carnet pe pagina de start: antet colorat și ultimele lui notițe.
class _NotebookSection extends StatelessWidget {
  const _NotebookSection({
    required this.notebook,
    required this.tint,
    required this.notes,
    required this.count,
    required this.onOpen,
  });

  final Notebook notebook;
  final GroupTint tint;
  final List<Note> notes;
  final int count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    // scrisul în culoarea aleasă pentru carnet
    final scheme = tint.scheme(context);
    final accent = tint.onContainer(context);
    final muted = TextStyle(fontSize: 13, color: scheme.onSurfaceVariant);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: tint.surface(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpen,
            onLongPress: () => showNotebookMenu(context, notebook),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 6),
              child: Row(
                children: [
                  NotebookBadge(notebook: notebook, size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      notebook.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: tint.container(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Notiță nouă în ${notebook.name}',
                    icon: Icon(Icons.add, color: accent),
                    onPressed: () =>
                        createAndOpenNote(context, notebookId: notebook.id),
                  ),
                  Icon(Icons.chevron_right, color: accent),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
          if (notes.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text('Nicio notiță încă', style: muted),
            )
          else ...[
            for (final n in notes) ...[
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: accent.withValues(alpha: 0.15),
              ),
              InkWell(
                onTap: () => openNote(context, n),
                onLongPress: () => showNoteActions(context, n),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                  child: Row(
                    children: [
                      if (n.pinned) ...[
                        Icon(Icons.push_pin, size: 15, color: accent),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          n.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      if (n.hasReminder && !n.reminderDone) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.alarm, size: 15, color: muted.color),
                      ],
                      const SizedBox(width: 10),
                      Text(formatShortDate(n.updatedAt), style: muted),
                    ],
                  ),
                ),
              ),
            ],
            if (count > notes.length)
              InkWell(
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Text(
                    'Toate cele $count notițe ›',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}
