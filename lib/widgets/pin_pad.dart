import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/pin_lock.dart';

/// Introducerea unui cod de 6 cifre: puncte + tastatură numerică (merge și
/// cu tastatura fizică). [onCompleted] e apelat automat la a 6-a cifră și
/// întoarce `null` dacă e bine sau mesajul de eroare (codul se golește).
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.title,
    required this.onCompleted,
    this.subtitle,
    this.extraKey,
    this.initialError,
  });

  final String title;
  final String? subtitle;

  /// Mesaj de eroare arătat de la început (ex. după un pas anterior).
  final String? initialError;
  final Future<String?> Function(String pin) onCompleted;

  /// Tasta din stânga jos (ex. Face ID); goală dacă lipsește.
  final Widget? extraKey;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _pin = '';
  late String? _error = widget.initialError;
  bool _checking = false;
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    // Tastatura fizică (calculator): ascultare globală, fără să depindă de
    // focus — după un clic pe bara de jos, focusul rămâne acolo.
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _shake.dispose();
    super.dispose();
  }

  Future<void> _add(String digit) async {
    if (_checking || _pin.length >= PinLock.length) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length < PinLock.length) return;
    setState(() => _checking = true);
    final error = await widget.onCompleted(_pin);
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (error != null) {
        _error = error;
        _pin = '';
      }
    });
    if (error != null) {
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
    }
  }

  void _delete() {
    if (_checking || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  /// Doar cât ecranul e în față și nu se scrie într-un câmp de text.
  bool _onHardwareKey(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return false;
    }
    final ch = e.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      _add(ch);
      return true;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _delete();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.title,
            style: text.titleLarge,
            textAlign: TextAlign.center,
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: _shake,
            builder: (context, child) {
              // Tremurat scurt la cod greșit.
              final t = _shake.value;
              final dx = t == 0 ? 0.0 : 10 * (1 - t) * _wave(t);
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < PinLock.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.symmetric(horizontal: 9),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length
                          ? (_error != null ? scheme.error : scheme.primary)
                          : Colors.transparent,
                      border: Border.all(
                        color: _error != null ? scheme.error : scheme.outline,
                        width: 1.6,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: Center(
              child: _checking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _error ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error),
                    ),
            ),
          ),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [for (final d in row) _key(d)],
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 84,
                child: Center(child: widget.extraKey),
              ),
              _key('0'),
              SizedBox.square(
                dimension: 84,
                child: IconButton(
                  tooltip: 'Șterge',
                  iconSize: 26,
                  onPressed: _pin.isEmpty ? null : _delete,
                  icon: const Icon(Icons.backspace_outlined),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 3 oscilații pe durata animației.
  static double _wave(double t) => sin(t * 3 * 2 * pi);

  Widget _key(String digit) => Padding(
    padding: const EdgeInsets.all(6),
    child: SizedBox.square(
      dimension: 72,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _add(digit),
          child: Center(
            child: Text(
              digit,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    ),
  );
}
