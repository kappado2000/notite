import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/app_settings.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/reminder_service.dart';
import 'services/privacy_shield.dart';
import 'session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ro');
  await Hive.initFlutter('notite');
  final settings = AppSettings(await Hive.openBox('settings'));
  await PrivacyShield.apply(settings.hideInSwitcher);
  await ReminderService.instance.init();

  String? firebaseError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Copie locală a datelor din cloud: aplicația merge și fără internet.
    if (kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
      );
    }
  } catch (e) {
    firebaseError = '$e';
  }

  runApp(
    ChangeNotifierProvider.value(
      value: settings,
      child: firebaseError != null
          ? _FirebaseMissingApp(error: firebaseError)
          : ChangeNotifierProvider(
              create: (_) => AuthService(),
              child: const NotiteApp(),
            ),
    ),
  );
}

/// Alege între ecranul de logare și aplicația contului logat.
class NotiteApp extends StatelessWidget {
  const NotiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (!auth.ready) {
      return notiteMaterialApp(
        context,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    final user = auth.user;
    if (user == null) {
      return notiteMaterialApp(context, home: const LoginScreen());
    }
    // Cheie pe uid: la schimbarea contului se deschide o sesiune nouă.
    return SessionApp(key: ValueKey(user.uid), user: user);
  }
}

class _FirebaseMissingApp extends StatelessWidget {
  const _FirebaseMissingApp({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) => notiteMaterialApp(
    context,
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 56),
              const SizedBox(height: 12),
              const Text(
                'Conectarea la cloud nu este configurată',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(error, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}
