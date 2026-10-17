import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/notes_store.dart';
import '../../models/secret_item.dart';
import '../../services/password_tools.dart';
import '../../services/totp.dart';
import 'password_generator_sheet.dart';

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
  bool _showPassword = false;

  bool get _isNew => context.read<NotesStore>().secret(_i.id) == null;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    for (final (a, b, _) in _custom) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    String v(String k) => _c[k]!.text.trim();
    _i
      ..title = v('title')
      ..url = v('url')
      ..username = v('username')
      ..password = _c['password']!.text
      ..totp = v('totp')
      ..cardHolder = v('cardHolder')
      ..cardNumber = v('cardNumber')
      ..cardExpiry = v('cardExpiry')
      ..cardCvv = v('cardCvv')
      ..cardPin = v('cardPin')
      ..notes = _c['notes']!.text.trim()
      ..custom = [
        for (final (l, val, hidden) in _custom)
          if (l.text.trim().isNotEmpty || val.text.isNotEmpty)
            CustomField(label: l.text.trim(), value: val.text, hidden: hidden),
      ];
    await context.read<NotesStore>().saveSecret(_i);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _generate() async {
    final p = await showPasswordGenerator(context);
    if (p != null) {
      setState(() {
        _c['password']!.text = p;
        _showPassword = true;
      });
    }
  }

  Widget _text(
    String key,
    String label, {
    IconData? icon,
    TextInputType? keyboard,
    String? Function(String?)? validator,
    bool obscure = false,
    int maxLines = 1,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: _c[key],
      keyboardType: keyboard,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon),
        border: const OutlineInputBorder(),
      ),
    ),
  );

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_isNew ? 'Adaugă' : 'Editează'}: ${_i.type.label}'),
        actions: [TextButton(onPressed: _save, child: const Text('Salvează'))],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
          children: [
            _text(
              'title',
              'Nume (opțional)',
              icon: Icons.label_outline,
              hint: switch (_i.type) {
                SecretType.login => 'ex. Gmail, Banca, eMAG',
                SecretType.card => 'ex. Card salariu',
                SecretType.wifi => 'ex. Wi-Fi acasă',
              },
            ),
            ...switch (_i.type) {
              SecretType.login => [
                _text(
                  'username',
                  'Utilizator / email',
                  icon: Icons.person_outline,
                  keyboard: TextInputType.emailAddress,
                ),
                _passwordField('Parolă'),
                _text(
                  'url',
                  'Site / aplicație',
                  icon: Icons.link,
                  keyboard: TextInputType.url,
                ),
                _text(
                  'totp',
                  'Cheie 2FA (opțional)',
                  icon: Icons.verified_user_outlined,
                  hint: 'Cheia text sau linkul otpauth:// de la site',
                  validator: (v) =>
                      (v ?? '').trim().isEmpty || Totp.parse(v!) != null
                      ? null
                      : 'Cheie 2FA invalidă',
                ),
              ],
              SecretType.card => [
                _text('cardHolder', 'Titular', icon: Icons.person_outline),
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
                  children: [
                    Expanded(
                      child: _text(
                        'cardExpiry',
                        'Expiră (LL/AA)',
                        keyboard: TextInputType.datetime,
                        validator: (v) =>
                            (v ?? '').isEmpty ||
                                RegExp(r'^(0[1-9]|1[0-2])/\d{2}$')
                                    .hasMatch(v!.trim())
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
                    DropdownMenuItem(
                      value: 'WPA',
                      child: Text('WPA/WPA2/WPA3'),
                    ),
                    DropdownMenuItem(value: 'WEP', child: Text('WEP')),
                    DropdownMenuItem(
                      value: 'nopass',
                      child: Text('Fără parolă'),
                    ),
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
            },
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
              maxLines: 4,
              keyboard: TextInputType.multiline,
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
              decoration: const InputDecoration(
                labelText: 'Nume câmp',
                hintText: 'ex. IBAN',
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
