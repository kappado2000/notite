import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/notes_store.dart';
import '../models/attachment.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../models/secret_item.dart';
import 'vault.dart';

enum SyncState { connecting, synced, offline, error }

/// Sincronizare bidirecțională cu Firestore, sub `users/{uid}/...`,
/// cu criptare end-to-end: în cloud ajunge doar text criptat ([Vault]).
///
/// - Hive rămâne sursa locală; Firestore ține și el o copie offline și
///   trimite modificările când revine conexiunea.
/// - Conflicte: câștigă versiunea cu `updatedAt` mai nou.
/// - Ștergerile devin „pietre funerare” (`deleted: true`), ca să ajungă
///   și pe dispozitivele care erau offline.
/// - Atașamentele se salvează în bucăți criptate de max. 700 KB
///   (`blobs`), fiindcă un document Firestore are limita de 1 MB.
class FirestoreSync implements SyncSink {
  FirestoreSync(this.store, this.vault);

  final NotesStore store;
  final Vault vault;
  final state = ValueNotifier(SyncState.connecting);

  static const _chunkSize = 700 * 1024;

  final _subs = <StreamSubscription>[];
  final _downloading = <String>{};

  /// Scrierile rulează pe rând, în ordinea modificărilor: criptarea e
  /// asincronă și altfel o versiune veche ar putea ajunge după una nouă.
  Future<void> _queue = Future.value();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> keysDoc(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('keys')
          .doc('main');

  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _db.collection('users').doc(store.uid).collection(name);

  void start() {
    _listen('notebooks', _onNotebook, _uploadMissingNotebooks);
    _listen('notes', _onNote, _uploadMissingNotes);
    _listen('attachments', _onAttachment, _uploadMissingAttachments);
    _listen('secrets', _onSecret, _uploadMissingSecrets);
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

  Future<Map<String, dynamic>> _open(
    String col,
    String id,
    Map<String, dynamic> doc,
  ) => vault.decryptMap(doc['enc'] as String, '$col/$id');

  // ------------------------------------------------------------- primire

  Future<void> _onNote(String id, Map<String, dynamic> doc) async {
    if (doc['deleted'] == true) {
      final local = store.noteUpdatedAt(id);
      if (local == null) return;
      if (!local.isAfter(_date(doc['updatedAt']))) {
        await store.applyRemoteNoteDeleted(id);
      } else {
        // Modificată local după ștergere: o readucem în cloud.
        final n = store.note(id);
        if (n != null) noteChanged(n);
      }
      return;
    }
    await store.applyRemoteNote(await _open('notes', id, doc));
  }

  Future<void> _onNotebook(String id, Map<String, dynamic> doc) async {
    if (doc['deleted'] == true) {
      await store.applyRemoteNotebookDeleted(id);
      return;
    }
    await store.applyRemoteNotebook(await _open('notebooks', id, doc));
  }

  Future<void> _onAttachment(String id, Map<String, dynamic> doc) async {
    if (doc['deleted'] == true) {
      await store.applyRemoteAttachmentDeleted(id);
      return;
    }
    final meta = await _open('attachments', id, doc);
    if (store.hasBlob(id)) {
      await store.applyRemoteAttachment(meta, null);
      return;
    }
    if (!_downloading.add(id)) return;
    try {
      final chunks = (doc['chunks'] as int?) ?? 0;
      final builder = BytesBuilder(copy: false);
      for (var i = 0; i < chunks; i++) {
        final chunkId = '${id}_$i';
        final snap = await _col('blobs').doc(chunkId).get();
        final blob = snap.data()?['data'];
        if (blob is! Blob) return; // încă se încarcă de pe alt dispozitiv
        builder.add(await vault.decryptBytes(blob.bytes, 'blobs/$chunkId'));
      }
      await store.applyRemoteAttachment(meta, builder.takeBytes());
    } finally {
      _downloading.remove(id);
    }
  }

  Future<void> _onSecret(String id, Map<String, dynamic> doc) async {
    if (doc['deleted'] == true) {
      final local = store.secretUpdatedAt(id);
      if (local == null) return;
      if (!local.isAfter(_date(doc['updatedAt']))) {
        await store.applyRemoteSecretDeleted(id);
      }
      return;
    }
    await store.applyRemoteSecret(await _open('secrets', id, doc));
  }

  // --------------------------------------------- urcare inițială (o dată)

  Future<void> _uploadMissingSecrets(Set<String> remote) async {
    for (final i in store.allSecrets.toList()) {
      if (!remote.contains(i.id)) secretChanged(i);
    }
  }

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

  void _enqueue(Future<void> Function() op) {
    _queue = _queue.then((_) => op()).catchError((Object e) {
      debugPrint('Sync write: $e');
      state.value = SyncState.error;
    });
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Scrie documentul criptat. Copia datelor se face acum, sincron, ca
  /// modificările ulterioare ale obiectului să nu intre în această scriere.
  void _put(String col, String id, Map<String, dynamic> data) {
    _enqueue(() async {
      await _col(col)
          .doc(id)
          .set({'enc': await vault.encryptMap(data, '$col/$id')});
    });
  }

  void _tombstone(String col, String id) {
    final at = _now;
    _enqueue(() => _col(col).doc(id).set({'deleted': true, 'updatedAt': at}));
  }

  @override
  void noteChanged(Note note) => _put('notes', note.id, note.toMap());

  @override
  void noteDeleted(String id) => _tombstone('notes', id);

  @override
  void secretChanged(SecretItem item) => _put('secrets', item.id, item.toMap());

  @override
  void secretDeleted(String id) => _tombstone('secrets', id);

  @override
  void notebookChanged(Notebook notebook) =>
      _put('notebooks', notebook.id, notebook.toMap());

  @override
  void notebookDeleted(String id) => _tombstone('notebooks', id);

  @override
  void attachmentAdded(Attachment attachment, Uint8List bytes) {
    final meta = attachment.toMap();
    final id = attachment.id;
    _enqueue(() async {
      final chunks = (bytes.length / _chunkSize).ceil();
      for (var i = 0; i < chunks; i++) {
        final end = ((i + 1) * _chunkSize).clamp(0, bytes.length);
        final chunkId = '${id}_$i';
        final enc = await vault.encryptBytes(
          Uint8List.sublistView(bytes, i * _chunkSize, end),
          'blobs/$chunkId',
        );
        await _col('blobs').doc(chunkId).set({'data': Blob(enc)});
      }
      // Metadatele la final, ca celelalte dispozitive să găsească bucățile.
      await _col('attachments').doc(id).set({
        'enc': await vault.encryptMap(meta, 'attachments/$id'),
        'chunks': chunks,
      });
    });
  }

  @override
  void attachmentChanged(Attachment attachment) {
    final meta = attachment.toMap();
    final id = attachment.id;
    _enqueue(() async {
      await _col('attachments').doc(id).set({
        'enc': await vault.encryptMap(meta, 'attachments/$id'),
      }, SetOptions(merge: true));
    });
  }

  @override
  void attachmentDeleted(String id) {
    final at = _now;
    _enqueue(() async {
      final meta = await _col('attachments').doc(id).get();
      final chunks = (meta.data()?['chunks'] as int?) ?? 0;
      await _col('attachments').doc(id).set({'deleted': true, 'updatedAt': at});
      for (var i = 0; i < chunks; i++) {
        await _col('blobs').doc('${id}_$i').delete();
      }
    });
  }

  /// Așteaptă trimiterea tuturor modificărilor din coadă.
  Future<void> flush() => _queue;

  /// Șterge din cloud toate datele contului, inclusiv cheile.
  static Future<void> deleteAllRemote(String uid) async {
    final user = FirebaseFirestore.instance.collection('users').doc(uid);
    for (final name in [
      'notes',
      'notebooks',
      'attachments',
      'blobs',
      'secrets',
      'keys',
    ]) {
      while (true) {
        final page = await user.collection(name).limit(200).get();
        if (page.docs.isEmpty) break;
        final batch = FirebaseFirestore.instance.batch();
        for (final d in page.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    }
  }
}
