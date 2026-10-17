import 'package:flutter/foundation.dart';
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

  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Deblochează Notițe',
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('Biometric: $e');
      return false;
    }
  }
}
