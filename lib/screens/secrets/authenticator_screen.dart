import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_settings.dart';
import '../../data/notes_store.dart';
import '../../models/secret_item.dart';
import '../../services/secret_helpers.dart';
import '../../services/totp.dart';
import '../qr_scan_screen.dart';
import 'recovery_codes_screen.dart';
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

  Future<void> _settings() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final s = ctx.watch<AppSettings>();
      Widget opt(String v, IconData icon, String title, String sub) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(sub),
        trailing: s.authOrder == v
            ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary)
            : null,
        onTap: () {
          s.authOrder = v;
          Navigator.pop(ctx);
        },
      );
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Ordinea conturilor',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            opt(
              'alpha',
              Icons.sort_by_alpha,
              'Alfabetic',
              'După numele site-ului',
            ),
            opt(
              'recent',
              Icons.history,
              'Folosite recent',
              'Întâi cele al căror cod l-ai copiat ultima dată',
            ),
            opt(
              'manual',
              Icons.swap_vert,
              'Manual',
              'Ține apăsat pe un cont și trage-l unde vrei',
            ),
          ],
        ),
      );
    },
  );

  // ------------------------------------------------------------ ecran

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final settings = context.watch<AppSettings>();
    final all = store.secrets.where((i) => i.totp.trim().isNotEmpty).length;
    final items = _sorted(_items(store), settings);
    // tragerea merge doar în ordinea manuală și fără căutare (lista întreagă)
    final drag = settings.authOrder == 'manual' && _query.trim().isEmpty;
    // tras cu degetul de la dreapta la stânga: scoate DOAR 2FA (cu
    // confirmare); contul și parola rămân
    Widget tile(SecretItem i) => Dismissible(
      key: ValueKey('auth-${i.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Scoate 2FA',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.link_off,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ],
        ),
      ),
      confirmDismiss: (_) => removeTwoFactor(context, i),
      child: _CodeTile(item: i, onCopied: () => settings.markAuthUsed(i.id)),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Autentificator'),
        actions: [
          IconButton(
            tooltip: 'Coduri de rezervă (toate conturile)',
            icon: const Icon(Icons.password),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RecoveryCodesScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Setări (ordinea conturilor)',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _settings,
          ),
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
          : drag
          ? ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              buildDefaultDragHandles: false,
              itemCount: items.length,
              onReorderItem: (from, to) {
                final ids = [for (final i in items) i.id];
                ids.insert(to, ids.removeAt(from));
                settings.authManual = ids;
              },
              itemBuilder: (_, n) => ReorderableDelayedDragStartListener(
                key: ValueKey(items[n].id),
                index: n,
                child: tile(items[n]),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: items.length,
              itemBuilder: (_, n) => tile(items[n]),
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Scanează codul QR',
        onPressed: _scan,
        child: const Icon(Icons.qr_code_scanner),
      ),
    );
  }

  /// Ordinea aleasă în Setări. La „Manual”, conturile noi vin la final.
  List<SecretItem> _sorted(List<SecretItem> items, AppSettings s) {
    int alpha(SecretItem a, SecretItem b) =>
        a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
    final list = [...items]..sort(alpha);
    switch (s.authOrder) {
      case 'recent':
        final used = s.authUsed;
        list.sort((a, b) => (used[b.id] ?? 0).compareTo(used[a.id] ?? 0));
      case 'manual':
        final pos = {for (final (n, id) in s.authManual.indexed) id: n};
        list.sort(
          (a, b) => (pos[a.id] ?? 1 << 30).compareTo(pos[b.id] ?? 1 << 30),
        );
    }
    return list;
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

/// Un cont, ca în aplicațiile de autentificare: emblema mare în stânga;
/// site-ul, dedesubt utilizatorul, apoi codul mare cu cercul de timp;
/// săgeata spre cont în dreapta. Atingerea copiază codul.
class _CodeTile extends StatelessWidget {
  const _CodeTile({required this.item, required this.onCopied});
  final SecretItem item;
  final VoidCallback onCopied;

  /// Fontul sistemului, varianta pentru cifre mari (SF Pro Display pe
  /// iPhone, Segoe UI pe Windows).
  static String? get _displayFont => defaultTargetPlatform == TargetPlatform.iOS
      ? 'CupertinoSystemDisplay'
      : null;

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
    final codeColor = code == null || ending ? scheme.error : scheme.primary;
    return InkWell(
      onTap: code == null
          ? null
          : () {
              copyValue(context, code, secret: true, what: 'Cod copiat');
              onCopied();
            },
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 20, 4, 18),
        child: Row(
          children: [
            SecretAvatar(item: item, radius: 26),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, color: scheme.onSurface),
                  ),
                  if (item.username.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        pretty,
                        style: TextStyle(
                          fontFamily: _displayFont,
                          fontFamilyFallback: const ['Segoe UI', 'Roboto'],
                          fontSize: code == null ? 16 : 36,
                          fontWeight: FontWeight.w400,
                          height: 1.1,
                          letterSpacing: 0.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: codeColor,
                        ),
                      ),
                      if (totp != null) ...[
                        const SizedBox(width: 10),
                        SizedBox.square(
                          dimension: 24,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: left / totp.period,
                                strokeWidth: 2,
                                color: codeColor,
                                backgroundColor: scheme.outlineVariant,
                              ),
                              Text(
                                '$left',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: codeColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // meniul contului: aici se scoate DOAR 2FA, contul rămâne
            PopupMenuButton<String>(
              tooltip: 'Mai multe',
              icon: Icon(Icons.more_vert, color: scheme.outline),
              onSelected: (v) async {
                if (v == 'open') {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SecretDetailScreen(id: item.id),
                    ),
                  );
                } else if (v == 'copy' && code != null) {
                  await copyValue(
                    context,
                    code,
                    secret: true,
                    what: 'Cod copiat',
                  );
                  onCopied();
                } else if (v == 'remove2fa') {
                  await removeTwoFactor(context, item);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'open',
                  child: ListTile(
                    leading: Icon(Icons.open_in_new),
                    title: Text('Deschide contul'),
                  ),
                ),
                if (code != null)
                  const PopupMenuItem(
                    value: 'copy',
                    child: ListTile(
                      leading: Icon(Icons.copy),
                      title: Text('Copiază codul'),
                    ),
                  ),
                const PopupMenuItem(
                  value: 'remove2fa',
                  child: ListTile(
                    leading: Icon(Icons.link_off),
                    title: Text('Scoate 2FA de la acest cont'),
                    subtitle: Text('Contul și parola rămân'),
                  ),
                ),
              ],
            ),
          ],
        ),
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
