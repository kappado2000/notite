import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../models/note.dart';
import '../utils/format.dart';

Future<bool> confirm(
  BuildContext context,
  String message, {
  String action = 'Șterge',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Anulează'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String action = 'Salvează',
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        final v = ctrl.text.trim();
        if (v.isNotEmpty) Navigator.pop(ctx, v);
      }

      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anulează'),
          ),
          FilledButton(onPressed: submit, child: Text(action)),
        ],
      );
    },
  );
}

/// Alegerea carnetului; permite și crearea unui carnet nou.
Future<String?> pickNotebook(BuildContext context, {String? current}) {
  final store = context.read<NotesStore>();
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Mută în carnetul…',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            for (final nb in store.notebooks)
              ListTile(
                leading: const Icon(Icons.book_outlined),
                title: Text(nb.name),
                trailing: nb.id == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, nb.id),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Carnet nou'),
              onTap: () async {
                final name = await promptText(
                  ctx,
                  title: 'Carnet nou',
                  hint: 'Nume carnet',
                  action: 'Creează',
                );
                if (name == null) return;
                final nb = await store.createNotebook(name);
                if (ctx.mounted) Navigator.pop(ctx, nb.id);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Editare etichete cu sugestii din etichetele existente.
/// Modificările se păstrează și dacă panoul e închis fără „Gata”.
Future<List<String>?> editTags(
  BuildContext context,
  List<String> current,
) async {
  final tags = [...current];
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _TagEditor(tags: tags),
  );
  return tags;
}

class _TagEditor extends StatefulWidget {
  const _TagEditor({required this.tags});

  /// Lista editată pe loc.
  final List<String> tags;

  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  late final List<String> _tags = widget.tags;
  final _ctrl = TextEditingController();

  void _add(String t) {
    t = t.trim();
    if (t.isEmpty) return;
    if (!_tags.any((x) => x.toLowerCase() == t.toLowerCase())) {
      setState(() => _tags.add(t));
    }
    _ctrl.clear();
  }

  @override
  void dispose() {
    // Textul rămas în câmp la închidere devine etichetă.
    final pending = _ctrl.text.trim();
    if (pending.isNotEmpty &&
        !_tags.any((x) => x.toLowerCase() == pending.toLowerCase())) {
      _tags.add(pending);
    }
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = context.read<NotesStore>().allTags;
    final q = _ctrl.text.trim().toLowerCase();
    final suggestions = all
        .where((t) => !_tags.contains(t))
        .where((t) => q.isEmpty || t.toLowerCase().contains(q))
        .take(12)
        .toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Etichete',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in _tags)
                InputChip(
                  label: Text(t),
                  onDeleted: () => setState(() => _tags.remove(t)),
                ),
            ],
          ),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Adaugă etichetă',
              prefixIcon: const Icon(Icons.sell_outlined),
              suffixIcon: IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => _add(_ctrl.text),
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: _add,
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in suggestions)
                  ActionChip(label: Text(t), onPressed: () => _add(t)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                if (_ctrl.text.trim().isNotEmpty) _add(_ctrl.text);
                Navigator.pop(context);
              },
              child: const Text('Gata'),
            ),
          ),
        ],
      ),
    );
  }
}

class ReminderResult {
  ReminderResult.at(this.at) : remove = false, toggleDone = false;
  ReminderResult.remove() : at = null, remove = true, toggleDone = false;
  ReminderResult.toggleDone() : at = null, remove = false, toggleDone = true;

  final DateTime? at;
  final bool remove;
  final bool toggleDone;
}

Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Future<ReminderResult?> pickReminder(BuildContext context, Note note) {
  final now = DateTime.now();
  final tomorrow9 = DateTime(now.year, now.month, now.day + 1, 9);
  final nextWeek9 = DateTime(now.year, now.month, now.day + 7, 9);
  return showModalBottomSheet<ReminderResult>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (note.hasReminder) ...[
            ListTile(
              leading: Icon(
                note.reminderDone
                    ? Icons.radio_button_unchecked
                    : Icons.check_circle_outline,
              ),
              title: Text(
                note.reminderDone
                    ? 'Marchează ca nefăcut'
                    : 'Marchează ca făcut',
              ),
              subtitle: Text(formatDateTime(note.reminderAt!)),
              onTap: () => Navigator.pop(ctx, ReminderResult.toggleDone()),
            ),
            const Divider(),
          ],
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Peste o oră'),
            onTap: () => Navigator.pop(
              ctx,
              ReminderResult.at(now.add(const Duration(hours: 1))),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('Mâine, 09:00'),
            onTap: () => Navigator.pop(ctx, ReminderResult.at(tomorrow9)),
          ),
          ListTile(
            leading: const Icon(Icons.date_range_outlined),
            title: const Text('Săptămâna viitoare, 09:00'),
            onTap: () => Navigator.pop(ctx, ReminderResult.at(nextWeek9)),
          ),
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: const Text('Alege data și ora…'),
            onTap: () async {
              final at = await _pickDateTime(ctx, note.reminderAt ?? tomorrow9);
              if (at != null && ctx.mounted) {
                Navigator.pop(ctx, ReminderResult.at(at));
              }
            },
          ),
          if (note.hasReminder)
            ListTile(
              leading: const Icon(Icons.alarm_off),
              title: const Text('Elimină mementoul'),
              onTap: () => Navigator.pop(ctx, ReminderResult.remove()),
            ),
        ],
      ),
    ),
  );
}
