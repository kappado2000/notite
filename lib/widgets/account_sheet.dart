import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/firestore_sync.dart';
import '../session.dart';
import 'pickers.dart';

void showAccountSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: context.read<Session>()),
        ChangeNotifierProvider.value(value: context.read<AuthService>()),
      ],
      child: const _AccountSheet(),
    ),
  );
}

class _AccountSheet extends StatefulWidget {
  const _AccountSheet();

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  bool? _bioAvailable;
  String _bioLabel = 'amprentă';

  @override
  void initState() {
    super.initState();
    BiometricService.isAvailable().then((v) async {
      final label = await BiometricService.label();
      if (mounted) {
        setState(() {
          _bioAvailable = v;
          _bioLabel = label;
        });
      }
    });
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _toggleBiometric(Session session, bool on) async {
    if (on && !await BiometricService.authenticate()) return;
    session.biometricEnabled = on;
  }

  Future<void> _deleteAccount(Session session, AuthService auth) async {
    final ok = await confirm(
      context,
      'Ștergi definitiv contul și TOATE notițele lui, din cloud și de pe '
      'acest dispozitiv? Acțiunea nu poate fi anulată.',
      action: 'Continuă',
    );
    if (!ok || !mounted) return;
    final password = await promptText(
      context,
      title: 'Confirmă cu parola',
      hint: 'Parola contului',
      action: 'Șterge contul',
      obscure: true,
    );
    if (password == null || !mounted) return;
    final nav = Navigator.of(context);
    try {
      await session.deleteAccount(auth, password);
      nav.pop();
    } on AuthError catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Ștergerea nu a reușit: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final auth = context.watch<AuthService>();
    final user = auth.user ?? session.user;
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  (user.email ?? '?').substring(0, 1).toUpperCase(),
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ),
              title: Text(user.email ?? ''),
              subtitle: Text(
                user.emailVerified ? 'Email confirmat' : 'Email neconfirmat',
              ),
            ),
            if (!user.emailVerified)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () async {
                        try {
                          await auth.resendVerification();
                          _toast('Am retrimis emailul de confirmare');
                        } on AuthError catch (e) {
                          _toast(e.message);
                        }
                      },
                      child: const Text('Retrimite emailul'),
                    ),
                    TextButton(
                      onPressed: auth.reload,
                      child: const Text('Am confirmat'),
                    ),
                  ],
                ),
              ),
            ValueListenableBuilder(
              valueListenable: session.sync.state,
              builder: (_, state, _) {
                final (icon, text) = switch (state) {
                  SyncState.connecting => (Icons.sync, 'Se conectează…'),
                  SyncState.synced => (
                    Icons.cloud_done_outlined,
                    'Sincronizat cu cloudul',
                  ),
                  SyncState.offline => (
                    Icons.cloud_off_outlined,
                    'Offline — modificările se trimit când revine internetul',
                  ),
                  SyncState.error => (
                    Icons.error_outline,
                    'Eroare de sincronizare',
                  ),
                };
                return ListTile(leading: Icon(icon), title: Text(text));
              },
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Securitate',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (_bioAvailable == true)
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: Text('Deblocare cu $_bioLabel'),
                subtitle: const Text(
                  'Cerută la deschidere și după 1 minut în fundal',
                ),
                value: session.biometricEnabled,
                onChanged: (v) => _toggleBiometric(session, v),
              )
            else if (_bioAvailable == false)
              const ListTile(
                leading: Icon(Icons.fingerprint),
                title: Text('Deblocare biometrică'),
                subtitle: Text('Indisponibilă pe acest dispozitiv'),
              ),
            const ListTile(
              leading: Icon(Icons.enhanced_encryption_outlined),
              title: Text('Notițe criptate pe dispozitiv'),
              subtitle: Text(
                'AES-256, cu cheia păstrată în seiful securizat al sistemului',
              ),
            ),
            const ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('Acces în cloud doar pentru contul tău'),
              subtitle: Text(
                'Transfer criptat (HTTPS), reguli stricte de acces',
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Deconectare'),
              onTap: () async {
                Navigator.pop(context);
                await session.signOut(auth);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
              title: Text(
                'Șterge contul',
                style: TextStyle(color: scheme.error),
              ),
              onTap: () => _deleteAccount(session, auth),
            ),
          ],
        ),
      ),
    );
  }
}
