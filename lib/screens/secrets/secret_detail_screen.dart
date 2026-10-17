import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/notes_store.dart';
import '../../models/secret_item.dart';
import '../../services/password_tools.dart';
import '../../services/totp.dart';
import '../../utils/format.dart';
import '../../widgets/pickers.dart';
import 'secret_edit_screen.dart';

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
    final strength = passwordStrength(item.password);

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
              if (v != 'delete') return;
              final nav = Navigator.of(context);
              if (await confirm(
                context,
                'Ștergi definitiv „${item.displayTitle}”? Parola nu va mai '
                'putea fi recuperată.',
              )) {
                await store.deleteSecret(item);
                nav.pop();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Șterge'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
        children: [
          ...switch (item.type) {
            SecretType.login => [
              _Field('Utilizator / email', item.username),
              _Field('Parolă', item.password, secret: true),
              if (item.password.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Putere: ${strength.label}',
                    style: TextStyle(color: Color(strength.color)),
                  ),
                ),
              if (item.totp.isNotEmpty) _TotpField(secret: item.totp),
              _Field('Site / aplicație', item.url),
            ],
            SecretType.card => [
              _Field('Titular', item.cardHolder),
              _Field(
                'Număr card${cardBrand(item.cardDigits).isEmpty ? '' : ' · ${cardBrand(item.cardDigits)}'}',
                item.cardNumber,
                secret: true,
                copyValue: item.cardDigits,
              ),
              _Field('Expiră', item.cardExpiry),
              _Field('CVV', item.cardCvv, secret: true),
              _Field('PIN', item.cardPin, secret: true),
            ],
            SecretType.wifi => [
              _Field('Nume rețea (SSID)', item.username),
              _Field('Parolă', item.password, secret: true),
              _Field(
                'Securitate',
                item.wifiSecurity == 'nopass'
                    ? 'Fără parolă'
                    : item.wifiSecurity,
                copyable: false,
              ),
              if (item.username.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('Arată codul QR pentru conectare'),
                    onPressed: () => _showWifiQr(context, item),
                  ),
                ),
            ],
          },
          for (final f in item.custom)
            _Field(
              f.label.isEmpty ? 'Câmp' : f.label,
              f.value,
              secret: f.hidden,
            ),
          if (item.notes.isNotEmpty)
            _Field('Notițe', item.notes, multiline: true),
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

/// Un câmp afișat, cu copiere și (pentru cele secrete) afișare la cerere.
class _Field extends StatefulWidget {
  const _Field(
    this.label,
    this.value, {
    this.secret = false,
    this.copyable = true,
    this.multiline = false,
    this.copyValue,
  });

  final String label;
  final String value;
  final bool secret;
  final bool copyable;
  final bool multiline;
  final String? copyValue;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.value.isEmpty) return const SizedBox.shrink();
    final hidden = widget.secret && !_revealed;
    return ListTile(
      title: Text(widget.label, style: Theme.of(context).textTheme.labelMedium),
      subtitle: SelectableText(
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
          if (widget.copyable)
            IconButton(
              tooltip: 'Copiază',
              icon: const Icon(Icons.copy),
              onPressed: () {
                SecureClipboard.copy(widget.copyValue ?? widget.value);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      widget.secret
                          ? 'Copiat — se șterge din clipboard în 30 s'
                          : 'Copiat',
                    ),
                  ),
                );
              },
            ),
        ],
      ),
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
    return ListTile(
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
            onPressed: () {
              SecureClipboard.copy(code);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Cod copiat')));
            },
          ),
        ],
      ),
    );
  }
}
