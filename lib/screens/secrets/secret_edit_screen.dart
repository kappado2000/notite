import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../data/notes_store.dart';
import '../../models/attachment.dart';
import '../../models/secret_item.dart';
import '../../services/card_parser.dart';
import '../../services/id_card_parser.dart';
import '../../services/password_tools.dart';
import '../../services/scan_service.dart';
import '../../services/secret_helpers.dart';
import '../../services/totp.dart';
import '../../utils/format.dart';
import '../qr_scan_screen.dart';
import 'password_generator_sheet.dart';
import 'secret_widgets.dart';

/// Adăugare / editare pentru o intrare din „Parole”. Lucrează pe o copie;
/// nimic nu se salvează până la „Salvează”.
class SecretEditScreen extends StatefulWidget {
  const SecretEditScreen({super.key, required this.item});

  final SecretItem item;

  @override
  State<SecretEditScreen> createState() => _SecretEditScreenState();
}

class _SecretEditScreenState extends State<SecretEditScreen> {
  final _form = GlobalKey<FormState>();
  late final SecretItem _i = widget.item;
  late final NotesStore _store = context.read<NotesStore>();
  late final Map<String, TextEditingController> _c = {
    for (final e in {
      'title': _i.title,
      'url': _i.url,
      'username': _i.username,
      'password': _i.password,
      'totp': _i.totp,
      'cardHolder': _i.cardHolder,
      'cardNumber': _i.cardNumber,
      'cardExpiry': _i.cardExpiry,
      'cardCvv': _i.cardCvv,
      'cardPin': _i.cardPin,
      'holder': _i.holder,
      'bankName': _i.bankName,
      'iban': _i.iban,
      'swift': _i.swift,
      'lastName': _i.lastName,
      'firstName': _i.firstName,
      'cnp': _i.cnp,
      'address': _i.address,
      'docSeries': _i.docSeries,
      'docNumber': _i.docNumber,
      'issuedBy': _i.issuedBy,
      'price': _i.price,
      'notes': _i.notes,
    }.entries)
      e.key: TextEditingController(text: e.value),
  };
  late final List<(TextEditingController, TextEditingController, bool)>
  _custom = [
    for (final f in _i.custom)
      (
        TextEditingController(text: f.label),
        TextEditingController(text: f.value),
        f.hidden,
      ),
  ];
  late DocKind _docKind = _i.docKind;
  late DateTime? _issueDate = _i.issueDate;
  late DateTime? _expiryDate = _i.expiryDate;
  late DateTime? _renewalDate = _i.renewalDate;
  late String _currency = _i.currency;
  late BillingPeriod _period = _i.period;
  bool _showPassword = false;
  bool _clipAvailable = false;
  bool _reading = false;

  /// Atașamente adăugate în acest ecran: la „Renunță” sunt eliminate.
  final _added = <Attachment>[];
  bool _saved = false;

  bool get _isNew => _store.secret(_i.id) == null;
  SecretType get _type => _i.type;

  @override
  void initState() {
    super.initState();
    // Doar verifică dacă există text (fără să-l citească — pe iPhone
    // citirea ar afișa avertismentul „a lipit din…”).
    Clipboard.hasStrings()
        .then((v) {
          if (mounted && v) setState(() => _clipAvailable = true);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    if (!_saved) {
      for (final a in _added) {
        _store.removeAttachment(a);
      }
    }
    for (final c in _c.values) {
      c.dispose();
    }
    for (final (a, b, _) in _custom) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  String _v(String k) => _c[k]!.text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    _i
      ..title = _v('title')
      ..url = _v('url')
      ..username = _v('username')
      ..password = _c['password']!.text
      ..totp = _v('totp')
      ..cardHolder = _v('cardHolder')
      ..cardNumber = _v('cardNumber')
      ..cardExpiry = _v('cardExpiry')
      ..cardCvv = _v('cardCvv')
      ..cardPin = _v('cardPin')
      ..holder = _v('holder')
      ..bankName = _v('bankName')
      ..iban = _v('iban').isEmpty ? '' : formatIban(_v('iban'))
      ..swift = _v('swift').toUpperCase()
      ..lastName = _v('lastName')
      ..firstName = _v('firstName')
      ..cnp = _v('cnp')
      ..address = _v('address')
      ..docSeries = _v('docSeries').toUpperCase()
      ..docNumber = _v('docNumber')
      ..issuedBy = _v('issuedBy')
      ..docKind = _docKind
      ..issueDate = _issueDate
      ..expiryDate = _expiryDate
      ..price = _v('price')
      ..currency = _currency
      ..period = _period
      ..renewalDate = _renewalDate
      ..notes = _c['notes']!.text.trim()
      ..custom = [
        for (final (l, val, hidden) in _custom)
          if (l.text.trim().isNotEmpty || val.text.isNotEmpty)
            CustomField(label: l.text.trim(), value: val.text, hidden: hidden),
      ];
    _saved = true;
    await _store.saveSecret(_i);
    if (mounted) Navigator.pop(context);
  }

  /// [ocrText]: textul recunoscut, arătat la cerere (pentru verificare).
  void _toast(String m, {String? ocrText}) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(m),
        duration: Duration(seconds: ocrText == null ? 4 : 8),
        action: ocrText == null
            ? null
            : SnackBarAction(
                label: 'Text citit',
                onPressed: () => _showOcrText(ocrText),
              ),
      ),
    );

  void _showOcrText(String text) => showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Textul recunoscut'),
      content: SingleChildScrollView(
        child: SelectableText(text.trim().isEmpty ? '(nimic)' : text),
      ),
      actions: [
        TextButton(
          onPressed: () => copyValue(ctx, text, secret: true, what: 'Text'),
          child: const Text('Copiază'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Închide'),
        ),
      ],
    ),
  );

  Future<void> _generate() async {
    final p = await showPasswordGenerator(context);
    if (p != null) {
      setState(() {
        _c['password']!.text = p;
        _showPassword = true;
      });
    }
  }

  // ------------------------------------------------------------ 2FA din QR

  Future<void> _scanTotp() async {
    final code = await scanCode(context);
    if (code == null || !mounted) return;
    _applyOtpauth(code.value);
  }

  void _applyOtpauth(String value) {
    if (Totp.parse(value) == null) {
      _toast('Codul scanat nu este o cheie 2FA.');
      return;
    }
    setState(() {
      _c['totp']!.text = value.trim();
      final label = otpauthLabel(value);
      if (label != null) {
        if (_v('title').isEmpty && label.issuer.isNotEmpty) {
          _c['title']!.text = recognizeSite(label.issuer)?.name ?? label.issuer;
        }
        if (_v('username').isEmpty && label.account.isNotEmpty) {
          _c['username']!.text = label.account;
        }
      }
    });
    _toast('Cheia 2FA a fost adăugată.');
  }

  // -------------------------------------------------------------- clipboard

  Future<void> _pasteClipboard() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      setState(() => _clipAvailable = false);
      _toast('Clipboard-ul e gol.');
      return;
    }
    final kind = classifyClip(text);
    if (kind == ClipKind.otpauth) {
      _applyOtpauth(text);
      return;
    }
    // Câmpul potrivit pentru tipul intrării și felul textului.
    final target = switch ((_type, kind)) {
      (SecretType.bank, ClipKind.iban) => 'iban',
      (SecretType.card, ClipKind.card) => 'cardNumber',
      (SecretType.identity, _) when cnpValid(text) => 'cnp',
      (SecretType.login || SecretType.subscription, ClipKind.email) =>
        'username',
      (SecretType.login || SecretType.subscription, ClipKind.url) => 'url',
      (
        SecretType.login || SecretType.subscription || SecretType.wifi,
        ClipKind.password,
      ) =>
        'password',
      (SecretType.note, _) => 'notes',
      _ => null,
    };
    if (target == null) {
      _toast('Nu știu în ce câmp să pun textul copiat — lipește-l manual.');
      return;
    }
    setState(() {
      _c[target]!.text = target == 'notes' && _v('notes').isNotEmpty
          ? '${_c['notes']!.text}\n$text'
          : text;
      if (target == 'iban') _ibanChanged(text);
      if (target == 'url' && _v('title').isEmpty) {
        final site = recognizeSite(text);
        if (site != null) _c['title']!.text = site.name;
      }
    });
    const names = {
      'iban': 'IBAN',
      'cardNumber': 'Număr card',
      'cnp': 'CNP',
      'username': 'Utilizator / email',
      'url': 'Site',
      'password': 'Parolă',
      'notes': 'Notițe',
    };
    _toast('Lipit în „${names[target]}”.');
  }

  // ------------------------------------------------------------------- IBAN

  void _ibanChanged(String v) {
    final bank = bankFromIban(v);
    if (bank == null) return;
    if (_v('bankName').isEmpty) _c['bankName']!.text = bank.name;
    if (_v('swift').isEmpty) _c['swift']!.text = bank.swift;
  }

  // ------------------------------------------- buletin / card din poză sau PDF

  /// Completează câmpurile actului sau ale cardului din text recunoscut.
  /// Sursa: scaner cu camera, o poză existentă sau un PDF.
  Future<void> _readDocument() async {
    final isCard = _type == SecretType.card;
    final what = isCard ? 'cardul' : 'actul';
    final fileBase = isCard ? 'Card' : _docKind.label;
    if (!ScanService.scanSupported) {
      _toast('Citirea textului merge pe telefon (iPhone / Android).');
      return;
    }
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (v, icon, label) in [
              ('scan', Icons.document_scanner_outlined, 'Fotografiază $what'),
              ('image', Icons.photo_outlined, 'Alege o poză'),
              ('pdf', Icons.picture_as_pdf_outlined, 'Alege un PDF'),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.pop(ctx, v),
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _reading = true);
    try {
      // (nume, conținut, tip, imagine pentru OCR)
      final files = <(String, Uint8List, String, Uint8List)>[];
      switch (source) {
        case 'scan':
          for (final p in await ScanService.scan()) {
            files.add(('$fileBase.jpg', p.bytes, 'image/jpeg', p.bytes));
          }
        case 'image':
          for (final f in await FilePicker.pickFiles(type: FileType.image)) {
            final b = await f.readAsBytes();
            files.add((f.name, b, Attachment.mimeFromName(f.name), b));
          }
        case 'pdf':
          final picked = await FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: const ['pdf'],
          );
          for (final f in picked) {
            final b = await f.readAsBytes();
            // Primele 2 pagini, la rezoluție bună pentru OCR.
            var first = true;
            await for (final page in Printing.raster(
              b,
              pages: const [0, 1],
              dpi: 250,
            )) {
              final png = await page.toPng();
              // PDF-ul se atașează o singură dată; paginile doar se citesc.
              files.add((
                f.name,
                first ? b : Uint8List(0),
                'application/pdf',
                png,
              ));
              first = false;
            }
          }
      }
      if (files.isEmpty || !mounted) return;
      final texts = <String>[];
      for (final (name, bytes, mime, image) in files) {
        texts.add(await ScanService.recognize(image));
        if (bytes.isEmpty) continue;
        // Documentul rămâne atașat la intrare (criptat).
        final a = await _store.addAttachment(
          noteId: _i.attachmentOwnerId,
          name: name,
          bytes: bytes,
          mime: mime,
        );
        _added.add(a);
      }
      final text = texts.join('\n');
      if (!mounted) return;
      void put(String k, String v) {
        if (v.isNotEmpty) _c[k]!.text = v;
      }

      int found;
      if (isCard) {
        final d = parseCardText(text);
        found = d.found;
        if (found > 0) {
          setState(() {
            put('cardNumber', d.number);
            put('cardExpiry', d.expiry);
            put('cardHolder', d.holder);
          });
        }
      } else {
        final d = parseRomanianId(text);
        found = d.found;
        if (found > 0) {
          setState(() {
            put('lastName', d.lastName);
            put('firstName', d.firstName);
            put('cnp', d.cnp);
            put('address', d.address);
            put('docSeries', d.series);
            put('docNumber', d.number);
            put('issuedBy', d.issuedBy);
            _issueDate = d.issueDate ?? _issueDate;
            _expiryDate = d.expiryDate ?? _expiryDate;
          });
        }
      }
      if (found == 0) {
        _toast(
          'Nu am putut citi datele. Folosește o imagine dreaptă, clară, '
          'fără reflexii. Documentul a fost atașat.',
          ocrText: text,
        );
        return;
      }
      _toast(
        'Am completat $found '
        '${found == 1 ? 'câmp' : 'câmpuri'}. Verifică-le — citirea '
        'automată poate greși o cifră.'
        '${isCard ? ' CVV-ul și PIN-ul nu se citesc: scrie-le tu.' : ''}',
        ocrText: text,
      );
    } catch (e) {
      if (mounted) _toast('Nu am putut citi $what: $e');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  // ---------------------------------------------------------------- câmpuri

  Widget _text(
    String key,
    String label, {
    IconData? icon,
    TextInputType? keyboard,
    String? Function(String?)? validator,
    bool obscure = false,
    int maxLines = 1,
    String? hint,
    TextCapitalization caps = TextCapitalization.none,
    void Function(String)? onChanged,
    Widget? suffix,
    double bottom = 14,
  }) => Padding(
    padding: EdgeInsets.only(bottom: bottom),
    child: TextFormField(
      controller: _c[key],
      keyboardType: keyboard,
      textCapitalization: caps,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      validator: validator,
      onChanged: onChanged,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon),
        suffixIcon: suffix,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  /// Rând de sugestii atinse cu un deget, sub un câmp.
  Widget _suggestions(List<(String, VoidCallback)> items) => items.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, onTap) in items)
                ActionChip(
                  label: Text(label),
                  visualDensity: VisualDensity.compact,
                  onPressed: onTap,
                ),
            ],
          ),
        );

  Widget _titleSuggestions() {
    if (_type != SecretType.login && _type != SecretType.subscription) {
      return const SizedBox.shrink();
    }
    final t = _v('title');
    final sites = suggestSites(t).where((s) => s.name != t).toList();
    return _suggestions([
      for (final s in sites)
        (
          '${s.name} · ${s.domain}',
          () => setState(() {
            _c['title']!.text = s.name;
            if (_v('url').isEmpty) _c['url']!.text = s.domain;
            FocusScope.of(context).nextFocus();
          }),
        ),
    ]);
  }

  Widget _usernameField(String label) {
    final typed = _v('username');
    final sugg = typed.isEmpty
        ? const <String>[]
        : usernameSuggestions(typed, _store.allSecrets);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _text(
          'username',
          label,
          icon: Icons.person_outline,
          keyboard: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
          bottom: sugg.isEmpty ? 14 : 8,
        ),
        _suggestions([
          for (final s in sugg)
            (s, () => setState(() => _c['username']!.text = s)),
        ]),
      ],
    );
  }

  Widget _passwordField(String label) {
    final strength = passwordStrength(_c['password']!.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _c['password'],
            obscureText: !_showPassword,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.key_outlined),
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _showPassword ? 'Ascunde' : 'Arată',
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                  IconButton(
                    tooltip: 'Generează o parolă',
                    icon: const Icon(Icons.casino_outlined),
                    onPressed: _generate,
                  ),
                ],
              ),
            ),
          ),
          if (_c['password']!.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: (strength.index + 1) / Strength.values.length,
              color: Color(strength.color),
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
            const SizedBox(height: 4),
            Text(
              'Putere: ${strength.label}',
              style: TextStyle(color: Color(strength.color), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _totpField() => _text(
    'totp',
    'Cheie 2FA (opțional)',
    icon: Icons.verified_user_outlined,
    hint: 'Scanează codul QR de pe site sau scrie cheia',
    suffix: IconButton(
      tooltip: 'Scanează codul QR 2FA',
      icon: const Icon(Icons.qr_code_scanner),
      onPressed: _scanTotp,
    ),
    validator: (v) => (v ?? '').trim().isEmpty || Totp.parse(v!) != null
        ? null
        : 'Cheie 2FA invalidă',
  );

  Widget _dateField(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> onChanged, {
    IconData icon = Icons.event_outlined,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(1950),
          lastDate: DateTime(now.year + 30),
        );
        if (d != null) setState(() => onChanged(d));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
          suffixIcon: value == null
              ? null
              : IconButton(
                  tooltip: 'Șterge data',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => onChanged(null)),
                ),
        ),
        child: Text(value == null ? '' : formatShortDate(value)),
      ),
    ),
  );

  Widget _dropdown<T>(
    String label,
    IconData icon,
    T value,
    List<(T, String)> items,
    ValueChanged<T> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final (v, l) in items) DropdownMenuItem(value: v, child: Text(l)),
      ],
      onChanged: (v) {
        if (v != null) setState(() => onChanged(v));
      },
    ),
  );

  Widget _readButton() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: OutlinedButton.icon(
      icon: _reading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.document_scanner_outlined),
      label: const Text('Completează din fotografie sau PDF'),
      onPressed: _reading ? null : _readDocument,
    ),
  );

  String? _ibanValidator(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    return ibanValid(s) ? null : 'IBAN invalid — verifică cifrele';
  }

  List<Widget> _typeFields() => switch (_type) {
    SecretType.login => [
      _usernameField('Utilizator / email'),
      _passwordField('Parolă'),
      _text(
        'url',
        'Site / aplicație',
        icon: Icons.link,
        keyboard: TextInputType.url,
      ),
      _totpField(),
    ],
    SecretType.card => [
      _readButton(),
      _text(
        'cardHolder',
        'Titular',
        icon: Icons.person_outline,
        caps: TextCapitalization.characters,
      ),
      _text(
        'cardNumber',
        'Număr card',
        icon: Icons.credit_card,
        keyboard: TextInputType.number,
        validator: (v) {
          final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
          if (d.isEmpty) return null;
          return luhnValid(d) ? null : 'Numărul nu pare valid';
        },
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _text(
              'cardExpiry',
              'Expiră (LL/AA)',
              keyboard: TextInputType.datetime,
              validator: (v) =>
                  (v ?? '').isEmpty ||
                      RegExp(r'^(0[1-9]|1[0-2])/\d{2}$').hasMatch(v!.trim())
                  ? null
                  : 'Format LL/AA',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _text(
              'cardCvv',
              'CVV',
              keyboard: TextInputType.number,
              obscure: true,
            ),
          ),
        ],
      ),
      _text(
        'cardPin',
        'PIN (opțional)',
        icon: Icons.pin_outlined,
        keyboard: TextInputType.number,
        obscure: true,
      ),
    ],
    SecretType.bank => [
      _text(
        'iban',
        'IBAN',
        icon: Icons.numbers,
        caps: TextCapitalization.characters,
        validator: _ibanValidator,
        onChanged: (v) => setState(() => _ibanChanged(v)),
      ),
      _text(
        'holder',
        'Titular',
        icon: Icons.person_outline,
        caps: TextCapitalization.words,
      ),
      _text(
        'bankName',
        'Banca',
        icon: Icons.account_balance_outlined,
        caps: TextCapitalization.words,
        hint: 'Se completează singură din IBAN',
      ),
      _text(
        'swift',
        'Cod SWIFT / BIC',
        icon: Icons.public,
        caps: TextCapitalization.characters,
        validator: (v) =>
            (v ?? '').trim().isEmpty ||
                RegExp(r'^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$')
                    .hasMatch(v!.trim().toUpperCase())
            ? null
            : 'SWIFT are 8 sau 11 caractere',
      ),
    ],
    SecretType.identity => [
      _dropdown<DocKind>('Tip act', Icons.badge_outlined, _docKind, [
        for (final k in DocKind.values) (k, k.label),
      ], (v) => _docKind = v),
      if (_docKind == DocKind.ci) _readButton(),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _text(
              'lastName',
              'Nume',
              caps: TextCapitalization.characters,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _text(
              'firstName',
              'Prenume',
              caps: TextCapitalization.characters,
            ),
          ),
        ],
      ),
      _text(
        'cnp',
        'CNP',
        icon: Icons.fingerprint,
        keyboard: TextInputType.number,
        validator: (v) =>
            (v ?? '').trim().isEmpty || cnpValid(v!) ? null : 'CNP invalid',
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: _text(
              'docSeries',
              'Seria',
              caps: TextCapitalization.characters,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _text(
              'docNumber',
              'Număr',
              keyboard: _docKind == DocKind.ci ? TextInputType.number : null,
              caps: TextCapitalization.characters,
            ),
          ),
        ],
      ),
      _text(
        'address',
        'Domiciliu',
        icon: Icons.home_outlined,
        caps: TextCapitalization.words,
        maxLines: 2,
      ),
      _text(
        'issuedBy',
        'Eliberat de',
        icon: Icons.account_balance_outlined,
        hint: 'ex. SPCLEP Cluj-Napoca',
      ),
      _dateField('Data eliberării', _issueDate, (d) => _issueDate = d),
      _dateField(
        'Valabil până la',
        _expiryDate,
        (d) => _expiryDate = d,
        icon: Icons.event_busy_outlined,
      ),
    ],
    SecretType.subscription => [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _text(
              'price',
              'Preț',
              icon: Icons.payments_outlined,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ||
                      double.tryParse(v!.replaceAll(',', '.').trim()) != null
                  ? null
                  : 'Doar cifre',
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: const InputDecoration(
                labelText: 'Monedă',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'RON', child: Text('RON')),
                DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                DropdownMenuItem(value: 'USD', child: Text('USD')),
              ],
              onChanged: (v) => _currency = v ?? 'RON',
            ),
          ),
        ],
      ),
      _dropdown<BillingPeriod>('Se plătește', Icons.repeat, _period, [
        for (final p in BillingPeriod.values) (p, p.label),
      ], (v) => _period = v),
      _dateField(
        'Următoarea reînnoire',
        _renewalDate,
        (d) => _renewalDate = d,
        icon: Icons.event_repeat_outlined,
      ),
      _usernameField('Cont (email)'),
      _passwordField('Parolă'),
      _text('url', 'Site', icon: Icons.link, keyboard: TextInputType.url),
    ],
    SecretType.wifi => [
      _text('username', 'Nume rețea (SSID)', icon: Icons.wifi),
      _passwordField('Parolă Wi-Fi'),
      DropdownButtonFormField<String>(
        initialValue: _i.wifiSecurity,
        decoration: const InputDecoration(
          labelText: 'Securitate',
          prefixIcon: Icon(Icons.security),
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: 'WPA', child: Text('WPA/WPA2/WPA3')),
          DropdownMenuItem(value: 'WEP', child: Text('WEP')),
          DropdownMenuItem(value: 'nopass', child: Text('Fără parolă')),
        ],
        onChanged: (v) => _i.wifiSecurity = v ?? 'WPA',
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _i.wifiHidden,
        onChanged: (v) => setState(() => _i.wifiHidden = v ?? false),
        title: const Text('Rețea ascunsă'),
      ),
    ],
    SecretType.note => [],
  };

  @override
  Widget build(BuildContext context) {
    final isNote = _type == SecretType.note;
    return Scaffold(
      appBar: AppBar(
        title: Text('${_isNew ? 'Adaugă' : 'Editează'}: ${_type.label}'),
        actions: [TextButton(onPressed: _save, child: const Text('Salvează'))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
          children: [
            if (_clipAvailable)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ActionChip(
                    avatar: const Icon(Icons.content_paste, size: 18),
                    label: const Text('Lipește din clipboard'),
                    onPressed: _pasteClipboard,
                  ),
                ),
              ),
            _text(
              'title',
              isNote ? 'Titlu' : 'Nume (opțional)',
              icon: Icons.label_outline,
              caps: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              bottom: 8,
              hint: switch (_type) {
                SecretType.login => 'ex. Gmail, Banca, eMAG',
                SecretType.card => 'ex. Card salariu',
                SecretType.bank => 'ex. Cont salariu BT',
                SecretType.identity => 'ex. Buletinul meu',
                SecretType.subscription => 'ex. Netflix, Spotify',
                SecretType.wifi => 'ex. Wi-Fi acasă',
                SecretType.note => 'ex. Coduri de rezervă',
              },
            ),
            _titleSuggestions(),
            const SizedBox(height: 6),
            ..._typeFields(),
            if (isNote)
              _text(
                'notes',
                'Conținut',
                caps: TextCapitalization.sentences,
                maxLines: 14,
                keyboard: TextInputType.multiline,
              ),
            if (!isNote) ...[
              const SizedBox(height: 8),
              Text(
                'Câmpuri proprii',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (var k = 0; k < _custom.length; k++) _customRow(k),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Adaugă câmp'),
                  onPressed: () => setState(
                    () => _custom.add((
                      TextEditingController(),
                      TextEditingController(),
                      false,
                    )),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _text(
                'notes',
                'Notițe',
                icon: Icons.notes,
                caps: TextCapitalization.sentences,
                maxLines: 4,
                keyboard: TextInputType.multiline,
              ),
            ],
            SecretAttachments(
              ownerId: _i.attachmentOwnerId,
              editable: true,
              onAdded: _added.add,
            ),
          ],
        ),
      ),
    );
  }

  Widget _customRow(int k) {
    final (label, value, hidden) = _custom[k];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: label,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nume câmp',
                hintText: 'ex. Întrebare',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: value,
              obscureText: hidden,
              decoration: const InputDecoration(
                labelText: 'Valoare',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            tooltip: hidden
                ? 'Câmp secret (apasă pentru vizibil)'
                : 'Fă-l secret',
            icon: Icon(hidden ? Icons.lock : Icons.lock_open_outlined),
            onPressed: () =>
                setState(() => _custom[k] = (label, value, !hidden)),
          ),
          IconButton(
            tooltip: 'Elimină',
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
              _custom.removeAt(k);
              label.dispose();
              value.dispose();
            }),
          ),
        ],
      ),
    );
  }
}
