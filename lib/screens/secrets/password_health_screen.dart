import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/notes_store.dart';
import '../../models/secret_item.dart';
import '../../services/breach_check.dart';
import '../../services/password_tools.dart';
import 'secrets_screen.dart';

/// Verificare de securitate: parole slabe, repetate, vechi și — la cerere —
/// parole apărute în scurgeri de date publice.
class PasswordHealthScreen extends StatefulWidget {
  const PasswordHealthScreen({super.key});

  @override
  State<PasswordHealthScreen> createState() => _PasswordHealthScreenState();
}

class _PasswordHealthScreenState extends State<PasswordHealthScreen> {
  /// Intrările găsite în scurgeri (null = neverificat încă).
  List<(SecretItem, int)>? _breached;
  bool _checking = false;
  int _done = 0;
  int _total = 0;
  String? _error;

  Future<void> _checkBreaches() async {
    final items = context
        .read<NotesStore>()
        .allSecrets
        .where((i) => i.password.isNotEmpty && i.type != SecretType.card)
        .toList();
    // O singură cerere pe parolă, chiar dacă e folosită de mai multe ori.
    final byPassword = <String, List<SecretItem>>{};
    for (final i in items) {
      byPassword.putIfAbsent(i.password, () => []).add(i);
    }
    setState(() {
      _checking = true;
      _error = null;
      _done = 0;
      _total = byPassword.length;
    });
    final check = BreachCheck();
    final found = <(SecretItem, int)>[];
    try {
      for (final e in byPassword.entries) {
        final n = await check.timesPwned(e.key);
        if (n > 0) found.addAll([for (final i in e.value) (i, n)]);
        if (!mounted) return;
        setState(() => _done++);
      }
      found.sort((a, b) => b.$2.compareTo(a.$2));
      setState(() => _breached = found);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Nu am putut verifica (fără internet?).');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = PasswordReport.of(context.watch<NotesStore>().allSecrets);
    final scheme = Theme.of(context).colorScheme;
    Widget section(String title, String help, IconData icon, List<Widget> c) =>
        c.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: Icon(icon, color: scheme.error),
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(help),
              ),
              ...c,
              const Divider(),
            ],
          );

    final breached = _breached;
    return Scaffold(
      appBar: AppBar(title: const Text('Verificare securitate')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Parole compromise',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Verifică dacă parolele tale apar în scurgeri de date '
                    'publice (Have I Been Pwned). Parolele nu părăsesc '
                    'telefonul: se trimit doar 5 caractere dintr-o amprentă '
                    'a lor, comune pentru sute de parole diferite.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  if (_checking)
                    LinearProgressIndicator(
                      value: _total == 0 ? null : _done / _total,
                    )
                  else
                    OutlinedButton.icon(
                      icon: const Icon(Icons.travel_explore),
                      label: Text(
                        breached == null ? 'Verifică acum' : 'Verifică din nou',
                      ),
                      onPressed: _checkBreaches,
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: scheme.error)),
                  ],
                  if (breached != null && breached.isEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.gpp_good_outlined, color: scheme.primary),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Nicio parolă nu apare în scurgeri.'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (breached != null)
            section(
              'Compromise (${breached.length})',
              'Apar în scurgeri de date: schimbă-le imediat.',
              Icons.gpp_bad_outlined,
              [
                for (final (i, n) in breached)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SecretTile(item: i),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                        child: Text(
                          'Văzută de $n ori',
                          style: TextStyle(color: scheme.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          section(
            'Parole slabe (${report.weak.length})',
            'Ușor de ghicit. Schimbă-le cu parole generate.',
            Icons.warning_amber_rounded,
            [for (final i in report.weak) SecretTile(item: i)],
          ),
          section(
            'Parole repetate (${report.reused.length})',
            'Aceeași parolă pe mai multe conturi: dacă una e furată, '
                'toate sunt în pericol.',
            Icons.content_copy_outlined,
            [
              for (final g in report.reused) ...[
                for (final i in g) SecretTile(item: i),
                const SizedBox(height: 8),
              ],
            ],
          ),
          section(
            'Parole vechi (${report.old.length})',
            'Neschimbate de peste un an.',
            Icons.history,
            [for (final i in report.old) SecretTile(item: i)],
          ),
          if (report.problems == 0)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.verified_outlined, size: 48),
                  SizedBox(height: 8),
                  Text('Nicio parolă slabă, repetată sau veche.'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
