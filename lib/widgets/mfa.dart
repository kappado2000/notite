import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';

/// Cere codul de 6 cifre din aplicația de autentificare. `null` = renunțat.
Future<String?> askMfaCode(BuildContext context, String? error) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      void submit() {
        final v = c.text.replaceAll(RegExp(r'\s'), '');
        if (v.length >= 6) Navigator.pop(ctx, v);
      }

      return AlertDialog(
        icon: const Icon(Icons.verified_user_outlined),
        title: const Text('Cod de verificare'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Introdu codul de 6 cifre din aplicația de autentificare '
              '(Google Authenticator, Microsoft Authenticator…).',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, letterSpacing: 6),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: '000000',
                errorText: error,
              ),
              onSubmitted: (_) => submit(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Renunță'),
          ),
          FilledButton(onPressed: submit, child: const Text('Confirmă')),
        ],
      );
    },
  );
}

/// Cere parola contului (pentru operațiile care cer o logare recentă).
Future<String?> askAccountPassword(BuildContext context, String title) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Parola contului',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Renunță'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text),
          child: const Text('Continuă'),
        ),
      ],
    ),
  );
}

/// Activarea / oprirea autentificării în doi pași (Cont).
class MfaScreen extends StatefulWidget {
  const MfaScreen({super.key});

  @override
  State<MfaScreen> createState() => _MfaScreenState();
}

class _MfaScreenState extends State<MfaScreen> {
  bool? _enabled;
  bool _busy = false;
  String? _error;
  TotpSecret? _secret;
  String? _qrUrl;
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final on = await context.read<AuthService>().mfaEnabled();
    if (mounted) setState(() => _enabled = on);
  }

  Future<bool> _confirmPassword(String title) async {
    final auth = context.read<AuthService>();
    final pw = await askAccountPassword(context, title);
    if (pw == null || pw.isEmpty || !mounted) return false;
    await auth.reauthenticate(pw, askCode: (e) => askMfaCode(context, e));
    return true;
  }

  bool _verifySent = false;

  Future<void> _sendVerification() async {
    try {
      await context.read<AuthService>().resendVerification();
      if (mounted) setState(() => _verifySent = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Eroare: $e');
    }
  }

  Future<void> _checkVerified() async {
    final auth = context.read<AuthService>();
    await auth.reload();
    if (!mounted) return;
    setState(
      () => _error = auth.user?.emailVerified == true ? null : 'Încă nu e confirmat. Apasă linkul din email, apoi încearcă din nou.',
    );
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      if (!await _confirmPassword('Confirmă parola contului')) return;
      final secret = await auth.startTotpEnrollment();
      final url = await secret.generateQrCodeUrl(
        accountName: auth.user?.email ?? 'Notițe',
        issuer: 'Notițe',
      );
      if (mounted) {
        setState(() {
          _secret = secret;
          _qrUrl = url;
        });
      }
    } on AuthError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      // orice altă eroare: o arătăm, ca să știm ce s-a întâmplat
      if (mounted) setState(() => _error = 'Eroare: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    final s = _secret;
    if (s == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().finishTotpEnrollment(s, _code.text);
      if (!mounted) return;
      setState(() {
        _enabled = true;
        _secret = null;
        _qrUrl = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Autentificarea în doi pași e activă.')),
      );
    } on AuthError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      // orice altă eroare: o arătăm, ca să știm ce s-a întâmplat
      if (mounted) setState(() => _error = 'Eroare: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Oprești verificarea în doi pași?'),
        content: const Text(
          'Contul va fi protejat doar de parolă. Recomandat să o lași '
          'pornită.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Renunță'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Oprește'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthService>();
      if (!await _confirmPassword('Confirmă parola contului')) return;
      await auth.disableMfa();
      if (mounted) setState(() => _enabled = false);
    } on AuthError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      // orice altă eroare: o arătăm, ca să știm ce s-a întâmplat
      if (mounted) setState(() => _error = 'Eroare: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Verificare în doi pași')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_enabled == null)
                const Center(child: CircularProgressIndicator())
              else if (_enabled!) ...[
                Icon(Icons.verified_user, size: 56, color: scheme.primary),
                const SizedBox(height: 12),
                Text(
                  'Activă',
                  textAlign: TextAlign.center,
                  style: text.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'La conectarea pe un dispozitiv nou (și în extensia de '
                  'browser) îți cerem, pe lângă parolă, codul de 6 cifre din '
                  'aplicația de autentificare.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _disable,
                  icon: const Icon(Icons.remove_moderator_outlined),
                  label: const Text('Oprește verificarea în doi pași'),
                ),
              ] else if (_secret == null) ...[
                Icon(Icons.shield_outlined, size: 56, color: scheme.primary),
                const SizedBox(height: 12),
                Text(
                  'Protejează contul cu un al doilea pas',
                  textAlign: TextAlign.center,
                  style: text.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Pe lângă parolă, la conectare îți cerem un cod de 6 cifre '
                  'care se schimbă la 30 de secunde, din aplicația de '
                  'autentificare de pe telefon (Google Authenticator, '
                  'Microsoft Authenticator sau Parole pe iPhone). Cine îți '
                  'află parola nu poate intra fără telefonul tău.',
                ),
                const SizedBox(height: 12),
                Card(
                  color: scheme.secondaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Important: dacă pierzi aplicația de autentificare, nu '
                      'te mai poți conecta pe un dispozitiv nou. Păstrează '
                      'cheia afișată la pasul următor (sau adaug-o în două '
                      'aplicații de autentificare).',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (context.watch<AuthService>().user?.emailVerified !=
                    true) ...[
                  // Firebase cere emailul confirmat înainte de 2FA.
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Pasul 1: confirmă adresa de email',
                            style: text.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _verifySent
                                ? 'Ți-am trimis un email la '
                                      '${context.read<AuthService>().user?.email}. '
                                      'Apasă linkul din el (verifică și Spam), '
                                      'apoi „Am confirmat”.'
                                : 'Îți trimitem un email cu un link de '
                                      'confirmare.',
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _sendVerification,
                            icon: const Icon(Icons.mark_email_read_outlined),
                            label: Text(
                              _verifySent
                                  ? 'Retrimite emailul'
                                  : 'Trimite emailul de confirmare',
                            ),
                          ),
                          const SizedBox(height: 6),
                          FilledButton(
                            onPressed: _checkVerified,
                            child: const Text('Am confirmat'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: _busy ? null : _start,
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('Activează'),
                  ),
              ] else ...[
                Text('1. Adaugă contul în aplicație', style: text.titleMedium),
                const SizedBox(height: 8),
                const Text(
                  'Scanează codul QR cu aplicația de autentificare. Pe '
                  'telefonul pe care e și aplicația, apasă „Deschide în '
                  'aplicația de autentificare” sau copiază cheia.',
                ),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(10),
                    child: QrImageView(data: _qrUrl!, size: 200),
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  _secret!.secretKey,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _secret!.secretKey),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Cheia a fost copiată.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiază cheia'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(_qrUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text(
                        'Deschide în aplicația de autentificare',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('2. Scrie codul afișat', style: text.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 26, letterSpacing: 6),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '000000',
                  ),
                  onSubmitted: (_) => _finish(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _finish,
                  child: const Text('Confirmă și activează'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
