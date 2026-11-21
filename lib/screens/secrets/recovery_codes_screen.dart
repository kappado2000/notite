import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_settings.dart';
import '../../data/notes_store.dart';
import '../../models/secret_item.dart';
import '../../services/file_opener.dart';
import '../../services/recovery_codes.dart';
import '../../utils/format.dart';
import 'secret_detail_screen.dart';
import 'secret_edit_screen.dart';
import 'secret_widgets.dart';

/// „Coduri de rezervă”: toate conturile cu 2FA și codurile lor de
/// recuperare, mereu la zi; exportul pe hârtie (PDF) și semnalul când foaia
/// printată nu mai e la zi.
class RecoveryCodesScreen extends StatefulWidget {
  const RecoveryCodesScreen({super.key});

  @override
  State<RecoveryCodesScreen> createState() => _RecoveryCodesScreenState();
}

class _RecoveryCodesScreenState extends State<RecoveryCodesScreen> {
  bool _shown = false;
  bool _checkedNotes = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkedNotes) return;
    _checkedNotes = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _moveFromNotes());
  }

  /// Codurile scrise până acum în „Notițe” trec, cu acordul tău, în câmpul
  /// lor („Coduri de rezervă 2FA”).
  Future<void> _moveFromNotes() async {
    final store = context.read<NotesStore>();
    final found = [
      for (final i in RecoveryCodes.accounts(store.secrets))
        if (i.recoveryCodes.trim().isEmpty)
          if (RecoveryCodes.fromNotes(i.notes) case final r?) (i, r),
    ];
    if (found.isEmpty || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Coduri găsite în notițe'),
        content: SingleChildScrollView(
          child: Text(
            'Am găsit coduri de rezervă scrise în notițele '
            '${found.length == 1 ? 'unui cont' : 'a ${found.length} conturi'}:\n\n'
            '${found.map((f) => '• ${f.$1.displayTitle}${f.$1.username.isEmpty ? '' : ' (${f.$1.username})'} – ${RecoveryCodes.lines(f.$2.codes).length} coduri').join('\n')}\n\n'
            'Le mut în câmpul „Coduri de rezervă 2FA”? Restul notițelor rămâne '
            'neschimbat.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nu acum'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mută-le'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final (i, r) in found) {
      final current = store.secret(i.id);
      if (current == null) continue;
      await store.saveSecret(
        current.copy()
          ..recoveryCodes = r.codes
          ..notes = r.notes,
      );
    }
  }

  Future<void> _export(List<SecretItem> accounts) async {
    final settings = context.read<AppSettings>();
    final messenger = ScaffoldMessenger.of(context);
    final kind = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.print_outlined),
        title: const Text('Exportă codurile de rezervă'),
        content: const Text(
          'Fișierul cu toate codurile e NECRIPTAT. Printează-l sau copiază-l '
          'într-un loc sigur, apoi șterge-l de pe dispozitiv (și din '
          'Descărcări / coș).\n\n'
          'PDF: foaie gata de printat, cu căsuțe de bifat.\n'
          'Text: fișier .txt simplu, se deschide oriunde.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Renunță'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'txt'),
            child: const Text('Text'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'pdf'),
            child: const Text('PDF'),
          ),
        ],
      ),
    );
    if (kind == null) return;
    try {
      final open = kIsWeb ? FileOpener.open : FileOpener.share;
      if (kind == 'pdf') {
        await open(
          'Coduri-rezerva-2FA.pdf',
          'application/pdf',
          await RecoveryCodes.pdf(accounts),
        );
      } else {
        await open(
          'Coduri-rezerva-2FA.txt',
          'text/plain',
          utf8.encode(RecoveryCodes.text(accounts)),
        );
      }
      settings.markRecoveryExport(RecoveryCodes.fingerprint(accounts));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Exportul a eșuat: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final settings = context.watch<AppSettings>();
    final scheme = Theme.of(context).colorScheme;
    final accounts = RecoveryCodes.accounts(store.secrets);
    final withCodes = accounts
        .where((i) => i.recoveryCodes.trim().isNotEmpty)
        .length;
    final lastAt = settings.recoveryExportAt;
    final stale =
        accounts.isNotEmpty &&
        settings.recoveryExportHash != RecoveryCodes.fingerprint(accounts);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coduri de rezervă'),
        actions: [
          IconButton(
            tooltip: _shown ? 'Ascunde codurile' : 'Arată codurile',
            icon: Icon(
              _shown
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: () => setState(() => _shown = !_shown),
          ),
          IconButton(
            tooltip: 'Exportă (PDF de printat)',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: accounts.isEmpty ? null : () => _export(accounts),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            color: stale ? scheme.tertiaryContainer : null,
            child: ListTile(
              leading: Icon(
                stale ? Icons.print_outlined : Icons.check_circle_outline,
              ),
              title: Text(
                '$withCodes din ${accounts.length} conturi cu 2FA au coduri '
                'de rezervă',
              ),
              subtitle: Text(
                lastAt == null
                    ? 'Nu ai exportat încă foaia de printat.'
                    : stale
                    ? 'S-au schimbat de la ultimul export '
                          '(${formatShortDate(lastAt)}). Exportă și printează '
                          'din nou.'
                    : 'Foaia exportată pe ${formatShortDate(lastAt)} e la zi.',
              ),
              trailing: accounts.isEmpty
                  ? null
                  : FilledButton.tonal(
                      onPressed: () => _export(accounts),
                      child: const Text('Exportă'),
                    ),
            ),
          ),
          if (accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Niciun cont cu 2FA încă. Codurile de rezervă le primești de '
                'la site când activezi verificarea în doi pași.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final i in accounts) _row(i),
        ],
      ),
    );
  }

  Widget _row(SecretItem i) {
    final scheme = Theme.of(context).colorScheme;
    final codes = RecoveryCodes.lines(i.recoveryCodes);
    final sub = [if (i.username.isNotEmpty) i.username].join(' · ');
    if (codes.isEmpty) {
      return ListTile(
        leading: SecretAvatar(item: i),
        title: Text(i.displayTitle),
        subtitle: Text.rich(
          TextSpan(
            children: [
              if (sub.isNotEmpty) TextSpan(text: '$sub\n'),
              TextSpan(
                text: 'Fără coduri de rezervă – atinge ca să le adaugi',
                style: TextStyle(color: scheme.error),
              ),
            ],
          ),
        ),
        isThreeLine: sub.isNotEmpty,
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SecretEditScreen(item: i.copy())),
        ),
      );
    }
    return ListTile(
      leading: SecretAvatar(item: i),
      title: Text(i.displayTitle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sub.isNotEmpty) Text(sub),
          const SizedBox(height: 4),
          Wrap(
            spacing: 14,
            runSpacing: 2,
            children: [
              for (final c in codes)
                Text(
                  _shown ? c : '•' * c.length.clamp(4, 10),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                ),
            ],
          ),
        ],
      ),
      trailing: IconButton(
        tooltip: 'Copiază codurile',
        icon: const Icon(Icons.copy),
        onPressed: () => copyValue(
          context,
          codes.join('\n'),
          secret: true,
          what: 'Coduri copiate',
        ),
      ),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => SecretDetailScreen(id: i.id))),
    );
  }
}
