import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/app_settings.dart';
import '../../data/notes_store.dart';
import '../../models/secret_item.dart';
import '../../services/biometric_service.dart';
import '../../services/csv_import.dart';
import '../../services/firestore_sync.dart';
import '../../services/password_tools.dart';
import '../../services/secret_helpers.dart';
import '../../theme.dart';
import '../../services/pin_lock.dart';
import '../../services/vault.dart';
import '../../session.dart';
import '../../utils/format.dart';
import '../../widgets/note_actions.dart';
import '../../widgets/pin_pad.dart';
import '../shell.dart';
import 'password_fix_screen.dart';
import 'password_health_screen.dart';
import 'pin_setup.dart';
import 'secret_detail_screen.dart';
import 'secret_edit_screen.dart';
import 'secrets_trash_screen.dart';
import 'authenticator_screen.dart';
import '../../widgets/auth_icon.dart';
import 'password_compare_screen.dart';
import '../../services/google_compare.dart';
import '../../services/file_opener.dart';
import 'secret_widgets.dart';
import 'two_factor_screen.dart';
import '../../services/two_factor_sites.dart';

const secretsRouteName = 'parole';

/// [authenticator]: după deblocare se deschide direct „Autentificator”
/// (butonul de pe Acasă).
Future<void> openSecrets(BuildContext context, {bool authenticator = false}) =>
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: secretsRouteName),
        builder: (_) => SecretsScreen(openAuthenticator: authenticator),
      ),
    );

/// Secțiunea „Parole”. Are deblocare proprie, cerută la fiecare intrare
/// și din nou dacă aplicația trece în fundal.
class SecretsScreen extends StatefulWidget {
  const SecretsScreen({super.key, this.openAuthenticator = false});

  final bool openAuthenticator;

  @override
  State<SecretsScreen> createState() => _SecretsScreenState();
}

class _SecretsScreenState extends State<SecretsScreen>
    with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _authOpened = false;
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

  /// În „Conturi”: subcategoria deschisă (null = lista subcategoriilor).
  LoginCategory? _category;
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
    // Orice atingere / tastă, oriunde în aplicație, amână blocarea.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
    _initPin();
    _initBiometric();
    TwoFactorSites.instance
      ..addListener(_tfaChanged)
      ..load();
  }

  void _tfaChanged() {
    if (mounted) setState(() {});
  }

  // ------------------------------------------- blocare după inactivitate

  Timer? _idle;

  void _onPointer(PointerEvent e) {
    if (e is PointerDownEvent || e is PointerScrollEvent) _activity();
  }

  bool _onKey(KeyEvent e) {
    _activity();
    return false;
  }

  void _activity() {
    if (!_unlocked) return;
    _idle?.cancel();
    final minutes = context.read<AppSettings>().secretsAutoLockMinutes;
    if (minutes <= 0) return;
    _idle = Timer(Duration(minutes: minutes), _relock);
  }

  Future<void> _chooseAutoLock() async {
    final settings = context.read<AppSettings>();
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Blocare automată'),
        children: [
          for (final m in [1, 2, 5, 10, 15, 30, 0])
            ListTile(
              leading: Icon(
                settings.secretsAutoLockMinutes == m
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(
                m == 0
                    ? 'Doar la ieșirea din aplicație'
                    : 'După $m ${m == 1 ? 'minut' : 'minute'} fără folosire',
              ),
              onTap: () => Navigator.pop(ctx, m),
            ),
        ],
      ),
    );
    if (v == null) return;
    settings.secretsAutoLockMinutes = v;
    _activity();
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
    } else if (state == AppLifecycleState.resumed &&
        mounted &&
        !_unlocked &&
        _bioAvailable &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      // revenire în aplicație pe Parole: Face ID pornește singur
      _unlockBiometric();
    }
  }

  /// Închide detaliile deschise și blochează din nou secțiunea.
  void _relock() {
    _idle?.cancel();
    if (!mounted || !_unlocked) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() {
      _unlocked = false;
      _password.clear();
    });
  }

  @override
  void dispose() {
    _idle?.cancel();
    TwoFactorSites.instance.removeListener(_tfaChanged);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    _password.dispose();
    _search.dispose();
    super.dispose();
  }

  /// O dată pe pornire: același site + același utilizator = un singur cont.
  /// Parola cea mai nouă rămâne actuală; celelalte intră în „Parole
  /// anterioare”, de unde pot fi alese.
  static bool _mergeChecked = false;

  Future<void> _autoMerge() async {
    final store = context.read<NotesStore>();
    final messenger = ScaffoldMessenger.of(context);
    // nu mai unim pe tăcute: întâi lista, apoi doar dacă ești de acord
    final groups = duplicateGroups(store.allSecrets);
    if (groups.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          groups.length == 1
              ? 'Un cont apare de mai multe ori'
              : '${groups.length} conturi apar de mai multe ori',
        ),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'Același site și același utilizator. Le unesc într-unul '
                'singur? Parola cea mai nouă rămâne; celelalte intră în '
                '„Parole anterioare”, iar copiile merg în coș (30 de zile).',
              ),
              const SizedBox(height: 12),
              for (final g in groups)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text('${g.length}×'),
                  title: Text(g.first.displayTitle),
                  subtitle: Text(
                    g.first.username.isEmpty ? '—' : g.first.username,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nu acum'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unește'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = await store.mergeDuplicateSecrets();
    if (n > 0) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            'Am unit $n ${n == 1 ? 'dublură' : 'dubluri'} (același site și '
            'utilizator). Parolele vechi sunt în „Parole anterioare” la '
            'fiecare cont.',
          ),
        ),
      );
    }
  }

  /// Lista celor care expiră curând; atingerea deschide intrarea.
  void _showExpiring(List<SecretItem> soon) {
    if (soon.length == 1) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SecretDetailScreen(id: soon.first.id),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Expiră curând',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            for (final i in soon)
              ListTile(
                leading: SecretAvatar(item: i),
                title: Text(i.displayTitle),
                subtitle: Text('Expiră ${formatShortDate(i.expiresOn!)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SecretDetailScreen(id: i.id),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
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
                  backgroundColor: secretTint(ctx, t).container(ctx),
                  foregroundColor: secretTint(ctx, t).onContainer(ctx),
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

  Future<void> _compareCsv() async {
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
      final r = compareWithCsv(
        text,
        existing: store.allSecrets,
        create: ([t = SecretType.login]) => store.newSecret(t),
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PasswordCompareScreen(result: r)),
      );
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Nu am putut citi fișierul: $e')),
      );
    }
  }

  Future<void> _exportGoogle() async {
    final store = context.read<NotesStore>();
    final messenger = ScaffoldMessenger.of(context);
    final r = googleCsv(store.allSecrets);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Export pentru Google'),
        content: Text(
          '${r.rows} ${r.rows == 1 ? 'rând' : 'rânduri'} '
          '(câte unul pentru fiecare site al unui cont)'
          '${r.skipped > 0 ? '; ${r.skipped} conturi fără site rămân doar în Notițe' : ''}.\n\n'
          'Fișierul are parolele NECRIPTATE. Importă-l imediat pe '
          'passwords.google.com → Setări → Importă parolele, apoi '
          'șterge-l (și din Coșul de gunoi).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Renunță'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exportă'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // pe PC (web): descărcare; pe telefon: Salvează în Fișiere
      await (kIsWeb ? FileOpener.open : FileOpener.share)(
        'Notite-pentru-Google.csv',
        'text/csv',
        utf8.encode(r.csv),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Nu am putut exporta: $e')),
      );
    }
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
        create: ([t = SecretType.login]) => store.newSecret(t),
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
    // Tocmai deblocat (sau setarea s-a schimbat): pornește numărătoarea.
    if (_unlocked && _idle?.isActive != true) _activity();
    if (_unlocked && widget.openAuthenticator && !_authOpened) {
      _authOpened = true;
      // unirea dublurilor rămâne pentru următoarea intrare în Parole
      _mergeChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AuthenticatorScreen()));
      });
    }
    if (_unlocked && !_mergeChecked) {
      _mergeChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoMerge());
    }
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
              tooltip: context.watch<AppSettings>().secretsHeaderHidden
                  ? 'Arată cardurile de sus'
                  : 'Ascunde cardurile de sus',
              icon: Icon(
                context.watch<AppSettings>().secretsHeaderHidden
                    ? Icons.grid_view
                    : Icons.grid_off,
              ),
              onPressed: () {
                final s = context.read<AppSettings>();
                s.secretsHeaderHidden = !s.secretsHeaderHidden;
              },
            ),
          if (_unlocked)
            IconButton(
              tooltip: 'Autentificator (coduri 2FA)',
              icon: const AuthIcon(),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AuthenticatorScreen()),
              ),
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
                if (v == 'compare') _compareCsv();
                if (v == 'exportGoogle') _exportGoogle();
                if (v == 'autolock') _chooseAutoLock();
                if (v == 'trash') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SecretsTrashScreen(),
                    ),
                  );
                }
                if (v == 'health') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PasswordHealthScreen(),
                    ),
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'autolock',
                  child: ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Blocare automată'),
                    subtitle: Text(switch (context
                        .read<AppSettings>()
                        .secretsAutoLockMinutes) {
                      0 => 'Doar la ieșirea din aplicație',
                      1 => 'După 1 minut',
                      final m => 'După $m minute',
                    }),
                  ),
                ),
                const PopupMenuItem(
                  value: 'health',
                  child: ListTile(
                    leading: Icon(Icons.health_and_safety_outlined),
                    title: Text('Verificare securitate'),
                  ),
                ),
                PopupMenuItem(
                  value: 'trash',
                  child: ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Coș și jurnal ștergeri'),
                    subtitle: Text(
                      '${context.read<NotesStore>().trashedSecrets.length} '
                      'în coș (30 de zile)',
                    ),
                  ),
                ),
                const PopupMenuItem(
                  value: 'import',
                  child: ListTile(
                    leading: Icon(Icons.file_download_outlined),
                    title: Text('Importă din CSV'),
                    subtitle: Text('Chrome, iCloud, Bitwarden, LastPass'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'compare',
                  child: ListTile(
                    leading: Icon(Icons.compare_arrows),
                    title: Text('Compară cu Google'),
                    subtitle: Text('Ce lipsește din Notițe (export CSV)'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'exportGoogle',
                  child: ListTile(
                    leading: Icon(Icons.file_upload_outlined),
                    title: Text('Exportă pentru Google'),
                    subtitle: Text('Fișier CSV pentru Importă parolele'),
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
    context.watch<AppSettings>(); // culorile tipurilor
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
    // conturi de pe site-uri cu 2FA prin aplicație, fără cheie salvată
    final noTfa = TwoFactorSites.instance.missing(all);
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

    // pe ecrane late conținutul nu se întinde pe tot monitorul
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(
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
            // Cardurile de sus (tipuri, avertizări): se pot trage în lateral
            // cu butonul de lângă titlu, ca să rămână tot ecranul pentru listă.
            ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => SizeTransition(
                  sizeFactor: anim,
                  alignment: Alignment.topCenter,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(-1, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: context.watch<AppSettings>().secretsHeaderHidden
                    ? const SizedBox(
                        key: ValueKey('ascuns'),
                        width: double.infinity,
                      )
                    : Column(
                        key: const ValueKey('vizibil'),
                        children: [
                          // Toate tipurile la vedere: grilă 4×2, pătrate egale.
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                            // telefon: 4×2; ecran lat (PC, tabletă): un rând de 8, scund
                            child: LayoutBuilder(
                              builder: (context, box) {
                                final wide = box.maxWidth >= 640;
                                final cols = wide ? 8 : 4;
                                final tileW =
                                    (box.maxWidth - 8 * (cols - 1)) / cols;
                                final extent = wide
                                    ? 66.0
                                    : (tileW / 1.25).clamp(60.0, 90.0);
                                final scheme = Theme.of(context).colorScheme;
                                // avertizările: pe un rând separat, împărțit
                                // egal; cu cât sunt mai puține, cu atât mai
                                // explicit titlul (3 → scurt, 1 → complet)
                                final alerts = [
                                  if (report.problems > 0)
                                    (
                                      icon: Icons.health_and_safety_outlined,
                                      count: report.accounts,
                                      color: scheme.error,
                                      labels: const [
                                        'Risc',
                                        'Conturi de reparat',
                                        'Conturi de reparat: slabe, repetate sau vechi',
                                      ],
                                      tooltip: 'Conturi de reparat: slabe, repetate, vechi',
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const PasswordFixScreen(),
                                        ),
                                      ),
                                    ),
                                  if (soon.isNotEmpty &&
                                      _type == null &&
                                      _query.isEmpty)
                                    (
                                      icon: Icons.event_busy_outlined,
                                      count: soon.length,
                                      color: scheme.secondary,
                                      labels: [
                                        'Expiră',
                                        'Expiră curând',
                                        [
                                          'Expiră curând: '
                                              '${soon.first.displayTitle} · '
                                              '${formatShortDate(soon.first.expiresOn!)}',
                                          if (soon.length > 1)
                                            '+${soon.length - 1}',
                                        ].join(' '),
                                      ],
                                      tooltip: 'Expiră curând',
                                      onTap: () => _showExpiring(soon),
                                    ),
                                  if (noTfa.isNotEmpty)
                                    (
                                      icon: Icons.shield_outlined,
                                      count: noTfa.length,
                                      color: scheme.tertiary,
                                      labels: const [
                                        '2FA',
                                        'Conturi fără 2FA',
                                        'Conturi fără 2FA, deși site-ul îl permite',
                                      ],
                                      tooltip: 'Conturi fără 2FA, deși site-ul îl permite',
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const TwoFactorScreen(),
                                        ),
                                      ),
                                    ),
                                ];
                                final n = alerts.length;
                                return Column(
                                  children: [
                                    GridView(
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: cols,
                                            mainAxisSpacing: 8,
                                            crossAxisSpacing: 8,
                                            mainAxisExtent: extent,
                                          ),
                                      children: [
                                        _typeTile(
                                          icon: Icons.apps,
                                          label: 'Toate',
                                          count: all.length,
                                          tint: null,
                                          selected:
                                              _type == null && !_favorites,
                                          onTap: () => setState(() {
                                            _type = null;
                                            _category = null;
                                            _favorites = false;
                                          }),
                                        ),
                                        for (final t in SecretType.values)
                                          _typeTile(
                                            icon: t.icon,
                                            label: _short(t),
                                            count: all
                                                .where((i) => i.type == t)
                                                .length,
                                            tint: secretTint(context, t),
                                            onLongPress: () =>
                                                editSecretTypeTint(context, t),
                                            selected: _type == t,
                                            onTap: () => setState(() {
                                              _favorites = false;
                                              _type = _type == t ? null : t;
                                              _category = null;
                                            }),
                                          ),
                                      ],
                                    ),
                                    if (n > 0) ...[
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        height: extent,
                                        child: Row(
                                          children: [
                                            for (final (k, a)
                                                in alerts.indexed) ...[
                                              if (k > 0)
                                                const SizedBox(width: 8),
                                              Expanded(
                                                child: _alertTile(
                                                  icon: a.icon,
                                                  label: a.labels[3 - n],
                                                  count: a.count,
                                                  color: a.color,
                                                  fontSize: n == 3 ? 12.5 : 14,
                                                  tooltip: a.tooltip,
                                                  onTap: a.onTap,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),
                          if (all
                                  .where((i) => i.pendingPassword.isNotEmpty)
                                  .toList()
                              case final pending when pending.isNotEmpty)
                            Card(
                              margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                              color: Theme.of(context)
                                  .colorScheme
                                  .tertiaryContainer,
                              child: ListTile(
                                leading: const Icon(
                                  Icons.pending_actions_outlined,
                                ),
                                title: Text(
                                  pending.length == 1
                                      ? 'Schimbare de parolă neterminată: ${pending.first.displayTitle}'
                                      : '${pending.length} schimbări de parolă neterminate',
                                ),
                                subtitle: const Text(
                                  'Ai salvat-o pe site? Confirm-o în „Repară parolele”.',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const PasswordFixScreen(),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
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
                      padding: EdgeInsets.fromLTRB(
                        12,
                        4,
                        12,
                        bottomSpace(context),
                      ),
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
                      padding: EdgeInsets.fromLTRB(
                        12,
                        4,
                        12,
                        bottomSpace(context),
                      ),
                      children: [
                        _section(
                          _type!,
                          shownItems,
                          // în „Conturi”: subgrupe Email, Rețele sociale…
                          byCategory: _type == SecretType.login,
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(bottom: bottomSpace(context)),
                      itemCount: shownItems.length,
                      itemBuilder: (_, i) => _swipe(
                        shownItems[i],
                        SecretTile(item: shownItems[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _swipe(SecretItem item, Widget child) {
    return SwipeToDelete(
      id: 'secret-${item.id}',
      label: 'Șterge',
      question:
          'Ștergi „${item.displayTitle}”? Merge în coș (Parole → ⋮ → '
          'Coș), de unde îl poți recupera 30 de zile.',
      onDelete: (store) => store.deleteSecret(item),
      doneMessage: 'Mutat în coș',
      onUndo: (store) => store.restoreSecret(item),
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
  Widget _section(
    SecretType t,
    List<SecretItem> list, {
    bool byCategory = false,
  }) {
    final tint = secretTint(context, t);
    final accent = tint.onContainer(context);
    final sorted = _alphabetical(list);
    void open() => setState(() {
      _type = t;
      _category = null;
    });
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: tint.surface(context),
      // margine subțire, în nuanța închisă a tipului
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: list.isEmpty ? () => _addType(t) : open,
            onLongPress: () => editSecretTypeTint(context, t),
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
                  IconButton(
                    tooltip: 'Culoare',
                    icon: Icon(Icons.palette_outlined, color: accent),
                    onPressed: () => editSecretTypeTint(context, t),
                  ),
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
                  color: tint.scheme(context).onSurfaceVariant,
                ),
              ),
            ),
          if (!byCategory)
            ..._siteRows(sorted, tint, accent)
          else if (_query.trim().isEmpty && _category == null)
            // întâi subcategoriile (Email, Rețele sociale, Bănci…), cu câte
            // conturi are fiecare; atingerea deschide subcategoria
            for (final c in LoginCategory.values)
              if (sorted.where((i) => loginCategory(i) == c).length case final n
                  when n > 0) ...[
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: accent.withValues(alpha: 0.15),
                ),
                ListTile(
                  leading: Icon(c.icon, color: accent),
                  title: Text(
                    c.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$n',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, color: accent),
                    ],
                  ),
                  onTap: () => setState(() => _category = c),
                ),
              ] else
                ...[]
          else ...[
            if (_category != null && _query.trim().isEmpty)
              InkWell(
                onTap: () => setState(() => _category = null),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_back, size: 18, color: accent),
                      const SizedBox(width: 6),
                      Text(
                        'Toate categoriile',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            for (final c in LoginCategory.values)
              if (_category == null ||
                  _category == c ||
                  _query.trim().isNotEmpty)
                if (sorted.where((i) => loginCategory(i) == c).toList()
                    case final group when group.isNotEmpty) ...[
                  // titlul subgrupei: iconiță, nume, câte sunt
                  Container(
                    color: tint.container(context).withValues(alpha: 0.55),
                    padding: const EdgeInsets.fromLTRB(16, 9, 16, 7),
                    child: Row(
                      children: [
                        Icon(c.icon, size: 17, color: accent),
                        const SizedBox(width: 8),
                        Text(
                          c.label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${group.length}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: accent.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ..._siteRows(group, tint, accent, firstDivider: false),
                ],
          ],
        ],
      ),
    );
  }

  /// Site-urile deschise în listă (grupurile cu mai multe conturi).
  final Set<String> _openSites = {};

  /// Ordinea conturilor aceluiași site: telefoanele, apoi adresele de
  /// email, apoi restul; fiecare alfabetic.
  static int _userKind(String u) {
    final v = u.trim();
    if (RegExp(r'^\+?[\d\s().-]{7,}$').hasMatch(v)) return 0;
    if (v.contains('@')) return 1;
    return 2;
  }

  /// Numele afișat al site-ului: „facebook.com”, „yahoo.com”; fără adresă,
  /// numele contului.
  static String _siteLabel(SecretItem i) {
    final h = hostOf(i.url).split(':').first;
    if (h.isEmpty) return siteOf(i)?.domain ?? i.displayTitle;
    final p = h.split('.');
    if (p.length <= 2) return h;
    final two = p.sublist(p.length - 2).join('.');
    // „co.uk”, „com.ro”: încă o etichetă
    return RegExp(r'^(co|com|org|net|gov|ac)\.[a-z]{2}$').hasMatch(two)
        ? p.sublist(p.length - 3).join('.')
        : two;
  }

  /// Conturile grupate pe site, ca în managerele de parole: un site cu un
  /// singur cont = un rând; cu mai multe = un rând cu iconița site-ului și
  /// câte conturi are, care se deschide cu toate conturile lui.
  List<Widget> _siteRows(
    List<SecretItem> items,
    GroupTint tint,
    Color accent, {
    bool firstDivider = true,
  }) {
    final groups = <String, List<SecretItem>>{};
    for (final i in items) {
      final k = i.type == SecretType.login ? siteBase(i) : '';
      groups.putIfAbsent(k.isEmpty ? 'id:${i.id}' : k, () => []).add(i);
    }
    final searching = _query.trim().isNotEmpty;
    final out = <Widget>[];
    Widget divider({double indent = 16}) => Divider(
      height: 1,
      indent: indent,
      endIndent: 16,
      color: accent.withValues(alpha: 0.15),
    );
    Widget tile(SecretItem i) =>
        tint.themed(context, _swipe(i, SecretTile(item: i, plain: true)));
    for (final MapEntry(key: k, value: g) in groups.entries) {
      if (out.isNotEmpty || firstDivider) out.add(divider());
      if (g.length == 1) {
        out.add(tile(g.first));
        continue;
      }
      g.sort(
        (a, b) => _userKind(a.username).compareTo(_userKind(b.username)) != 0
            ? _userKind(a.username).compareTo(_userKind(b.username))
            : NotesStore.foldText(
                a.username.isEmpty ? a.displayTitle : a.username,
              ).compareTo(
                NotesStore.foldText(
                  b.username.isEmpty ? b.displayTitle : b.username,
                ),
              ),
      );
      final first = g.firstWhere(
        (i) => i.url.isNotEmpty,
        orElse: () => g.first,
      );
      final open = searching || _openSites.contains(k);
      out.add(
        tint.themed(
          context,
          ListTile(
            leading: SecretAvatar(item: first),
            title: Text(
              _siteLabel(first),
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('${g.length} conturi'),
            trailing: Icon(
              open ? Icons.expand_less : Icons.expand_more,
              color: accent,
            ),
            onTap: () =>
                setState(() => open ? _openSites.remove(k) : _openSites.add(k)),
          ),
        ),
      );
      if (!open) continue;
      for (final i in g) {
        out.add(divider(indent: 40));
        out.add(
          Padding(padding: const EdgeInsets.only(left: 24), child: tile(i)),
        );
      }
    }
    return out;
  }

  /// „59,99 RON + 10 EUR” (sumele pe monede, înmulțite cu [factor]).
  static String _money(Map<String, double> byCurrency, int factor) => [
    for (final e in byCurrency.entries)
      '${(e.value * factor).toStringAsFixed(2).replaceAll('.00', '').replaceAll('.', ',')} ${e.key}',
  ].join(' + ');

  /// Numele scurt din grila de sus (încape pe un rând).
  static String _short(SecretType t) => switch (t) {
    SecretType.bank => 'Bancă',
    SecretType.subscription => 'Abonat',
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
    VoidCallback? onLongPress,
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
        onLongPress: onLongPress,
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

  /// Avertizare (Risc, Expiră, 2FA) în formatul pătratelor de tipuri:
  /// iconiță și număr, dedesubt numele; în culoarea avertizării.
  Widget _alertTile({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
    double fontSize = 12.5,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final bg = Color.alphaBlend(
      color.withValues(alpha: 0.12),
      scheme.surfaceContainerLowest,
    );
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withValues(alpha: 0.55)),
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
                    Icon(icon, size: 20, color: color),
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
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
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
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
    final tint = secretTint(context, item.type);
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
        child:
            (plain ? (Widget w) => w : (Widget w) => tint.themed(context, w))(
              ListTile(
                leading: SecretAvatar(item: item),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.displayTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                        onPressed: () => copyValue(
                          context,
                          copy,
                          secret: secret,
                          what: what,
                        ),
                      ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SecretDetailScreen(id: item.id),
                  ),
                ),
              ),
            ),
      ),
    );
  }
}
