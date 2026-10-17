import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/firestore_sync.dart';
import '../services/vault.dart';

/// Pregătește cheia de criptare end-to-end a contului:
/// - cont nou → creează cheia și arată codul de recuperare;
/// - dispozitiv nou → o deblochează cu parola;
/// - parolă resetată → o deblochează cu codul de recuperare.
class KeyScreen extends StatefulWidget {
  const KeyScreen({super.key, required this.user, required this.onReady});

  final User user;
  final void Function(Vault vault) onReady;

  @override
  State<KeyScreen> createState() => _KeyScreenState();
}

enum _Step { working, password, recovery, showCode, error }

class _KeyScreenState extends State<KeyScreen> {
  _Step _step = _Step.working;
  String _status = 'Se pregătește criptarea…';
  String? _error;
  Map<String, dynamic>? _keysDoc;
  Vault? _vault;
  String? _recoveryCode;
  String? _password;
  bool _saved = false;
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _step = _Step.working;
      _error = null;
    });
    _password ??= context.read<AuthService>().takePendingPassword();
    try {
      final snap = await FirestoreSync.keysDoc(widget.user.uid)
          .get(const GetOptions(source: Source.server));
      _keysDoc = snap.data();
      if (_keysDoc == null) {
        if (_password == null) {
          setState(() => _step = _Step.password);
        } else {
          await _create(_password!);
        }
      } else if (_password != null) {
        await _unlockWithPassword(_password!);
      } else {
        setState(() => _step = _Step.password);
      }
    } catch (e) {
      _showNetworkError(e);
    }
  }

  void _showNetworkError(Object e) {
    if (!mounted) return;
    setState(() {
      _step = _Step.error;
      _error =
          'Nu am putut contacta serverul. Prima deschidere a contului pe '
          'un dispozitiv are nevoie de internet.\n\n$e';
    });
  }

  Future<void> _guarded(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _showNetworkError(e);
    }
  }

  /// Prima configurare a contului: cheie nouă + cod de recuperare.
  Future<void> _create(String password) async {
    setState(() {
      _step = _Step.working;
      _status = 'Se generează cheia de criptare…';
    });
    final r = await Vault.create(password);
    await FirestoreSync.keysDoc(widget.user.uid).set(r.keysDoc);
    await r.vault.saveLocal(widget.user.uid);
    setState(() {
      _vault = r.vault;
      _recoveryCode = r.recoveryCode;
      _step = _Step.showCode;
    });
  }

  Future<void> _unlockWithPassword(String password) async {
    setState(() {
      _step = _Step.working;
      _status = 'Se deblochează notițele…';
    });
    final vault = await Vault.unlockWithPassword(_keysDoc!, password);
    if (vault != null) {
      await vault.saveLocal(widget.user.uid);
      widget.onReady(vault);
      return;
    }
    // Parola contului e corectă (Firebase a acceptat-o), dar cheia a fost
    // împachetată cu cea veche → parola a fost resetată.
    _password = password;
    setState(() {
      _step = _Step.recovery;
      _input.clear();
    });
  }

  Future<void> _submitPassword() async {
    final pw = _input.text;
    if (pw.isEmpty) return;
    setState(() {
      _step = _Step.working;
      _status = 'Se verifică parola…';
      _error = null;
    });
    try {
      await context.read<AuthService>().reauthenticate(pw);
    } on AuthError catch (e) {
      setState(() {
        _step = _Step.password;
        _error = e.message;
      });
      return;
    }
    _password = pw;
    await _guarded(
      () => _keysDoc == null ? _create(pw) : _unlockWithPassword(pw),
    );
  }

  Future<void> _submitRecovery() async {
    setState(() {
      _step = _Step.working;
      _status = 'Se verifică codul…';
      _error = null;
    });
    final vault = await Vault.unlockWithRecoveryCode(_keysDoc!, _input.text);
    if (vault == null) {
      setState(() {
        _step = _Step.recovery;
        _error = 'Codul de recuperare nu este corect.';
      });
      return;
    }
    await _guarded(() async {
      // Reîmpachetăm cheia cu parola nouă, ca data viitoare să meargă direct.
      await FirestoreSync.keysDoc(widget.user.uid).set({
        'password': await vault.wrapForPassword(_password!),
      }, SetOptions(merge: true));
      await vault.saveLocal(widget.user.uid);
      widget.onReady(vault);
    });
  }

  Future<void> _startOver() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, size: 40),
        title: const Text('Începi de la zero?'),
        content: const Text(
          'Fără codul de recuperare, notițele din cloud nu pot fi '
          'descifrate de nimeni. Le ștergem din cloud și creăm o cheie nouă. '
          'Notițele salvate pe ACEST dispozitiv se păstrează și vor fi '
          'urcate din nou.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Anulează'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Șterge din cloud'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _step = _Step.working;
      _status = 'Se șterg datele vechi din cloud…';
    });
    await _guarded(() async {
      await FirestoreSync.deleteAllRemote(widget.user.uid);
      await _create(_password!);
    });
  }

  // ------------------------------------------------------------ interfață

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: switch (_step) {
                _Step.working => _working(),
                _Step.password => _passwordStep(),
                _Step.recovery => _recoveryStep(),
                _Step.showCode => _showCodeStep(),
                _Step.error => _errorStep(),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(IconData icon, String title, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, size: 52, color: scheme.primary),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _working() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const CircularProgressIndicator(),
      const SizedBox(height: 16),
      Text(_status),
    ],
  );

  Widget _signOutButton() => TextButton(
    onPressed: () => context.read<AuthService>().signOut(),
    child: const Text('Deconectează-te'),
  );

  Widget _passwordStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _header(
        Icons.lock_person_outlined,
        'Introdu parola',
        'Notițele tale sunt criptate end-to-end. Parola contului le '
            'deblochează pe acest dispozitiv.',
      ),
      TextField(
        controller: _input,
        obscureText: true,
        autofocus: true,
        onSubmitted: (_) => _submitPassword(),
        decoration: InputDecoration(
          labelText: 'Parola contului',
          prefixIcon: const Icon(Icons.lock_outline),
          border: const OutlineInputBorder(),
          errorText: _error,
          errorMaxLines: 3,
        ),
      ),
      const SizedBox(height: 14),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        onPressed: _submitPassword,
        child: const Text('Deblochează'),
      ),
      const SizedBox(height: 8),
      _signOutButton(),
    ],
  );

  Widget _recoveryStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _header(
        Icons.key_outlined,
        'Codul de recuperare',
        'Parola a fost schimbată, iar notițele sunt criptate cu cea veche. '
            'Introdu codul de recuperare primit la crearea contului '
            '(32 de caractere, ex. ABCD-EFGH-…).',
      ),
      TextField(
        controller: _input,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        onSubmitted: (_) => _submitRecovery(),
        decoration: InputDecoration(
          labelText: 'Cod de recuperare',
          prefixIcon: const Icon(Icons.key_outlined),
          border: const OutlineInputBorder(),
          errorText: _error,
        ),
      ),
      const SizedBox(height: 14),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        onPressed: _submitRecovery,
        child: const Text('Recuperează notițele'),
      ),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: _startOver,
        child: const Text('Nu am codul — încep de la zero'),
      ),
      _signOutButton(),
    ],
  );

  Widget _showCodeStep() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          Icons.verified_user_outlined,
          'Salvează codul de recuperare',
          'Notițele tale sunt criptate end-to-end: nici noi, nici Google nu '
              'le putem citi. Dacă îți uiți parola, DOAR acest cod îți poate '
              'recupera notițele. Notează-l și păstrează-l în siguranță.',
        ),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            _recoveryCode!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: scheme.onSecondaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copiază codul'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _recoveryCode!));
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Cod copiat')));
          },
        ),
        CheckboxListTile(
          value: _saved,
          onChanged: (v) => setState(() => _saved = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Am salvat codul într-un loc sigur'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: _saved ? () => widget.onReady(_vault!) : null,
          child: const Text('Continuă'),
        ),
      ],
    );
  }

  Widget _errorStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _header(Icons.cloud_off, 'Fără conexiune', _error ?? ''),
      FilledButton(onPressed: _start, child: const Text('Încearcă din nou')),
      _signOutButton(),
    ],
  );
}
