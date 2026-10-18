import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/notes_store.dart';
import '../../models/secret_item.dart';
import '../../services/biometric_service.dart';
import '../../services/firestore_sync.dart';
import '../../services/password_tools.dart';
import '../../services/vault.dart';
import '../../session.dart';
import '../shell.dart';
import 'password_health_screen.dart';
import 'secret_detail_screen.dart';
import 'secret_edit_screen.dart';

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

enum _Filter { all, favorite, login, card, wifi }

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
  _Filter _filter = _Filter.all;

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
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
      (i) => switch (_filter) {
        _Filter.all => true,
        _Filter.favorite => i.favorite,
        _Filter.login => i.type == SecretType.login,
        _Filter.card => i.type == SecretType.card,
        _Filter.wifi => i.type == SecretType.wifi,
      },
    );
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
              for (final (f, label) in [
                (_Filter.all, 'Toate (${all.length})'),
                (_Filter.favorite, 'Favorite'),
                (_Filter.login, 'Conturi'),
                (_Filter.card, 'Carduri'),
                (_Filter.wifi, 'Wi-Fi'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Center(
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
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
                  itemBuilder: (_, i) => SecretTile(item: items[i]),
                ),
        ),
      ],
    );
  }
}

class SecretTile extends StatelessWidget {
  const SecretTile({super.key, required this.item});

  final SecretItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final copyValue = switch (item.type) {
      SecretType.login || SecretType.wifi => item.password,
      SecretType.card => item.cardDigits,
    };
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: item.type == SecretType.login && item.displayTitle.isNotEmpty
            ? Text(item.displayTitle.substring(0, 1).toUpperCase())
            : Icon(item.type.icon, size: 20),
      ),
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
      trailing: copyValue.isEmpty
          ? null
          : IconButton(
              tooltip: item.type == SecretType.card
                  ? 'Copiază numărul'
                  : 'Copiază parola',
              icon: const Icon(Icons.copy),
              onPressed: () {
                SecureClipboard.copy(copyValue);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copiat — se șterge din clipboard în 30 s'),
                  ),
                );
              },
            ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SecretDetailScreen(id: item.id)),
      ),
    );
  }
}
