import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_settings.dart';
import '../services/auth_service.dart';

/// Autentificare și creare cont (email + parolă).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(
    text: context.read<AppSettings>().lastEmail,
  );
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _register = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    context.read<AppSettings>().lastEmail = _email.text.trim();
    try {
      if (_register) {
        await auth.register(_email.text, _password.text);
      } else {
        await auth.signIn(_email.text, _password.text);
      }
    } on AuthError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final ctrl = TextEditingController(text: _email.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resetare parolă'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Îți trimitem pe email un link pentru alegerea unei parole noi.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anulează'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Trimite'),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AuthService>().sendPasswordReset(email);
      messenger.showSnackBar(
        SnackBar(content: Text('Am trimis linkul de resetare la $email')),
      );
    } on AuthError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        child: const Icon(Icons.edit_note, size: 40),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Notițe',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _register
                            ? 'Creează un cont ca să-ți ai notițele pe toate '
                                  'dispozitivele'
                            : 'Intră în cont',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.mail_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (s.isEmpty) return 'Introdu adresa de email';
                          if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(s)) {
                            return 'Adresa de email nu este validă';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: [
                          _register
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        textInputAction: _register
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!_register) _submit();
                        },
                        decoration: InputDecoration(
                          labelText: 'Parolă',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Arată parola' : 'Ascunde',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) {
                          if ((v ?? '').isEmpty) return 'Introdu parola';
                          if (_register && v!.length < 6) {
                            return 'Cel puțin 6 caractere';
                          }
                          return null;
                        },
                      ),
                      if (_register) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirm,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Confirmă parola',
                            prefixIcon: Icon(Icons.lock_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => v != _password.text
                              ? 'Parolele nu coincid'
                              : null,
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(color: scheme.onErrorContainer),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                _register ? 'Creează contul' : 'Intră în cont',
                              ),
                      ),
                      if (!_register)
                        TextButton(
                          onPressed: _busy ? null : _forgotPassword,
                          child: const Text('Ai uitat parola?'),
                        ),
                      const SizedBox(height: 8),
                      const Divider(),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _register = !_register;
                                _error = null;
                              }),
                        child: Text(
                          _register
                              ? 'Ai deja cont? Intră în cont'
                              : 'Nu ai cont? Creează unul',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
