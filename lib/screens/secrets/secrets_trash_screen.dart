import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/notes_store.dart';
import '../../models/note.dart';
import '../../models/secret_item.dart';

/// Coșul parolelor și jurnalul ștergerilor: fiecare cont șters (de tine,
/// din extensie sau la unirea dublurilor) stă aici 30 de zile, cu data,
/// dispozitivul și motivul. Se poate recupera sau șterge definitiv.
class SecretsTrashScreen extends StatelessWidget {
  const SecretsTrashScreen({super.key});

  static String _when(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  static int _daysLeft(SecretItem i) {
    final end = i.deletedAt!.add(const Duration(days: Note.trashDays));
    return end.difference(DateTime.now()).inDays.clamp(0, Note.trashDays);
  }

  Future<void> _purge(BuildContext context, SecretItem i) async {
    final store = context.read<NotesStore>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ștergi definitiv „${i.displayTitle}”?'),
        content: const Text('Nu se mai poate recupera.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Renunță'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Șterge definitiv'),
          ),
        ],
      ),
    );
    if (ok == true) await store.purgeSecret(i);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final list = store.trashedSecrets;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Coș parole')),
      body: list.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Coșul e gol.\n\nCe ștergi (sau ce se unește ca dublură) '
                  'stă aici 30 de zile, cu data, dispozitivul și motivul.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: list.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, n) {
                if (n == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'Jurnalul ștergerilor: fiecare cont rămâne 30 de zile, '
                      'apoi se șterge definitiv.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  );
                }
                final i = list[n - 1];
                return ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: Text(i.displayTitle),
                  subtitle: Text(
                    [
                      if (i.username.isNotEmpty) i.username,
                      'Șters ${_when(i.deletedAt!)}'
                          '${i.deletedFrom.isEmpty ? '' : ' · ${i.deletedFrom}'}',
                      if (i.deletedWhy.isNotEmpty) i.deletedWhy,
                      'Mai stă ${_daysLeft(i)} zile',
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Recuperează',
                        icon: const Icon(Icons.restore),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await store.restoreSecret(i);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('„${i.displayTitle}” a revenit.'),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Șterge definitiv',
                        icon: const Icon(Icons.delete_forever_outlined),
                        onPressed: () => _purge(context, i),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
