import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import 'data/app_settings.dart';
import 'theme.dart';

/// Configurația comună a aplicației (temă, limbă română).
MaterialApp notiteMaterialApp(
  BuildContext context, {
  required Widget home,
  GlobalKey<NavigatorState>? navigatorKey,
  TransitionBuilder? builder,
}) {
  final themeMode = context.select<AppSettings, ThemeMode>((s) => s.themeMode);
  return MaterialApp(
    title: 'Notițe',
    navigatorKey: navigatorKey,
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    themeMode: themeMode,
    locale: const Locale('ro'),
    supportedLocales: const [Locale('ro'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    // Ignorăm „Text aldin” din setările de accesibilitate iOS: altfel tot
    // textul devine îngroșat, iar lista nu mai arată ca în Evernote (cerință
    // explicită). Mărimea textului din setări rămâne respectată.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(boldText: false),
      child: builder == null
          ? child ?? const SizedBox.shrink()
          : builder(context, child),
    ),
    home: home,
  );
}
