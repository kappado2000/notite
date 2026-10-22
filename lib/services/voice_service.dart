import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Notițe vocale: înregistrare (AAC/m4a) și transcriere în text.
class VoiceService {
  static const _speech = MethodChannel('notite/speech');

  /// Înregistrarea e disponibilă pe telefon și desktop (nu în browser).
  static bool get recordingSupported => !kIsWeb;

  /// Transcrierea folosește recunoașterea vocală Apple (doar iPhone).
  static bool get transcriptionSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<String> newRecordingPath() async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}/nota_vocala_$stamp.m4a';
  }

  /// Configurație potrivită pentru voce: mono, 64 kbps.
  static const recordConfig = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 64000,
    sampleRate: 44100,
    numChannels: 1,
    autoGain: true,
    noiseSuppress: true,
  );

  /// Transcrie fișierul audio. Întoarce textul sau aruncă o eroare cu un
  /// mesaj în română (permisiune refuzată, limbă indisponibilă etc.).
  static Future<({String text, bool onDevice})> transcribe(String path) async {
    if (!transcriptionSupported) {
      throw UnsupportedError('Transcrierea e disponibilă doar pe iPhone');
    }
    final result = await _speech.invokeMapMethod<String, dynamic>(
      'transcribe',
      {'path': path, 'locale': 'ro-RO'},
    );
    return (
      text: ((result?['text'] as String?) ?? '').trim(),
      onDevice: (result?['onDevice'] as bool?) ?? false,
    );
  }
}
