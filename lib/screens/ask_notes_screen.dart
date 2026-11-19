import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../models/note.dart';
import '../services/on_device_ai.dart';
import 'note_editor_screen.dart';

/// „Întreabă notițele”: o întrebare în cuvinte obișnuite („când expiră
/// RCA-ul?”), răspunsul din notițele tale. Rulează pe telefon (Apple
/// Intelligence); notițele blocate nu sunt citite.
class AskNotesScreen extends StatefulWidget {
  const AskNotesScreen({super.key});

  @override
  State<AskNotesScreen> createState() => _AskNotesScreenState();
}

class _AskNotesScreenState extends State<AskNotesScreen> {
  final _q = TextEditingController();
  bool _busy = false;
  String? _answer;
  List<Note> _sources = const [];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final q = _q.text.trim();
    if (q.isEmpty || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _answer = null;
      _sources = const [];
    });
    try {
      final r = await OnDeviceAI.ask(q, context.read<NotesStore>().activeNotes);
      if (!mounted) return;
      setState(() {
        _answer = r.answer;
        _sources = r.sources;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _answer = 'Asistentul nu a putut răspunde: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Întreabă notițele')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _q,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _ask(),
            decoration: InputDecoration(
              hintText:
                  'Ex.: când expiră RCA-ul? ce am cumpărat de la Dedeman?',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.send),
                onPressed: _ask,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Răspunde modelul Apple de pe telefon: notițele nu pleacă de pe '
            'dispozitiv. Notițele blocate nu sunt citite. Verifică răspunsul '
            'în notița din care vine.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.outline),
          ),
          const SizedBox(height: 16),
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (_answer != null)
            Card(
              color: scheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(_answer!),
              ),
            ),
          if (_sources.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Din notițele', style: Theme.of(context).textTheme.labelLarge),
            for (final n in _sources)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(n.displayTitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteEditorScreen(noteId: n.id),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
