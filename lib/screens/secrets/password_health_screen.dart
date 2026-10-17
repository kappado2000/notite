import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/notes_store.dart';
import '../../services/password_tools.dart';
import 'secrets_screen.dart';

/// Verificare de securitate: parole slabe, repetate și vechi.
class PasswordHealthScreen extends StatelessWidget {
  const PasswordHealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final report = PasswordReport.of(context.watch<NotesStore>().allSecrets);
    Widget section(String title, String help, IconData icon, List<Widget> c) =>
        c.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: Icon(icon, color: Theme.of(context).colorScheme.error),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Verificare securitate')),
      body: report.problems == 0
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_outlined, size: 56),
                  SizedBox(height: 12),
                  Text('Nicio problemă găsită'),
                ],
              ),
            )
          : ListView(
              children: [
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
              ],
            ),
    );
  }
}
