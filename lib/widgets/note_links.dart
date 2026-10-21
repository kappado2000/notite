import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../models/note.dart';

/// Legăturile între notițe arată ca `notite://note/<id>`.
const kNoteLinkPrefix = 'notite://note/';

String noteLink(String noteId) => '$kNoteLinkPrefix$noteId';

/// Id-ul notiței dintr-o legătură internă, sau `null` pentru linkuri web.
String? noteIdFromLink(String url) {
  if (!url.startsWith(kNoteLinkPrefix)) return null;
  final id = url.substring(kNoteLinkPrefix.length).trim();
  return id.isEmpty ? null : id;
}

/// Alegerea notiței spre care se face legătura (cu căutare).
Future<Note?> pickNoteToLink(BuildContext context, {String? exceptId}) =>
    showModalBottomSheet<Note>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<NotesStore>(),
        child: _NotePicker(exceptId: exceptId),
      ),
    );

class _NotePicker extends StatefulWidget {
  const _NotePicker({this.exceptId});
  final String? exceptId;

  @override
  State<_NotePicker> createState() => _NotePickerState();
}

class _NotePickerState extends State<_NotePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final notes = store
        .search(_query, store.activeNotes)
        .where((n) => n.id != widget.exceptId)
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              autoFocus: true,
              hintText: 'Legătură spre notița…',
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: notes.isEmpty
                ? const Center(child: Text('Nicio notiță găsită'))
                : ListView.builder(
                    controller: scroll,
                    itemCount: notes.length,
                    itemBuilder: (_, i) => ListTile(
                      leading: Icon(
                        notes[i].locked
                            ? Icons.lock_outline
                            : Icons.sticky_note_2_outlined,
                      ),
                      title: Text(notes[i].displayTitle),
                      subtitle: Text(
                        store.notebook(notes[i].notebookId)?.name ?? '',
                      ),
                      onTap: () => Navigator.pop(context, notes[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
