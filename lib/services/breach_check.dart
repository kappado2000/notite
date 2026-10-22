import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Verifică dacă o parolă apare în scurgeri de date publice
/// (Have I Been Pwned, „k-anonymity”): se trimit DOAR primele 5 caractere
/// din amprenta SHA-1 a parolei; parola și amprenta completă nu părăsesc
/// telefonul. Răspunsul e completat cu rânduri false („Add-Padding”), ca
/// nici mărimea lui să nu dezvăluie nimic.
class BreachCheck {
  BreachCheck({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final _cache = <String, Map<String, int>>{};

  static String sha1Hex(String password) =>
      sha1.convert(utf8.encode(password)).toString().toUpperCase();

  /// De câte ori a apărut parola în scurgeri (0 = niciodată).
  Future<int> timesPwned(String password) async {
    if (password.isEmpty) return 0;
    final hash = sha1Hex(password);
    final prefix = hash.substring(0, 5);
    final suffixes = _cache[prefix] ??= await _range(prefix);
    return suffixes[hash.substring(5)] ?? 0;
  }

  Future<Map<String, int>> _range(String prefix) async {
    final res = await _client
        .get(
          Uri.parse('https://api.pwnedpasswords.com/range/$prefix'),
          headers: {'Add-Padding': 'true'},
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Serviciul a răspuns cu ${res.statusCode}');
    }
    return parseRange(res.body);
  }

  /// „SUFIX:NUMĂR” pe fiecare rând; rândurile de umplutură au numărul 0.
  static Map<String, int> parseRange(String body) => {
    for (final line in const LineSplitter().convert(body))
      if (line.split(':') case [final s, final n]
          when (int.tryParse(n.trim()) ?? 0) > 0)
        s.trim().toUpperCase(): int.parse(n.trim()),
  };
}
