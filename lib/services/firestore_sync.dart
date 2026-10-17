import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/notes_store.dart';
import '../models/attachment.dart';
import '../models/note.dart';
import '../models/notebook.dart';

enum SyncState { connecting, synced, offline, error }

/// Sincronizare bidirecțională cu Firestore, sub `users/{uid}/...`.
///
/// - Hive rămâne sursa locală; Firestore ține și el o copie offline și
///   trimite modificările când revine conexiunea.
/// - Conflicte: câștigă versiunea cu `updatedAt` mai nou.
/// - Ștergerile devin „pietre funerare” (`deleted: true`), ca să ajungă
///   și pe dispozitivele care erau offline.
/// - Atașamentele se salvează în bucăți de max. 700 KB (`blobs`), fiindcă
///   un document Firestore are limita de 1 MB.
class FirestoreSync implements SyncSink {
  FirestoreSync(this.store);

  final NotesStore store;
  final state = ValueNotifier(SyncState.connecting);

  static const _chunkSize = 700 * 1024;

  final _subs = <StreamSubscription>[];
  final _downloading = <String>{};

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  DocumentReference get _user => _db.collection('users').doc(store.uid);
  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _user.collection(name);

  void start() {
    _listen('notebooks', _onNotebook, _uploadMissingNotebooks);
    _listen('notes', _onNote, _uploadMissingNotes);
    _listen('attachments', _onAttachment, _uploadMissingAttachments);
  }

  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  void _listen(
    String name,
    Future<void> Function(String id, Map<String, dynamic> data) onDoc,
    Future<void> Function(Set<String> remoteIds) onFirstServerSnapshot,
  ) {
    var reconciled = false;
    _subs.add(
      _col(name)
          .snapshots(includeMetadataChanges: true)
          .listen(
            (snap) async {
              state.value = snap.metadata.isFromCache
                  ? SyncState.offline
                  : SyncState.synced;
              for (final ch in snap.docChanges) {
                if (ch.type == DocumentChangeType.removed) continue;
                final data = ch.doc.data();
                if (data == null || ch.doc.metadata.hasPendingWrites) continue;
                try {
                  await onDoc(ch.doc.id, data);
                } catch (e) {
                  debugPrint('Sync $name/${ch.doc.id}: $e');
                }
              }
              // Prima imagine completă de pe server: urcăm ce există doar local.
              if (!reconciled && !snap.metadata.isFromCache) {
                reconciled = true;
                await onFirstServerSnapshot(snap.docs.map((d) => d.id).toSet());
              }
            },
            onError: (Object e) {
              debugPrint('Sync $name: $e');
              state.value = SyncState.error;
            },
          ),
    );
  }

  static DateTime _date(Object? v) =>
      DateTime.fromMillisecondsSinceEpoch((v as int?) ?? 0);

  // ------------------------------------------------------------- primire

  Future<void> _onNote(String id, Map<String, dynamic> data) async {
    if (data['deleted'] == true) {
      final local = store.noteUpdatedAt(id);
      if (local == null) return;
      if (!local.isAfter(_date(data['updatedAt']))) {
        await store.applyRemoteNoteDeleted(id);
      } else {
        // Modificată local după ștergere: o readucem în cloud.
        final n = store.note(id);
        if (n != null) noteChanged(n);
      }
      return;
    }
    await store.applyRemoteNote(data);
  }

  Future<void> _onNotebook(String id, Map<String, dynamic> data) async {
    if (data['deleted'] == true) {
      await store.applyRemoteNotebookDeleted(id);
      return;
    }
    await store.applyRemoteNotebook(data);
  }

  Future<void> _onAttachment(String id, Map<String, dynamic> data) async {
    if (data['deleted'] == true) {
      await store.applyRemoteAttachmentDeleted(id);
      return;
    }
    if (store.hasBlob(id)) {
      await store.applyRemoteAttachment(data, null);
      return;
    }
    if (!_downloading.add(id)) return;
    try {
      final chunks = (data['chunks'] as int?) ?? 0;
      final builder = BytesBuilder(copy: false);
      for (var i = 0; i < chunks; i++) {
        final doc = await _col('blobs').doc('${id}_$i').get();
        final blob = doc.data()?['data'];
        if (blob is! Blob) return; // încă se încarcă de pe alt dispozitiv
        builder.add(blob.bytes);
      }
      await store.applyRemoteAttachment(data, builder.takeBytes());
    } finally {
      _downloading.remove(id);
    }
  }

  // --------------------------------------------- urcare inițială (o dată)

  Future<void> _uploadMissingNotes(Set<String> remote) async {
    for (final n in store.allNotes.toList()) {
      if (!remote.contains(n.id)) noteChanged(n);
    }
  }

  Future<void> _uploadMissingNotebooks(Set<String> remote) async {
    for (final nb in store.allNotebooks.toList()) {
      if (!remote.contains(nb.id)) notebookChanged(nb);
    }
  }

  Future<void> _uploadMissingAttachments(Set<String> remote) async {
    for (final a in store.allAttachments.toList()) {
      final bytes = store.bytesOf(a.id);
      if (!remote.contains(a.id) && bytes != null) attachmentAdded(a, bytes);
    }
  }

  // -------------------------------------------------------------- trimitere

  void _write(Future<void> f) => f.catchError((Object e) {
    debugPrint('Sync write: $e');
    state.value = SyncState.error;
  });

  int get _now => DateTime.now().millisecondsSinceEpoch;

  @override
  void noteChanged(Note note) =>
      _write(_col('notes').doc(note.id).set(note.toMap()));

  @override
  void noteDeleted(String id) => _write(
    _col('notes').doc(id).set({'id': id, 'deleted': true, 'updatedAt': _now}),
  );

  @override
  void notebookChanged(Notebook notebook) =>
      _write(_col('notebooks').doc(notebook.id).set(notebook.toMap()));

  @override
  void notebookDeleted(String id) => _write(
    _col('notebooks')
        .doc(id)
        .set({'id': id, 'deleted': true, 'updatedAt': _now}),
  );

  @override
  void attachmentAdded(Attachment attachment, Uint8List bytes) {
    _write(() async {
      final chunks = (bytes.length / _chunkSize).ceil();
      for (var i = 0; i < chunks; i++) {
        final end = ((i + 1) * _chunkSize).clamp(0, bytes.length);
        await _col('blobs').doc('${attachment.id}_$i').set({
          'data': Blob(Uint8List.sublistView(bytes, i * _chunkSize, end)),
        });
      }
      // Metadatele la final, ca celelalte dispozitive să găsească bucățile.
      await _col('attachments')
          .doc(attachment.id)
          .set({...attachment.toMap(), 'chunks': chunks});
    }());
  }

  @override
  void attachmentChanged(Attachment attachment) => _write(
    _col('attachments')
        .doc(attachment.id)
        .set(attachment.toMap(), SetOptions(merge: true)),
  );

  @override
  void attachmentDeleted(String id) {
    _write(() async {
      final meta = await _col('attachments').doc(id).get();
      final chunks = (meta.data()?['chunks'] as int?) ?? 0;
      await _col('attachments')
          .doc(id)
          .set({'id': id, 'deleted': true, 'updatedAt': _now});
      for (var i = 0; i < chunks; i++) {
        await _col('blobs').doc('${id}_$i').delete();
      }
    }());
  }

  /// Șterge din cloud toate datele contului (la ștergerea contului).
  Future<void> deleteAllRemote() async {
    await stop();
    for (final name in ['notes', 'notebooks', 'attachments', 'blobs']) {
      while (true) {
        final page = await _col(name).limit(200).get();
        if (page.docs.isEmpty) break;
        final batch = _db.batch();
        for (final d in page.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    }
  }
}
