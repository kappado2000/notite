import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:notite/data/notes_store.dart';
import 'package:notite/services/incoming_files.dart';
import 'package:notite/widgets/attachment_image_embed.dart';

void main() {
  late NotesStore store;
  late Directory dir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('notite_test');
    Hive.init(dir.path);
    await Hive.openBox('settings');
    store = NotesStore('test');
    await store.init();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('fișier text → titlu din nume, conținutul în notiță', () async {
    final note = await createNoteFromFile(
      store,
      'Lista cumpărături.txt',
      Uint8List.fromList(utf8.encode('Pâine\nLapte\n')),
    );
    expect(note.title, 'Lista cumpărături');
    expect(note.plainText, 'Pâine\nLapte');
    expect(jsonDecode(note.contentJson), [
      {'insert': 'Pâine\nLapte\n'},
    ]);
    expect(store.attachmentsOf(note.id), isEmpty);
  });

  test('PDF → atașat, titlu fără extensie', () async {
    final note = await createNoteFromFile(
      store,
      'Permis pescuit 2026.pdf',
      Uint8List.fromList([37, 80, 68, 70, 45]), // %PDF-
    );
    expect(note.title, 'Permis pescuit 2026');
    final atts = store.attachmentsOf(note.id);
    expect(atts.single.name, 'Permis pescuit 2026.pdf');
    expect(atts.single.mime, 'application/pdf');
    expect(store.bytesOf(atts.single.id), [37, 80, 68, 70, 45]);
  });

  test('imagine → atașată și inserată în text', () async {
    final note = await createNoteFromFile(
      store,
      'bon.jpg',
      Uint8List.fromList([1, 2, 3]),
    );
    final att = store.attachmentsOf(note.id).single;
    expect(att.isImage, isTrue);
    expect(jsonDecode(note.contentJson), [
      {
        'insert': {kAttachmentImageEmbed: att.id},
      },
      {'insert': '\n'},
    ]);
    // Notița e salvată în stocare și apare în listă.
    expect(store.activeNotes.map((n) => n.id), contains(note.id));
  });
}
