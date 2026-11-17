import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_settings.dart';
import '../models/note_template.dart';

/// Un element care poate fi ales și pus în ordinea dorită (card de pe
/// Acasă, unealtă din bara tastaturii / meniul „+”, șablon).
class ToolDef {
  const ToolDef(this.id, this.icon, this.label);
  final String id;
  final IconData icon;
  final String label;
}

/// Cardurile de sus de pe Acasă.
const homeCardDefs = <ToolDef>[
  ToolDef('list', Icons.checklist, 'Listă'),
  ToolDef('note', Icons.edit_outlined, 'Notiță'),
  ToolDef('scan', Icons.document_scanner_outlined, 'Scanează'),
  ToolDef('pinned', Icons.push_pin_outlined, 'Fixate'),
  ToolDef('qr', Icons.qr_code_scanner, 'Cod QR'),
  ToolDef('bon', Icons.receipt_long_outlined, 'Bon'),
  ToolDef('reminders', Icons.alarm, 'Mementouri'),
];
const homeCardDefaults = ['list', 'note', 'scan', 'qr', 'bon'];

/// Uneltele notiței (bara de deasupra tastaturii și meniul „+”).
const editorToolDefs = <ToolDef>[
  ToolDef('checklist', Icons.checklist, 'Listă de bifat'),
  ToolDef('file', Icons.attach_file, 'Fișier (agrafă)'),
  ToolDef('scan', Icons.document_scanner_outlined, 'Scanează document'),
  ToolDef('camera', Icons.photo_camera_outlined, 'Fotografie'),
  ToolDef('image', Icons.image_outlined, 'Imagine din galerie'),
  ToolDef('voice', Icons.mic_none, 'Notă vocală'),
  ToolDef('qr', Icons.qr_code_scanner, 'Cod QR / de bare'),
  ToolDef('share', Icons.ios_share, 'Partajează notița'),
];
const editorBarDefaults = ['file', 'checklist'];
const addMenuDefaults = [
  'checklist',
  'scan',
  'camera',
  'image',
  'voice',
  'qr',
  'file',
];

List<ToolDef> templateDefs() => [
  for (final t in noteTemplates) ToolDef(t.name, t.icon, t.name),
];

/// Ce liste se pot personaliza: cheia din setări, elementele, implicitul.
enum CustomList {
  homeCards('Carduri pe Acasă', 'homeCards'),
  editorBar('Bara de deasupra tastaturii', 'editorBar'),
  addMenu('Meniul „+” din notiță', 'addMenu'),
  templates('Șabloane', 'templates');

  const CustomList(this.title, this.key);
  final String title;
  final String key;

  List<ToolDef> get defs => switch (this) {
    homeCards => homeCardDefs,
    editorBar || addMenu => editorToolDefs,
    templates => templateDefs(),
  };

  List<String> get defaults => switch (this) {
    homeCards => homeCardDefaults,
    editorBar => editorBarDefaults,
    addMenu => addMenuDefaults,
    templates => [for (final t in noteTemplates) t.name],
  };

  /// Elementele alese, în ordinea aleasă.
  List<ToolDef> chosen(AppSettings s) {
    final ids = s.customList(key) ?? defaults;
    final byId = {for (final d in defs) d.id: d};
    return [for (final id in ids) ?byId[id]];
  }
}

/// Ecranul de personalizare: pentru fiecare listă, elementele bifate apar,
/// în ordinea în care le tragi (de mânerul din dreapta).
class CustomizeScreen extends StatelessWidget {
  const CustomizeScreen({super.key, this.only});

  /// Deschis direct pe o singură listă (ex. din meniul „+”).
  final CustomList? only;

  @override
  Widget build(BuildContext context) {
    final lists = only == null ? CustomList.values : [only!];
    return DefaultTabController(
      length: lists.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(only?.title ?? 'Personalizare'),
          bottom: lists.length == 1
              ? null
              : TabBar(
                  isScrollable: true,
                  tabs: [
                    for (final l in lists)
                      Tab(text: l.title.replaceFirst(' din notiță', '')),
                  ],
                ),
        ),
        body: TabBarView(
          children: [for (final l in lists) _ListEditor(list: l)],
        ),
      ),
    );
  }
}

class _ListEditor extends StatelessWidget {
  const _ListEditor({required this.list});
  final CustomList list;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final chosen = list.chosen(settings);
    final chosenIds = chosen.map((d) => d.id).toList();
    final rest = [
      for (final d in list.defs)
        if (!chosenIds.contains(d.id)) d,
    ];
    void save(List<String> ids) => settings.setCustomList(list.key, ids);
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Bifează ce vrei să apară; trage de ≡ ca să schimbi ordinea.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) {
            final ids = [...chosenIds];
            ids.insert(to, ids.removeAt(from));
            save(ids);
          },
          children: [
            for (final (i, d) in chosen.indexed)
              ListTile(
                key: ValueKey(d.id),
                leading: Checkbox(
                  value: true,
                  onChanged: (_) => save([...chosenIds]..remove(d.id)),
                ),
                title: Row(
                  children: [
                    Icon(d.icon, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(d.label)),
                  ],
                ),
                trailing: ReorderableDragStartListener(
                  index: i,
                  child: const Icon(Icons.drag_handle),
                ),
              ),
          ],
        ),
        if (rest.isNotEmpty) ...[
          const Divider(),
          for (final d in rest)
            ListTile(
              leading: Checkbox(
                value: false,
                onChanged: (_) => save([...chosenIds, d.id]),
              ),
              title: Row(
                children: [
                  Icon(d.icon, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      d.label,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.restart_alt),
            label: const Text('Revino la ordinea inițială'),
            onPressed: () => settings.setCustomList(list.key, null),
          ),
        ),
      ],
    );
  }
}
