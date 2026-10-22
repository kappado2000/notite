import 'dart:async';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../services/voice_service.dart';

/// Panoul de înregistrare: pornește imediat, arată cronometrul și nivelul
/// sunetului. Întoarce calea fișierului (sau null la renunțare).
Future<({String path, Duration duration})?> recordVoiceNote(
  BuildContext context,
) => showModalBottomSheet<({String path, Duration duration})>(
  context: context,
  isDismissible: false,
  enableDrag: false,
  builder: (_) => const _RecorderSheet(),
);

class _RecorderSheet extends StatefulWidget {
  const _RecorderSheet();

  @override
  State<_RecorderSheet> createState() => _RecorderSheetState();
}

class _RecorderSheetState extends State<_RecorderSheet> {
  final _recorder = AudioRecorder();
  final _watch = Stopwatch();
  Timer? _ticker;
  StreamSubscription<Amplitude>? _ampSub;
  double _level = 0;
  String? _error;
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        setState(
          () => _error =
              'Aplicația nu are acces la microfon. Permite-l din '
              'Setări → Notițe → Microfon.',
        );
        return;
      }
      await _recorder.start(
        VoiceService.recordConfig,
        path: await VoiceService.newRecordingPath(),
      );
      _watch.start();
      _ticker = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => setState(() {}),
      );
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((a) {
            // dBFS (-60…0) → 0…1
            setState(() => _level = ((a.current + 60) / 60).clamp(0.0, 1.0));
          });
      setState(() => _recording = true);
    } catch (e) {
      setState(() => _error = 'Înregistrarea nu a pornit: $e');
    }
  }

  Future<void> _stop() async {
    _watch.stop();
    final path = await _recorder.stop();
    if (!mounted) return;
    Navigator.pop(
      context,
      path == null ? null : (path: path, duration: _watch.elapsed),
    );
  }

  Future<void> _cancel() async {
    if (_recording) await _recorder.cancel();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ampSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = _watch.elapsed;
    final time =
        '${e.inMinutes.toString().padLeft(2, '0')}:'
        '${(e.inSeconds % 60).toString().padLeft(2, '0')}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Notă vocală', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            if (_error != null)
              Text(_error!, textAlign: TextAlign.center)
            else ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 96 + 40 * _level,
                height: 96 + 40 * _level,
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.mic, size: 48, color: scheme.error),
              ),
              const SizedBox(height: 16),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 28,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                VoiceService.transcriptionSupported
                    ? 'La final, înregistrarea e transcrisă în text'
                    : 'Înregistrarea se atașează la notiță',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancel,
                    child: const Text('Renunță'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _recording ? _stop : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Salvează'),
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
