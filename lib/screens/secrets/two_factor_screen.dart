import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/notes_store.dart';
import '../../models/secret_item.dart';
import '../../services/secret_helpers.dart';
import '../../services/two_factor_sites.dart';
import 'secret_edit_screen.dart';
import '../../widgets/auth_icon.dart';

/// „Activează 2FA aici”: conturile de pe site-uri care permit verificarea
/// în doi pași cu cod din aplicație, la care nu ai salvat încă cheia.
/// După activare, cheia se pune în Notițe la contul respectiv, iar codul
/// se completează singur (extensie, iPhone).
class TwoFactorScreen extends StatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  @override
  void initState() {
    super.initState();
    TwoFactorSites.instance.load();
  }

  Future<void> _open(SecretItem i, String doc) async {
    final target = doc.isNotEmpty
        ? doc
        : (i.url.isNotEmpty
              ? (i.url.contains('://') ? i.url : 'https://${i.url}')
              : '');
    if (target.isEmpty) return;
    await launchUrl(Uri.parse(target), webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    return ListenableBuilder(
      listenable: TwoFactorSites.instance,
      builder: (context, _) {
        final tfa = TwoFactorSites.instance;
        final list = tfa.missing(store.allSecrets);
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Activează 2FA')),
          body: !tfa.loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                  children: [
                    Card(
                      color: scheme.secondaryContainer,
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Aceste site-uri permit verificarea în doi pași cu '
                          'cod din aplicație. Cu ea, o parolă furată nu mai '
                          'ajunge pentru a intra în cont.\n\n'
                          '1. Apasă „Cum activez” și urmează pașii site-ului '
                          '(alege „aplicație de autentificare”).\n'
                          '2. Când site-ul arată codul QR, apasă „Adaugă '
                          'cheia” și scanează-l (sau lipește cheia).\n'
                          '3. Gata: Notițe completează singur codul — în '
                          'browser și pe iPhone.',
                        ),
                      ),
                    ),
                    if (list.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Nicio sugestie: conturile tale au deja 2FA salvat '
                          'sau site-urile lor nu îl oferă prin aplicație.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                        child: Text(
                          '${list.length} '
                          '${list.length == 1 ? 'cont' : 'conturi'}',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    for (final (i, doc) in list)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                leading: const AuthIcon(),
                                title: Text(i.displayTitle),
                                subtitle: Text(
                                  [
                                    if (i.username.isNotEmpty) i.username,
                                    if (hostOf(i.url).isNotEmpty) hostOf(i.url),
                                  ].join(' · '),
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (_) async {
                                    await tfa.dismiss(i.id);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        persist: false,
                                        content: Text(
                                          '${i.displayTitle} nu mai apare aici.',
                                        ),
                                        action: SnackBarAction(
                                          label: 'Anulează',
                                          onPressed: () => tfa.undismiss(i.id),
                                        ),
                                      ),
                                    );
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'hide',
                                      child: Text('Nu vreau 2FA aici'),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.open_in_new),
                                      label: const Text('Cum activez'),
                                      onPressed: () => _open(i, doc),
                                    ),
                                    FilledButton.tonalIcon(
                                      icon: const Icon(Icons.qr_code_scanner),
                                      label: const Text('Adaugă cheia'),
                                      onPressed: () => Navigator.of(context)
                                          .push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  SecretEditScreen(item: i),
                                            ),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}
