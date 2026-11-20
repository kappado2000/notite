import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/notes_store.dart';
import '../../models/secret_item.dart';
import '../../services/google_compare.dart';

/// Rezultatul „Compară cu Google”: ce lipsește din Notițe (se adaugă doar
/// ce bifezi), ce are altă parolă (rămâne cea din Notițe, dacă nu alegi
/// altfel) și câte sunt identice.
class PasswordCompareScreen extends StatefulWidget {
  const PasswordCompareScreen({super.key, required this.result});

  final PasswordCompare result;

  @override
  State<PasswordCompareScreen> createState() => _PasswordCompareScreenState();
}

class _PasswordCompareScreenState extends State<PasswordCompareScreen> {
  late final Set<String> _pick = {for (final i in widget.result.missing) i.id};
  final Set<String> _added = {};
  final Set<String> _usedOther = {};

  String _sub(SecretItem i) => [
    if (i.username.isNotEmpty) i.username,
    if (hostOfSafe(i.url).isNotEmpty) hostOfSafe(i.url),
  ].join(' · ');

  static String hostOfSafe(String u) {
    final m = RegExp(r'^(?:[a-z]+://)?([^/?#]+)').firstMatch(u.trim());
    return (m?[1] ?? '').replaceFirst(RegExp(r'^www\.'), '');
  }

  Future<void> _addPicked() async {
    final store = context.read<NotesStore>();
    final messenger = ScaffoldMessenger.of(context);
    final items = [
      for (final i in widget.result.missing)
        if (_pick.contains(i.id) && !_added.contains(i.id)) i,
    ];
    if (items.isEmpty) return;
    for (final i in items) {
      i.notes = [
        if (i.notes.trim().isNotEmpty) i.notes.trim(),
        'Adăugat din compararea cu ${widget.result.source}.',
      ].join('\n\n');
    }
    await store.addSecrets(items);
    setState(() => _added.addAll(items.map((i) => i.id)));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          items.length == 1
              ? 'Un cont adăugat în Notițe.'
              : '${items.length} conturi adăugate în Notițe.',
        ),
      ),
    );
  }

  Future<void> _useOther(PasswordDiff d) async {
    final store = context.read<NotesStore>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Folosești parola din ${widget.result.source}?'),
        content: Text(
          'Pentru „${d.local.displayTitle}”'
          '${d.local.username.isEmpty ? '' : ' (${d.local.username})'}. '
          'Parola actuală din Notițe intră în „Parole anterioare”.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Renunță'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Folosește-o'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final current = store.secret(d.local.id);
    if (current == null) return;
    await store.saveSecret(current.copy()..password = d.other.password);
    setState(() => _usedOther.add(d.local.id));
  }

  /// Numărul curent din listă (1, 2, 3…).
  Widget _num(int n) => SizedBox(
    width: 36,
    child: Text(
      '${n + 1}.',
      textAlign: TextAlign.right,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );

  Widget _header(String text, {String? sub}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: Theme.of(context).textTheme.titleMedium),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              sub,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final left = r.missing.where((i) => !_added.contains(i.id)).toList();
    final picked = left.where((i) => _pick.contains(i.id)).length;
    final older = r.different.where((d) => d.olderInNotite).length;
    return Scaffold(
      appBar: AppBar(title: Text('Comparare cu ${r.source}')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                '${r.missing.length} lipsesc din Notițe · '
                '${r.different.length} cu altă parolă · '
                '${r.same} identice\n\n'
                'După ce termini, șterge fișierul exportat: parolele sunt '
                'necriptate în el.',
              ),
            ),
          ),
          _header(
            'Lipsesc din Notițe (${left.length})',
            sub: left.isEmpty
                ? 'Toate conturile sunt și în Notițe.'
                : 'Bifează ce vrei să adaugi.',
          ),
          for (final (n, i) in left.indexed)
            CheckboxListTile(
              secondary: _num(n),
              value: _pick.contains(i.id),
              onChanged: (v) => setState(
                () => v == true ? _pick.add(i.id) : _pick.remove(i.id),
              ),
              title: Text(i.displayTitle),
              subtitle: Text(_sub(i)),
            ),
          if (r.different.isNotEmpty) ...[
            _header(
              'Altă parolă în ${r.source} (${r.different.length})',
              sub:
                  'Rămâne parola din Notițe. '
                  '${older > 0 ? '$older au în ${r.source} o parolă veche, pe care ai schimbat-o deja în Notițe. ' : ''}'
                  'Alege „Folosește” doar dacă știi că cea din '
                  '${r.source} e cea bună.',
            ),
            for (final (n, d) in r.different.indexed)
              ListTile(
                leading: _num(n),
                title: Text(d.local.displayTitle),
                subtitle: Text(
                  [
                    if (_sub(d.local).isNotEmpty) _sub(d.local),
                    _usedOther.contains(d.local.id)
                        ? 'Folosește acum parola din ${r.source}'
                        : d.olderInNotite
                        ? 'Parolă veche în ${r.source} (deja schimbată)'
                        : 'Parolă diferită — verifică pe site',
                  ].join('\n'),
                ),
                isThreeLine: _sub(d.local).isNotEmpty,
                trailing: d.olderInNotite || _usedOther.contains(d.local.id)
                    ? null
                    : TextButton(
                        onPressed: () => _useOther(d),
                        child: const Text('Folosește'),
                      ),
              ),
          ],
        ],
      ),
      floatingActionButton: picked == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: _addPicked,
              icon: const Icon(Icons.add),
              label: Text(
                picked == 1 ? 'Adaugă 1 cont' : 'Adaugă $picked conturi',
              ),
            ),
    );
  }
}
