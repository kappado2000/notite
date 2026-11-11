import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:notite/data/notes_store.dart';
import 'package:notite/models/note_template.dart';
import 'package:notite/models/notebook.dart';
import 'package:notite/services/note_pdf.dart';
import 'package:notite/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  Future<NotesStore> openStore(String uid) async {
    final s = NotesStore(uid);
    await s.init();
    return s;
  }

  setUp(() async {
    await initializeDateFormatting('ro');
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('notite_feat');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('șabloanele produc documente valide pentru editor', () {
    for (final t in noteTemplates) {
      final doc = Document.fromJson(jsonDecode(t.contentJson()) as List);
      expect(doc.toPlainText().endsWith('\n'), isTrue, reason: t.name);
      expect(t.title(DateTime(2026, 10, 21)), isNotEmpty);
    }
    final shopping = noteTemplates.first;
    final doc = Document.fromJson(jsonDecode(shopping.contentJson()) as List);
    // nimic scris de fapt: doar texte-exemplu pe rânduri goale
    expect(doc.toPlainText().trim(), isEmpty);
    final block = doc.root.children.first as Block;
    final line = block.children.first as Line;
    expect(line.style.attributes['list']?.value, 'unchecked');
    expect(line.style.attributes[lineHintKey]?.value, 'Pâine');
    expect(lineHintOf(line), 'Pâine');
    // după ce scrii pe rând, exemplul nu mai e afișat
    doc.insert(0, 'Cafea');
    expect(lineHintOf(line), isNull);
  });

  test('exemplul dispare de pe rândul scris; Enter nu-l copiază', () {
    final c = QuillController(
      document: Document.fromJson(
        jsonDecode(noteTemplates.first.contentJson()) as List,
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    c.replaceText(0, 0, 'Cafea', const TextSelection.collapsed(offset: 5));
    dropFilledHints(c.document);
    c.replaceText(5, 0, '\n', const TextSelection.collapsed(offset: 6));
    dropFilledHints(c.document);
    final lines = [
      for (final b in c.document.root.children)
        for (final l in (b as Block).children) l as Line,
    ];
    expect(lines[0].toPlainText(), 'Cafea\n');
    expect(lines[0].style.attributes.containsKey(lineHintKey), isFalse);
    // rândul nou, gol, nu primește „Pâine”
    expect(lines[1].length, 1);
    expect(lineHintOf(lines[1]), isNull);
    // celelalte exemple rămân
    expect(lineHintOf(lines[2]), 'Lapte');
    // textul notiței conține doar ce s-a scris
    expect(c.document.toPlainText().trim(), 'Cafea');
  });

  test('fiecare carnet nou are altă nuanță; nuanța aleasă rămâne', () async {
    final store = await openStore('tint');
    expect(NotesStore.tintCount, GroupTint.all.length);
    final made = [
      for (var i = 0; i < 4; i++) await store.createNotebook('C$i'),
    ];
    final tints = {for (final nb in store.allNotebooks) store.tintOf(nb)};
    expect(tints.length, store.allNotebooks.length);
    await store.updateNotebook(
      made.first,
      name: 'C0',
      emoji: made.first.emoji,
      color: 6,
    );
    expect(store.tintOf(made.first), 5);
  });

  test('intensitatea și scrisul carnetului se păstrează', () async {
    final store = await openStore('intens');
    final nb = await store.createNotebook('Bonuri');
    await store.updateNotebook(
      nb,
      name: 'Bonuri',
      emoji: nb.emoji,
      color: 5,
      intensity: 5,
      textMode: TintText.light.index,
    );
    final again = Notebook.fromMap(nb.toMap());
    expect((again.color, again.intensity, again.textMode), (5, 5, 2));
    final tint = store.notebookTint(nb);
    expect((tint.level, tint.text), (5, TintText.light));
    // carnetele vechi, fără câmpurile noi: intensitate implicită, scris automat
    final old = Notebook.fromMap(
      nb.toMap()
        ..remove('intensity')
        ..remove('textMode'),
    );
    expect((old.intensity, old.textMode), (1, 0));
  });

  test('notița blocată nu se găsește după conținut, doar după titlu', () async {
    final store = await openStore('u1');
    final n = await store.createNote();
    n
      ..title = 'Conturi bancare'
      ..plainText = 'IBAN RO49AAAA1B31007593840000';
    await store.saveNote(n);
    expect(store.search('RO49AAAA', store.activeNotes), hasLength(1));
    await store.setLocked(n, true);
    expect(store.search('RO49AAAA', store.activeNotes), isEmpty);
    expect(store.search('bancare', store.activeNotes), hasLength(1));
  });

  test('backup: export → restaurare completă, fără dubluri', () async {
    final a = await openStore('sursa');
    final nb = await a.createNotebook('Muncă');
    final n = await a.createNote(notebookId: nb.id);
    n
      ..title = 'Ședință'
      ..tags = ['proiect']
      ..plainText = 'Buget Q4';
    await a.saveNote(n);
    await a.addAttachment(
      noteId: n.id,
      name: 'contract.pdf',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
    );
    final backup = jsonDecode(jsonEncode(a.exportBackup()));

    final b = await openStore('destinatie');
    final r = await b.importBackup(backup as Map<String, dynamic>);
    expect(r.notes, 1);
    expect(r.attachments, 1);
    final restored = b.note(n.id)!;
    expect(restored.title, 'Ședință');
    expect(restored.tags, ['proiect']);
    expect(b.notebook(restored.notebookId)!.name, 'Muncă');
    final att = b.attachmentsOf(n.id).single;
    expect(b.bytesOf(att.id), [1, 2, 3, 4]);

    final again = await b.importBackup(backup);
    expect((again.notes, again.attachments, again.notebooks), (0, 0, 0));
  });

  test('backup invalid e refuzat', () async {
    final s = await openStore('u2');
    expect(
      () => s.importBackup({'format': 'altceva'}),
      throwsA(isA<FormatException>()),
    );
  });

  test('export PDF: valid, cu formatare și diacritice', () async {
    final store = await openStore('u3');
    final n = await store.createNote();
    n
      ..title = 'Țară și șosea'
      ..contentJson = jsonEncode([
        {'insert': 'Titlu'},
        {
          'insert': '\n',
          'attributes': {'header': 2},
        },
        {
          'insert': 'îngroșat',
          'attributes': {'bold': true},
        },
        {'insert': ' normal\nPunct'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
        {'insert': 'Făcut'},
        {
          'insert': '\n',
          'attributes': {'list': 'checked'},
        },
      ]);
    await store.saveNote(n);
    final widgets = noteWidgets(n, store);
    // antet (titlu, spațiu, detalii, separator) + exact 4 rânduri de conținut
    expect(widgets.skip(4).length, 4);
    final pdf = await notesToPdf([n], store, title: 'Test');
    expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
    expect(pdf.length, greaterThan(1000));
  });
}
