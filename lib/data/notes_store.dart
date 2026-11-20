import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/attachment.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../models/secret_item.dart';
import '../services/encryption_key_service.dart';
import '../services/password_tools.dart';
import '../services/reminder_service.dart';
import '../theme.dart';

enum NoteSort { updated, created, title, docDate }

/// Primește fiecare modificare locală, ca s-o trimită în cloud.
abstract class SyncSink {
  void noteChanged(Note note);
  void noteDeleted(String id);
  void notebookChanged(Notebook notebook);
  void notebookDeleted(String id);
  void attachmentAdded(Attachment attachment, Uint8List bytes);
  void attachmentChanged(Attachment attachment);
  void attachmentDeleted(String id);
  void secretChanged(SecretItem item);
  void secretDeleted(String id);
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
  late Box<Map> _secretsBox;
  late Box _settingsBox;

  final Map<String, Note> _notes = {};
  final Map<String, Notebook> _notebooks = {};
  final Map<String, Attachment> _attachments = {};
  final Map<String, SecretItem> _secrets = {};

  /// Id fix pentru carnetul implicit — același pe toate dispozitivele,
  /// ca să nu apară dubluri la sincronizare.
  String get _defaultNotebookSeedId => 'implicit_$uid';

  Future<void> init() async {
    _settingsBox = Hive.box('settings');
    try {
      await _openBoxes();
    } catch (e) {
      // Datele locale nu se pot decripta (ex. cheia din seif s-a pierdut).
      // Le abandonăm și pornim cu un spațiu local nou: totul revine din
      // cloud prin sincronizare. Nu ștergem baza veche — pe web ștergerea
      // IndexedDB se poate bloca; datele ei rămân oricum de necitit.
      debugPrint('NotesStore: date locale ilizibile, se reiau din cloud ($e)');
      await _settingsBox.put('boxGeneration_$uid', _generation + 1);
      await _openBoxes();
    }
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
    for (final m in _secretsBox.values) {
      final i = SecretItem.fromMap(m);
      _secrets[i.id] = i;
    }
    if (_notebooks.isEmpty) {
      await createNotebook('Primul meu carnet', id: _defaultNotebookSeedId);
    }
    await purgeExpiredTrash();
  }

  /// Șterge definitiv notițele aflate în coș de peste 30 de zile. Rulează la
  /// pornire și la intrarea în coș (aplicația poate sta deschisă zile).
  Future<int> purgeExpiredTrash() async {
    final limit = DateTime.now().subtract(const Duration(days: Note.trashDays));
    final expired = trashedNotes
        .where((n) => n.trashedAt!.isBefore(limit))
        .toList();
    for (final n in expired) {
      await deleteForever(n);
    }
    final oldSecrets = trashedSecrets
        .where((i) => i.deletedAt!.isBefore(limit))
        .toList();
    for (final i in oldSecrets) {
      await purgeSecret(i);
    }
    return expired.length + oldSecrets.length;
  }

  int get _generation => (_settingsBox.get('boxGeneration_$uid') as int?) ?? 0;

  String _boxName(String base) =>
      _generation == 0 ? '${base}_$uid' : '${base}_${uid}_g$_generation';

  /// Toate datele contului sunt criptate AES-256 pe dispozitiv.
  Future<void> _openBoxes() async {
    final cipher = await EncryptionKeyService.cipherFor(uid);
    Future<Box<T>> open<T>(String base) async {
      final box = await Hive.openBox<T>(
        _boxName(base),
        encryptionCipher: cipher,
      );
      // Citirea forțează decriptarea: o cheie greșită aruncă eroare aici.
      box.values.toList();
      return box;
    }

    _notesBox = await open<Map>('notes');
    _notebooksBox = await open<Map>('notebooks');
    _attachmentsBox = await open<Map>('attachments');
    _blobsBox = await open<Uint8List>('blobs');
    _secretsBox = await open<Map>('secrets');
  }

  /// Notițele create înainte de conturi (cutii fără uid) trec în primul
  /// cont care se autentifică pe acest dispozitiv.
  Future<void> _migrateLegacyData() async {
    // O singură dată per dispozitiv. Nu folosim Hive.boxExists/deleteFromDisk:
    // pe web lasă o conexiune IndexedDB deschisă și ștergerea se blochează.
    if (_settingsBox.get('legacyMigrated') == true) return;
    if (_notesBox.isEmpty && _notebooksBox.isEmpty) {
      // Carnetul implicit vechi primește id-ul comun tuturor dispozitivelor,
      // altfel ar apărea două „Primul meu carnet” după sincronizare.
      String? oldDefaultId;

      final notebooks = await Hive.openBox<Map>('notebooks');
      for (final e in notebooks.toMap().entries) {
        var key = e.key;
        var value = e.value;
        if (oldDefaultId == null && value['name'] == 'Primul meu carnet') {
          oldDefaultId = key as String;
          key = _defaultNotebookSeedId;
          value = {...value, 'id': _defaultNotebookSeedId};
        }
        await _notebooksBox.put(key, value);
      }
      await notebooks.clear();
      await notebooks.close();

      final notes = await Hive.openBox<Map>('notes');
      for (final e in notes.toMap().entries) {
        final value = e.value['notebookId'] == oldDefaultId
            ? {...e.value, 'notebookId': _defaultNotebookSeedId}
            : e.value;
        await _notesBox.put(e.key, value);
      }
      await notes.clear();
      await notes.close();

      Future<void> copy<T>(String name, Box<T> target) async {
        final legacy = await Hive.openBox<T>(name);
        if (legacy.isNotEmpty) {
          await target.putAll(Map<dynamic, T>.from(legacy.toMap()));
          await legacy.clear();
        }
        await legacy.close();
      }

      await copy<Map>('attachments', _attachmentsBox);
      await copy<Uint8List>('blobs', _blobsBox);
    }
    await _settingsBox.put('legacyMigrated', true);
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
    await _secretsBox.close();
  }

  /// Șterge de pe dispozitiv toate datele acestui cont.
  Future<void> wipeLocal() async {
    _closed = true;
    sync = null;
    await EncryptionKeyService.deleteFor(uid);
    // Golire + închidere, nu deleteFromDisk: pe web ștergerea bazei
    // IndexedDB se poate bloca la nesfârșit. Datele dispar oricum.
    for (final box in <Box>[
      _notesBox,
      _notebooksBox,
      _attachmentsBox,
      _blobsBox,
      _secretsBox,
    ]) {
      await box.clear();
      await box.close();
    }
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

  /// Nuanța carnetului (index în `GroupTint.all`). Cea aleasă de user
  /// (`color` 1…8); altfel una automată, după ordinea creării, ca fiecare
  /// carnet să arate diferit.
  int tintOf(Notebook nb) {
    if (nb.color > 0) return nb.color - 1;
    final ordered = _notebooks.values.toList()
      ..sort((a, b) {
        final c = a.createdAt.compareTo(b.createdAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return ordered.indexOf(nb) % tintCount;
  }

  static const tintCount = 8;

  /// Nuanța completă a carnetului: culoarea, intensitatea și scrisul.
  GroupTint notebookTint(Notebook nb) =>
      GroupTint.at(tintOf(nb))
          .styled(level: nb.intensity, text: TintText.values[nb.textMode % 3]);

  /// Prima nuanță nefolosită de alt carnet (sau cea mai puțin folosită).
  int freeTint() {
    final used = List.filled(tintCount, 0);
    for (final nb in _notebooks.values) {
      used[tintOf(nb) % tintCount]++;
    }
    var best = 0;
    for (var i = 1; i < tintCount; i++) {
      if (used[i] < used[best]) best = i;
    }
    return best;
  }

  int notebookCount(String id) =>
      activeNotes.where((n) => n.notebookId == id).length;

  Future<Notebook> createNotebook(
    String name, {
    String? id,
    String emoji = '📒',
    int color = 0,
  }) async {
    final now = DateTime.now();
    final nb = Notebook(
      id: id ?? _uuid.v4(),
      name: name.trim(),
      createdAt: now,
      updatedAt: now,
      emoji: emoji,
      color: color > 0 ? color : freeTint() + 1,
    );
    _notebooks[nb.id] = nb;
    await _notebooksBox.put(nb.id, nb.toMap());
    sync?.notebookChanged(nb);
    notifyListeners();
    return nb;
  }

  Future<void> updateNotebook(
    Notebook nb, {
    required String name,
    required String emoji,
    required int color,
    int? intensity,
    int? textMode,
  }) async {
    nb
      ..name = name.trim()
      ..emoji = emoji
      ..color = color
      ..intensity = intensity ?? nb.intensity
      ..textMode = textMode ?? nb.textMode
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

  static final _titleDate = RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{4})');

  /// Data documentului: cea din titlu (bonuri: „Bon · Lidl · 14.11.2026”),
  /// altfel data creării notiței.
  static DateTime docDate(Note n) {
    final m = _titleDate.firstMatch(n.title);
    if (m != null) {
      final d = DateTime.tryParse(
        '${m[3]}-${m[2]!.padLeft(2, '0')}-${m[1]!.padLeft(2, '0')}',
      );
      if (d != null) return d;
    }
    return n.createdAt;
  }

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
      case NoteSort.docDate:
        list.sort((a, b) => docDate(b).compareTo(docDate(a)));
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
        ..write(n.tags.join(' '));
      // La notițele blocate se caută doar în titlu și etichete.
      if (!n.locked) {
        buf
          ..write(' ')
          ..write(n.plainText);
      }
      for (final a in n.locked ? const <Attachment>[] : attachmentsOf(n.id)) {
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

  /// Text pentru comparat/sortat: fără diacritice, cu litere mici.
  static String foldText(String s) => _fold(s);

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

  Future<void> setLocked(Note note, bool locked) async {
    note.locked = locked;
    await saveNote(note);
    await ReminderService.instance.sync(note);
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

  // ------------------------------------------------- semnătura salvată

  /// Semnătura desenată pentru PDF-uri, păstrată criptat doar pe acest
  /// dispozitiv (nu se sincronizează și nu intră în backup).
  static const _signatureKey = '_semnatura';

  Uint8List? get savedSignature => _blobsBox.get(_signatureKey);

  Future<void> saveSignature(Uint8List? png) => png == null
      ? _blobsBox.delete(_signatureKey)
      : _blobsBox.put(_signatureKey, png);

  // ------------------------------------------------------- backup local

  /// Datele contului pentru un fișier de backup (fără parole: fișierul nu
  /// e criptat). Atașamentele sunt incluse, codate base64.
  ///
  /// [withSecrets]: și parolele cu atașamentele lor — DOAR pentru backup-ul
  /// criptat ([FullBackup]).
  Map<String, dynamic> exportBackup({bool withSecrets = false}) => {
    'format': 'notite-backup',
    'version': 1,
    'createdAt': DateTime.now().millisecondsSinceEpoch,
    'notebooks': [for (final nb in _notebooks.values) nb.toMap()],
    'notes': [for (final n in _notes.values) n.toMap()],
    'attachments': [
      for (final a in _attachments.values)
        if (withSecrets || !a.noteId.startsWith('secret:'))
          if (_blobsBox.get(a.id) case final bytes?)
            {...a.toMap(), 'data': base64Encode(bytes)},
    ],
    if (withSecrets) 'secrets': [for (final i in _secrets.values) i.toMap()],
  };

  /// Spațiul ocupat de date (aproximativ cât ocupă și în cloud): atașamente
  /// și text (notițe, carnete, parole).
  ({int attachmentBytes, int attachments, int textBytes}) storageUsage() {
    var att = 0;
    for (final a in _attachments.values) {
      att += a.size;
    }
    var text = 0;
    for (final m in [
      ..._notesBox.values,
      ..._notebooksBox.values,
      ..._secretsBox.values,
      ..._attachmentsBox.values,
    ]) {
      text += jsonEncode(m, toEncodable: (o) => o.toString()).length;
    }
    return (
      attachmentBytes: att,
      attachments: _attachments.length,
      textBytes: text,
    );
  }

  /// Restaurează dintr-un backup. Nu dublează nimic: elementele existente
  /// rămân; o notiță existentă e înlocuită doar dacă cea din backup e mai
  /// nouă. Tot ce se adaugă e și sincronizat în cloud.
  Future<({int notebooks, int notes, int attachments, int secrets})>
  importBackup(Map<String, dynamic> data) async {
    if (data['format'] != 'notite-backup') {
      throw const FormatException('Fișierul nu este un backup Notițe.');
    }
    var nbs = 0, notes = 0, atts = 0;
    for (final m in (data['notebooks'] as List? ?? const [])) {
      final nb = Notebook.fromMap(m as Map);
      if (_notebooks.containsKey(nb.id)) continue;
      _notebooks[nb.id] = nb;
      await _notebooksBox.put(nb.id, nb.toMap());
      sync?.notebookChanged(nb);
      nbs++;
    }
    for (final m in (data['notes'] as List? ?? const [])) {
      final n = Note.fromMap(m as Map);
      final local = _notes[n.id];
      if (local != null && !n.updatedAt.isAfter(local.updatedAt)) continue;
      if (!_notebooks.containsKey(n.notebookId)) {
        n.notebookId = defaultNotebookId;
      }
      _notes[n.id] = n;
      await _persist(n);
      await ReminderService.instance.sync(n);
      notes++;
    }
    // parolele (doar din backup-ul criptat): se adaugă cele lipsă și se
    // înlocuiesc cele mai vechi decât în backup
    var secrets = 0;
    for (final m in (data['secrets'] as List? ?? const [])) {
      final i = SecretItem.fromMap(m as Map);
      final local = _secrets[i.id];
      if (local != null && !i.updatedAt.isAfter(local.updatedAt)) continue;
      _secrets[i.id] = i;
      await _secretsBox.put(i.id, i.toMap());
      sync?.secretChanged(i);
      await ReminderService.instance.syncSecret(i);
      secrets++;
    }
    for (final m in (data['attachments'] as List? ?? const [])) {
      final map = m as Map;
      final a = Attachment.fromMap(map);
      final owner = a.noteId.startsWith('secret:')
          ? _secrets.containsKey(a.noteId.substring(7))
          : _notes.containsKey(a.noteId);
      if (_attachments.containsKey(a.id) || !owner) {
        continue;
      }
      final bytes = base64Decode(map['data'] as String);
      _attachments[a.id] = a;
      await _blobsBox.put(a.id, bytes);
      await _attachmentsBox.put(a.id, a.toMap());
      sync?.attachmentAdded(a, bytes);
      atts++;
    }
    notifyListeners();
    return (notebooks: nbs, notes: notes, attachments: atts, secrets: secrets);
  }

  // ------------------------------------------------------------- parole

  List<SecretItem> get secrets => allSecrets.toList()
    ..sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return a.displayTitle.toLowerCase().compareTo(
        b.displayTitle.toLowerCase(),
      );
    });

  /// Conturile active (fără cele din coș).
  Iterable<SecretItem> get allSecrets =>
      _secrets.values.where((i) => !i.isTrashed);

  /// Coșul parolelor: cele mai recent șterse primele.
  List<SecretItem> get trashedSecrets =>
      _secrets.values.where((i) => i.isTrashed).toList()
        ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));

  SecretItem? secret(String id) {
    final i = _secrets[id];
    return i == null || i.isTrashed ? null : i;
  }

  /// Numele dispozitivului, pentru jurnalul ștergerilor.
  static String get deviceLabel {
    if (kIsWeb) return 'PC (Notițe web)';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'iPhone / iPad',
      TargetPlatform.android => 'Android',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows => 'PC (Windows)',
      _ => 'alt dispozitiv',
    };
  }

  static final _scheme = RegExp(r'https?://|www\.');

  /// Căutare în parole. „http://”, „https://” și „www.” din adrese nu se
  /// iau în seamă (altfel „tp” s-ar potrivi cu orice site). Rezultatele
  /// sunt ordonate după cât de bine se potrivesc: întâi titlurile care
  /// încep cu textul căutat (TP-Link pentru „tp”), apoi cuvinte din titlu
  /// care încep cu el, apoi titlul care îl conține, apoi utilizatorul,
  /// apoi restul (site, notițe).
  List<SecretItem> searchSecrets(String query, Iterable<SecretItem> scope) {
    final words = _fold(query)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return scope.toList();
    final first = words.first;
    int rank(SecretItem i) {
      final title = _fold(i.displayTitle);
      if (title.startsWith(first)) return 0;
      if (title.split(RegExp(r'[^a-z0-9]+')).any((w) => w.startsWith(first))) {
        return 1;
      }
      if (title.contains(first)) return 2;
      if (_fold(i.username).contains(first)) return 3;
      return 4;
    }

    final hits = [
      for (final i in scope)
        if (_fold(i.searchText).replaceAll(_scheme, ' ') case final text
            when words.every(text.contains))
          (i, rank(i)),
    ];
    hits.sort((a, b) {
      final r = a.$2.compareTo(b.$2);
      return r != 0
          ? r
          : _fold(a.$1.displayTitle).compareTo(_fold(b.$1.displayTitle));
    });
    return [for (final h in hits) h.$1];
  }

  SecretItem newSecret(SecretType type) {
    final now = DateTime.now();
    return SecretItem(
      id: _uuid.v4(),
      type: type,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> saveSecret(SecretItem item) async {
    if (_closed) return;
    final previous = _secrets[item.id];
    if (previous != null && previous.password != item.password) {
      item.passwordChangedAt = DateTime.now();
      // Istoric: parola veche intră prima în listă (max. 10).
      if (previous.password.isNotEmpty) {
        item.passwordHistory = [
          PasswordVersion(previous.password, DateTime.now()),
          ...previous.passwordHistory.where((p) => p.password != item.password),
        ].take(10).toList();
      }
    }
    // parola nouă „în curs” a ajuns parola contului: schimbarea s-a încheiat
    if (item.pendingPassword.isNotEmpty &&
        item.pendingPassword == item.password) {
      item.pendingPassword = '';
    }
    item.updatedAt = DateTime.now();
    _secrets[item.id] = item;
    await _secretsBox.put(item.id, item.toMap());
    sync?.secretChanged(item);
    await ReminderService.instance.syncSecret(item);
    notifyListeners();
  }

  /// Adaugă mai multe intrări odată (import CSV).
  Future<void> addSecrets(List<SecretItem> items) async {
    if (_closed) return;
    for (final item in items) {
      _secrets[item.id] = item;
      await _secretsBox.put(item.id, item.toMap());
      sync?.secretChanged(item);
    }
    notifyListeners();
  }

  /// Ștergere = mutare în coș (30 de zile, criptat și sincronizat ca orice
  /// cont), cu jurnal: când, de pe ce dispozitiv și de ce.
  Future<void> deleteSecret(
    SecretItem item, {
    String why = 'Șters de tine',
  }) async {
    if (_closed) return;
    final t = (_secrets[item.id] ?? item).copy()
      ..deletedAt = DateTime.now()
      ..deletedFrom = deviceLabel
      ..deletedWhy = why
      ..updatedAt = DateTime.now();
    _secrets[t.id] = t;
    await _secretsBox.put(t.id, t.toMap());
    sync?.secretChanged(t);
    await ReminderService.instance.cancelSecret(t.id);
    notifyListeners();
  }

  /// Scoate contul din coș.
  Future<void> restoreSecret(SecretItem item) async {
    if (_closed) return;
    final r = (_secrets[item.id] ?? item).copy()
      ..deletedAt = null
      ..deletedFrom = ''
      ..deletedWhy = ''
      ..updatedAt = DateTime.now();
    _secrets[r.id] = r;
    await _secretsBox.put(r.id, r.toMap());
    sync?.secretChanged(r);
    await ReminderService.instance.syncSecret(r);
    notifyListeners();
  }

  /// Ștergere definitivă (din coș, sau după 30 de zile).
  Future<void> purgeSecret(SecretItem item) async {
    if (_closed) return;
    _secrets.remove(item.id);
    await _secretsBox.delete(item.id);
    sync?.secretDeleted(item.id);
    await ReminderService.instance.cancelSecret(item.id);
    for (final a in attachmentsOf(item.attachmentOwnerId)) {
      await _removeAttachmentData(a);
    }
    notifyListeners();
  }

  DateTime? secretUpdatedAt(String id) => _secrets[id]?.updatedAt;

  /// Unește dublurile: același site și utilizator (parola cea mai nouă
  /// rămâne, celelalte intră în istoric).
  /// Grupurile în care mai multe intrări au atașamente sunt lăsate așa.
  /// Întoarce câte intrări au fost șterse.
  Future<int> mergeDuplicateSecrets() async {
    var removed = 0;
    bool hasAtt(SecretItem i) => attachmentsOf(i.attachmentOwnerId).isNotEmpty;
    for (final g in duplicateGroups(allSecrets)) {
      if (g.where(hasAtt).length > 1) continue;
      final r = mergeDuplicates(g, hasAttachments: hasAtt);
      await saveSecret(r.keep);
      final who = r.keep.username.isEmpty
          ? r.keep.displayTitle
          : '${r.keep.displayTitle} (${r.keep.username})';
      for (final o in r.remove) {
        await deleteSecret(o, why: 'Unit cu „$who” (dublură)');
        removed++;
      }
    }
    return removed;
  }

  Future<void> applyRemoteSecret(Map<String, dynamic> m) async {
    final remote = SecretItem.fromMap(m);
    final local = _secrets[remote.id];
    if (local != null && !remote.updatedAt.isAfter(local.updatedAt)) return;
    _secrets[remote.id] = remote;
    await _secretsBox.put(remote.id, remote.toMap());
    if (remote.isTrashed) {
      await ReminderService.instance.cancelSecret(remote.id);
    } else {
      await ReminderService.instance.syncSecret(remote);
    }
    notifyListeners();
  }

  Future<void> applyRemoteSecretDeleted(String id) async {
    if (_secrets.remove(id) == null) return;
    await _secretsBox.delete(id);
    await ReminderService.instance.cancelSecret(id);
    notifyListeners();
  }
}
