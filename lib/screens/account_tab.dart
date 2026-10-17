import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/app_settings.dart';
import '../data/notes_store.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/firestore_sync.dart';
import '../session.dart';
import '../widgets/pickers.dart';
import 'shell.dart';

/// Contul, securitatea și aspectul aplicației.
class AccountTab extends StatefulWidget {
  const AccountTab({super.key});

  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
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

  Future<void> _newRecoveryCode(Session session) async {
    if (session.preview) {
      _toast('Indisponibil în previzualizare');
      return;
    }
    final ok = await confirm(
      context,
      'Generezi un cod de recuperare nou? Codul vechi nu va mai funcționa.',
      action: 'Generează',
    );
    if (!ok || !mounted) return;
    final String code;
    try {
      code = await session.regenerateRecoveryCode();
    } catch (e) {
      _toast('Nu am putut genera codul (ești online?): $e');
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.key_outlined, size: 36),
        title: const Text('Noul cod de recuperare'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Notează-l într-un loc sigur. E singura cale de a-ți recupera '
              'notițele dacă îți uiți parola.',
            ),
            const SizedBox(height: 16),
            SelectableText(
              code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copiază'),
            onPressed: () => Clipboard.setData(ClipboardData(text: code)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Am salvat codul'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(Session session) async {
    if (session.preview) {
      _toast('Indisponibil în previzualizare');
      return;
    }
    final auth = context.read<AuthService>();
    final ok = await confirm(
      context,
      'Ștergi definitiv contul și TOATE notițele și parolele lui, din cloud '
      'și de pe acest dispozitiv? Acțiunea nu poate fi anulată.',
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
    try {
      await session.deleteAccount(auth, password);
    } on AuthError catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Ștergerea nu a reușit: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final settings = context.watch<AppSettings>();
    final store = context.watch<NotesStore>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Cont')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, bottomSpace(context)),
        children: [
          // ---- profil
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        child: Text(
                          session.email.isEmpty
                              ? '?'
                              : session.email.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.email.isEmpty
                                  ? 'Previzualizare'
                                  : session.email,
                              style: text.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            _SyncStatus(session: session),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _Stat('${store.activeNotes.length}', 'notițe'),
                      _Stat('${store.notebooks.length}', 'carnete'),
                      _Stat('${store.secrets.length}', 'parole'),
                    ],
                  ),
                  if (!session.preview) _VerifyEmail(toast: _toast),
                ],
              ),
            ),
          ),

          // ---- securitate
          const _SectionTitle('Securitate'),
          Card(
            child: Column(
              children: [
                if (_bioAvailable == true)
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: Text('Deblocare cu $_bioLabel'),
                    subtitle: const Text(
                      'La deschidere și după 1 minut în fundal',
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
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('Cod de recuperare nou'),
                  subtitle: const Text('Dacă l-ai pierdut pe cel vechi'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _newRecoveryCode(session),
                ),
                const Divider(indent: 16, endIndent: 16),
                const _Info(
                  Icons.shield_outlined,
                  'Criptare end-to-end',
                  'Notițele și parolele pleacă de pe dispozitiv deja '
                      'criptate — nimeni altcineva nu le poate citi.',
                ),
                const _Info(
                  Icons.enhanced_encryption_outlined,
                  'Criptate și pe dispozitiv',
                  'AES-256, cu cheia în seiful securizat al sistemului.',
                ),
              ],
            ),
          ),

          // ---- aspect
          const _SectionTitle('Aspect'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Temă', style: text.labelLarge),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('Automat'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Luminos'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Întunecat'),
                        ),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (s) => settings.themeMode = s.first,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Afișare notițe', style: text.labelLarge),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false, label: Text('Listă')),
                        ButtonSegment(value: true, label: Text('Grilă')),
                      ],
                      selected: {settings.notesGrid},
                      onSelectionChanged: (s) => settings.notesGrid = s.first,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ---- cont
          const _SectionTitle('Cont'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Deconectare'),
                  onTap: session.preview
                      ? () => _toast('Indisponibil în previzualizare')
                      : () => session.signOut(context.read<AuthService>()),
                ),
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: scheme.error,
                  ),
                  title: Text(
                    'Șterge contul',
                    style: TextStyle(color: scheme.error),
                  ),
                  onTap: () => _deleteAccount(session),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Notițe · versiunea 1.0',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncStatus extends StatelessWidget {
  const _SyncStatus({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sync = session.sync;
    if (sync == null) {
      return Text(
        'Doar local (previzualizare)',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }
    return ValueListenableBuilder(
      valueListenable: sync.state,
      builder: (_, state, _) {
        final (icon, label, color) = switch (state) {
          SyncState.connecting => (
            Icons.sync,
            'Se conectează…',
            scheme.outline,
          ),
          SyncState.synced => (
            Icons.cloud_done_outlined,
            'Sincronizat',
            scheme.primary,
          ),
          SyncState.offline => (
            Icons.cloud_off_outlined,
            'Offline — se trimite când revine internetul',
            scheme.secondary,
          ),
          SyncState.error => (
            Icons.error_outline,
            'Eroare de sincronizare',
            scheme.error,
          ),
        };
        return Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label, style: TextStyle(color: color, fontSize: 13)),
            ),
          ],
        );
      },
    );
  }
}

class _VerifyEmail extends StatelessWidget {
  const _VerifyEmail({required this.toast});
  final void Function(String) toast;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user;
    if (user == null || user.emailVerified) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confirmă adresa de email din mesajul primit.',
            style: TextStyle(color: scheme.onSecondaryContainer),
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: () async {
                  try {
                    await auth.resendVerification();
                    toast('Am retrimis emailul de confirmare');
                  } on AuthError catch (e) {
                    toast(e.message);
                  }
                },
                child: const Text('Retrimite'),
              ),
              TextButton(
                onPressed: auth.reload,
                child: const Text('Am confirmat'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: scheme.primary),
            ),
            Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _Info extends StatelessWidget {
  const _Info(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(title),
    subtitle: Text(text),
  );
}
