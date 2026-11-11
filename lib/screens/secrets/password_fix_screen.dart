import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/notes_store.dart';
import '../../models/secret_item.dart';
import '../../services/breach_check.dart';
import '../../services/password_tools.dart';
import '../../services/secret_helpers.dart';
import '../../utils/format.dart';
import '../shell.dart';
import 'secret_detail_screen.dart';
import 'secret_widgets.dart';

/// Categoriile calculate, pe cont și versiunea lui (recunoașterea site-ului
/// e costisitoare, iar ecranul se reface des în timpul verificării).
final _categoryCache = <String, LoginCategory>{};

LoginCategory _categoryOf(SecretItem i) => _categoryCache.putIfAbsent(
  '${i.id}:${i.updatedAt.millisecondsSinceEpoch}:${i.category}',
  () => loginCategory(i),
);

/// O problemă de securitate a unui cont, cu scorul de risc.
class _Issue {
  _Issue(this.item);
  final SecretItem item;
  int breaches = 0;
  bool weak = false;
  int reusedWith = 0; // pe câte alte conturi e aceeași parolă
  bool old = false;

  /// Calculată o singură dată (recunoașterea site-ului e costisitoare).
  late final LoginCategory category = _categoryOf(item);

  bool get any => breaches > 0 || weak || reusedWith > 0 || old;

  /// Ordinea: compromise, apoi email (resetează orice cont), bănci,
  /// parole repetate, slabe, vechi.
  int get score =>
      (breaches > 0 ? 10000 : 0) +
      (category == LoginCategory.email ? 3000 : 0) +
      (category == LoginCategory.bank ? 2500 : 0) +
      (reusedWith > 0 ? 500 + reusedWith * 10 : 0) +
      (weak ? 300 : 0) +
      (old ? 100 : 0);
}

enum _Filter {
  all('Toate'),
  breached('Compromise'),
  email('Email'),
  bank('Bănci');

  const _Filter(this.label);
  final String label;
}

/// Asistentul care te duce pe rând prin parolele de reparat.
class PasswordFixScreen extends StatefulWidget {
  const PasswordFixScreen({super.key});

  @override
  State<PasswordFixScreen> createState() => _PasswordFixScreenState();
}

class _PasswordFixScreenState extends State<PasswordFixScreen> {
  /// Rezultatele verificării scurgerilor, pe id de intrare.
  final _breaches = <String, int>{};
  bool _checking = false;
  int _done = 0;
  int _total = 0;
  String? _error;
  int _fixedNow = 0;
  _Filter _filter = _Filter.all;
  bool _showIgnored = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBreaches());
  }

  Future<void> _checkBreaches() async {
    final items = context
        .read<NotesStore>()
        .allSecrets
        .where(
          (i) =>
              (i.type == SecretType.login ||
                  i.type == SecretType.subscription) &&
              i.password.isNotEmpty &&
              !isLocalAccount(i),
        )
        .toList();
    // o singură cerere pe parolă (doar 5 caractere din amprenta ei)
    final byPassword = <String, List<SecretItem>>{};
    for (final i in items) {
      byPassword.putIfAbsent(i.password, () => []).add(i);
    }
    setState(() {
      _checking = true;
      _error = null;
      _done = 0;
      _total = byPassword.length;
    });
    final check = BreachCheck();
    final entries = byPassword.entries.toList();
    var lastPaint = DateTime.now();
    try {
      // câte 8 parole deodată; ecranul se reface de max. ~3 ori pe secundă
      for (var k = 0; k < entries.length; k += 8) {
        final batch = entries.skip(k).take(8).toList();
        final counts = await Future.wait(
          batch.map((e) => check.timesPwned(e.key)),
        );
        if (!mounted) return;
        for (var j = 0; j < batch.length; j++) {
          for (final i in batch[j].value) {
            _breaches[i.id] = counts[j];
          }
        }
        _done += batch.length;
        final now = DateTime.now();
        if (now.difference(lastPaint).inMilliseconds > 300 ||
            k + 8 >= entries.length) {
          lastPaint = now;
          setState(() {});
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Verificarea scurgerilor nu a mers (fără internet?). '
              'Restul problemelor sunt afișate.',
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  List<_Issue> _issues(Iterable<SecretItem> all, {required bool ignored}) {
    final report = PasswordReport.of(all);
    final byId = <String, _Issue>{};
    _Issue of(SecretItem i) => byId.putIfAbsent(i.id, () => _Issue(i));
    for (final i in report.weak) {
      of(i).weak = true;
    }
    for (final g in report.reused) {
      for (final i in g) {
        of(i).reusedWith = g.length - 1;
      }
    }
    for (final i in report.old) {
      of(i).old = true;
    }
    for (final i in all) {
      final n = _breaches[i.id] ?? 0;
      if (n > 0 && !i.ignoreHealth) of(i).breaches = n;
    }
    if (ignored) {
      return [
        for (final i in all)
          if (i.ignoreHealth) _Issue(i),
      ];
    }
    return byId.values.where((x) => x.any).toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  bool _matches(_Issue x) => switch (_filter) {
    _Filter.all => true,
    _Filter.breached => x.breaches > 0,
    _Filter.email => x.category == LoginCategory.email,
    _Filter.bank => x.category == LoginCategory.bank,
  };

  Future<void> _mergeDuplicates() async {
    final store = context.read<NotesStore>();
    final messenger = ScaffoldMessenger.of(context);
    final groups = duplicateGroups(store.allSecrets);
    final extra = groups.fold<int>(0, (s, g) => s + g.length - 1);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unești dublurile?'),
        content: Text(
          '$extra ${extra == 1 ? 'intrare identică' : 'intrări identice'} '
          '(același site, utilizator și parolă). Păstrez câte una, cu '
          'toate notițele, câmpurile și istoricul adunate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Renunță'),
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
    messenger.showSnackBar(
      SnackBar(content: Text('Am unit dublurile: $n intrări în minus.')),
    );
  }

  Future<void> _fix(_Issue x) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<NotesStore>(),
        child: _ChangeSheet(item: x.item),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        _fixedNow++;
        _breaches.remove(x.item.id);
      });
    }
  }

  Future<void> _ignore(SecretItem i, bool value) async {
    i.ignoreHealth = value;
    await context.read<NotesStore>().saveSecret(i);
    if (!mounted || !value) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('„${i.displayTitle}” nu mai e verificat.'),
        action: SnackBarAction(
          label: 'Anulează',
          onPressed: () => _ignore(i, false),
        ),
      ),
    );
  }

  Future<void> _delete(SecretItem i) async {
    final store = context.read<NotesStore>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ștergi „${i.displayTitle}”?'),
        content: const Text(
          'Pentru conturi pe care nu le mai folosești. Ideal, închide '
          'întâi contul și pe site.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Renunță'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Șterge'),
          ),
        ],
      ),
    );
    if (ok == true) await store.deleteSecret(i);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final scheme = Theme.of(context).colorScheme;
    final all = store.allSecrets.toList();
    final issues = _issues(all, ignored: false);
    final ignored = _issues(all, ignored: true);
    final shown = issues.where(_matches).toList();
    final dupGroups = duplicateGroups(all);
    final dupExtra = dupGroups.fold<int>(0, (s, g) => s + g.length - 1);
    final breached = issues.where((x) => x.breaches > 0).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Repară parolele')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: EdgeInsets.fromLTRB(12, 4, 12, bottomSpace(context)),
            children: [
              // progresul
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        issues.isEmpty
                            ? 'Nicio problemă rămasă 🎉'
                            : 'Rămase: ${issues.length}'
                                  '${breached > 0 ? ' · compromise: $breached' : ''}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (_fixedNow > 0)
                        Text(
                          'Rezolvate acum: $_fixedNow',
                          style: TextStyle(color: scheme.primary),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        'Începe cu cele de sus: parolele compromise, apoi '
                        'emailul (cine îl are îți poate reseta orice cont) '
                        'și băncile. Restul le poți face treptat.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      if (_checking) ...[
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: _total == 0 ? null : _done / _total,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Verific scurgerile de date: $_done / $_total '
                          '(se trimit doar 5 caractere din amprenta '
                          'parolei, nu parola)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: TextStyle(color: scheme.error)),
                      ],
                    ],
                  ),
                ),
              ),
              if (dupExtra > 0)
                Card(
                  color: scheme.secondaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.merge_type),
                    title: Text(
                      '$dupExtra ${dupExtra == 1 ? 'dublură' : 'dubluri'} '
                      'din importuri',
                    ),
                    subtitle: const Text(
                      'Același cont salvat de mai multe ori',
                    ),
                    trailing: FilledButton(
                      onPressed: _mergeDuplicates,
                      child: const Text('Unește'),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  for (final f in _Filter.values)
                    ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              for (final x in shown)
                _IssueCard(
                  issue: x,
                  onFix: () => _fix(x),
                  onIgnore: () => _ignore(x.item, true),
                  onDelete: () => _delete(x.item),
                ),
              if (shown.isEmpty && issues.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Nimic de reparat aici.')),
                ),
              if (ignored.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setState(() => _showIgnored = !_showIgnored),
                  icon: Icon(
                    _showIgnored ? Icons.expand_less : Icons.expand_more,
                  ),
                  label: Text('Ignorate (${ignored.length})'),
                ),
                if (_showIgnored)
                  for (final x in ignored)
                    ListTile(
                      leading: SecretAvatar(item: x.item),
                      title: Text(x.item.displayTitle),
                      subtitle: Text(x.item.username),
                      trailing: TextButton(
                        onPressed: () => _ignore(x.item, false),
                        child: const Text('Readu'),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({
    required this.issue,
    required this.onFix,
    required this.onIgnore,
    required this.onDelete,
  });
  final _Issue issue;
  final VoidCallback onFix;
  final VoidCallback onIgnore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i = issue.item;
    Widget chip(String t, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        t,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
    final danger = issue.breaches > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: danger
              ? scheme.error.withValues(alpha: 0.6)
              : scheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SecretDetailScreen(id: i.id)),
              ),
              child: Row(
                children: [
                  SecretAvatar(item: i),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i.displayTitle,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          [
                            if (i.username.isNotEmpty) i.username,
                            issue.category.label,
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (danger)
                  chip(
                    'Compromisă (găsită de ${_count(issue.breaches)} ori în scurgeri)',
                    scheme.errorContainer,
                    scheme.onErrorContainer,
                  ),
                if (issue.reusedWith > 0)
                  chip(
                    'Folosită și la alte ${issue.reusedWith} '
                    '${issue.reusedWith == 1 ? 'cont' : 'conturi'}',
                    scheme.secondaryContainer,
                    scheme.onSecondaryContainer,
                  ),
                if (issue.weak)
                  chip(
                    'Slabă',
                    scheme.secondaryContainer,
                    scheme.onSecondaryContainer,
                  ),
                if (issue.old)
                  chip(
                    'Neschimbată din ${formatShortDate(i.passwordChangedAt)}',
                    scheme.surfaceContainerHigh,
                    scheme.onSurface,
                  ),
              ],
            ),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: onFix,
                  icon: const Icon(Icons.autorenew, size: 18),
                  label: const Text('Schimbă parola'),
                ),
                const Spacer(),
                TextButton(onPressed: onIgnore, child: const Text('Ignoră')),
                IconButton(
                  tooltip: 'Șterge contul',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _count(int n) => n >= 1000000
      ? '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')} mil.'
      : n >= 1000
      ? '${(n / 1000).round()} de mii de'
      : n >= 20
      ? '$n de'
      : '$n';
}

/// Pașii pentru o parolă: parolă nouă generată, pagina de schimbare de pe
/// site, apoi salvarea în Notițe (cea veche rămâne în istoric).
class _ChangeSheet extends StatefulWidget {
  const _ChangeSheet({required this.item});
  final SecretItem item;

  @override
  State<_ChangeSheet> createState() => _ChangeSheetState();
}

class _ChangeSheetState extends State<_ChangeSheet> {
  late final _pass = TextEditingController(text: _gen());
  bool _show = true;

  /// Confirmarea copierii, chiar în fereastră (un SnackBar ar rămâne
  /// ascuns în spatele ei).
  bool _copied = false;
  Timer? _copiedTimer;

  /// Cât rămâne parola nouă în clipboard: timp să te conectezi pe site și
  /// să ajungi la „Parolă nouă”.
  static const _keepFor = Duration(minutes: 3);

  Future<void> _copy() async {
    await SecureClipboard.copy(_pass.text, keepFor: _keepFor);
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  static String _gen() => PasswordGenerator.generate(length: 20);

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _pass.dispose();
    super.dispose();
  }

  /// Adresa standard de schimbare a parolei (RFC „change-password”);
  /// site-urile care nu o au te duc pe pagina lor principală.
  String get _host {
    final i = widget.item;
    final h = hostOf(i.url);
    return h.isNotEmpty ? h : (recognizeSite(i.title)?.domain ?? '');
  }

  /// Pagina contului, așa cum e salvată (de obicei cea de logare) — merge
  /// mereu; altfel pagina principală a site-ului.
  Uri? get _siteUrl {
    final u = widget.item.url.trim();
    if (u.isNotEmpty) {
      final parsed = Uri.tryParse(u.contains('://') ? u : 'https://$u');
      if (parsed != null && parsed.host.isNotEmpty) return parsed;
    }
    return _host.isEmpty ? null : Uri.parse('https://$_host');
  }

  /// Adresa standard de schimbare a parolei — o au doar o parte dintre
  /// site-uri (Google, Apple, Microsoft…); celelalte dau o pagină de eroare.
  Uri? get _changeUrl => _host.isEmpty
      ? null
      : Uri.parse('https://$_host/.well-known/change-password');

  Future<void> _open(Uri url) async {
    final ok = await launchUrl(url, webOnlyWindowName: '_blank');
    if (!ok && mounted) {
      setState(
        () => _openError =
            'Nu am putut deschide ${url.host}. Deschide-l '
            'manual în browser.',
      );
    }
  }

  String? _openError;

  Future<void> _save() async {
    final p = _pass.text;
    if (p.isEmpty) return;
    final store = context.read<NotesStore>();
    final nav = Navigator.of(context);
    widget.item
      ..password = p
      ..ignoreHealth = false;
    await store.saveSecret(widget.item);
    nav.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    final url = _changeUrl;
    final site = _siteUrl;
    final scheme = Theme.of(context).colorScheme;
    Widget step(String n, String text) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            child: Text(n, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Parolă nouă: ${i.displayTitle}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (i.username.isNotEmpty)
              Text(
                i.username,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            step('1', 'Copiază parola nouă'),
            TextField(
              controller: _pass,
              obscureText: !_show,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Altă parolă',
                      icon: const Icon(Icons.casino_outlined),
                      onPressed: () => setState(() => _pass.text = _gen()),
                    ),
                    IconButton(
                      tooltip: _show ? 'Ascunde' : 'Arată',
                      icon: Icon(
                        _show ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _show = !_show),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _copy,
              icon: Icon(_copied ? Icons.check_circle : Icons.copy),
              label: Text(
                _copied
                    ? 'Copiată — o poți lipi pe site (Ctrl+V / Lipește)'
                    : 'Copiază parola nouă',
              ),
            ),
            step('2', 'Schimb-o pe site'),
            Text(
              'Conectează-te, mergi la setările contului → Parolă și '
              'lipește parola nouă. Parola actuală o găsești în Notițe.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: site == null ? null : () => _open(site),
              icon: const Icon(Icons.open_in_new),
              label: Text(
                site == null
                    ? 'Site necunoscut — deschide-l manual'
                    : 'Deschide site-ul (${site.host})',
              ),
            ),
            if (url != null)
              TextButton(
                onPressed: () => _open(url),
                child: const Text(
                  'Încearcă direct pagina de schimbare a parolei',
                ),
              ),
            if (_openError != null)
              Text(_openError!, style: TextStyle(color: scheme.error)),
            step('3', 'Am schimbat-o pe site'),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Salvează parola nouă în Notițe'),
            ),
            const SizedBox(height: 6),
            Text(
              'Parola veche rămâne în istoricul contului.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
