import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/notes_store.dart';
import 'screens/home_screen.dart';
import 'screens/key_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/note_editor_screen.dart';
import 'services/auth_service.dart';
import 'services/biometric_service.dart';
import 'services/firestore_sync.dart';
import 'services/reminder_service.dart';
import 'services/vault.dart';

/// Starea sesiunii unui cont logat: blocare biometrică și sincronizare.
class Session extends ChangeNotifier {
  Session(this.user, this.store, this.sync);

  final User user;
  final NotesStore store;
  final FirestoreSync sync;

  final _settings = Hive.box('settings');

  bool locked = false;

  bool get biometricEnabled =>
      (_settings.get('biometric_${user.uid}') as bool?) ?? false;

  set biometricEnabled(bool v) {
    _settings.put('biometric_${user.uid}', v);
    notifyListeners();
  }

  /// Am întrebat deja dacă vrea deblocare biometrică (o singură dată).
  bool get biometricOffered =>
      (_settings.get('biometricOffered_${user.uid}') as bool?) ?? false;
  set biometricOffered(bool v) =>
      _settings.put('biometricOffered_${user.uid}', v);

  void lock() {
    if (!biometricEnabled || locked) return;
    locked = true;
    notifyListeners();
  }

  void unlock() {
    locked = false;
    notifyListeners();
  }

  Future<void> signOut(AuthService auth) async {
    await ReminderService.instance.cancelAll();
    // Trimitem ce a mai rămas în coadă, apoi scoatem cheia de criptare de
    // pe dispozitiv: la relogare, parola o deblochează din nou.
    try {
      await sync.flush().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Offline: modificările rămân în coada Firestore locală.
    }
    await sync.stop();
    await Vault.deleteLocal(user.uid);
    await auth.signOut();
  }

  /// Cod de recuperare nou (cel vechi nu mai funcționează).
  Future<String> regenerateRecoveryCode() async {
    final r = await sync.vault.newRecovery();
    await FirestoreSync.keysDoc(user.uid)
        .set({'recovery': r.wrapped}, SetOptions(merge: true));
    return r.code;
  }

  /// Șterge definitiv contul: datele din cloud, de pe dispozitiv și contul.
  Future<void> deleteAccount(AuthService auth, String password) async {
    await auth.reauthenticate(password);
    await ReminderService.instance.cancelAll();
    await sync.stop();
    await FirestoreSync.deleteAllRemote(user.uid);
    await store.wipeLocal();
    await Vault.deleteLocal(user.uid);
    await _settings.delete('biometric_${user.uid}');
    await _settings.delete('biometricOffered_${user.uid}');
    await auth.deleteAccount();
  }
}

/// Aplicația pentru un cont logat. Deschide datele contului, pornește
/// sincronizarea și afișează ecranul de blocare când e cazul.
class SessionApp extends StatefulWidget {
  const SessionApp({super.key, required this.user});

  final User user;

  @override
  State<SessionApp> createState() => _SessionAppState();
}

class _SessionAppState extends State<SessionApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  Session? _session;
  bool _needsKey = false;
  DateTime? _pausedAt;

  /// După cât timp în fundal se cere din nou deblocarea.
  static const _relockAfter = Duration(minutes: 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  Future<void> _open() async {
    final vault = await Vault.loadLocal(widget.user.uid);
    if (vault == null) {
      // Prima deschidere pe acest dispozitiv: cheia vine din cloud.
      if (mounted) setState(() => _needsKey = true);
      return;
    }
    await _openWith(vault);
  }

  Future<void> _openWith(Vault vault) async {
    final store = NotesStore(widget.user.uid);
    await store.init();
    final sync = FirestoreSync(store, vault);
    store.sync = sync;
    sync.start();
    final session = Session(widget.user, store, sync);
    session.locked = session.biometricEnabled;
    ReminderService.instance.onOpenNote = (id) {
      if (store.note(id) == null) return;
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)),
      );
    };
    if (!mounted) {
      await sync.stop();
      await store.close();
      return;
    }
    setState(() {
      _needsKey = false;
      _session = session;
    });
    if (!session.biometricEnabled && !session.biometricOffered) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _offerBiometric());
    }
  }

  /// La prima logare pe un dispozitiv cu biometrie, propune activarea.
  Future<void> _offerBiometric() async {
    final session = _session;
    final ctx = _navigatorKey.currentContext;
    if (session == null || ctx == null) return;
    if (!await BiometricService.isAvailable()) return;
    final label = await BiometricService.label();
    session.biometricOffered = true;
    if (!ctx.mounted) return;
    final yes = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.fingerprint, size: 40),
        title: Text('Deblocare cu $label?'),
        content: Text(
          'Notițele vor fi protejate: la deschiderea aplicației îți cerem '
          '$label. Poți schimba oricând din meniul Cont.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Nu acum'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Activează'),
          ),
        ],
      ),
    );
    if (yes == true && await BiometricService.authenticate()) {
      session.biometricEnabled = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _pausedAt;
      _pausedAt = null;
      if (since != null && DateTime.now().difference(since) > _relockAfter) {
        _session?.lock();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final s = _session;
    if (s != null) {
      s.sync.stop();
      s.store.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (_needsKey && session == null) {
      return notiteMaterialApp(
        context,
        home: KeyScreen(user: widget.user, onReady: _openWith),
      );
    }
    if (session == null) {
      return notiteMaterialApp(
        context,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: session.store),
      ],
      child: notiteMaterialApp(
        context,
        navigatorKey: _navigatorKey,
        home: const HomeScreen(),
        // Ecranul de blocare acoperă tot, inclusiv notițele deschise.
        builder: (context, child) => Consumer<Session>(
          builder: (context, s, _) => Stack(
            children: [
              ?child,
              if (s.locked) const Positioned.fill(child: LockScreen()),
            ],
          ),
        ),
      ),
    );
  }
}
