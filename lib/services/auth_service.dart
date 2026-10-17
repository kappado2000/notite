import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Contul utilizatorului (Firebase Auth, email + parolă).
/// Sesiunea rămâne salvată pe dispozitiv și funcționează și offline.
class AuthService extends ChangeNotifier {
  AuthService() {
    _sub = _auth.authStateChanges().listen((u) {
      user = u;
      ready = true;
      notifyListeners();
    });
  }

  final _auth = FirebaseAuth.instance;
  late final StreamSubscription<User?> _sub;

  User? user;

  /// Devine adevărat după ce Firebase a spus dacă există o sesiune salvată.
  bool ready = false;

  Future<void> signIn(String email, String password) => _guard(
    () => _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  Future<void> register(String email, String password) => _guard(() async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await cred.user?.sendEmailVerification();
  });

  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  Future<void> resendVerification() =>
      _guard(() async => _auth.currentUser?.sendEmailVerification());

  /// Reîncarcă starea contului (ex. după confirmarea emailului).
  Future<void> reload() async {
    await _auth.currentUser?.reload();
    user = _auth.currentUser;
    notifyListeners();
  }

  Future<void> signOut() => _auth.signOut();

  /// Confirmă parola curentă — cerută de Firebase înainte de ștergerea contului.
  Future<void> reauthenticate(String password) => _guard(() async {
    final u = _auth.currentUser!;
    await u.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: u.email!, password: password),
    );
  });

  Future<void> deleteAccount() => _guard(() => _auth.currentUser!.delete());

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw AuthError(_message(e.code));
    } catch (e) {
      throw AuthError('A apărut o eroare: $e');
    }
  }

  static String _message(String code) => switch (code) {
    'invalid-email' => 'Adresa de email nu este validă.',
    'user-disabled' => 'Acest cont a fost dezactivat.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' ||
    'INVALID_LOGIN_CREDENTIALS' => 'Email sau parolă greșite.',
    'email-already-in-use' => 'Există deja un cont cu acest email.',
    'weak-password' => 'Parola e prea slabă — folosește cel puțin 6 caractere.',
    'too-many-requests' =>
      'Prea multe încercări. Încearcă din nou peste câteva minute.',
    'network-request-failed' => 'Nu există conexiune la internet.',
    'requires-recent-login' =>
      'Din motive de securitate, introdu din nou parola.',
    'operation-not-allowed' =>
      'Logarea cu email și parolă nu este activată în Firebase.',
    _ => 'A apărut o eroare ($code).',
  };

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

class AuthError implements Exception {
  AuthError(this.message);
  final String message;

  @override
  String toString() => message;
}
