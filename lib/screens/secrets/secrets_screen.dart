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
import '../../theme.dart';
import '../../services/pin_lock.dart';
import '../../services/vault.dart';
import '../../session.dart';
import '../../utils/format.dart';
import '../../widgets/note_actions.dart';
import '../../widgets/pin_pad.dart';
import '../shell.dart';
import 'password_health_screen.dart';
import 'pin_setup.dart';
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

  /// Codul de 6 cifre (pe acest dispozitiv).
  late final PinLock _pin = PinLock(context.read<Session>().uid);
  bool _pinSet = false;

  /// Deblocare cu parola contului în loc de cod (la cerere sau după prea
  /// multe coduri greșite).
  bool _usePassword = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPin();
    _initBiometric();
  }

  Future<void> _initPin() async {
    final set = await _pin.isSet();
    final lockedOut = set && await _pin.isLockedOut();
    if (!mounted) return;
    setState(() {
      _pinSet = set;
      if (lockedOut) {
        _usePassword = true;
        _error = 'Prea multe coduri greșite. Deblochează cu parola contului.';
      }
    });
  }

  Future<String?> _checkPin(String pin) async {
    switch (await _pin.verify(pin)) {
      case PinResult.ok:
        if (mounted) setState(() => _unlocked = true);
        return null;
      case PinResult.wrong:
        final left = PinLock.maxAttempts - await _pin.failedAttempts();
        return 'Cod greșit. ${left == 1 ? 'Mai ai o încercare.' : 'Mai ai $left încercări.'}';
      case PinResult.lockedOut:
        if (mounted) {
          setState(() {
            _usePassword = true;
            _error =
                'Prea multe coduri greșite. Deblochează cu parola contului.';
          });
        }
        return null;
    }
  }

  /// După deblocarea cu parola: codul e iar valabil; dacă nu există încă,
  /// propunem unul (o singură dată).
  Future<void> _afterPasswordUnlock() async {
    await _pin.resetAttempts();
    if (!mounted) return;
    setState(() => _usePassword = false);
    final session = context.read<Session>();
    if (_pinSet || session.pinOffered) return;
    session.pinOffered = true;
    final want = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.pin_outlined),
        title: const Text('Folosești un cod de 6 cifre?'),
        content: const Text(
          'Data viitoare deschizi Parolele cu un cod de 6 cifre, verificat '
          'automat după ultima cifră, în loc de parola contului. Îl poți '
          'schimba oricând din Cont → Securitate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nu acum'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Setează codul'),
          ),
        ],
      ),
    );
    if (want == true && mounted && await showPinSetup(context, _pin)) {
      if (mounted) setState(() => _pinSet = true);
    }
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
        _error = null;
      });
      await _afterPasswordUnlock();
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
      if (ok) await _afterPasswordUnlock();
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
                leading: CircleAvatar(
                  backgroundColor: secretTint(t).container(ctx),
                  foregroundColor: secretTint(t).onContainer(ctx),
                  child: Icon(t.icon, size: 20),
                ),
                title: Text(t.label),
                onTap: () => Navigator.pop(ctx, t),
              ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    await _addType(type);
  }

  Future<void> _addType(SecretType type) async {
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
          if (_unlocked &&
              context.watch<NotesStore>().secrets.any((i) => i.favorite))
            IconButton(
              tooltip: _favorites ? 'Toate' : 'Doar favoritele',
              icon: Icon(_favorites ? Icons.star : Icons.star_outline),
              onPressed: () => setState(() {
                _favorites = !_favorites;
                if (_favorites) _type = null;
              }),
            ),
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
    if (_pinSet && !_usePassword) return _pinView();
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
                  errorMaxLines: 3,
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
              if (_pinSet && _error == null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _usePassword = false),
                  child: const Text('Folosește codul de 6 cifre'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Deblocare cu codul de 6 cifre: verificat automat la ultima cifră.
  Widget _pinView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PinPad(
              title: 'Introdu codul',
              subtitle: 'Parolele sunt protejate.',
              onCompleted: _checkPin,
              extraKey: _bioAvailable
                  ? IconButton(
                      tooltip: 'Deblochează cu $_bioLabel',
                      iconSize: 30,
                      onPressed: _busy ? null : _unlockBiometric,
                      icon: const Icon(Icons.fingerprint),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() {
                _usePassword = true;
                _error = null;
              }),
              child: const Text('Am uitat codul — folosește parola contului'),
            ),
          ],
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
    final grouped = _type == null && !_favorites && _query.trim().isEmpty;
    // fără căutare: alfabetic; cu căutare: ordinea potrivirilor
    final shownItems = _query.trim().isEmpty ? _alphabetical(items) : items;
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
        // Toate tipurile la vedere: grilă 4×2, pătrate egale.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.25,
            children: [
              _typeTile(
                icon: Icons.apps,
                label: 'Toate',
                count: all.length,
                tint: null,
                selected: _type == null && !_favorites,
                onTap: () => setState(() {
                  _type = null;
                  _favorites = false;
                }),
              ),
              for (final t in SecretType.values)
                _typeTile(
                  icon: t.icon,
                  label: _short(t),
                  count: all.where((i) => i.type == t).length,
                  tint: secretTint(t),
                  selected: _type == t,
                  onTap: () => setState(() {
                    _favorites = false;
                    _type = _type == t ? null : t;
                  }),
                ),
            ],
          ),
        ),
        if (report.problems > 0)
          Card(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            color: Theme.of(context).colorScheme.errorContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: Theme.of(context).colorScheme.error
                    .withValues(alpha: 0.55),
              ),
            ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: Theme.of(context).colorScheme.secondary
                    .withValues(alpha: 0.55),
              ),
            ),
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
          child: items.isEmpty && !grouped
              ? Center(
                  child: Text(
                    all.isEmpty
                        ? 'Nicio parolă salvată.\nApasă „Adaugă” pentru prima.'
                        : 'Niciun rezultat',
                    textAlign: TextAlign.center,
                  ),
                )
              : grouped
              // „Toate”, fără căutare: câte o secțiune pe tip, în nuanța lui.
              ? ListView(
                  padding: EdgeInsets.fromLTRB(12, 4, 12, bottomSpace(context)),
                  children: [
                    // toate tipurile, mereu în aceeași ordine (și cele goale)
                    for (final t in SecretType.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _section(
                          t,
                          items.where((i) => i.type == t).toList(),
                        ),
                      ),
                  ],
                )
              // un singur tip deschis: intrările lui, încadrate în cardul tipului
              : _type != null
              ? ListView(
                  padding: EdgeInsets.fromLTRB(12, 4, 12, bottomSpace(context)),
                  children: [_section(_type!, shownItems)],
                )
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: bottomSpace(context)),
                  itemCount: shownItems.length,
                  itemBuilder: (_, i) =>
                      _swipe(shownItems[i], SecretTile(item: shownItems[i])),
                ),
        ),
      ],
    );
  }

  Widget _swipe(SecretItem item, Widget child) {
    final store = context.read<NotesStore>();
    return SwipeToDelete(
      id: 'secret-${item.id}',
      label: 'Șterge',
      question:
          'Ștergi „${item.displayTitle}”? Datele salvate '
          'vor fi șterse definitiv.',
      onDelete: (store) => store.deleteSecret(item),
      doneMessage: 'Șters',
      // Fără „Anulează” când are atașamente: acelea se
      // șterg imediat, odată cu intrarea.
      onUndo: store.attachmentsOf(item.attachmentOwnerId).isEmpty
          ? (store) => store.saveSecret(item.copy())
          : null,
      child: child,
    );
  }

  /// După titlu, fără să țină cont de diacritice și de majuscule.
  static List<SecretItem> _alphabetical(Iterable<SecretItem> items) {
    String key(SecretItem i) => NotesStore.foldText(i.displayTitle.trim());
    return [...items]..sort((a, b) {
      final c = key(a).compareTo(key(b));
      return c != 0 ? c : a.displayTitle.compareTo(b.displayTitle);
    });
  }

  /// Secțiunea unui tip: antet colorat (nume, câte sunt, adaugă, deschide)
  /// și toate intrările lui, în ordine alfabetică.
  Widget _section(SecretType t, List<SecretItem> list) {
    final tint = secretTint(t);
    final accent = tint.onContainer(context);
    final sorted = _alphabetical(list);
    void open() => setState(() => _type = t);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: tint.surface(context),
      // margine subțire, în nuanța închisă a tipului
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: 0.55)),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: accent, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: list.isEmpty ? () => _addType(t) : open,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: tint.container(context),
                      foregroundColor: accent,
                      child: Icon(t.icon, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _plural(t),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: tint.container(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${list.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Adaugă: ${t.label}',
                      icon: Icon(Icons.add, color: accent),
                      onPressed: () => _addType(t),
                    ),
                    Icon(Icons.chevron_right, color: accent),
                    const SizedBox(width: 6),
                  ],
                ),
              ),
            ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Nimic salvat încă',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final i in sorted) ...[
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: accent.withValues(alpha: 0.15),
              ),
              _swipe(i, SecretTile(item: i, plain: true)),
            ],
          ],
        ),
      ),
    );
  }

  /// „59,99 RON + 10 EUR” (sumele pe monede, înmulțite cu [factor]).
  static String _money(Map<String, double> byCurrency, int factor) => [
    for (final e in byCurrency.entries)
      '${(e.value * factor).toStringAsFixed(2).replaceAll('.00', '').replaceAll('.', ',')} ${e.key}',
  ].join(' + ');

  /// Numele scurt din grila de sus (încape pe un rând).
  static String _short(SecretType t) => switch (t) {
    SecretType.bank => 'Bancă',
    _ => _plural(t),
  };

  /// Un pătrat din grila tipurilor: iconiță, nume, câte sunt.
  Widget _typeTile({
    required IconData icon,
    required String label,
    required int count,
    required GroupTint? tint,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final fg = tint?.onContainer(context) ?? scheme.onPrimaryContainer;
    final bg = selected
        ? (tint?.container(context) ?? scheme.primaryContainer)
        : (tint?.surface(context) ?? scheme.surfaceContainerLowest);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? fg : fg.withValues(alpha: 0.55),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
  const SecretTile({super.key, required this.item, this.plain = false});

  final SecretItem item;

  /// În secțiunea colorată a tipului: fără fundalul și bara proprii.
  final bool plain;

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
    final tint = secretTint(item.type);
    return Material(
      color: plain ? Colors.transparent : tint.surface(context),
      child: Container(
        decoration: plain
            ? null
            : BoxDecoration(
                border: Border(
                  left: BorderSide(color: tint.onContainer(context), width: 4),
                ),
              ),
        child: ListTile(
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
        ),
      ),
    );
  }
}
