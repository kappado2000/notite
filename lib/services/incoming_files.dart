import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/notes_store.dart';
import '../models/attachment.dart';
import '../models/note.dart';
import '../widgets/attachment_image_embed.dart';
import 'incoming_files_stub.dart'
    if (dart.library.io) 'incoming_files_io.dart'
    as io;

/// Fișiere trimise către Notițe din meniul de partajare iOS (PDF, imagini,
/// text). Partea nativă le copiază într-un folder temporar și anunță pe
/// canalul `notite/incoming_files`; aici le transformăm în notițe.
class IncomingFiles {
  IncomingFiles._();
  static final instance = IncomingFiles._();

  static const _channel = MethodChannel('notite/incoming_files');

  /// Apelat cu notița creată, ca s-o deschidem în editor.
  void Function(Note note)? onNoteCreated;

  NotesStore? _store;
  bool _busy = false;

  /// Pornește preluarea pentru contul deschis. Fișierele primite înainte
  /// de logare așteaptă în partea nativă până acum.
  void attach(NotesStore store) {
    _store = store;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'filesReceived') await _drain();
    });
    _drain();
  }

  void detach() {
    _store = null;
    onNoteCreated = null;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _drain() async {
    final store = _store;
    if (store == null || _busy) return;
    _busy = true;
    try {
      final List<dynamic> paths;
      try {
        paths = await _channel.invokeMethod<List<dynamic>>('takePending') ?? [];
      } on MissingPluginException {
        return; // platformă fără primire de fișiere (web, Android, Windows)
      }
      for (final p in paths.cast<String>()) {
        final file = await io.readAndDelete(p);
        if (file == null) continue;
        final note = await createNoteFromFile(store, file.name, file.bytes);
        onNoteCreated?.call(note);
      }
    } catch (e) {
      debugPrint('IncomingFiles: $e');
    } finally {
      _busy = false;
    }
  }
}

/// Creează o notiță dintr-un fișier: titlul = numele fișierului (fără
/// extensie). Text → conținutul notiței; imagine → inserată în notiță;
/// PDF și restul → atașate.
Future<Note> createNoteFromFile(
  NotesStore store,
  String fileName,
  Uint8List bytes,
) async {
  final note = await store.createNote();
  final dot = fileName.lastIndexOf('.');
  note.title = dot > 0 ? fileName.substring(0, dot) : fileName;
  final mime = Attachment.mimeFromName(fileName);

  if (mime == 'text/plain') {
    final text = utf8.decode(bytes, allowMalformed: true).trimRight();
    note
      ..contentJson = jsonEncode([
        {'insert': '$text\n'},
      ])
      ..plainText = text;
  } else {
    final att = await store.addAttachment(
      noteId: note.id,
      name: fileName,
      bytes: bytes,
      mime: mime,
    );
    if (att.isImage) {
      // Imaginea apare în text, ca la „Adaugă imagine” din editor.
      note.contentJson = jsonEncode([
        {
          'insert': {kAttachmentImageEmbed: att.id},
        },
        {'insert': '\n'},
      ]);
    }
  }
  await store.saveNote(note);
  return note;
}
