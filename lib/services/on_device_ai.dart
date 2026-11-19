import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/note.dart';

/// AI pe telefon: modelul de limbaj Apple (Apple Intelligence, iOS 26+),
/// care rulează DOAR pe dispozitiv — textul notițelor nu pleacă nicăieri și
/// nu costă nimic. Pe telefoanele fără Apple Intelligence (sau pe web)
/// funcțiile nu apar.
class OnDeviceAI {
  static const _channel = MethodChannel('notite/ai');

  /// Modelul are o fereastră mică (~4000 de unități de text): trimitem cel
  /// mult atâtea caractere.
  static const maxChars = 6000;

  static ({bool ok, String reason})? _status;

  static bool get _platform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Disponibil pe acest telefon (rezultatul e ținut minte).
  static Future<({bool ok, String reason})> status() async {
    if (_status case final s?) return s;
    if (!_platform) return (ok: false, reason: 'Doar pe iPhone');
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('available');
      final ok = r?['ok'] == true;
      final reason = switch (r?['reason']) {
        'deviceNotEligible' =>
          'Telefonul nu are Apple Intelligence (iPhone 15 Pro sau mai nou).',
        'appleIntelligenceNotEnabled' => 'Pornește Apple Intelligence din Setări → Apple Intelligence și Siri.',
        'modelNotReady' =>
          'Modelul Apple încă se descarcă. Încearcă puțin mai târziu.',
        'ios' => 'Necesită iOS 26 sau mai nou.',
        final String other => other,
        _ => '',
      };
      // „modelul se descarcă” nu se ține minte: peste puțin timp e gata
      final s = (ok: ok, reason: reason);
      if (r?['reason'] != 'modelNotReady') _status = s;
      return s;
    } catch (_) {
      return (ok: false, reason: 'Indisponibil');
    }
  }

  static Future<bool> available() async => (await status()).ok;

  static const _base =
      'Ești asistentul din aplicația de notițe „Notițe”. Răspunzi DOAR în '
      'limba română, scurt și clar, fără introduceri. Folosește numai '
      'informațiile din textul primit; nu inventa nimic.';

  static Future<String> _respond(String instructions, String prompt) async {
    final text = await _channel.invokeMethod<String>('respond', {
      'instructions': '$_base $instructions',
      'prompt': prompt,
    });
    return (text ?? '').trim();
  }

  static String _clip(String s) =>
      s.length <= maxChars ? s : '${s.substring(0, maxChars)}…';

  /// Rezumatul unei notițe (sau al transcrierii unei note vocale).
  static Future<String> summarize(String title, String body) => _respond(
    'Faci rezumate: 2–4 propoziții sau câteva puncte scurte cu ce e '
        'important (cifre, date, nume, decizii).',
    'Rezumă notița „$title”:\n\n${_clip(body)}',
  );

  /// Sarcinile de făcut din text, câte una pe rând.
  static Future<List<String>> tasks(String title, String body) async {
    final r = await _respond(
      'Extragi lucrurile de făcut dintr-un text. Scrie fiecare sarcină pe un '
          'rând separat, începând cu „- ”, scurt (max. 10 cuvinte), cu verb la '
          'început. Dacă nu există nimic de făcut, scrie doar „NIMIC”.',
      'Ce trebuie făcut, din notița „$title”:\n\n${_clip(body)}',
    );
    return parseList(r);
  }

  @visibleForTesting
  static List<String> parseList(String r) => [
    for (final line in r.split('\n'))
      if (line.trim().replaceFirst(RegExp(r'^([-•*]|\d+[.)])\s*'), '')
          case final t when t.isNotEmpty && t.toUpperCase() != 'NIMIC')
        t,
  ];

  /// Un titlu scurt pentru o notiță fără titlu.
  static Future<String> title(String body) async {
    final r = await _respond(
      'Propui titluri: maximum 6 cuvinte, fără ghilimele și fără punct.',
      'Titlu pentru notița:\n\n${_clip(body)}',
    );
    return r.split('\n').first.replaceAll(RegExp(r'^["„“]+|["”“.]+$'), '');
  }

  /// Răspuns la o întrebare, din notițele cele mai potrivite. Întoarce și
  /// notițele folosite (ca să le poți deschide).
  static Future<({String answer, List<Note> sources})> ask(
    String question,
    Iterable<Note> notes,
  ) async {
    final sources = relevantNotes(question, notes);
    if (sources.isEmpty) {
      return (
        answer: 'Nu am găsit notițe despre asta.',
        sources: const <Note>[],
      );
    }
    final per = maxChars ~/ sources.length;
    final context = [
      for (final n in sources)
        '### ${n.displayTitle}\n'
            '${n.plainText.length > per ? n.plainText.substring(0, per) : n.plainText}',
    ].join('\n\n');
    final answer = await _respond(
      'Răspunzi la întrebări folosind notițele utilizatorului. Spune din ce '
          'notiță ai luat răspunsul. Dacă răspunsul nu e în notițe, spune '
          '„Nu scrie în notițe.”',
      'Notițele:\n\n$context\n\nÎntrebarea: $question',
    );
    return (answer: answer, sources: sources);
  }

  static String _fold(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[ăâ]'), 'a')
      .replaceAll('î', 'i')
      .replaceAll(RegExp('[șş]'), 's')
      .replaceAll(RegExp('[țţ]'), 't');

  static const _stop = {
    'care',
    'unde',
    'cand',
    'este',
    'sunt',
    'pentru',
    'cine',
    'cum',
    'ce',
    'din',
    'despre',
    'mea',
    'meu',
    'mele',
    'mei',
    'imi',
    'am',
    'are',
    'la',
    'de',
    'si',
    'in',
    'cu',
    'pe',
    'un',
    'o',
    'a',
    'al',
    'ale',
    'lui',
    'cat',
    'cate',
    'cati',
    'ma',
    'mi',
    'se',
    'sa',
    'fost',
    'avea',
    'trebuie',
  };

  /// Cele mai potrivite notițe (max. 4) pentru întrebare: cuvinte comune,
  /// titlul cântărește mai mult; fără notițele blocate sau din coș.
  @visibleForTesting
  static List<Note> relevantNotes(String question, Iterable<Note> notes) {
    final words = _fold(question)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length >= 3 && !_stop.contains(w))
        // rădăcină: „expirarea” ↔ „expiră” (primele 5 litere)
        .map((w) => w.length > 5 ? w.substring(0, 5) : w)
        .toSet();
    if (words.isEmpty) return const [];
    final scored = <(Note, int)>[];
    for (final n in notes) {
      if (n.locked || n.isTrashed) continue;
      final title = _fold(n.title);
      final body = _fold(n.plainText);
      var score = 0;
      for (final w in words) {
        if (title.contains(w)) score += 3;
        if (body.contains(w)) score += 1;
      }
      if (score > 0) scored.add((n, score));
    }
    scored.sort((a, b) {
      final s = b.$2.compareTo(a.$2);
      return s != 0 ? s : b.$1.updatedAt.compareTo(a.$1.updatedAt);
    });
    return [for (final e in scored.take(4)) e.$1];
  }
}
