import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Cere utilizatorului codul de 6 cifre din aplicația de autentificare
/// ([error] = mesajul de afișat după un cod greșit); `null` = a renunțat.
typedef MfaCodePrompt = Future<String?> Function(String? error);

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

  /// Parola tocmai folosită la logare, ținută doar în memorie până
  /// deblochează cheia de criptare (ca să nu fie cerută de două ori).
  String? _pendingPassword;

  String? takePendingPassword() {
    final p = _pendingPassword;
    _pendingPassword = null;
    return p;
  }

  Future<void> signIn(
    String email,
    String password, {
    MfaCodePrompt? askCode,
  }) => _guard(() async {
    _pendingPassword = password;
    try {
      await _withMfa(
        () => _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ),
        askCode,
      );
    } catch (_) {
      _pendingPassword = null;
      rethrow;
    }
  });

  Future<void> register(String email, String password) => _guard(() async {
    _pendingPassword = password;
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await cred.user?.sendEmailVerification();
    } catch (_) {
      _pendingPassword = null;
      rethrow;
    }
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
  Future<void> reauthenticate(String password, {MfaCodePrompt? askCode}) =>
      _guard(() async {
        final u = _auth.currentUser!;
        await _withMfa(
          () => u.reauthenticateWithCredential(
            EmailAuthProvider.credential(email: u.email!, password: password),
          ),
          askCode,
        );
      });

  // ------------------------------------- autentificarea în doi pași (TOTP)

  /// Contul are 2FA activ (un cod din aplicația de autentificare)?
  Future<bool> mfaEnabled() async {
    final u = _auth.currentUser;
    if (u == null) return false;
    return (await u.multiFactor.getEnrolledFactors()).isNotEmpty;
  }

  /// Pasul 1: cheia secretă nouă (pentru codul QR). Cere o logare recentă:
  /// apelează întâi [reauthenticate].
  Future<TotpSecret> startTotpEnrollment() async {
    try {
      final session = await _auth.currentUser!.multiFactor.getSession();
      return await TotpMultiFactorGenerator.generateSecret(session);
    } on FirebaseAuthException catch (e) {
      throw AuthError(_message(e.code));
    }
  }

  /// Pasul 2: primul cod din aplicație confirmă că a fost adăugată corect.
  Future<void> finishTotpEnrollment(TotpSecret secret, String code) =>
      _guard(() async {
        final assertion =
            await TotpMultiFactorGenerator.getAssertionForEnrollment(
              secret,
              code.trim(),
            );
        await _auth.currentUser!.multiFactor.enroll(
          assertion,
          displayName: 'Aplicație de autentificare',
        );
      });

  /// Oprește 2FA (cere o logare recentă).
  Future<void> disableMfa() => _guard(() async {
    final mf = _auth.currentUser!.multiFactor;
    for (final f in await mf.getEnrolledFactors()) {
      await mf.unenroll(multiFactorInfo: f);
    }
  });

  /// Rulează [action]; dacă Firebase cere al doilea factor, întreabă codul
  /// (până e corect sau userul renunță).
  Future<void> _withMfa(
    Future<Object?> Function() action,
    MfaCodePrompt? askCode,
  ) async {
    try {
      await action();
    } on FirebaseAuthMultiFactorException catch (e) {
      if (askCode == null) {
        throw FirebaseAuthException(code: 'second-factor-required');
      }
      final hints = e.resolver.hints;
      final hint = hints.firstWhere(
        (h) => h is TotpMultiFactorInfo,
        orElse: () => hints.first,
      );
      String? error;
      while (true) {
        final code = await askCode(error);
        if (code == null) throw FirebaseAuthException(code: 'mfa-cancelled');
        try {
          final assertion =
              await TotpMultiFactorGenerator.getAssertionForSignIn(
                hint.uid,
                code.trim(),
              );
          await e.resolver.resolveSignIn(assertion);
          return;
        } on FirebaseAuthException catch (x) {
          if (x.code == 'invalid-verification-code' ||
              x.code == 'invalid-credential' ||
              x.code == 'missing-code') {
            error = 'Cod greșit sau expirat. Încearcă din nou.';
            continue;
          }
          rethrow;
        }
      }
    }
  }

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
    'mfa-cancelled' => 'Ai renunțat la codul de verificare.',
    'second-factor-required' => 'Contul cere și codul de verificare.',
    'invalid-verification-code' => 'Cod greșit sau expirat.',
    'unverified-email' =>
      'Confirmă întâi adresa de email (linkul primit pe email), apoi '
          'activează verificarea în doi pași.',
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
