import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';

/// Deblocare cu amprentă / Face ID / Windows Hello.
class BiometricService {
  static final _auth = LocalAuthentication();

  static Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Numele afișat: „Face ID” pe iPhone, „amprentă” în rest.
  static Future<String> label() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          types.contains(BiometricType.face)) {
        return 'Face ID';
      }
      if (defaultTargetPlatform == TargetPlatform.windows) {
        return 'Windows Hello';
      }
    } catch (_) {}
    return 'amprentă';
  }

  static Future<bool>? _inFlight;
  static DateTime? _lastOk;

  /// Cere Face ID / amprenta. Pornește singur la deschiderea aplicației, așa
  /// că:
  /// - așteaptă până când aplicația e cu adevărat activă (altfel iOS refuză
  ///   fereastra Face ID și userul trebuia să apese butonul);
  /// - cererile simultane (blocarea aplicației + secțiunea Parole) primesc
  ///   UN SINGUR Face ID;
  /// - dacă iOS refuză instantaneu (aplicația încă se deschidea), reîncearcă
  ///   o dată.
  static Future<bool> authenticate() {
    final last = _lastOk;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 3)) {
      return Future.value(true);
    }
    return _inFlight ??= _run().whenComplete(() => _inFlight = null);
  }

  static Future<bool> _run() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      await _whenActive();
      final started = DateTime.now();
      var ok = false;
      try {
        ok = await _auth.authenticate(
          localizedReason: 'Deblochează Notițe',
          persistAcrossBackgrounding: true,
        );
      } catch (e) {
        debugPrint('Biometric: $e');
      }
      if (ok) {
        _lastOk = DateTime.now();
        return true;
      }
      // anulat de user (a durat) → nu mai insistăm
      if (DateTime.now().difference(started) >
          const Duration(milliseconds: 800)) {
        return false;
      }
    }
    return false;
  }

  static Future<void> _whenActive() async {
    final binding = WidgetsBinding.instance;
    final state = binding.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) {
      final done = Completer<void>();
      final listener = AppLifecycleListener(
        onResume: () {
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future.timeout(const Duration(minutes: 5), onTimeout: () {});
      listener.dispose();
    }
    // iOS are nevoie de o clipă după activare ca să arate Face ID
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }
}
