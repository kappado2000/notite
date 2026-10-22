import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ascunde conținutul aplicației în comutatorul de aplicații.
/// iPhone: ecranul e estompat cât timp aplicația nu e în prim-plan.
/// Android: fereastra e marcată „securizată” (previzualizare goală; nici
/// capturile de ecran nu mai merg).
class PrivacyShield {
  static const _channel = MethodChannel('notite/privacy');

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  static Future<void> apply(bool enabled) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('setEnabled', enabled);
    } catch (e) {
      debugPrint('PrivacyShield: $e');
    }
  }
}
