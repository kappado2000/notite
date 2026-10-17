import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../session.dart';

/// Ecran de blocare: deblocare biometrică, cu parola contului ca rezervă.
/// Stă deasupra navigatorului, deci nu folosește dialoguri.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _password = TextEditingController();
  String _label = 'amprentă';
  bool _usePassword = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    BiometricService.label().then((l) {
      if (mounted) setState(() => _label = l);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _biometric() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await BiometricService.authenticate();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.read<Session>().unlock();
  }

  Future<void> _withPassword() async {
    if (_password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().reauthenticate(_password.text);
      if (mounted) context.read<Session>().unlock();
    } on AuthError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = context.read<Session>();
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_outline, size: 56, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Notițe blocate',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    session.email,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  if (!_usePassword) ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: _busy ? null : _biometric,
                      icon: const Icon(Icons.fingerprint),
                      label: Text('Deblochează cu $_label'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setState(() => _usePassword = true),
                      child: const Text('Folosește parola contului'),
                    ),
                  ] else ...[
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofocus: true,
                      onSubmitted: (_) => _withPassword(),
                      decoration: InputDecoration(
                        labelText: 'Parola contului',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        errorText: _error,
                        errorMaxLines: 3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: _busy ? null : _withPassword,
                      child: const Text('Deblochează'),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _usePassword = false),
                      icon: const Icon(Icons.fingerprint),
                      label: Text('Înapoi la $_label'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => session.signOut(context.read<AuthService>()),
                    child: const Text('Deconectează-te'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
