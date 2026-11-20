import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/notes_store.dart';
import '../../models/secret_item.dart';
import '../../services/google_compare.dart';
import 'secret_detail_screen.dart';
import 'secret_widgets.dart';

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

  /// Ce conține intrarea din fișier (și, la parolă diferită, contul din
  /// Notițe): site, utilizator, parolă (ascunsă, cu „Arată” / copiere),
  /// notițe.
  Future<void> _details(SecretItem i, {PasswordDiff? diff}) {
    final src = widget.result.source;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(i.displayTitle, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Din $src',
                style: TextStyle(color: Theme.of(ctx).colorScheme.primary),
              ),
              const SizedBox(height: 12),
              _Field('Site', i.url),
              _Field('Utilizator', i.username),
              _Field('Parolă', i.password, secret: true),
              if (i.notes.trim().isNotEmpty) _Field('Notițe', i.notes.trim()),
              if (diff != null) ...[
                const Divider(height: 32),
                Text(
                  'În Notițe',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.primary),
                ),
                const SizedBox(height: 8),
                _Field('Site', diff.local.url),
                _Field('Utilizator', diff.local.username),
                _Field('Parolă', diff.local.password, secret: true),
                if (diff.olderInNotite)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Parola din $src e una veche a acestui cont (o găsești '
                      'în „Parole anterioare”).',
                    ),
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SecretDetailScreen(id: diff.local.id),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Deschide contul din Notițe'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
                : 'Bifează ce vrei să adaugi. Atinge un rând ca să vezi '
                      'ce conține.',
          ),
          if (left.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: picked == left.length
                        ? null
                        : () => setState(
                            () => _pick.addAll(left.map((i) => i.id)),
                          ),
                    icon: const Icon(Icons.check_box_outlined),
                    label: const Text('Bifează toate'),
                  ),
                  TextButton.icon(
                    onPressed: picked == 0
                        ? null
                        : () => setState(
                            () => _pick.removeAll(left.map((i) => i.id)),
                          ),
                    icon: const Icon(Icons.check_box_outline_blank),
                    label: const Text('Debifează toate'),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('$picked bifate'),
                  ),
                ],
              ),
            ),
          for (final (n, i) in left.indexed)
            ListTile(
              leading: _num(n),
              title: Text(i.displayTitle),
              subtitle: Text(_sub(i)),
              onTap: () => _details(i),
              trailing: Checkbox(
                value: _pick.contains(i.id),
                onChanged: (v) => setState(
                  () => v == true ? _pick.add(i.id) : _pick.remove(i.id),
                ),
              ),
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
                onTap: () => _details(d.other, diff: d),
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

/// Un câmp în fișa de detalii: valoarea, cu copiere; parola ascunsă până
/// apeși „Arată”.
class _Field extends StatefulWidget {
  const _Field(this.label, this.value, {this.secret = false});

  final String label;
  final String value;
  final bool secret;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final hidden = widget.secret && !_shown;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(widget.label),
      subtitle: SelectableText(
        v.isEmpty ? '—' : (hidden ? '•' * 10 : v),
        style: const TextStyle(fontSize: 15),
      ),
      trailing: v.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.secret)
                  IconButton(
                    tooltip: _shown ? 'Ascunde' : 'Arată',
                    icon: Icon(
                      _shown
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _shown = !_shown),
                  ),
                IconButton(
                  tooltip: 'Copiază',
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () => copyValue(
                    context,
                    v,
                    secret: widget.secret,
                    what: widget.secret
                        ? '${widget.label} copiată'
                        : '${widget.label} copiat',
                  ),
                ),
              ],
            ),
    );
  }
}
