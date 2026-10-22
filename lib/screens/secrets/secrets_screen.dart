import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/notes_store.dart';
import '../../models/secret_item.dart';
import '../../services/biometric_service.dart';
import '../../services/csv_import.dart';
import '../../services/firestore_sync.dart';
import '../../services/password_tools.dart';
import '../../services/vault.dart';
import '../../session.dart';
import '../../utils/format.dart';
import '../../widgets/note_actions.dart';
import '../shell.dart';
import 'password_health_screen.dart';
import 'secret_detail_screen.dart';
import 'secret_edit_screen.dart';
import 'secret_widgets.dart';

const secretsRouteName = 'parole';

Future<void> openSecrets(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute(
    settings: const RouteSettings(name: secretsRouteName),
    builder: (_) => const SecretsScreen(),
  ),
);

/// Secțiunea „Parole”. Are deblocare proprie, cerută la fiecare intrare
/// și din nou dacă aplicația trece în fundal.
class SecretsScreen extends StatefulWidget {
  const SecretsScreen({super.key});

  @override
  State<SecretsScreen> createState() => _SecretsScreenState();
}

class _SecretsScreenState extends State<SecretsScreen>
    with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _busy = false;
  bool _bioAvailable = false;
  String _bioLabel = 'amprentă';
  String? _error;
  final _password = TextEditingController();
  final _search = TextEditingController();
  String _query = '';
  bool _searchOpen = false;

  /// null = toate; altfel un tip anume.
  SecretType? _type;
  bool _favorites = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initBiometric();
  }

  Future<void> _initBiometric() async {
    _bioAvailable = await BiometricService.isAvailable();
    _bioLabel = await BiometricService.label();
    if (!mounted) return;
    setState(() {});
    if (_bioAvailable) _unlockBiometric();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _relock();
    }
  }

  /// Închide detaliile deschise și blochează din nou secțiunea.
  void _relock() {
    if (!mounted || !_unlocked) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() {
      _unlocked = false;
      _password.clear();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _password.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _unlockBiometric() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await BiometricService.authenticate();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _unlocked = true;
    });
  }

  /// Verificare cu parola contului — merge și offline, fiindcă folosește
  /// cheile de criptare (copia locală Firestore), nu serverul de logare.
  Future<void> _unlockPassword() async {
    if (_password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.read<Session>();
    final uid = session.uid;
    if (session.preview) {
      // Previzualizare fără cloud: nu există chei de verificat.
      setState(() {
        _unlocked = true;
        _busy = false;
      });
      return;
    }
    try {
      final doc = (await FirestoreSync.keysDoc(uid).get()).data();
      final ok =
          doc != null &&
          await Vault.unlockWithPassword(doc, _password.text) != null;
      setState(() {
        _unlocked = ok;
        _error = ok ? null : 'Parolă greșită.';
      });
    } catch (e) {
      setState(() => _error = 'Nu am putut verifica parola: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final type = await showModalBottomSheet<SecretType>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final t in SecretType.values)
              ListTile(
                leading: Icon(t.icon),
                title: Text(t.label),
                onTap: () => Navigator.pop(ctx, t),
              ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    final store = context.read<NotesStore>();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SecretEditScreen(item: store.newSecret(type)),
      ),
    );
  }

  Future<void> _importCsv() async {
    final store = context.read<NotesStore>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (files.isEmpty || !mounted) return;
      final text = utf8.decode(
        await files.first.readAsBytes(),
        allowMalformed: true,
      );
      final r = secretsFromCsv(
        text,
        existing: store.allSecrets,
        create: () => store.newSecret(SecretType.login),
      );
      if (!mounted) return;
      if (r.items.isEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Nicio parolă nouă (${r.skipped} existente sau incomplete).',
            ),
          ),
        );
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.file_download_outlined),
          title: const Text('Import parole'),
          content: Text(
            'Am găsit ${r.items.length} '
            '${r.items.length == 1 ? 'parolă nouă' : 'parole noi'} '
            '(format ${r.source})'
            '${r.skipped > 0 ? '; ${r.skipped} sărite (deja existente sau goale)' : ''}.'
            '\n\nDupă import, șterge fișierul CSV: parolele sunt în el '
            'necriptate.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Anulează'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Importă'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await store.addSecrets(r.items);
      messenger.showSnackBar(
        SnackBar(content: Text('${r.items.length} parole importate.')),
      );
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Nu am putut citi fișierul: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parole'),
        actions: [
          if (_unlocked)
            IconButton(
              tooltip: _searchOpen ? 'Închide căutarea' : 'Caută',
              icon: Icon(_searchOpen ? Icons.search_off : Icons.search),
              onPressed: () => setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) {
                  _search.clear();
                  _query = '';
                }
              }),
            ),
          if (_unlocked)
            IconButton(
              tooltip: 'Blochează',
              icon: const Icon(Icons.lock_outline),
              onPressed: _relock,
            ),
          if (_unlocked)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'import') _importCsv();
                if (v == 'health') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PasswordHealthScreen(),
                    ),
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'health',
                  child: ListTile(
                    leading: Icon(Icons.health_and_safety_outlined),
                    title: Text('Verificare securitate'),
                  ),
                ),
                PopupMenuItem(
                  value: 'import',
                  child: ListTile(
                    leading: Icon(Icons.file_download_outlined),
                    title: Text('Importă din CSV'),
                    subtitle: Text('Chrome, iCloud, Bitwarden, LastPass'),
                  ),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: aboveNavBar(
        context,
        _unlocked
            ? FloatingActionButton.extended(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('Adaugă'),
              )
            : null,
      ),
      body: _unlocked ? _list() : _lockView(),
    );
  }

  Widget _lockView() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.password, size: 56, color: scheme.primary),
              const SizedBox(height: 12),
              Text(
                'Parolele sunt protejate',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Confirmă că ești tu ca să le vezi.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              if (_bioAvailable) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: _busy ? null : _unlockBiometric,
                  icon: const Icon(Icons.fingerprint),
                  label: Text('Deblochează cu $_bioLabel'),
                ),
                const SizedBox(height: 20),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('sau'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              TextField(
                controller: _password,
                obscureText: true,
                autofocus: !_bioAvailable,
                onSubmitted: (_) => _unlockPassword(),
                decoration: InputDecoration(
                  labelText: 'Parola contului',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _busy ? null : _unlockPassword,
                child: const Text('Deblochează cu parola'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list() {
    final store = context.watch<NotesStore>();
    final all = store.secrets;
    final scoped = all.where(
      (i) => (!_favorites || i.favorite) && (_type == null || i.type == _type),
    );
    final types = {for (final i in all) i.type};
    final today = DateUtils.dateOnly(DateTime.now());
    final soon = [
      for (final i in all)
        if (i.expiresOn case final d?)
          if (DateUtils.dateOnly(d).difference(today).inDays <= 30) i,
    ]..sort((a, b) => a.expiresOn!.compareTo(b.expiresOn!));
    // Totalul lunar al abonamentelor, pe monede.
    final monthly = <String, double>{};
    for (final i in all.where((i) => i.type == SecretType.subscription)) {
      final c = i.monthlyCost;
      if (c != null) monthly[i.currency] = (monthly[i.currency] ?? 0) + c;
    }
    final items = store.searchSecrets(_query, scoped);
    final report = PasswordReport.of(all);

    return Column(
      children: [
        if (_searchOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: SearchBar(
              controller: _search,
              hintText: 'Caută site, utilizator, card…',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              autoFocus: true,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final (selected, label, onTap) in [
                (
                  _type == null && !_favorites,
                  'Toate (${all.length})',
                  () => setState(() {
                    _type = null;
                    _favorites = false;
                  }),
                ),
                if (all.any((i) => i.favorite))
                  (
                    _favorites,
                    'Favorite',
                    () => setState(() => _favorites = !_favorites),
                  ),
                for (final t in SecretType.values)
                  if (types.contains(t))
                    (
                      _type == t,
                      _plural(t),
                      () => setState(() => _type = _type == t ? null : t),
                    ),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Center(
                    child: ChoiceChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: (_) => onTap(),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (report.problems > 0)
          Card(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.health_and_safety_outlined),
              title: Text(
                '${report.problems} '
                '${report.problems == 1 ? 'problemă' : 'probleme'} '
                'de securitate',
              ),
              subtitle: const Text('Parole slabe, repetate sau vechi'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PasswordHealthScreen()),
              ),
            ),
          ),
        if (soon.isNotEmpty && _type == null && _query.isEmpty)
          Card(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.event_busy_outlined),
              title: Text(
                soon.length == 1
                    ? '${soon.first.displayTitle} expiră curând'
                    : '${soon.length} intrări expiră curând',
              ),
              subtitle: Text(
                [
                  for (final i in soon.take(3))
                    '${i.displayTitle}: ${formatShortDate(i.expiresOn!)}',
                ].join('\n'),
              ),
              onTap: soon.length == 1
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SecretDetailScreen(id: soon.first.id),
                      ),
                    )
                  : null,
            ),
          ),
        if (_type == SecretType.subscription && monthly.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              'Pe lună: ${_money(monthly, 1)}\n'
              'Pe an: ${_money(monthly, 12)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    all.isEmpty
                        ? 'Nicio parolă salvată.\nApasă „Adaugă” pentru prima.'
                        : 'Niciun rezultat',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: bottomSpace(context)),
                  itemCount: items.length,
                  itemBuilder: (_, i) => SwipeToDelete(
                    id: 'secret-${items[i].id}',
                    label: 'Șterge',
                    question:
                        'Ștergi „${items[i].displayTitle}”? Datele salvate '
                        'vor fi șterse definitiv.',
                    onDelete: (store) => store.deleteSecret(items[i]),
                    doneMessage: 'Șters',
                    // Fără „Anulează” când are atașamente: acelea se
                    // șterg imediat, odată cu intrarea.
                    onUndo:
                        store.attachmentsOf(items[i].attachmentOwnerId).isEmpty
                        ? (store) => store.saveSecret(items[i].copy())
                        : null,
                    child: SecretTile(item: items[i]),
                  ),
                ),
        ),
      ],
    );
  }

  /// „59,99 RON + 10 EUR” (sumele pe monede, înmulțite cu [factor]).
  static String _money(Map<String, double> byCurrency, int factor) => [
    for (final e in byCurrency.entries)
      '${(e.value * factor).toStringAsFixed(2).replaceAll('.00', '').replaceAll('.', ',')} ${e.key}',
  ].join(' + ');

  static String _plural(SecretType t) => switch (t) {
    SecretType.login => 'Conturi',
    SecretType.card => 'Carduri',
    SecretType.bank => 'Conturi bancare',
    SecretType.identity => 'Acte',
    SecretType.subscription => 'Abonamente',
    SecretType.wifi => 'Wi-Fi',
    SecretType.note => 'Note',
  };
}

class SecretTile extends StatelessWidget {
  const SecretTile({super.key, required this.item});

  final SecretItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Ce copiază butonul din listă, pe tip.
    final (copy, what, secret) = switch (item.type) {
      SecretType.login ||
      SecretType.wifi ||
      SecretType.subscription => (item.password, 'Parola copiată', true),
      SecretType.card => (item.cardDigits, 'Numărul cardului copiat', true),
      SecretType.bank => (item.ibanCompact, 'IBAN copiat', false),
      SecretType.identity => (item.cnp, 'CNP copiat', true),
      SecretType.note => (item.notes, 'Nota copiată', true),
    };
    return ListTile(
      leading: SecretAvatar(item: item),
      title: Row(
        children: [
          Flexible(
            child: Text(item.displayTitle, overflow: TextOverflow.ellipsis),
          ),
          if (item.favorite) ...[
            const SizedBox(width: 4),
            Icon(Icons.star, size: 16, color: scheme.primary),
          ],
        ],
      ),
      subtitle: item.subtitle.isEmpty
          ? null
          : Text(item.subtitle, overflow: TextOverflow.ellipsis),
      trailing: copy.isEmpty
          ? null
          : IconButton(
              tooltip: 'Copiază',
              icon: const Icon(Icons.copy),
              onPressed: () =>
                  copyValue(context, copy, secret: secret, what: what),
            ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SecretDetailScreen(id: item.id)),
      ),
    );
  }
}
