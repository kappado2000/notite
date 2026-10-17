import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/attachment.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../services/encryption_key_service.dart';
import '../services/reminder_service.dart';

enum NoteSort { updated, created, title }

/// Primește fiecare modificare locală, ca s-o trimită în cloud.
abstract class SyncSink {
  void noteChanged(Note note);
  void noteDeleted(String id);
  void notebookChanged(Notebook notebook);
  void notebookDeleted(String id);
  void attachmentAdded(Attachment attachment, Uint8List bytes);
  void attachmentChanged(Attachment attachment);
  void attachmentDeleted(String id);
}

/// Sursa unică de adevăr pentru notițele unui cont: notițe, carnete și
/// atașamente. Stocare locală Hive per utilizator (merge și offline);
/// modificările sunt trimise în cloud prin [sync], iar cele venite din
/// cloud intră prin metodele `applyRemote*` (ultima modificare câștigă).
class NotesStore extends ChangeNotifier {
  NotesStore(this.uid);

  static const _uuid = Uuid();

  final String uid;

  /// Conectat de sesiune după autentificare.
  SyncSink? sync;

  late Box<Map> _notesBox;
  late Box<Map> _notebooksBox;
  late Box<Map> _attachmentsBox;
  late Box<Uint8List> _blobsBox;
  late Box _settingsBox;

  final Map<String, Note> _notes = {};
  final Map<String, Notebook> _notebooks = {};
  final Map<String, Attachment> _attachments = {};

  /// Id fix pentru carnetul implicit — același pe toate dispozitivele,
  /// ca să nu apară dubluri la sincronizare.
  String get _defaultNotebookSeedId => 'implicit_$uid';

  Future<void> init() async {
    // Toate datele contului sunt criptate AES-256 pe dispozitiv.
    final cipher = await EncryptionKeyService.cipherFor(uid);
    _notesBox = await Hive.openBox<Map>('notes_$uid', encryptionCipher: cipher);
    _notebooksBox = await Hive.openBox<Map>(
      'notebooks_$uid',
      encryptionCipher: cipher,
    );
    _attachmentsBox = await Hive.openBox<Map>(
      'attachments_$uid',
      encryptionCipher: cipher,
    );
    _blobsBox = await Hive.openBox<Uint8List>(
      'blobs_$uid',
      encryptionCipher: cipher,
    );
    _settingsBox = Hive.box('settings');
    await _migrateLegacyData();

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
      await createNotebook('Primul meu carnet', id: _defaultNotebookSeedId);
    }
    // Curăță automat coșul: notițele mai vechi de 30 de zile.
    final limit = DateTime.now().subtract(const Duration(days: 30));
    for (final n in trashedNotes.where((n) => n.trashedAt!.isBefore(limit))) {
      await deleteForever(n);
    }
  }

  /// Notițele create înainte de conturi (cutii fără uid) trec în primul
  /// cont care se autentifică pe acest dispozitiv.
  Future<void> _migrateLegacyData() async {
    if (_notesBox.isNotEmpty || _notebooksBox.isNotEmpty) return;
    if (!await Hive.boxExists('notebooks')) return;
    Future<void> copy<T>(String name, Box<T> target) async {
      final legacy = await Hive.openBox<T>(name);
      await target.putAll(Map<dynamic, T>.from(legacy.toMap()));
      await legacy.deleteFromDisk();
    }

    await copy<Map>('notebooks', _notebooksBox);
    await copy<Map>('notes', _notesBox);
    await copy<Map>('attachments', _attachmentsBox);
    await copy<Uint8List>('blobs', _blobsBox);
  }

  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    sync = null;
    await _notesBox.close();
    await _notebooksBox.close();
    await _attachmentsBox.close();
    await _blobsBox.close();
  }

  /// Șterge de pe dispozitiv toate datele acestui cont.
  Future<void> wipeLocal() async {
    _closed = true;
    sync = null;
    await EncryptionKeyService.deleteFor(uid);
    await _notesBox.deleteFromDisk();
    await _notebooksBox.deleteFromDisk();
    await _attachmentsBox.deleteFromDisk();
    await _blobsBox.deleteFromDisk();
    await _settingsBox.delete('defaultNotebook_$uid');
  }

  // ---------------------------------------------------------------- setări

  NoteSort get sort => NoteSort.values[(_settingsBox.get('sort') as int?) ?? 0];
  set sort(NoteSort v) {
    _settingsBox.put('sort', v.index);
    notifyListeners();
  }

  String get defaultNotebookId {
    final id = _settingsBox.get('defaultNotebook_$uid') as String?;
    if (id != null && _notebooks.containsKey(id)) return id;
    return notebooks.first.id;
  }

  set defaultNotebookId(String id) {
    _settingsBox.put('defaultNotebook_$uid', id);
    notifyListeners();
  }

  // --------------------------------------------------------------- carnete

  List<Notebook> get notebooks =>
      _notebooks.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Notebook? notebook(String id) => _notebooks[id];

  int notebookCount(String id) =>
      activeNotes.where((n) => n.notebookId == id).length;

  Future<Notebook> createNotebook(String name, {String? id}) async {
    final now = DateTime.now();
    final nb = Notebook(
      id: id ?? _uuid.v4(),
      name: name.trim(),
      createdAt: now,
      updatedAt: now,
    );
    _notebooks[nb.id] = nb;
    await _notebooksBox.put(nb.id, nb.toMap());
    sync?.notebookChanged(nb);
    notifyListeners();
    return nb;
  }

  Future<void> renameNotebook(Notebook nb, String name) async {
    nb
      ..name = name.trim()
      ..updatedAt = DateTime.now();
    await _notebooksBox.put(nb.id, nb.toMap());
    sync?.notebookChanged(nb);
    notifyListeners();
  }

  /// Șterge carnetul; notițele lui ajung în coș (ca în Evernote).
  /// Trebuie să rămână cel puțin un carnet.
  Future<bool> deleteNotebook(Notebook nb) async {
    if (_notebooks.length <= 1) return false;
    _notebooks.remove(nb.id);
    await _notebooksBox.delete(nb.id);
    sync?.notebookDeleted(nb.id);
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
    if (_closed) return;
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
    sync?.noteDeleted(note.id);
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

  Future<void> _persist(Note n) async {
    if (_closed) return; // ex. editor închis după deconectare
    await _notesBox.put(n.id, n.toMap());
    sync?.noteChanged(n);
  }

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
    sync?.attachmentAdded(a, bytes);
    final note = _notes[noteId];
    if (note != null) await saveNote(note);
    notifyListeners();
    return a;
  }

  Future<void> setOcrText(Attachment a, String text) async {
    a.ocrText = text;
    await _attachmentsBox.put(a.id, a.toMap());
    sync?.attachmentChanged(a);
    notifyListeners();
  }

  Future<void> removeAttachment(Attachment a) async {
    await _removeAttachmentData(a);
    final note = _notes[a.noteId];
    if (note != null) await saveNote(note);
    notifyListeners();
  }

  Future<void> _removeAttachmentData(
    Attachment a, {
    bool remote = false,
  }) async {
    _attachments.remove(a.id);
    await _attachmentsBox.delete(a.id);
    await _blobsBox.delete(a.id);
    if (!remote) sync?.attachmentDeleted(a.id);
  }

  // ------------------------------------------- modificări venite din cloud

  Iterable<Note> get allNotes => _notes.values;
  Iterable<Notebook> get allNotebooks => _notebooks.values;
  Iterable<Attachment> get allAttachments => _attachments.values;

  bool hasBlob(String attachmentId) => _blobsBox.containsKey(attachmentId);

  DateTime? noteUpdatedAt(String id) => _notes[id]?.updatedAt;
  DateTime? notebookUpdatedAt(String id) => _notebooks[id]?.updatedAt;

  Future<void> applyRemoteNote(Map<String, dynamic> m) async {
    final remote = Note.fromMap(m);
    final local = _notes[remote.id];
    if (local != null && !remote.updatedAt.isAfter(local.updatedAt)) return;
    _notes[remote.id] = remote;
    await _notesBox.put(remote.id, remote.toMap());
    await ReminderService.instance.sync(remote);
    notifyListeners();
  }

  Future<void> applyRemoteNoteDeleted(String id) async {
    final local = _notes.remove(id);
    if (local == null) return;
    await ReminderService.instance.cancel(local);
    for (final a in attachmentsOf(id)) {
      await _removeAttachmentData(a, remote: true);
    }
    await _notesBox.delete(id);
    notifyListeners();
  }

  Future<void> applyRemoteNotebook(Map<String, dynamic> m) async {
    final remote = Notebook.fromMap(m);
    final local = _notebooks[remote.id];
    if (local != null && !remote.updatedAt.isAfter(local.updatedAt)) return;
    _notebooks[remote.id] = remote;
    await _notebooksBox.put(remote.id, remote.toMap());
    notifyListeners();
  }

  Future<void> applyRemoteNotebookDeleted(String id) async {
    // Păstrăm măcar un carnet; notițele lui vin separat (deja mutate).
    if (!_notebooks.containsKey(id) || _notebooks.length <= 1) return;
    _notebooks.remove(id);
    await _notebooksBox.delete(id);
    notifyListeners();
  }

  Future<void> applyRemoteAttachment(
    Map<String, dynamic> m,
    Uint8List? bytes,
  ) async {
    final remote = Attachment.fromMap(m);
    final local = _attachments[remote.id];
    if (local != null) {
      if (remote.ocrText.isNotEmpty && local.ocrText != remote.ocrText) {
        local.ocrText = remote.ocrText;
        await _attachmentsBox.put(local.id, local.toMap());
        notifyListeners();
      }
      return;
    }
    if (bytes == null) return;
    _attachments[remote.id] = remote;
    await _blobsBox.put(remote.id, bytes);
    await _attachmentsBox.put(remote.id, remote.toMap());
    notifyListeners();
  }

  Future<void> applyRemoteAttachmentDeleted(String id) async {
    final local = _attachments[id];
    if (local == null) return;
    await _removeAttachmentData(local, remote: true);
    notifyListeners();
  }
}
