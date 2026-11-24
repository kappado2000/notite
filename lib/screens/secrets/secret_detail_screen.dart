import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/notes_store.dart';
import '../../models/secret_item.dart';
import '../../services/breach_check.dart';
import '../../services/password_tools.dart';
import '../../services/totp.dart';
import '../../utils/format.dart';
import '../../widgets/pickers.dart';
import 'secret_edit_screen.dart';
import 'share_credentials.dart';
import 'secret_widgets.dart';
import '../../widgets/auth_icon.dart';

/// Un câmp afișat: etichetă, valoare, dacă e secret, ce se copiază.
typedef _F = ({String label, String value, bool secret, String? copy});

_F _f(String label, String value, {bool secret = false, String? copy}) =>
    (label: label, value: value, secret: secret, copy: copy);

/// Datele completate pe care tipul actual nu le arată (rămase după mutarea
/// la alt tip): nu se pierd, apar separat în fișă.
List<_F> _keptFields(SecretItem i, List<_F> shown) {
  final seen = {for (final f in shown) f.value.trim()};
  return [
    for (final f in [
      _f('Utilizator / email', i.username),
      _f('Parolă', i.password, secret: true),
      _f('Site / adresă', i.url),
      _f('Titular card', i.cardHolder),
      _f('Număr card', i.cardNumber, secret: true, copy: i.cardDigits),
      _f('Titular cont', i.holder),
      _f('Bancă', i.bankName),
      _f('IBAN', i.iban),
      _f('Nume', '${i.lastName} ${i.firstName}'.trim()),
      _f('CNP', i.cnp, secret: true),
      _f('Adresă', i.address),
    ])
      if (f.value.trim().isNotEmpty && !seen.contains(f.value.trim())) f,
  ];
}

/// Câmpurile unei intrări, în ordinea afișării (doar cele completate).
List<_F> _secretFields(SecretItem i) {
  String? date(DateTime? d) => d == null ? null : formatShortDate(d);
  final brand = cardBrand(i.cardDigits);
  final fields = switch (i.type) {
    SecretType.login => [
      _f('Utilizator / email', i.username),
      _f('Parolă', i.password, secret: true),
      _f('Site / aplicație', i.url),
    ],
    SecretType.card => [
      _f('Titular', i.cardHolder),
      _f(
        'Număr card${brand.isEmpty ? '' : ' · $brand'}',
        i.cardNumber,
        secret: true,
        copy: i.cardDigits,
      ),
      _f('Expiră', i.cardExpiry),
      _f('CVV', i.cardCvv, secret: true),
      _f('PIN', i.cardPin, secret: true),
    ],
    SecretType.bank => [
      _f('IBAN', i.iban, copy: i.ibanCompact),
      _f('Titular', i.holder),
      _f('Banca', i.bankName),
      _f('Cod SWIFT / BIC', i.swift),
    ],
    SecretType.identity => [
      _f('Tip act', i.docKind.label),
      _f('Nume', i.lastName),
      _f('Prenume', i.firstName),
      _f('CNP', i.cnp, secret: true),
      _f('Seria', i.docSeries),
      _f('Număr', i.docNumber),
      _f('Domiciliu', i.address),
      _f('Eliberat de', i.issuedBy),
      _f('Data eliberării', date(i.issueDate) ?? ''),
      _f('Valabil până la', date(i.expiryDate) ?? ''),
    ],
    SecretType.subscription => [
      _f(
        'Preț',
        i.price.isEmpty ? '' : '${i.price} ${i.currency} / ${i.period.label}',
        copy: i.price,
      ),
      _f('Următoarea reînnoire', date(i.renewalDate) ?? ''),
      _f('Cont (email)', i.username),
      _f('Parolă', i.password, secret: true),
      _f('Site', i.url),
    ],
    SecretType.wifi => [
      _f('Nume rețea (SSID)', i.username),
      _f('Parolă', i.password, secret: true),
      _f(
        'Securitate',
        i.wifiSecurity == 'nopass' ? 'Fără parolă' : i.wifiSecurity,
      ),
    ],
    SecretType.note => <_F>[],
  };
  return [
    ...fields,
    for (final c in i.custom)
      _f(c.label.isEmpty ? 'Câmp' : c.label, c.value, secret: c.hidden),
    _f(i.type == SecretType.note ? 'Conținut' : 'Notițe', i.notes),
  ].where((f) => f.value.trim().isNotEmpty).toList();
}

/// Toate datele, ca text, pentru „Copiază toate datele”.
String secretAsText(SecretItem i) => [
  i.displayTitle,
  for (final f in _secretFields(i)) '${f.label}: ${f.value}',
].join('\n');

class SecretDetailScreen extends StatelessWidget {
  const SecretDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final item = store.secret(id);
    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Intrarea a fost ștearsă')),
      );
    }
    final hasPassword =
        item.password.isNotEmpty &&
        (item.type == SecretType.login || item.type == SecretType.subscription);
    final strength = passwordStrength(item.password);
    final fields = _secretFields(item);
    final expires = item.expiresOn;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.displayTitle),
        actions: [
          IconButton(
            tooltip: item.favorite ? 'Scoate din favorite' : 'Favorit',
            icon: Icon(item.favorite ? Icons.star : Icons.star_outline),
            onPressed: () {
              final copy = item.copy()..favorite = !item.favorite;
              store.saveSecret(copy);
            },
          ),
          if (item.username.isNotEmpty || item.password.isNotEmpty)
            IconButton(
              tooltip: 'Trimite (WhatsApp, email, SMS)',
              icon: const Icon(Icons.send_outlined),
              onPressed: () => shareCredentials(context, item),
            ),
          IconButton(
            tooltip: 'Editează',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SecretEditScreen(item: item.copy()),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'copyAll') {
                await copyValue(
                  context,
                  secretAsText(item),
                  secret: true,
                  what: 'Toate datele copiate',
                );
                return;
              }
              if (v == 'remove2fa') {
                await removeTwoFactor(context, item);
                return;
              }
              if (v == 'convert') {
                final t = await showModalBottomSheet<SecretType>(
                  context: context,
                  showDragHandle: true,
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                          child: Text(
                            'Muți „${item.displayTitle}” la tipul:',
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text(
                            'Nimic nu se pierde: datele pe care tipul nou nu '
                            'le arată rămân în fișă, la „Păstrate din tipul '
                            'anterior”. Verifici în editare înainte să salvezi.',
                          ),
                        ),
                        for (final t in SecretType.values)
                          if (t != item.type)
                            ListTile(
                              leading: Icon(t.icon),
                              title: Text(t.label),
                              onTap: () => Navigator.pop(ctx, t),
                            ),
                      ],
                    ),
                  ),
                );
                if (t == null || !context.mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SecretEditScreen(
                      item: SecretItem.fromMap({
                        ...item.toMap(),
                        'type': t.name,
                      }),
                    ),
                  ),
                );
                return;
              }
              if (v != 'delete') return;
              final nav = Navigator.of(context);
              if (await confirm(
                context,
                'Ștergi TOT contul „${item.displayTitle}”'
                '${item.username.isEmpty ? '' : ' (${item.username})'}?\n\n'
                'Se șterg utilizatorul, parola'
                '${item.totp.isNotEmpty ? ', cheia 2FA' : ''}'
                '${item.recoveryCodes.isNotEmpty ? ', codurile de rezervă' : ''}'
                ' și notițele lui. Merge în coș (Parole → ⋮ → Coș), de unde '
                'îl poți recupera 30 de zile.'
                '${item.totp.isNotEmpty ? '\n\nVrei doar să scoți 2FA? Alege „Scoate doar 2FA” din meniu.' : ''}',
                action: 'Șterge contul',
              )) {
                await store.deleteSecret(item);
                nav.pop();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'copyAll',
                child: ListTile(
                  leading: Icon(Icons.copy_all_outlined),
                  title: Text('Copiază toate datele'),
                ),
              ),
              const PopupMenuItem(
                value: 'convert',
                child: ListTile(
                  leading: Icon(Icons.swap_horiz),
                  title: Text('Mută la alt tip…'),
                  subtitle: Text('ex. Cont → Wi-Fi'),
                ),
              ),
              if (item.totp.isNotEmpty)
                const PopupMenuItem(
                  value: 'remove2fa',
                  child: ListTile(
                    leading: Icon(Icons.link_off),
                    title: Text('Scoate doar 2FA'),
                    subtitle: Text('Contul și parola rămân'),
                  ),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Șterge tot contul'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                SecretAvatar(item: item, radius: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    item.type.label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (expires != null) _ExpiryBanner(item: item, date: expires),
          for (final f in fields) ...[
            _Field(
              f.label,
              f.value,
              secret: f.secret,
              copyValue: f.copy,
              multiline: f.label == 'Notițe' || f.label == 'Conținut',
            ),
            if (f.label == 'Parolă' && hasPassword) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  'Putere: ${strength.label}',
                  style: TextStyle(color: Color(strength.color)),
                ),
              ),
              _BreachCheckTile(password: item.password),
            ],
          ],
          // date păstrate după mutarea la alt tip (ex. adresa ruterului la
          // un Wi-Fi): nu se pierd și se văd aici
          if (_keptFields(item, fields) case final kept
              when kept.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
              child: Text(
                'Păstrate din tipul anterior',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final f in kept)
              _Field(f.label, f.value, secret: f.secret, copyValue: f.copy),
          ],
          if (item.totp.isNotEmpty) _TotpField(secret: item.totp),
          if (item.recoveryCodes.trim().isNotEmpty)
            _RecoveryField(codes: item.recoveryCodes.trim()),
          if (item.type == SecretType.wifi && item.username.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Arată codul QR pentru conectare'),
                onPressed: () => _showWifiQr(context, item),
              ),
            ),
          if (item.passwordHistory.isNotEmpty) _PasswordHistory(item: item),
          SecretAttachments(ownerId: item.attachmentOwnerId),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Modificată: ${formatDateTime(item.updatedAt)}\n'
              'Creată: ${formatDateTime(item.createdAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  void _showWifiQr(BuildContext context, SecretItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.username),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(
                data: wifiQrPayload(item),
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Scanează cu camera telefonului ca să te conectezi.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Închide'),
          ),
        ],
      ),
    );
  }
}

/// Avertisment pentru card / act expirat sau aproape de expirare.
class _ExpiryBanner extends StatelessWidget {
  const _ExpiryBanner({required this.item, required this.date});

  final SecretItem item;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final days = DateUtils.dateOnly(date).difference(today).inDays;
    if (days > 30) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final sub = item.type == SecretType.subscription;
    final text = days < 0
        ? (sub ? 'Data reînnoirii a trecut' : 'Expirat')
        : days == 0
        ? (sub ? 'Se reînnoiește azi' : 'Expiră azi')
        : '${sub ? 'Se reînnoiește' : 'Expiră'} în $days '
              '${days == 1 ? 'zi' : 'zile'}';
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      color: days < 0 ? scheme.errorContainer : scheme.secondaryContainer,
      child: ListTile(
        leading: const Icon(Icons.event_busy_outlined),
        title: Text(text),
        subtitle: Text(formatShortDate(date)),
      ),
    );
  }
}

/// Un câmp afișat, cu copiere și (pentru cele secrete) afișare la cerere.
/// Atingerea pe rând copiază valoarea.
class _Field extends StatefulWidget {
  const _Field(
    this.label,
    this.value, {
    this.secret = false,
    this.multiline = false,
    this.copyValue,
  });

  final String label;
  final String value;
  final bool secret;
  final bool multiline;
  final String? copyValue;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  bool _revealed = false;

  void _copy() => copyValue(
    context,
    widget.copyValue ?? widget.value,
    secret: widget.secret,
    what: '${widget.label} copiat',
  );

  @override
  Widget build(BuildContext context) {
    if (widget.value.isEmpty) return const SizedBox.shrink();
    final hidden = widget.secret && !_revealed;
    return ListTile(
      onTap: _copy,
      title: Text(widget.label, style: Theme.of(context).textTheme.labelMedium),
      subtitle: Text(
        hidden ? '•' * widget.value.length.clamp(6, 16) : widget.value,
        style: TextStyle(
          fontSize: 16,
          fontFamily: widget.secret ? 'monospace' : null,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        maxLines: widget.multiline ? null : 3,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.secret)
            IconButton(
              tooltip: _revealed ? 'Ascunde' : 'Arată',
              icon: Icon(
                _revealed
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _revealed = !_revealed),
            ),
          IconButton(
            tooltip: 'Copiază',
            icon: const Icon(Icons.copy),
            onPressed: _copy,
          ),
        ],
      ),
    );
  }
}

/// Verificare la cerere în baza de parole furate (HIBP). Nu pornește
/// singură: trimite în rețea primele 5 caractere ale amprentei SHA-1.
class _BreachCheckTile extends StatefulWidget {
  const _BreachCheckTile({required this.password});
  final String password;

  @override
  State<_BreachCheckTile> createState() => _BreachCheckTileState();
}

class _BreachCheckTileState extends State<_BreachCheckTile> {
  bool _busy = false;
  int? _count;
  String? _error;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = await BreachCheck().timesPwned(widget.password);
      if (mounted) setState(() => _count = n);
    } catch (e) {
      if (mounted) setState(() => _error = 'Fără conexiune la serviciu.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = _count;
    if (n != null) {
      return ListTile(
        dense: true,
        leading: Icon(
          n > 0 ? Icons.gpp_bad_outlined : Icons.gpp_good_outlined,
          color: n > 0 ? scheme.error : scheme.primary,
        ),
        title: Text(
          n > 0
              ? 'Parolă compromisă — apare de $n ori în scurgeri de date. '
                    'Schimb-o!'
              : 'Nu apare în scurgerile de date cunoscute.',
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: TextButton.icon(
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.travel_explore, size: 18),
          label: Text(_error ?? 'Verifică dacă a fost compromisă'),
          onPressed: _busy ? null : _check,
        ),
      ),
    );
  }
}

/// Parolele anterioare (ascunse; arătate și copiate la cerere).
class _PasswordHistory extends StatelessWidget {
  const _PasswordHistory({required this.item});
  final SecretItem item;

  /// Parola aleasă devine cea actuală; cea actuală trece în istoric.
  Future<void> _use(BuildContext context, PasswordVersion p) async {
    final store = context.read<NotesStore>();
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final updated = item.copy();
    updated.passwordHistory = [
      if (item.password.isNotEmpty) PasswordVersion(item.password, now),
      ...item.passwordHistory.where((h) => h.password != p.password),
    ].take(10).toList();
    updated
      ..password = p.password
      ..passwordChangedAt = now
      ..pendingPassword = '';
    await store.saveSecret(updated);
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Parola aleasă e acum cea actuală (se completează de acum '
          'înainte). Cea de până acum a trecut în „Parole anterioare”.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.history),
      title: Text('Parole anterioare (${item.passwordHistory.length})'),
      shape: const Border(),
      children: [
        for (final p in item.passwordHistory) ...[
          _Field(
            'Folosită până la ${formatShortDate(p.until)}',
            p.password,
            secret: true,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                icon: const Icon(Icons.swap_vert, size: 18),
                label: const Text('Folosește-o ca parolă actuală'),
                onPressed: () => _use(context, p),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Codul 2FA curent, actualizat la fiecare secundă.
class _TotpField extends StatefulWidget {
  const _TotpField({required this.secret});
  final String secret;

  @override
  State<_TotpField> createState() => _TotpFieldState();
}

class _TotpFieldState extends State<_TotpField> {
  Timer? _timer;
  late final Totp? _totp = Totp.parse(widget.secret);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totp = _totp;
    if (totp == null) {
      return const ListTile(
        title: Text('Cod 2FA'),
        subtitle: Text('Cheie 2FA invalidă — verific-o în editare'),
      );
    }
    final code = totp.code();
    final left = totp.secondsLeft();
    final pretty = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code;
    void copy() => copyValue(context, code, secret: true, what: 'Cod copiat');
    return ListTile(
      onTap: copy,
      leading: const AuthIcon(size: 28),
      title: Text('Cod 2FA', style: Theme.of(context).textTheme.labelMedium),
      subtitle: Text(
        pretty,
        style: TextStyle(
          fontSize: 26,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: left / totp.period,
                  strokeWidth: 3,
                ),
                Text('$left', style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiază codul',
            icon: const Icon(Icons.copy),
            onPressed: copy,
          ),
        ],
      ),
    );
  }
}

/// Codurile de rezervă 2FA: ascunse până apeși „Arată”; copiere.
class _RecoveryField extends StatefulWidget {
  const _RecoveryField({required this.codes});
  final String codes;

  @override
  State<_RecoveryField> createState() => _RecoveryFieldState();
}

class _RecoveryFieldState extends State<_RecoveryField> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.codes.split('\n').where((l) => l.trim().isNotEmpty).length;
    return ListTile(
      leading: const Icon(Icons.password),
      title: Text(
        'Coduri de rezervă 2FA ($n)',
        style: Theme.of(context).textTheme.labelMedium,
      ),
      subtitle: SelectableText(
        _shown ? widget.codes : '•••• •••• (ascunse)',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
            tooltip: 'Copiază codurile',
            icon: const Icon(Icons.copy),
            onPressed: () => copyValue(
              context,
              widget.codes,
              secret: true,
              what: 'Coduri copiate',
            ),
          ),
        ],
      ),
    );
  }
}
