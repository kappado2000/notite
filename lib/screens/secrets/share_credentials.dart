import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/secret_item.dart';

/// Trimite utilizatorul (și, la alegere, parola) pe WhatsApp, email, SMS sau
/// prin orice aplicație din meniul de partajare al telefonului.
Future<void> shareCredentials(BuildContext context, SecretItem item) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ShareSheet(item: item),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.item});
  final SecretItem item;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  bool _withPassword = true;
  bool _withSite = true;

  String get _text {
    final i = widget.item;
    return [
      i.displayTitle,
      if (_withSite && i.url.trim().isNotEmpty) 'Site: ${i.url.trim()}',
      if (i.username.trim().isNotEmpty) 'Utilizator: ${i.username.trim()}',
      if (_withPassword && i.password.isNotEmpty) 'Parolă: ${i.password}',
    ].join('\n');
  }

  Future<void> _open(Uri uri) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nu am găsit aplicația potrivită.')),
      );
      return;
    }
    nav.pop();
  }

  void _whatsApp() =>
      _open(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_text)}'));

  void _email() => _open(
    Uri(
      scheme: 'mailto',
      query:
          'subject=${Uri.encodeComponent(widget.item.displayTitle)}'
          '&body=${Uri.encodeComponent(_text)}',
    ),
  );

  // iOS vrea „sms:&body=”, Android „sms:?body=”
  void _sms() => _open(
    Uri.parse(
      defaultTargetPlatform == TargetPlatform.iOS
          ? 'sms:&body=${Uri.encodeComponent(_text)}'
          : 'sms:?body=${Uri.encodeComponent(_text)}',
    ),
  );

  Future<void> _other() async {
    final nav = Navigator.of(context);
    await SharePlus.instance.share(
      ShareParams(text: _text, subject: widget.item.displayTitle),
    );
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i = widget.item;
    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FilledButton.tonal(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [Icon(icon), const SizedBox(height: 4), Text(label)],
          ),
        ),
      ),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Trimite „${i.displayTitle}”',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (i.password.isNotEmpty)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include parola'),
                value: _withPassword,
                onChanged: (v) => setState(() => _withPassword = v),
              ),
            if (i.url.trim().isNotEmpty)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include site-ul'),
                value: _withSite,
                onChanged: (v) => setState(() => _withSite = v),
              ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                _text,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
            if (_withPassword && i.password.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Mesajul pleacă necriptat. După ce a fost folosit, șterge-l '
                'din conversație la amândoi.',
                style: TextStyle(color: scheme.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                action(Icons.chat_outlined, 'WhatsApp', _whatsApp),
                action(Icons.mail_outline, 'Email', _email),
                action(Icons.sms_outlined, 'SMS', _sms),
                action(Icons.ios_share, 'Altele', _other),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
