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
    // Textul aldin și mărimea textului se aleg din Cont → Aspect. Implicit
    // scrisul e normal (ca în Evernote), chiar dacă telefonul are „Text aldin”.
    builder: (context, child) {
      final settings = context.watch<AppSettings>();
      final mq = MediaQuery.of(context);
      // Mărimea din aplicație se aplică peste cea din setările telefonului.
      final systemFactor = mq.textScaler.scale(14) / 14;
      return MediaQuery(
        data: mq.copyWith(
          boldText: settings.boldText,
          textScaler: TextScaler.linear(systemFactor * settings.textScale),
        ),
        child: builder == null
            ? child ?? const SizedBox.shrink()
            : builder(context, child),
      );
    },
    home: home,
  );
}
