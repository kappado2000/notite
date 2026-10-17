import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import 'data/app_settings.dart';

const _seed = Color(0xFF00A82D);

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
    builder: builder,
    home: home,
  );
}
