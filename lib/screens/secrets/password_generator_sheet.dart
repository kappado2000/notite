import 'package:flutter/material.dart';

import '../../services/password_tools.dart';
import '../../services/secret_helpers.dart';

/// Panou de generare a parolelor; întoarce parola aleasă.
Future<String?> showPasswordGenerator(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _GeneratorSheet(),
    );

class _GeneratorSheet extends StatefulWidget {
  const _GeneratorSheet();

  @override
  State<_GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends State<_GeneratorSheet> {
  double _length = 20;
  bool _upper = true;
  bool _digits = true;
  bool _symbols = true;
  bool _avoidAmbiguous = true;

  /// Frază din cuvinte românești, mai ușor de ținut minte și de tastat.
  bool _phrase = false;
  double _words = 5;
  late String _password = _make();

  String _make() => _phrase
      ? generatePassphrase(words: _words.round())
      : PasswordGenerator.generate(
          length: _length.round(),
          upper: _upper,
          digits: _digits,
          symbols: _symbols,
          avoidAmbiguous: _avoidAmbiguous,
        );

  void _regen() => setState(() => _password = _make());

  @override
  Widget build(BuildContext context) {
    final strength = passwordStrength(_password);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Generator de parole',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _password,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Alta',
                    icon: const Icon(Icons.refresh),
                    onPressed: _regen,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Putere: ${strength.label}',
              style: TextStyle(color: Color(strength.color)),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Parolă')),
                ButtonSegment(value: true, label: Text('Frază-parolă')),
              ],
              selected: {_phrase},
              onSelectionChanged: (v) {
                _phrase = v.first;
                _regen();
              },
            ),
            const SizedBox(height: 12),
            if (_phrase) ...[
              Text('Cuvinte: ${_words.round()}'),
              Slider(
                value: _words,
                min: 3,
                max: 8,
                divisions: 5,
                label: '${_words.round()}',
                onChanged: (v) => setState(() {
                  _words = v;
                  _password = _make();
                }),
              ),
              Text(
                'Ex. „Soare-lac42-munte-ceai-tren” — ușor de citit și de '
                'tastat, greu de ghicit.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
            ] else ...[
              Text('Lungime: ${_length.round()}'),
              Slider(
                value: _length,
                min: 8,
                max: 64,
                divisions: 56,
                label: '${_length.round()}',
                onChanged: (v) => setState(() {
                  _length = v;
                  _password = _make();
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Majuscule (A-Z)'),
                value: _upper,
                onChanged: (v) {
                  _upper = v;
                  _regen();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Cifre (0-9)'),
                value: _digits,
                onChanged: (v) {
                  _digits = v;
                  _regen();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(r'Simboluri (!@#$…)'),
                value: _symbols,
                onChanged: (v) {
                  _symbols = v;
                  _regen();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fără caractere ușor de confundat'),
                subtitle: const Text('l, I, O, 0, 1'),
                value: _avoidAmbiguous,
                onChanged: (v) {
                  _avoidAmbiguous = v;
                  _regen();
                },
              ),
            ],
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => Navigator.pop(context, _password),
              child: const Text('Folosește parola'),
            ),
          ],
        ),
      ),
    );
  }
}
