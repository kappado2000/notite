import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/notes_store.dart';
import '../../models/secret_item.dart';
import '../../services/secret_helpers.dart';
import '../../services/totp.dart';
import '../qr_scan_screen.dart';
import 'secret_detail_screen.dart';
import 'secret_edit_screen.dart';
import 'secret_widgets.dart';

/// „Autentificator”: toate conturile cu cheie 2FA și codurile lor, ca într-o
/// aplicație de autentificare. Sus: căutare și (+) adăugare manuală; jos în
/// dreapta: scanarea codului QR de pe site. Cheia se pune la contul din
/// Notițe (existent sau nou), deci codul merge și la completarea automată.
class AuthenticatorScreen extends StatefulWidget {
  const AuthenticatorScreen({super.key});

  @override
  State<AuthenticatorScreen> createState() => _AuthenticatorScreenState();
}

class _AuthenticatorScreenState extends State<AuthenticatorScreen> {
  final _search = TextEditingController();
  String _query = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // codurile și cercurile de timp se reîmprospătează în fiecare secundă
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  static String _norm(String s) => s.toLowerCase().trim();

  List<SecretItem> _items(NotesStore store) {
    final q = _norm(_query);
    return [
      for (final i in store.secrets)
        if (i.totp.trim().isNotEmpty &&
            (q.isEmpty ||
                _norm(
                  '${i.displayTitle} ${i.username} ${i.url} ${i.sites.join(' ')}',
                ).contains(q)))
          i,
    ];
  }

  // ---------------------------------------------------------- adăugare

  Future<void> _scan() async {
    final code = await scanCode(context);
    if (code == null || !mounted) return;
    if (Totp.parse(code.value) == null) {
      _snack(
        'Codul scanat nu e un cod 2FA. Pe site alege „aplicație de '
        'autentificare” și scanează codul QR afișat acolo.',
      );
      return;
    }
    await _attach(code.value.trim());
  }

  Future<void> _addManual() async {
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => const _KeyDialog(),
    );
    if (key == null || !mounted) return;
    await _attach(key);
  }

  /// Pune cheia la un cont: cel potrivit (după emitent și utilizator), altul
  /// ales din listă sau unul nou.
  Future<void> _attach(String key) async {
    final store = context.read<NotesStore>();
    final label = otpauthLabel(key);
    final issuer = label?.issuer ?? '';
    final account = label?.account ?? '';
    final target = await showModalBottomSheet<_Target>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _PickAccountSheet(
        logins: store.secrets.where((i) => i.type == SecretType.login).toList(),
        issuer: issuer,
        account: account,
      ),
    );
    if (target == null || !mounted) return;
    final chosen = target.item;
    if (chosen == null) {
      // cont nou, completat cât se poate din codul QR
      final site = recognizeSite(issuer);
      final item = store.newSecret(SecretType.login)
        ..title = site?.name ?? issuer
        ..username = account
        ..url = site == null ? '' : 'https://${site.domain}'
        ..totp = key;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => SecretEditScreen(item: item)));
      return;
    }
    if (chosen.totp.trim().isNotEmpty && chosen.totp.trim() != key) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Înlocuiești cheia 2FA?'),
          content: Text(
            '„${chosen.displayTitle}” are deja o cheie 2FA. Dacă o '
            'înlocuiești, codurile vechi nu mai apar. Fă asta doar dacă ai '
            'reactivat 2FA pe site.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Renunță'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Înlocuiește'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final current = store.secret(chosen.id);
    if (current == null) return;
    await store.saveSecret(current.copy()..totp = key);
    _snack(
      'Cheia 2FA e la „${chosen.displayTitle}”. Scrie pe site codul afișat '
      'aici ca să termini activarea.',
    );
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  // ------------------------------------------------------------ ecran

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final all = store.secrets.where((i) => i.totp.trim().isNotEmpty).length;
    final items = _items(store);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Autentificator'),
        actions: [
          IconButton(
            tooltip: 'Adaugă cheie 2FA',
            icon: const Icon(Icons.add),
            onPressed: _addManual,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SearchBar(
              controller: _search,
              hintText: 'Caută conturi',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              trailing: [
                if (_query.isNotEmpty)
                  IconButton(
                    tooltip: 'Șterge căutarea',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  ),
              ],
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      ),
      body: items.isEmpty
          ? _Empty(searching: all > 0)
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, n) => _CodeTile(item: items[n]),
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Scanează codul QR',
        onPressed: _scan,
        child: const Icon(Icons.qr_code_scanner),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching});
  final bool searching;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        searching
            ? 'Niciun cont nu se potrivește căutării.'
            : 'Niciun cont cu 2FA încă.\n\nPe site, la Securitate, pornește '
                  'verificarea în doi pași cu „aplicație de autentificare”, '
                  'apoi apasă butonul de scanare de jos (sau + ca să lipești '
                  'cheia text).',
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

/// Un cont: emblema site-ului, numele, utilizatorul, codul mare și cercul
/// de timp. Atingerea copiază codul.
class _CodeTile extends StatelessWidget {
  const _CodeTile({required this.item});
  final SecretItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totp = Totp.parse(item.totp);
    final code = totp?.code();
    final left = totp?.secondsLeft() ?? 0;
    final pretty = code == null
        ? 'Cheie invalidă'
        : code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code;
    final ending = totp != null && left <= 5;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      leading: SecretAvatar(item: item),
      title: Text(
        [
          item.displayTitle,
          if (item.username.isNotEmpty) item.username,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
      ),
      subtitle: Text(
        pretty,
        style: TextStyle(
          fontSize: code == null ? 15 : 30,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
          color: code == null
              ? scheme.error
              : ending
              ? scheme.error
              : scheme.primary,
        ),
      ),
      onTap: code == null
          ? null
          : () => copyValue(context, code, secret: true, what: 'Cod copiat'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (totp != null)
            SizedBox(
              width: 30,
              height: 30,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: left / totp.period,
                    strokeWidth: 3,
                    color: ending ? scheme.error : null,
                  ),
                  Text('$left', style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          IconButton(
            tooltip: 'Deschide contul',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SecretDetailScreen(id: item.id),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cheia lipită de pe site („Nu poți scana?”): șirul de litere și cifre sau
/// linkul otpauth://.
class _KeyDialog extends StatefulWidget {
  const _KeyDialog();

  @override
  State<_KeyDialog> createState() => _KeyDialogState();
}

class _KeyDialogState extends State<_KeyDialog> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ok() {
    final v = _c.text.trim();
    if (Totp.parse(v) == null) {
      setState(
        () => _error = 'Nu e o cheie 2FA validă (litere A–Z și cifre 2–7).',
      );
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Adaugă cheie 2FA'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pe site, sub codul QR, alege „Nu poți scana?” / „Introdu cheia '
          'manual” și lipește aici șirul afișat.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _c,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Cheia 2FA',
            hintText: 'ex. JBSW Y3DP EHPK 3PXP',
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _ok(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Renunță'),
      ),
      FilledButton(onPressed: _ok, child: const Text('Continuă')),
    ],
  );
}

/// Alegerea contului: `item == null` înseamnă cont nou.
class _Target {
  const _Target(this.item);
  final SecretItem? item;
}

class _PickAccountSheet extends StatefulWidget {
  const _PickAccountSheet({
    required this.logins,
    required this.issuer,
    required this.account,
  });

  final List<SecretItem> logins;
  final String issuer;
  final String account;

  @override
  State<_PickAccountSheet> createState() => _PickAccountSheetState();
}

class _PickAccountSheetState extends State<_PickAccountSheet> {
  String _q = '';

  static String _n(String s) => s.toLowerCase().trim();

  /// Cât de bine se potrivește contul cu codul QR (emitent + utilizator).
  int _score(SecretItem i) {
    final issuer = _n(widget.issuer);
    final account = _n(widget.account);
    var s = 0;
    if (issuer.isNotEmpty) {
      final site = recognizeSite(widget.issuer);
      final hay = _n('${i.title} ${i.url} ${i.sites.join(' ')}');
      if (hay.contains(issuer) ||
          (site != null && siteOf(i)?.domain == site.domain)) {
        s += 2;
      }
    }
    if (account.isNotEmpty && _n(i.username) == account) s += 1;
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final q = _n(_q);
    final scored = [
      for (final i in widget.logins)
        if (q.isEmpty ||
            _n('${i.displayTitle} ${i.username} ${i.url}').contains(q))
          (i, _score(i)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final best = scored.where((e) => e.$2 >= 2).toList();
    final rest = scored.where((e) => e.$2 < 2).toList();
    final what = [
      widget.issuer,
      widget.account,
    ].where((s) => s.isNotEmpty).join(' · ');
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                what.isEmpty
                    ? 'La ce cont pui cheia 2FA?'
                    : 'La ce cont pui cheia 2FA pentru $what?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Caută contul',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.add)),
                    title: const Text('Cont nou'),
                    subtitle: what.isEmpty ? null : Text(what),
                    onTap: () => Navigator.pop(context, const _Target(null)),
                  ),
                  if (best.isNotEmpty) const _Section('Potrivite'),
                  for (final (i, _) in best) _row(i),
                  if (rest.isNotEmpty)
                    _Section(best.isEmpty ? 'Conturile tale' : 'Altele'),
                  for (final (i, _) in rest) _row(i),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(SecretItem i) => ListTile(
    leading: SecretAvatar(item: i),
    title: Text(i.displayTitle),
    subtitle: Text(
      [
        if (i.username.isNotEmpty) i.username,
        if (i.totp.trim().isNotEmpty) 'are deja 2FA',
      ].join(' · '),
    ),
    onTap: () => Navigator.pop(context, _Target(i)),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
