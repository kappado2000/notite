import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/attachment.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../services/reminder_service.dart';

enum NoteSort { updated, created, title }

/// Sursa unică de adevăr pentru notițe, carnete și atașamente.
/// Stocare locală Hive (merge și pe web); sincronizarea Firebase se va
/// conecta aici, pe baza câmpurilor `updatedAt`.
class NotesStore extends ChangeNotifier {
  static const _uuid = Uuid();

  late Box<Map> _notesBox;
  late Box<Map> _notebooksBox;
  late Box<Map> _attachmentsBox;
  late Box<Uint8List> _blobsBox;
  late Box _settingsBox;

  final Map<String, Note> _notes = {};
  final Map<String, Notebook> _notebooks = {};
  final Map<String, Attachment> _attachments = {};

  Future<void> init() async {
    await Hive.initFlutter('notite');
    _notesBox = await Hive.openBox<Map>('notes');
    _notebooksBox = await Hive.openBox<Map>('notebooks');
    _attachmentsBox = await Hive.openBox<Map>('attachments');
    _blobsBox = await Hive.openBox<Uint8List>('blobs');
    _settingsBox = await Hive.openBox('settings');

    for (final m in _notesBox.values) {
      final n = Note.fromMap(m);
      _notes[n.id] = n;
    }
    for (final m in _notebooksBox.values) {
      final nb = Notebook.fromMap(m);
      _notebooks[nb.id] = nb;
    }
    for (final m in _attachmentsBox.values) {
      final a = Attachment.fromMap(m);
      _attachments[a.id] = a;
    }
    if (_notebooks.isEmpty) {
      final nb = await createNotebook('Primul meu carnet');
      defaultNotebookId = nb.id;
    }
    // Curăță automat coșul: notițele mai vechi de 30 de zile.
    final limit = DateTime.now().subtract(const Duration(days: 30));
    for (final n in trashedNotes.where((n) => n.trashedAt!.isBefore(limit))) {
      await deleteForever(n);
    }
  }

  // ---------------------------------------------------------------- setări

  ThemeMode get themeMode =>
      ThemeMode.values[(_settingsBox.get('themeMode') as int?) ?? 0];
  set themeMode(ThemeMode v) {
    _settingsBox.put('themeMode', v.index);
    notifyListeners();
  }

  NoteSort get sort => NoteSort.values[(_settingsBox.get('sort') as int?) ?? 0];
  set sort(NoteSort v) {
    _settingsBox.put('sort', v.index);
    notifyListeners();
  }

  String get defaultNotebookId {
    final id = _settingsBox.get('defaultNotebook') as String?;
    if (id != null && _notebooks.containsKey(id)) return id;
    return notebooks.first.id;
  }

  set defaultNotebookId(String id) {
    _settingsBox.put('defaultNotebook', id);
    notifyListeners();
  }

  // --------------------------------------------------------------- carnete

  List<Notebook> get notebooks =>
      _notebooks.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Notebook? notebook(String id) => _notebooks[id];

  int notebookCount(String id) =>
      activeNotes.where((n) => n.notebookId == id).length;

  Future<Notebook> createNotebook(String name) async {
    final now = DateTime.now();
    final nb = Notebook(
      id: _uuid.v4(),
      name: name.trim(),
      createdAt: now,
      updatedAt: now,
    );
    _notebooks[nb.id] = nb;
    await _notebooksBox.put(nb.id, nb.toMap());
    notifyListeners();
    return nb;
  }

  Future<void> renameNotebook(Notebook nb, String name) async {
    nb
      ..name = name.trim()
      ..updatedAt = DateTime.now();
    await _notebooksBox.put(nb.id, nb.toMap());
    notifyListeners();
  }

  /// Șterge carnetul; notițele lui ajung în coș (ca în Evernote).
  /// Trebuie să rămână cel puțin un carnet.
  Future<bool> deleteNotebook(Notebook nb) async {
    if (_notebooks.length <= 1) return false;
    _notebooks.remove(nb.id);
    await _notebooksBox.delete(nb.id);
    final fallback = defaultNotebookId;
    for (final n in _notes.values.where((n) => n.notebookId == nb.id)) {
      n.notebookId = fallback;
      if (!n.isTrashed) n.trashedAt = DateTime.now();
      n.updatedAt = DateTime.now();
      await _persist(n);
    }
    notifyListeners();
    return true;
  }

  // --------------------------------------------------------------- notițe

  Note? note(String id) => _notes[id];

  List<Note> get activeNotes =>
      _sorted(_notes.values.where((n) => !n.isTrashed));

  List<Note> get trashedNotes =>
      _notes.values.where((n) => n.isTrashed).toList()
        ..sort((a, b) => b.trashedAt!.compareTo(a.trashedAt!));

  List<Note> get pinnedNotes => activeNotes.where((n) => n.pinned).toList();

  /// Mementourile active primele (cronologic), apoi cele bifate.
  List<Note> get reminderNotes {
    final list = activeNotes.where((n) => n.hasReminder).toList();
    list.sort((a, b) {
      if (a.reminderDone != b.reminderDone) return a.reminderDone ? 1 : -1;
      return a.reminderAt!.compareTo(b.reminderAt!);
    });
    return list;
  }

  List<Note> notesInNotebook(String id) =>
      activeNotes.where((n) => n.notebookId == id).toList();

  List<Note> notesWithTag(String tag) =>
      activeNotes.where((n) => n.tags.contains(tag)).toList();

  List<String> get allTags {
    final counts = <String, int>{};
    for (final n in activeNotes) {
      for (final t in n.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  int tagCount(String tag) => notesWithTag(tag).length;

  List<Note> _sorted(Iterable<Note> notes) {
    final list = notes.toList();
    switch (sort) {
      case NoteSort.updated:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case NoteSort.created:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case NoteSort.title:
        list.sort(
          (a, b) => a.displayTitle.toLowerCase().compareTo(
            b.displayTitle.toLowerCase(),
          ),
        );
    }
    // Notițele fixate rămân sus.
    final pinned = list.where((n) => n.pinned);
    final rest = list.where((n) => !n.pinned);
    return [...pinned, ...rest];
  }

  /// Căutare: toate cuvintele trebuie să apară în titlu, text, etichete,
  /// numele atașamentelor sau textul OCR. Fără diacritice și majuscule.
  List<Note> search(String query, Iterable<Note> scope) {
    final words = _fold(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return scope.toList();
    return scope.where((n) {
      final buf = StringBuffer()
        ..write(n.title)
        ..write(' ')
        ..write(n.plainText)
        ..write(' ')
        ..write(n.tags.join(' '));
      for (final a in attachmentsOf(n.id)) {
        buf
          ..write(' ')
          ..write(a.name)
          ..write(' ')
          ..write(a.ocrText);
      }
      final hay = _fold(buf.toString());
      return words.every(hay.contains);
    }).toList();
  }

  static String _fold(String s) {
    const from = 'ăâîșşțţĂÂÎȘŞȚŢ';
    const to = 'aaissttaaisstt';
    final sb = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      sb.write(i >= 0 ? to[i] : ch);
    }
    return sb.toString().toLowerCase();
  }

  Future<Note> createNote({String? notebookId, String? tag}) async {
    final now = DateTime.now();
    final note = Note(
      id: _uuid.v4(),
      notebookId: notebookId ?? defaultNotebookId,
      contentJson: Note.emptyContent,
      tags: tag == null ? null : [tag],
      createdAt: now,
      updatedAt: now,
    );
    _notes[note.id] = note;
    await _persist(note);
    notifyListeners();
    return note;
  }

  Future<void> saveNote(Note note) async {
    note.updatedAt = DateTime.now();
    await _persist(note);
    notifyListeners();
  }

  Future<void> togglePin(Note note) async {
    note.pinned = !note.pinned;
    await saveNote(note);
  }

  Future<void> setReminder(Note note, DateTime? at) async {
    note
      ..reminderAt = at
      ..reminderDone = false;
    await saveNote(note);
    await ReminderService.instance.sync(note);
  }

  Future<void> toggleReminderDone(Note note) async {
    note.reminderDone = !note.reminderDone;
    await saveNote(note);
    await ReminderService.instance.sync(note);
  }

  Future<void> trash(Note note) async {
    note.trashedAt = DateTime.now();
    await saveNote(note);
    await ReminderService.instance.cancel(note);
  }

  Future<void> restore(Note note) async {
    note.trashedAt = null;
    if (!_notebooks.containsKey(note.notebookId)) {
      note.notebookId = defaultNotebookId;
    }
    await saveNote(note);
    await ReminderService.instance.sync(note);
  }

  Future<void> deleteForever(Note note) async {
    await ReminderService.instance.cancel(note);
    for (final a in attachmentsOf(note.id)) {
      await _removeAttachmentData(a);
    }
    _notes.remove(note.id);
    await _notesBox.delete(note.id);
    notifyListeners();
  }

  Future<void> emptyTrash() async {
    for (final n in trashedNotes) {
      await deleteForever(n);
    }
  }

  Future<void> renameTag(String oldTag, String newTag) async {
    newTag = newTag.trim();
    for (final n in _notes.values.where((n) => n.tags.contains(oldTag))) {
      n.tags = {...n.tags.map((t) => t == oldTag ? newTag : t)}.toList();
      await saveNote(n);
    }
  }

  Future<void> deleteTag(String tag) async {
    for (final n in _notes.values.where((n) => n.tags.contains(tag))) {
      n.tags.remove(tag);
      await saveNote(n);
    }
  }

  Future<void> _persist(Note n) => _notesBox.put(n.id, n.toMap());

  // ----------------------------------------------------------- atașamente

  Attachment? attachment(String id) => _attachments[id];

  List<Attachment> attachmentsOf(String noteId) =>
      _attachments.values.where((a) => a.noteId == noteId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Attachment? firstImageOf(String noteId) {
    for (final a in attachmentsOf(noteId)) {
      if (a.isImage) return a;
    }
    return null;
  }

  Uint8List? bytesOf(String attachmentId) => _blobsBox.get(attachmentId);

  Future<Attachment> addAttachment({
    required String noteId,
    required String name,
    required Uint8List bytes,
    String? mime,
    String ocrText = '',
  }) async {
    final a = Attachment(
      id: _uuid.v4(),
      noteId: noteId,
      name: name,
      mime: mime ?? Attachment.mimeFromName(name),
      size: bytes.length,
      createdAt: DateTime.now(),
      ocrText: ocrText,
    );
    _attachments[a.id] = a;
    await _blobsBox.put(a.id, bytes);
    await _attachmentsBox.put(a.id, a.toMap());
    final note = _notes[noteId];
    if (note != null) await saveNote(note);
    notifyListeners();
    return a;
  }

  Future<void> setOcrText(Attachment a, String text) async {
    a.ocrText = text;
    await _attachmentsBox.put(a.id, a.toMap());
    notifyListeners();
  }

  Future<void> removeAttachment(Attachment a) async {
    await _removeAttachmentData(a);
    final note = _notes[a.noteId];
    if (note != null) await saveNote(note);
    notifyListeners();
  }

  Future<void> _removeAttachmentData(Attachment a) async {
    _attachments.remove(a.id);
    await _attachmentsBox.delete(a.id);
    await _blobsBox.delete(a.id);
  }
}
