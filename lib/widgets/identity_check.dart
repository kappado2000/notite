import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/biometric_service.dart';
import '../services/firestore_sync.dart';
import '../services/vault.dart';
import '../session.dart';

/// Confirmă că utilizatorul e chiar titularul contului: întâi Face ID /
/// amprentă (dacă există), apoi, ca rezervă, parola contului. Parola e
/// verificată cu cheile de criptare, deci merge și fără internet.
Future<bool> confirmIdentity(
  BuildContext context, {
  required String reason,
}) async {
  if (await BiometricService.isAvailable() &&
      await BiometricService.authenticate()) {
    return true;
  }
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<Session>(),
      child: _PasswordDialog(reason: reason),
    ),
  );
  return ok ?? false;
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.reason});
  final String reason;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_ctrl.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.read<Session>();
    bool ok;
    try {
      if (session.preview) {
        ok = true; // previzualizare fără cont: nu există chei de verificat
      } else {
        final doc = (await FirestoreSync.keysDoc(session.uid).get()).data();
        ok =
            doc != null &&
            await Vault.unlockWithPassword(doc, _ctrl.text) != null;
      }
    } catch (e) {
      ok = false;
      _error = 'Nu am putut verifica parola: $e';
    }
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error ??= 'Parolă greșită.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.lock_outline, size: 32),
    title: Text(widget.reason),
    content: TextField(
      controller: _ctrl,
      obscureText: true,
      autofocus: true,
      onSubmitted: (_) => _check(),
      decoration: InputDecoration(
        labelText: 'Parola contului',
        errorText: _error,
        errorMaxLines: 3,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Anulează'),
      ),
      FilledButton(
        onPressed: _busy ? null : _check,
        child: const Text('Confirmă'),
      ),
    ],
  );
}
