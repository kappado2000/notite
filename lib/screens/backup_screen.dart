import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../services/data_export.dart';
import '../services/file_opener.dart';
import '../services/full_backup.dart';
import '../session.dart';
import '../utils/format.dart';
import '../widgets/identity_check.dart';

/// „Backup și spațiu”: backup complet criptat (cu parole), automat o dată
/// pe săptămână, restaurare și spațiul ocupat în cloud.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  /// Planul gratuit Firebase (Spark): 1 GiB stocare Firestore în total.
  static const _quota = 1024 * 1024 * 1024;

  bool? _configured;
  String? _location;
  bool _busy = false;

  String get _uid => context.read<Session>().uid;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final c = await FullBackup.configured(_uid);
    final loc = FullBackup.autoSupported ? await FullBackup.location() : null;
    if (!mounted) return;
    setState(() {
      _configured = c;
      _location = loc;
    });
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(text), persist: false));

  Future<void> _setPassword() async {
    if (!await confirmIdentity(
      context,
      reason: 'Confirmă că ești tu ca să setezi parola de backup.',
    )) {
      return;
    }
    if (!mounted) return;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _BackupPasswordDialog(),
    );
    if (password == null) return;
    setState(() => _busy = true);
    try {
      await FullBackup.setPassword(_uid, password);
      if (!mounted) return;
      final where = FullBackup.autoSupported
          ? await FullBackup.runNow(context.read<NotesStore>(), _uid)
          : null;
      _toast(
        where == null
            ? 'Parola de backup e setată.'
            : 'Parola e setată; primul backup e în $where.',
      );
    } catch (e) {
      _toast('Nu a reușit: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _runNow() async {
    setState(() => _busy = true);
    try {
      final where = await FullBackup.runNow(context.read<NotesStore>(), _uid);
      _toast(
        where == null
            ? 'Nu am putut scrie backup-ul.'
            : 'Backup făcut: $where.',
      );
    } catch (e) {
      _toast('Nu a reușit: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Fișierul criptat, prin meniul de partajare (Fișiere, iCloud, email…).
  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final bytes = await FullBackup.build(context.read<NotesStore>(), _uid);
      if (bytes == null) return;
      await FileOpener.share(
        FullBackup.fileName(),
        'application/octet-stream',
        bytes,
      );
    } catch (e) {
      _toast('Nu a reușit: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Oprești backup-ul complet?'),
        content: const Text(
          'Nu se mai fac backup-uri automate. Fișierele deja făcute rămân '
          'și se pot restaura cu parola veche.',
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
    if (ok != true) return;
    await FullBackup.disable(_uid);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final usage = store.storageUsage();
    final used = usage.attachmentBytes + usage.textBytes;
    final ratio = (used / _quota).clamp(0.0, 1.0);
    final last = FullBackup.lastAuto(_uid);

    return Scaffold(
      appBar: AppBar(title: const Text('Backup și spațiu')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
        children: [
          if (_busy) const LinearProgressIndicator(),
          // ------------------------------------------------ backup complet
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.enhanced_encryption_outlined,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Backup complet criptat',
                          style: text.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tot ce e în Notițe — notițe, atașamente ȘI parolele — '
                    'într-un singur fișier criptat cu o parolă de backup. '
                    'Îl poți restaura pe orice dispozitiv, chiar dacă se '
                    'pierde contul din cloud.',
                  ),
                  const SizedBox(height: 12),
                  if (_configured == null)
                    const SizedBox.shrink()
                  else if (_configured == false) ...[
                    Text(
                      'Nu e pornit: parolele tale există doar în cloud și '
                      'pe dispozitive.',
                      style: TextStyle(color: scheme.error),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Pornește — alege parola de backup'),
                      onPressed: _busy ? null : _setPassword,
                    ),
                  ] else ...[
                    if (FullBackup.autoSupported)
                      _Line(
                        Icons.schedule,
                        'Automat, o dată pe săptămână',
                        [
                          if (_location != null) 'în $_location',
                          last == null
                              ? 'încă niciunul'
                              : 'ultimul: ${formatShortDate(last)}',
                        ].join(' · '),
                      )
                    else
                      const _Line(
                        Icons.info_outline,
                        'În browser nu se face automat',
                        'Backup-ul automat rulează pe iPhone. Aici îl poți '
                            'salva manual.',
                      ),
                    if (_location != null && !_location!.contains('iCloud'))
                      const _Line(
                        Icons.cloud_off_outlined,
                        'iCloud Drive nu e disponibil',
                        'Backup-ul rămâne doar pe telefon. Salvează-l din '
                            'când în când și în altă parte („Salvează în…”).',
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (FullBackup.autoSupported)
                          FilledButton.tonalIcon(
                            icon: const Icon(Icons.backup_outlined),
                            label: const Text('Fă backup acum'),
                            onPressed: _busy ? null : _runNow,
                          ),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.ios_share),
                          label: const Text('Salvează în…'),
                          onPressed: _busy ? null : _share,
                        ),
                        OutlinedButton(
                          onPressed: _busy ? null : _setPassword,
                          child: const Text('Schimbă parola'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _disable,
                          child: const Text('Oprește'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Fără parola de backup fișierul nu poate fi deschis de '
                    'nimeni — nici de tine. Poate fi aceeași cu parola '
                    'contului; notează-o în siguranță.',
                    style: text.bodySmall?.copyWith(color: scheme.outline),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore),
                  title: const Text('Restaurează din backup'),
                  subtitle: const Text(
                    'Backup complet (cere parola) sau export vechi. Adaugă ce '
                    'lipsește; nu dublează și nu șterge nimic.',
                  ),
                  onTap: () => DataExport.restoreBackup(context, store),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Exportă doar notițele (necriptat)'),
                  subtitle: const Text(
                    'Fișier JSON fără parole, de citit și în alte programe',
                  ),
                  onTap: () => DataExport.shareBackup(context, store),
                ),
              ],
            ),
          ),
          // --------------------------------------------------------- spațiu
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.storage_outlined, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Spațiu în cloud', style: text.titleMedium),
                      ),
                      Text('${_mb(used)} din 1 GB', style: text.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: ratio < 0.01 ? 0.01 : ratio,
                      minHeight: 10,
                      color: ratio > 0.8
                          ? scheme.error
                          : ratio > 0.6
                          ? scheme.tertiary
                          : scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Line(
                    Icons.attach_file,
                    'Atașamente: ${_mb(usage.attachmentBytes)}',
                    '${usage.attachments} fișiere (poze, PDF-uri, note vocale)',
                  ),
                  _Line(
                    Icons.notes,
                    'Text: ${_mb(usage.textBytes)}',
                    'Notițe, carnete, parole',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ratio > 0.8
                        ? 'Aproape plin: șterge atașamente mari (și golește '
                              'coșul), altfel sincronizarea se va opri.'
                        : 'Planul gratuit Firebase are 1 GB în total. Pozele '
                              'se micșorează automat la adăugare.',
                    style: text.bodySmall?.copyWith(
                      color: ratio > 0.8 ? scheme.error : scheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _mb(int bytes) {
    final mb = bytes / (1024 * 1024);
    return mb < 10 ? '${mb.toStringAsFixed(1)} MB' : '${mb.round()} MB';
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.title, this.subtitle);

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
  );
}

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog();

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _ok() {
    if (_a.text.length < 10) {
      setState(() => _error = 'Minim 10 caractere.');
      return;
    }
    if (_a.text != _b.text) {
      setState(() => _error = 'Parolele nu coincid.');
      return;
    }
    Navigator.pop(context, _a.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Parola de backup'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Cu ea se deschide fișierul de backup. Dacă o uiți, backup-ul nu '
          'mai poate fi folosit.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _a,
          obscureText: !_show,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Parola',
            suffixIcon: IconButton(
              icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _show = !_show),
            ),
          ),
        ),
        TextField(
          controller: _b,
          obscureText: !_show,
          decoration: InputDecoration(labelText: 'Din nou', errorText: _error),
          onSubmitted: (_) => _ok(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Renunță'),
      ),
      FilledButton(onPressed: _ok, child: const Text('Salvează')),
    ],
  );
}
