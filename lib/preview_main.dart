// Punct de intrare DOAR pentru previzualizarea interfeței, fără cont și
// fără cloud:  flutter run -t lib/preview_main.dart -d web-server
// Aplicația reală pornește din lib/main.dart.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/app_settings.dart';
import 'data/notes_store.dart';
import 'models/secret_item.dart';
import 'screens/shell.dart';
import 'session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ro');
  await Hive.initFlutter('notite_preview');
  final settings = AppSettings(await Hive.openBox('settings'));
  final store = NotesStore('preview');
  await store.init();
  if (store.activeNotes.isEmpty) await _seedDemo(store);
  final session = Session(
    uid: 'preview',
    email: 'previzualizare@notite.app',
    store: store,
    preview: true,
  );
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: store),
      ],
      child: Builder(
        builder: (context) =>
            notiteMaterialApp(context, home: const AppShell()),
      ),
    ),
  );
}

/// Date demonstrative pentru previzualizare (doar la primul start).
Future<void> _seedDemo(NotesStore store) async {
  final work = await store.createNotebook('Muncă', emoji: '💼', color: 5);
  final home = await store.createNotebook('Acasă', emoji: '🏠', color: 1);
  final ideas = await store.createNotebook('Idei', emoji: '💡', color: 4);
  final first = store.notebooks.firstWhere(
    (n) => n.name == 'Primul meu carnet',
  );
  await store.updateNotebook(first, name: 'Personal', emoji: '🌱', color: 0);

  Future<void> note(
    String nb,
    String title,
    List<Map<String, dynamic>> delta, {
    List<String> tags = const [],
    bool pinned = false,
    DateTime? reminder,
  }) async {
    final n = await store.createNote(notebookId: nb);
    n
      ..title = title
      ..contentJson = jsonEncode(delta)
      ..plainText = delta.map((op) => op['insert']).join()
      ..tags = [...tags]
      ..pinned = pinned
      ..reminderAt = reminder;
    await store.saveNote(n);
  }

  Map<String, dynamic> t(String s) => {'insert': s};
  Map<String, dynamic> check(bool done) => {
    'insert': '\n',
    'attributes': {'list': done ? 'checked' : 'unchecked'},
  };

  await note(
    home.id,
    'Lista de cumpărături',
    [
      t('Pâine'),
      check(true),
      t('Lapte'),
      check(false),
      t('Ouă'),
      check(false),
      t('Cafea'),
      check(false),
    ],
    tags: ['cumpărături'],
    pinned: true,
  );
  await note(
    work.id,
    'Ședință proiect — vineri',
    [
      t(
        'Puncte de discutat: buget Q4, termenul pentru faza 2 și '
        'echipa de testare.\n',
      ),
    ],
    tags: ['proiect', 'ședințe'],
    reminder: DateTime.now().add(const Duration(days: 1, hours: 2)),
  );
  await note(
    ideas.id,
    'Vacanță la munte',
    [
      t(
        'Cabane de verificat în Bran și Sinaia. De rezervat până la '
        'sfârșitul lunii.\n',
      ),
    ],
    tags: ['vacanță'],
  );
  await note(
    first.id,
    'Rețetă de clătite',
    [
      t(
        '2 ouă, 250 ml lapte, 150 g făină, un praf de sare. Se lasă '
        'compoziția 15 minute la odihnit.\n',
      ),
    ],
    tags: ['rețete'],
  );
  await note(
    work.id,
    'Raport lunar',
    [
      t(
        'Vânzările au crescut cu 12% față de luna trecută. De pregătit '
        'graficele pentru prezentare.\n',
      ),
    ],
    tags: ['proiect'],
  );

  final gmail = store.newSecret(SecretType.login)
    ..title = 'Gmail'
    ..username = 'exemplu@gmail.com'
    ..password = 'K7#pQ2!vX9mL4@tR'
    ..url = 'mail.google.com'
    ..totp = 'JBSWY3DPEHPK3PXP';
  final bank = store.newSecret(SecretType.login)
    ..title = 'Banca'
    ..username = 'ion.popescu'
    ..password = 'parola123';
  final wifi = store.newSecret(SecretType.wifi)
    ..title = 'Wi-Fi acasă'
    ..username = 'Acasa-5G'
    ..password = 'soare-munte-42';
  final card = store.newSecret(SecretType.card)
    ..title = 'Card salariu'
    ..cardHolder = 'ION POPESCU'
    ..cardNumber = '4111 1111 1111 1111'
    ..cardExpiry = '08/29'
    ..cardCvv = '123';
  for (final s in [gmail, bank, wifi, card]) {
    await store.saveSecret(s);
  }
}
