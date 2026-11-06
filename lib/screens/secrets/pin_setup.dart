import 'package:flutter/material.dart';

import '../../services/pin_lock.dart';
import '../../widgets/pin_pad.dart';

/// Setarea (sau schimbarea) codului de 6 cifre: introducere + confirmare.
/// Întoarce `true` dacă s-a salvat un cod nou.
Future<bool> showPinSetup(BuildContext context, PinLock lock) async {
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _PinSetupScreen(lock: lock),
    ),
  );
  return ok ?? false;
}

class _PinSetupScreen extends StatefulWidget {
  const _PinSetupScreen({required this.lock});
  final PinLock lock;

  @override
  State<_PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<_PinSetupScreen> {
  /// Codul de la primul pas; null cât timp nu a fost introdus.
  String? _first;
  String? _mismatch;

  Future<String?> _entered(String pin) async {
    final first = _first;
    if (first == null) {
      if (RegExp(r'^(\d)\1{5}$').hasMatch(pin) ||
          '0123456789'.contains(pin) ||
          '9876543210'.contains(pin)) {
        return 'Cod prea ușor de ghicit. Alege altul.';
      }
      setState(() {
        _first = pin;
        _mismatch = null;
      });
      return null;
    }
    if (pin != first) {
      // Înapoi la primul pas, cu mesajul afișat acolo.
      setState(() {
        _first = null;
        _mismatch = 'Codurile nu se potrivesc. Începe din nou.';
      });
      return null;
    }
    await widget.lock.set(pin);
    if (mounted) Navigator.pop(context, true);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cod pentru Parole')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: PinPad(
            // Cheie nouă la fiecare pas, ca punctele să pornească goale.
            key: ValueKey(_first == null),
            title: _first == null
                ? 'Alege un cod de 6 cifre'
                : 'Confirmă codul',
            subtitle: _first == null
                ? 'Îl vei folosi ca să deschizi Parolele pe acest dispozitiv.'
                : 'Introdu din nou același cod.',
            initialError: _first == null ? _mismatch : null,
            onCompleted: _entered,
          ),
        ),
      ),
    );
  }
}
