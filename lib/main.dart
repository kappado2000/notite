import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'data/notes_store.dart';
import 'screens/home_screen.dart';
import 'screens/note_editor_screen.dart';
import 'services/reminder_service.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ro');
  final store = NotesStore();
  await store.init();
  await ReminderService.instance.init();
  ReminderService.instance.onOpenNote = (id) {
    if (store.note(id) == null) return;
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)),
    );
  };
  runApp(ChangeNotifierProvider.value(value: store, child: const NotiteApp()));
}

class NotiteApp extends StatelessWidget {
  const NotiteApp({super.key});

  static const _seed = Color(0xFF00A82D);

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<NotesStore, ThemeMode>((s) => s.themeMode);
    return MaterialApp(
      title: 'Notițe',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: themeMode,
      locale: const Locale('ro'),
      supportedLocales: const [Locale('ro'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      home: const HomeScreen(),
    );
  }
}
