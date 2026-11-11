import 'dart:math';

import '../models/secret_item.dart';

// --------------------------------------------------------------- IBAN

String ibanCompact(String s) => s.replaceAll(RegExp(r'\s'), '').toUpperCase();

/// Validare IBAN (lungime pe țară + control mod 97).
bool ibanValid(String input) {
  final s = ibanCompact(input);
  if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{8,30}$').hasMatch(s)) return false;
  final len = _ibanLengths[s.substring(0, 2)];
  if (len != null && s.length != len) return false;
  final moved = s.substring(4) + s.substring(0, 4);
  var rem = 0;
  for (final ch in moved.codeUnits) {
    final v = ch >= 65 ? ch - 55 : ch - 48; // A=10 … Z=35
    rem = (v >= 10 ? rem * 100 + v : rem * 10 + v) % 97;
  }
  return rem == 1;
}

/// „RO49AAAA1B31007593840000” → „RO49 AAAA 1B31 0075 9384 0000”.
String formatIban(String input) {
  final s = ibanCompact(input);
  return [
    for (var i = 0; i < s.length; i += 4) s.substring(i, min(i + 4, s.length)),
  ].join(' ');
}

const _ibanLengths = {
  'RO': 24,
  'MD': 24,
  'DE': 22,
  'AT': 20,
  'BE': 16,
  'BG': 22,
  'CH': 21,
  'CY': 28,
  'CZ': 24,
  'DK': 18,
  'EE': 20,
  'ES': 24,
  'FI': 18,
  'FR': 27,
  'GB': 22,
  'GR': 27,
  'HR': 21,
  'HU': 28,
  'IE': 22,
  'IT': 27,
  'LT': 20,
  'LU': 20,
  'LV': 21,
  'MT': 31,
  'NL': 18,
  'NO': 15,
  'PL': 28,
  'PT': 25,
  'SE': 24,
  'SI': 19,
  'SK': 24,
  'UA': 29,
  'TR': 26,
};

/// Banca dedusă din codul din IBAN-ul românesc (caracterele 5–8).
({String name, String swift})? bankFromIban(String input) {
  final s = ibanCompact(input);
  if (!s.startsWith('RO') || s.length < 8) return null;
  return _roBanks[s.substring(4, 8)];
}

const _roBanks = <String, ({String name, String swift})>{
  'BTRL': (name: 'Banca Transilvania', swift: 'BTRLRO22'),
  'RNCB': (name: 'BCR', swift: 'RNCBROBU'),
  'BRDE': (name: 'BRD', swift: 'BRDEROBU'),
  'INGB': (name: 'ING Bank', swift: 'INGBROBU'),
  'RZBR': (name: 'Raiffeisen Bank', swift: 'RZBRROBU'),
  'CECE': (name: 'CEC Bank', swift: 'CECEROBU'),
  'BACX': (name: 'UniCredit Bank', swift: 'BACXROBU'),
  'UGBI': (name: 'Garanti BBVA', swift: 'UGBIROBU'),
  'OTPV': (name: 'OTP Bank', swift: 'OTPVROBU'),
  'LIBR': (name: 'Libra Internet Bank', swift: 'LIBRROBU'),
  'EXIM': (name: 'Exim Banca Românească', swift: 'EXIMROBU'),
  'BRMA': (name: 'Banca Românească', swift: 'BRMAROBU'),
  'PIRB': (name: 'First Bank', swift: 'PIRBROBU'),
  'WBAN': (name: 'Intesa Sanpaolo', swift: 'WBANROBU'),
  'BUCU': (name: 'Alpha Bank', swift: 'BUCUROBU'),
  'MIRO': (name: 'ProCredit Bank', swift: 'MIROROBU'),
  'CARP': (name: 'Patria Bank', swift: 'CARPRO22'),
  'EGNA': (name: 'Vista Bank', swift: 'EGNAROBX'),
  'TREZ': (name: 'Trezoreria Statului', swift: 'TREZROBU'),
  'REVO': (name: 'Revolut', swift: 'REVOROBB'),
};

// ----------------------------------------------------------------- CNP

/// Validare CNP (cifra de control + data nașterii plauzibilă).
bool cnpValid(String input) {
  final s = input.trim();
  if (!RegExp(r'^[1-9]\d{12}$').hasMatch(s)) return false;
  const k = '279146358279';
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(s[i]) * int.parse(k[i]);
  }
  var c = sum % 11;
  if (c == 10) c = 1;
  if (c != int.parse(s[12])) return false;
  return cnpBirthDate(s) != null;
}

/// Data nașterii codificată în CNP (null dacă e invalidă).
DateTime? cnpBirthDate(String s) {
  if (s.length != 13) return null;
  final century = switch (s[0]) {
    '1' || '2' => 1900,
    '3' || '4' => 1800,
    '5' || '6' => 2000,
    // 7, 8, 9 = rezidenți / străini: secolul nu e codificat.
    _ => int.parse(s.substring(1, 3)) > DateTime.now().year % 100 ? 1900 : 2000,
  };
  final y = century + int.parse(s.substring(1, 3));
  final m = int.parse(s.substring(3, 5));
  final d = int.parse(s.substring(5, 7));
  if (m < 1 || m > 12 || d < 1) return null;
  final date = DateTime(y, m, d);
  return date.month == m ? date : null;
}

// --------------------------------------------------------- fraze-parolă

/// Frază-parolă din cuvinte românești (fără diacritice, ușor de tastat).
/// 5 cuvinte din ~420 ≈ 43 de biți, plus cifrele și majuscula.
String generatePassphrase({
  int words = 5,
  String separator = '-',
  bool capitalize = true,
  bool addNumber = true,
}) {
  final r = Random.secure();
  final list = [
    for (var i = 0; i < words; i++)
      passphraseWords[r.nextInt(passphraseWords.length)],
  ];
  if (capitalize) {
    final i = r.nextInt(list.length);
    list[i] = list[i][0].toUpperCase() + list[i].substring(1);
  }
  if (addNumber) {
    final i = r.nextInt(list.length);
    list[i] = '${list[i]}${r.nextInt(90) + 10}';
  }
  return list.join(separator);
}

/// Cuvinte românești uzuale, fără diacritice, 4–8 litere.
const passphraseWords = [
  'abur',
  'acasa',
  'acord',
  'acvila',
  'adevar',
  'adapost',
  'aer',
  'afara',
  'aluat',
  'alun',
  'amiaza',
  'amic',
  'anotimp',
  'arbore',
  'arcas',
  'arcus',
  'argint',
  'arici',
  'armura',
  'arpa',
  'artist',
  'aster',
  'atlas',
  'aur',
  'avion',
  'bagaj',
  'balcon',
  'balena',
  'banca',
  'barca',
  'barza',
  'basm',
  'baston',
  'bazar',
  'berbec',
  'bibelou',
  'bicicleta',
  'biscuit',
  'bivol',
  'bluza',
  'boboc',
  'bocanc',
  'bogat',
  'bolta',
  'borcan',
  'brad',
  'bratara',
  'brazda',
  'briza',
  'broasca',
  'bucata',
  'bujor',
  'bunic',
  'burete',
  'busola',
  'buzunar',
  'cadou',
  'cafea',
  'caiet',
  'cais',
  'calator',
  'camila',
  'campie',
  'cana',
  'canion',
  'capac',
  'capra',
  'carte',
  'carus',
  'castel',
  'castor',
  'catel',
  'cazan',
  'ceai',
  'ceas',
  'cercel',
  'cerneala',
  'cetate',
  'chei',
  'chitara',
  'cires',
  'cizma',
  'clopot',
  'coada',
  'cocos',
  'colina',
  'comoara',
  'condur',
  'copac',
  'corabie',
  'corb',
  'cort',
  'cosmos',
  'covor',
  'creion',
  'crin',
  'cuib',
  'cupola',
  'curcubeu',
  'cutie',
  'dafin',
  'dans',
  'decor',
  'deal',
  'delfin',
  'desen',
  'destin',
  'diamant',
  'dinte',
  'dop',
  'dor',
  'dovleac',
  'drapel',
  'drum',
  'dulap',
  'duminica',
  'ecou',
  'elefant',
  'erou',
  'fag',
  'fanfara',
  'farfurie',
  'fazan',
  'fereastra',
  'ferma',
  'festival',
  'fierar',
  'fluier',
  'fluture',
  'foc',
  'fotoliu',
  'fragi',
  'frunza',
  'fulg',
  'fum',
  'furnica',
  'gaina',
  'galben',
  'gard',
  'gheata',
  'ghinda',
  'ghiozdan',
  'girafa',
  'glob',
  'golf',
  'gradina',
  'granit',
  'gutuie',
  'hamac',
  'harta',
  'hambar',
  'hotel',
  'iarba',
  'iarna',
  'iaurt',
  'iepure',
  'iglu',
  'insula',
  'izvor',
  'jar',
  'jilt',
  'joc',
  'jucarie',
  'lac',
  'lalea',
  'lampa',
  'lana',
  'lapte',
  'laur',
  'leagan',
  'lebada',
  'lemn',
  'leu',
  'liliac',
  'liniste',
  'livada',
  'lumina',
  'luna',
  'lup',
  'magazin',
  'magnet',
  'mare',
  'margea',
  'mar',
  'masa',
  'matase',
  'melc',
  'mesteacan',
  'miere',
  'mistret',
  'moara',
  'molid',
  'morcov',
  'munte',
  'muzeu',
  'nasture',
  'navigator',
  'nisip',
  'noapte',
  'nor',
  'nuc',
  'oaza',
  'ocean',
  'ochelari',
  'oglinda',
  'olar',
  'opal',
  'oras',
  'orhidee',
  'ou',
  'pahar',
  'palarie',
  'palat',
  'pantof',
  'papusa',
  'paine',
  'parc',
  'pasare',
  'pastel',
  'patina',
  'pelican',
  'pepene',
  'perla',
  'peste',
  'petala',
  'pian',
  'piatra',
  'pinguin',
  'pisica',
  'pitic',
  'plaja',
  'planeta',
  'ploaie',
  'poarta',
  'pod',
  'poiana',
  'portocala',
  'praf',
  'primavara',
  'prieten',
  'prun',
  'pui',
  'pulover',
  'rachita',
  'radacina',
  'rata',
  'raza',
  'rechin',
  'rinocer',
  'roata',
  'robot',
  'rodie',
  'rosie',
  'rubin',
  'sanie',
  'safir',
  'salcie',
  'salata',
  'sanda',
  'sat',
  'scara',
  'scaun',
  'scoica',
  'seara',
  'semn',
  'sertar',
  'sfera',
  'sirena',
  'soare',
  'soim',
  'soparla',
  'spic',
  'stafide',
  'stea',
  'stejar',
  'stilou',
  'stinca',
  'strada',
  'struguri',
  'stupar',
  'suflet',
  'tablou',
  'tamburina',
  'tanar',
  'tapet',
  'teatru',
  'tei',
  'telefon',
  'tigru',
  'toamna',
  'topaz',
  'trandafir',
  'tren',
  'trifoi',
  'trompeta',
  'tufis',
  'tunel',
  'turn',
  'ulcior',
  'umbrela',
  'urs',
  'vagon',
  'vapor',
  'vara',
  'vatra',
  'veverita',
  'vioara',
  'vis',
  'vulpe',
  'vultur',
  'zambila',
  'zapada',
  'zar',
  'zebra',
  'zid',
  'zmeu',
  'zori',
  'zumzet',
  'albina',
  'alune',
  'ancora',
  'arena',
  'balaur',
  'bambus',
  'banana',
  'barometru',
  'bec',
  'bidon',
  'bilet',
  'birou',
  'bolovan',
  'bomboana',
  'brutar',
  'cactus',
  'calendar',
  'camera',
  'canapea',
  'caramida',
  'carusel',
  'cascada',
  'ceapa',
  'cerc',
  'cerb',
  'chibrit',
  'cinema',
  'clatita',
  'clovn',
  'compas',
  'covrig',
  'cristal',
  'cuptor',
  'dinozaur',
  'dirijor',
  'domino',
  'dragon',
  'dulceata',
  'evantai',
  'fantana',
  'felinar',
  'fermoar',
  'flamingo',
  'floare',
  'foarfeca',
  'fotograf',
  'gem',
  'gondola',
  'gorila',
  'grafit',
  'harpa',
  'elicopter',
  'hipopotam',
  'inel',
  'jaguar',
  'jurnal',
  'koala',
  'labirint',
  'lamaie',
  'leopard',
  'lingura',
  'magnolie',
  'maimuta',
  'mandarina',
  'marmura',
  'meteor',
  'mozaic',
  'nautil',
  'oaie',
  'orchestra',
  'origami',
  'pantera',
  'papagal',
  'parasuta',
  'pensula',
  'piramida',
  'pirat',
  'plic',
  'porumbel',
  'puzzle',
  'racheta',
  'regina',
  'safari',
  'sculptor',
  'semafor',
  'serpentina',
  'sirop',
  'spiridus',
  'statuie',
  'telescop',
  'tobogan',
  'toporas',
  'trambulina',
  'triunghi',
  'tulipan',
  'vals',
  'vanilie',
  'vartej',
  'velur',
  'vulcan',
  'xilofon',
  'zeppelin',
];

// ------------------------------------------------------ recunoaștere site

/// Un serviciu cunoscut: nume afișat, domeniu, culoare de marcă.
class KnownSite {
  const KnownSite(
    this.name,
    this.domain,
    this.color, [
    this.aliases = const [],
  ]);
  final String name;
  final String domain;
  final int color;
  final List<String> aliases;

  String get initial => name.substring(0, 1).toUpperCase();
}

/// Lista e inclusă în aplicație: nu se face nicio cerere în rețea.
const knownSites = [
  KnownSite('Google', 'google.com', 0xFF4285F4, ['gmail', 'youtube']),
  KnownSite('Gmail', 'mail.google.com', 0xFFEA4335),
  KnownSite('YouTube', 'youtube.com', 0xFFFF0000),
  KnownSite('Facebook', 'facebook.com', 0xFF1877F2, ['fb']),
  KnownSite('Instagram', 'instagram.com', 0xFFE1306C, ['insta']),
  KnownSite('WhatsApp', 'whatsapp.com', 0xFF25D366),
  KnownSite('Messenger', 'messenger.com', 0xFF0084FF),
  KnownSite('TikTok', 'tiktok.com', 0xFF010101),
  KnownSite('X (Twitter)', 'x.com', 0xFF14171A, ['twitter']),
  KnownSite('LinkedIn', 'linkedin.com', 0xFF0A66C2),
  KnownSite('Apple', 'apple.com', 0xFF555555, ['icloud', 'apple id']),
  KnownSite('iCloud', 'icloud.com', 0xFF3693F3),
  KnownSite('Microsoft', 'microsoft.com', 0xFF00A4EF, ['outlook', 'hotmail']),
  KnownSite('Outlook', 'outlook.com', 0xFF0078D4, ['hotmail', 'live']),
  KnownSite('Yahoo', 'yahoo.com', 0xFF6001D2),
  KnownSite('Amazon', 'amazon.com', 0xFFFF9900),
  KnownSite('Netflix', 'netflix.com', 0xFFE50914),
  KnownSite('Spotify', 'spotify.com', 0xFF1DB954),
  KnownSite('Disney+', 'disneyplus.com', 0xFF113CCF, ['disney']),
  KnownSite('HBO Max', 'max.com', 0xFF002BE7, ['hbo', 'max']),
  KnownSite('SkyShowtime', 'skyshowtime.com', 0xFF1A1446),
  KnownSite('Voyo', 'voyo.ro', 0xFFE4002B),
  KnownSite('PayPal', 'paypal.com', 0xFF003087),
  KnownSite('Revolut', 'revolut.com', 0xFF191C1F),
  KnownSite('eMAG', 'emag.ro', 0xFF005EB8),
  KnownSite('OLX', 'olx.ro', 0xFF002F34),
  KnownSite('Altex', 'altex.ro', 0xFFE30613),
  KnownSite('Flanco', 'flanco.ro', 0xFF0062AF),
  KnownSite('Dedeman', 'dedeman.ro', 0xFFF7A600),
  KnownSite('IKEA', 'ikea.com', 0xFF0058A3),
  KnownSite('Decathlon', 'decathlon.ro', 0xFF0082C3),
  KnownSite('Fashion Days', 'fashiondays.ro', 0xFF000000),
  KnownSite('Elefant', 'elefant.ro', 0xFF8AB81E),
  KnownSite('Carturesti', 'carturesti.ro', 0xFFC8102E, ['cărturești']),
  KnownSite('Glovo', 'glovoapp.com', 0xFFFFC244),
  KnownSite('Tazz', 'tazz.ro', 0xFF5B2D90),
  KnownSite('Bolt', 'bolt.eu', 0xFF34D186),
  KnownSite('Uber', 'uber.com', 0xFF000000),
  KnownSite('Booking', 'booking.com', 0xFF003580),
  KnownSite('Airbnb', 'airbnb.com', 0xFFFF5A5F),
  KnownSite('CFR Călători', 'cfrcalatori.ro', 0xFF003F87, ['cfr']),
  KnownSite('Wizz Air', 'wizzair.com', 0xFFC6007E, ['wizz']),
  KnownSite('Ryanair', 'ryanair.com', 0xFF073590),
  KnownSite('TAROM', 'tarom.ro', 0xFF002D72),
  KnownSite('Banca Transilvania', 'bancatransilvania.ro', 0xFF0055A5, [
    'bt',
    'bt24',
    'neo',
  ]),
  KnownSite('BCR', 'bcr.ro', 0xFF00508F, ['george']),
  KnownSite('BRD', 'brd.ro', 0xFFE2001A, ['mybrd']),
  KnownSite('ING', 'ing.ro', 0xFFFF6200, ['homebank']),
  KnownSite('Raiffeisen', 'raiffeisen.ro', 0xFFFFE600, ['smart mobile']),
  KnownSite('CEC Bank', 'cec.ro', 0xFF005CA9, ['cec']),
  KnownSite('UniCredit', 'unicredit.ro', 0xFFE2001A),
  KnownSite('Garanti BBVA', 'garantibbva.ro', 0xFF004481, ['garanti']),
  KnownSite('ANAF', 'anaf.ro', 0xFF003399, ['spv', 'spatiul privat virtual']),
  KnownSite('Ghișeul.ro', 'ghiseul.ro', 0xFF1E5AA8, ['ghiseul']),
  KnownSite('eSănătateaMea', 'esanatateamea.ro', 0xFF0A7D5A),
  KnownSite('Enel', 'enel.ro', 0xFF0555FA),
  KnownSite('E.ON', 'eon.ro', 0xFFEA1C0A, ['eon']),
  KnownSite('Electrica', 'electricafurnizare.ro', 0xFF00539F),
  KnownSite('Engie', 'engie.ro', 0xFF00AAFF),
  KnownSite('Digi', 'digi.ro', 0xFF0047BB, ['rcs', 'rds', 'digi online']),
  KnownSite('Orange', 'orange.ro', 0xFFFF7900),
  KnownSite('Vodafone', 'vodafone.ro', 0xFFE60000),
  KnownSite('Telekom', 'telekom.ro', 0xFFE20074),
  KnownSite('Dropbox', 'dropbox.com', 0xFF0061FF),
  KnownSite('GitHub', 'github.com', 0xFF24292F),
  KnownSite('Steam', 'steampowered.com', 0xFF171A21),
  KnownSite('PlayStation', 'playstation.com', 0xFF003791, ['psn']),
  KnownSite('Xbox', 'xbox.com', 0xFF107C10),
  KnownSite('Zoom', 'zoom.us', 0xFF2D8CFF),
  KnownSite('Teams', 'teams.microsoft.com', 0xFF6264A7),
  KnownSite('Canva', 'canva.com', 0xFF00C4CC),
  KnownSite('ChatGPT', 'chatgpt.com', 0xFF10A37F, ['openai']),
  KnownSite('Claude', 'claude.ai', 0xFFD97757, ['anthropic']),
  KnownSite('Adobe', 'adobe.com', 0xFFFA0F00),
];

String _norm(String s) {
  final r = s.toLowerCase().trim();
  // fără diacritice (într-o singură trecere)
  if (!_diacritics.hasMatch(r)) return r;
  return r.replaceAllMapped(_diacritics, (m) => _plain[m[0]]!);
}

final _diacritics = RegExp('[ăâîșşțţ]');
const _plain = {
  'ă': 'a',
  'â': 'a',
  'î': 'i',
  'ș': 's',
  'ş': 's',
  'ț': 't',
  'ţ': 't',
};

/// Domeniul dintr-un URL sau text („https://www.emag.ro/x” → „emag.ro”).
String hostOf(String url) {
  var s = url.trim().toLowerCase();
  if (s.isEmpty) return '';
  if (!s.contains('://')) s = 'https://$s';
  final host = Uri.tryParse(s)?.host ?? '';
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// Caută un serviciu după nume, alias sau domeniu.
KnownSite? recognizeSite(String text) {
  final q = _norm(text);
  if (q.length < 2) return null;
  final host = hostOf(q);
  for (final s in knownSites) {
    if (host.isNotEmpty &&
        (host == s.domain || host.endsWith('.${s.domain}'))) {
      return s;
    }
  }
  return _byName[q];
}

/// Numele și aliasurile site-urilor cunoscute, normalizate o singură dată.
final Map<String, KnownSite> _byName = () {
  final m = <String, KnownSite>{};
  for (final s in knownSites) {
    for (final n in [s.name, ...s.aliases]) {
      m.putIfAbsent(_norm(n), () => s);
    }
  }
  return m;
}();

/// Sugestii pentru câmpul „Nume” pe măsură ce scrii (prefix).
List<KnownSite> suggestSites(String text, {int max = 4}) {
  final q = _norm(text);
  if (q.length < 2) return const [];
  return knownSites
      .where(
        (s) =>
            _norm(s.name).startsWith(q) ||
            s.domain.startsWith(q) ||
            s.aliases.any((a) => _norm(a).startsWith(q)),
      )
      .take(max)
      .toList();
}

/// Serviciul unei intrări (după URL, apoi după nume).
KnownSite? siteOf(SecretItem i) =>
    (i.url.isNotEmpty ? recognizeSite(i.url) : null) ?? recognizeSite(i.title);

// ------------------------------------------------- sugestii utilizator

const commonEmailDomains = [
  'gmail.com',
  'yahoo.com',
  'icloud.com',
  'outlook.com',
  'hotmail.com',
  'yahoo.ro',
];

/// Sugestii pentru „Utilizator / email”: cele deja folosite (cele mai
/// frecvente primele), apoi completarea domeniului după „@”.
List<String> usernameSuggestions(
  String typed,
  Iterable<SecretItem> items, {
  int max = 4,
}) {
  final q = typed.trim().toLowerCase();
  final counts = <String, int>{};
  for (final i in items) {
    if (i.type != SecretType.login || i.username.trim().isEmpty) continue;
    final u = i.username.trim();
    counts[u] = (counts[u] ?? 0) + 1;
  }
  final used = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  final out = <String>[
    for (final u in used)
      if (u.toLowerCase().startsWith(q) && u.toLowerCase() != q) u,
  ];
  final at = q.indexOf('@');
  if (at > 0) {
    final local = typed.trim().substring(0, at);
    final dom = q.substring(at + 1);
    for (final d in commonEmailDomains) {
      final s = '$local@$d';
      if (d.startsWith(dom) && d != dom && !out.contains(s)) out.add(s);
    }
  }
  return out.take(max).toList();
}

// ---------------------------------------------------- clipboard inteligent

enum ClipKind { otpauth, iban, card, email, url, password, text }

/// Ce fel de valoare e în clipboard, ca să știm în ce câmp s-o punem.
ClipKind classifyClip(String text) {
  final t = text.trim();
  if (t.toLowerCase().startsWith('otpauth://')) return ClipKind.otpauth;
  if (ibanValid(t)) return ClipKind.iban;
  final digits = t.replaceAll(RegExp(r'[\s-]'), '');
  if (RegExp(r'^\d{13,19}$').hasMatch(digits)) return ClipKind.card;
  if (RegExp(
    r'^[^@\s]+@[^@\s]+\.[a-z]{2,}$',
    caseSensitive: false,
  ).hasMatch(t)) {
    return ClipKind.email;
  }
  if (RegExp(r'^(https?://|www\.)\S+$', caseSensitive: false).hasMatch(t)) {
    return ClipKind.url;
  }
  // Un singur „cuvânt” fără spații, 6–64 caractere: probabil o parolă.
  if (!t.contains(RegExp(r'\s')) && t.length >= 6 && t.length <= 64) {
    return ClipKind.password;
  }
  return ClipKind.text;
}

// --------------------------------------------------------- 2FA din QR

/// Datele dintr-un link `otpauth://totp/Emitent:cont?secret=…&issuer=…`.
({String issuer, String account})? otpauthLabel(String uri) {
  final u = Uri.tryParse(uri.trim());
  if (u == null || u.scheme.toLowerCase() != 'otpauth') return null;
  final label = Uri.decodeComponent(
    u.path.startsWith('/') ? u.path.substring(1) : u.path,
  );
  var issuer = u.queryParameters['issuer'] ?? '';
  var account = label;
  final colon = label.indexOf(':');
  if (colon >= 0) {
    if (issuer.isEmpty) issuer = label.substring(0, colon).trim();
    account = label.substring(colon + 1).trim();
  }
  return (issuer: issuer, account: account);
}

// ------------------------------------------------- categoriile conturilor

/// Site-urile cunoscute (lista de mai sus) → categoria lor.
const _siteCategory = {
  'Google': LoginCategory.email,
  'Gmail': LoginCategory.email,
  'Apple': LoginCategory.email,
  'iCloud': LoginCategory.email,
  'Microsoft': LoginCategory.email,
  'Outlook': LoginCategory.email,
  'Yahoo': LoginCategory.email,
  'Facebook': LoginCategory.social,
  'Instagram': LoginCategory.social,
  'WhatsApp': LoginCategory.social,
  'Messenger': LoginCategory.social,
  'TikTok': LoginCategory.social,
  'X (Twitter)': LoginCategory.social,
  'LinkedIn': LoginCategory.social,
  'PayPal': LoginCategory.bank,
  'Revolut': LoginCategory.bank,
  'Banca Transilvania': LoginCategory.bank,
  'BCR': LoginCategory.bank,
  'BRD': LoginCategory.bank,
  'ING': LoginCategory.bank,
  'Raiffeisen': LoginCategory.bank,
  'CEC Bank': LoginCategory.bank,
  'UniCredit': LoginCategory.bank,
  'Garanti BBVA': LoginCategory.bank,
  'Amazon': LoginCategory.shopping,
  'eMAG': LoginCategory.shopping,
  'OLX': LoginCategory.shopping,
  'Altex': LoginCategory.shopping,
  'Flanco': LoginCategory.shopping,
  'Dedeman': LoginCategory.shopping,
  'IKEA': LoginCategory.shopping,
  'Decathlon': LoginCategory.shopping,
  'Fashion Days': LoginCategory.shopping,
  'Elefant': LoginCategory.shopping,
  'Carturesti': LoginCategory.shopping,
  'Glovo': LoginCategory.shopping,
  'Tazz': LoginCategory.shopping,
  'YouTube': LoginCategory.entertainment,
  'Netflix': LoginCategory.entertainment,
  'Spotify': LoginCategory.entertainment,
  'Disney+': LoginCategory.entertainment,
  'HBO Max': LoginCategory.entertainment,
  'SkyShowtime': LoginCategory.entertainment,
  'Voyo': LoginCategory.entertainment,
  'Steam': LoginCategory.entertainment,
  'PlayStation': LoginCategory.entertainment,
  'Xbox': LoginCategory.entertainment,
  'Bolt': LoginCategory.travel,
  'Uber': LoginCategory.travel,
  'Booking': LoginCategory.travel,
  'Airbnb': LoginCategory.travel,
  'CFR Călători': LoginCategory.travel,
  'Wizz Air': LoginCategory.travel,
  'Ryanair': LoginCategory.travel,
  'TAROM': LoginCategory.travel,
  'Enel': LoginCategory.utilities,
  'E.ON': LoginCategory.utilities,
  'Electrica': LoginCategory.utilities,
  'Engie': LoginCategory.utilities,
  'Digi': LoginCategory.utilities,
  'Orange': LoginCategory.utilities,
  'Vodafone': LoginCategory.utilities,
  'Telekom': LoginCategory.utilities,
  'ANAF': LoginCategory.publicServices,
  'Ghișeul.ro': LoginCategory.publicServices,
  'eSănătateaMea': LoginCategory.publicServices,
  'Dropbox': LoginCategory.tools,
  'GitHub': LoginCategory.tools,
  'Zoom': LoginCategory.tools,
  'Teams': LoginCategory.tools,
  'Canva': LoginCategory.tools,
  'ChatGPT': LoginCategory.tools,
  'Claude': LoginCategory.tools,
  'Adobe': LoginCategory.tools,
};

/// Cuvinte-cheie (fără diacritice, fără spații) căutate în domeniul și în
/// numele contului. Ordinea categoriilor contează: prima potrivire câștigă.
const _categoryKeywords = <LoginCategory, List<String>>{
  LoginCategory.email: [
    'webmail',
    'mail.',
    'email',
    'e-mail',
    'posta',
    'protonmail',
    'proton.me',
    'gmx',
    'zoho',
    'aol.',
    'yandex',
    'tutanota',
    'fastmail',
  ],
  LoginCategory.social: [
    'facebook',
    'instagram',
    'tiktok',
    'twitter',
    'linkedin',
    'snapchat',
    'pinterest',
    'reddit',
    'discord',
    'telegram',
    'signal.org',
    'threads',
    'tumblr',
    'quora',
    'viber',
    'skype',
    'bluesky',
    'mastodon',
    'tinder',
    'bumble',
    'badoo',
    'forum',
  ],
  LoginCategory.bank: [
    'bank',
    'banca',
    'banking',
    'homebank',
    'bt24',
    'george',
    'mybrd',
    'otpbank',
    'librabank',
    'eximbank',
    'patriabank',
    'vistabank',
    'intesasanpaolo',
    'procredit',
    'firstbank',
    'alphabank',
    'saltbank',
    'creditagricole',
    'ideabank',
    'revolut',
    'paypal',
    'wise.com',
    'n26',
    'monzo',
    'paysafe',
    'skrill',
    'binance',
    'coinbase',
    'kraken',
    'crypto.com',
    'tradeville',
    'xtb',
    'etoro',
    'interactivebrokers',
    'tbibank',
    'provident',
    'mokka',
    'leanpay',
    'allianz',
    'groupama',
    'omniasig',
    'asirom',
    'generali',
    'uniqa',
    'signal-iduna',
    'nn.ro',
    'metropolitan',
    'grawe',
    'asigurar',
    'pensii',
    'metropolitanlife',
    'bcrpensii',
  ],
  LoginCategory.shopping: [
    'emag',
    'olx',
    'altex',
    'flanco',
    'dedeman',
    'ikea',
    'decathlon',
    'fashiondays',
    'elefant',
    'carturesti',
    'libris',
    'carrefour',
    'kaufland',
    'lidl',
    'megaimage',
    'auchan',
    'profi.ro',
    'penny',
    'selgros',
    'metro.ro',
    'freshful',
    'bringo',
    'notino',
    'answear',
    'zara',
    'hm.com',
    'aboutyou',
    'temu',
    'shein',
    'aliexpress',
    'ebay',
    'vinted',
    'etsy',
    'cel.ro',
    'pcgarage',
    'evomag',
    'mediagalaxy',
    'vexio',
    'cargus',
    'fancourier',
    'sameday',
    'dpd',
    'mygls',
    'easybox',
    'glovo',
    'tazz',
    'foodpanda',
    'wolt',
    'pizza',
    'leroymerlin',
    'hornbach',
    'brico',
    'jysk',
    'mobexpert',
    'sephora',
    'douglas',
    'drmax',
    'zalando',
    'reserved',
    'bershka',
    'pull&bear',
    'nike',
    'adidas',
    'shop',
    'store',
    'magazin',
    'market',
    'comenzi',
    'livrare',
    'okazii',
    'autovit',
    'imobiliare',
    'storia',
    'publi24',
    'lajumate',
  ],
  LoginCategory.entertainment: [
    'youtube',
    'netflix',
    'spotify',
    'disney',
    'hbo',
    'max.com',
    'skyshowtime',
    'voyo',
    'antenaplay',
    'primevideo',
    'tv.apple',
    'music.apple',
    'deezer',
    'tidal',
    'audible',
    'twitch',
    'steam',
    'epicgames',
    'ea.com',
    'ubisoft',
    'nintendo',
    'playstation',
    'xbox',
    'roblox',
    'minecraft',
    'blizzard',
    'battle.net',
    'riotgames',
    'cinemacity',
    'happycinema',
    'eventim',
    'iabilet',
    'bilete',
    'superbet',
    'betano',
    'casapariurilor',
    'fortuna',
    'unibet',
    'stanleybet',
    'netbet',
    'goldenbet',
    'loto',
    'game',
    'joc',
    'film',
    'muzica',
    'music',
    'stream',
    'podcast',
    'kindle',
    'storytel',
    'wattpad',
  ],
  LoginCategory.travel: [
    'bolt',
    'uber',
    'booking',
    'airbnb',
    'cfr',
    'wizzair',
    'ryanair',
    'tarom',
    'lufthansa',
    'turkishairlines',
    'klm',
    'airfrance',
    'hisky',
    'trivago',
    'esky',
    'vola.ro',
    'kiwi.com',
    'skyscanner',
    'expedia',
    'flixbus',
    'autogari',
    'blablacar',
    'hertz',
    'sixt',
    'europcar',
    'travel',
    'calatori',
    'vacant',
    'hotel',
    'zbor',
    'trenuri',
    'regiotrans',
    'rovinieta',
    'parking',
    'parcare',
    'tpark',
    'stbsa',
    'metrorex',
    'ratb',
    '24pay',
    'mpay',
  ],
  LoginCategory.utilities: [
    'enel.ro',
    'eon.ro',
    'electrica',
    'engie',
    'hidroelectrica',
    'ppcenergy',
    'cez.ro',
    'premierenergy',
    'tinmar',
    'nova-power',
    'apanova',
    'aquatim',
    'compania de apa',
    'apavital',
    'distrigaz',
    'delgaz',
    'digi.ro',
    'digionline',
    'rcs-rds',
    'orange',
    'vodafone',
    'telekom',
    'upc',
    'akta',
    'netflash',
    'internet',
    'telefonie',
    'energie',
    'utilit',
    'salubr',
    'termoficare',
    'administratie bloc',
    'asociatia',
    'e-bloc',
    'ebloc',
    'xbloc',
    'romprest',
    'rosal',
  ],
  LoginCategory.publicServices: [
    '.gov.ro',
    'gov.ro',
    'anaf',
    'spv',
    'ghiseul',
    'esanatatea',
    'cnas',
    'cnpp',
    'pensii publice',
    'drpciv',
    'hub.mai',
    'mai.gov',
    'politia',
    'e-guvernare',
    'roeid',
    'onrc',
    'portal.just',
    'anofm',
    'anpc',
    'primari',
    'prefectura',
    'consulat',
    'pasapoarte',
    'evidenta',
    'dgaspc',
    'edu.ro',
    'siiir',
    'bacalaureat',
    'admitere',
    'taxe',
    'impozit',
    'amenzi',
  ],
  LoginCategory.health: [
    'reginamaria',
    'medlife',
    'sanador',
    'synevo',
    'bioclinica',
    'affidea',
    'medicover',
    'polisano',
    'monza',
    'hiperdia',
    'catena',
    'drmax',
    'helpnet',
    'sensiblu',
    'farmaciatei',
    'belladonna',
    'farmacia',
    'doctolib',
    'clinic',
    'spital',
    'medic',
    'sanatate',
    'health',
    'dental',
    'stomatolog',
    'optica',
    'lensa',
    'worldclass',
    '7card',
    'gym',
    'fitness',
    'strava',
    'garmin',
    'fitbit',
    'myfitnesspal',
    'calorii',
  ],
  LoginCategory.tools: [
    'dropbox',
    'drive.google',
    'onedrive',
    'github',
    'gitlab',
    'bitbucket',
    'zoom',
    'teams',
    'slack',
    'notion',
    'trello',
    'asana',
    'jira',
    'atlassian',
    'canva',
    'figma',
    'chatgpt',
    'openai',
    'claude',
    'anthropic',
    'gemini',
    'perplexity',
    'adobe',
    'wetransfer',
    'mega.nz',
    'mega.io',
    'evernote',
    'lastpass',
    'bitwarden',
    '1password',
    'firebase',
    'aws.amazon',
    'azure',
    'cloudflare',
    'hostinger',
    'godaddy',
    'rotld',
    'namecheap',
    'romarg',
    'vercel',
    'netlify',
    'heroku',
    'digitalocean',
    'wordpress',
    'wix',
    'squarespace',
    'office',
    'docusign',
    'smartbill',
    'facturis',
    'oblio',
    'efactura',
    'duolingo',
    'coursera',
    'udemy',
    'khan',
    'scribd',
    'grammarly',
    'deepl',
    'remotedesktop',
    'teamviewer',
    'anydesk',
    'nordvpn',
    'expressvpn',
    'proton',
    'vpn',
    'router',
    '192.168.',
    '127.0.0.1',
    'localhost',
    'synology',
  ],
};

/// Cuvinte comune (nu nume de firme): se verifică abia la urmă.
const _genericKeywords = {
  'webmail',
  'email',
  'e-mail',
  'posta',
  'forum',
  'bank',
  'banca',
  'banking',
  'asigurar',
  'pensii',
  'shop',
  'store',
  'magazin',
  'market',
  'comenzi',
  'livrare',
  'pizza',
  'game',
  'joc',
  'film',
  'muzica',
  'music',
  'stream',
  'podcast',
  'bilete',
  'loto',
  'travel',
  'calatori',
  'vacant',
  'hotel',
  'zbor',
  'trenuri',
  'parking',
  'parcare',
  'internet',
  'telefonie',
  'energie',
  'utilit',
  'salubr',
  'termoficare',
  'asociatia',
  'taxe',
  'impozit',
  'amenzi',
  'primari',
  'evidenta',
  'admitere',
  'farmacia',
  'clinic',
  'spital',
  'medic',
  'sanatate',
  'health',
  'dental',
  'stomatolog',
  'optica',
  'gym',
  'fitness',
  'calorii',
  'office',
  'vpn',
  'router',
};

final _spaces = RegExp(r'\s+');
String _squash(String s) => _norm(s).replaceAll(_spaces, '');

/// Categoria automată a unui cont, după site / nume.
LoginCategory autoLoginCategory(SecretItem i) {
  final site =
      recognizeSite(i.url.isNotEmpty ? i.url : i.title) ??
      (i.url.isNotEmpty ? recognizeSite(i.title) : null);
  final known = site == null ? null : _siteCategory[site.name];
  if (known != null) return known;
  // domeniul complet (cu subdomeniu și cale) + numele, fără spații
  final host = hostOf(i.url);
  final title = _squash(i.title);
  final hay = '$host ${_norm(i.url)} $title ${_norm(i.title)}';
  // întâi numele de firme / site-uri, apoi cuvintele generice
  // (ex. „store.epicgames.com” e joc, nu magazin); o singură căutare pe
  // categorie (expresii pregătite o dată), în ordinea categoriilor.
  for (final pass in [_specificPatterns, _genericPatterns]) {
    for (final (category, pattern) in pass) {
      if (pattern.hasMatch(hay)) return category;
    }
  }
  return LoginCategory.other;
}

List<(LoginCategory, RegExp)> _patterns({required bool generic}) => [
  for (final e in _categoryKeywords.entries)
    if (e.value.where((k) => _genericKeywords.contains(k) == generic).toList()
        case final words when words.isNotEmpty)
      (e.key, RegExp(words.map(RegExp.escape).join('|'))),
];

final _specificPatterns = _patterns(generic: false);
final _genericPatterns = _patterns(generic: true);

/// Categoria contului: cea aleasă de user, altfel cea automată.
LoginCategory loginCategory(SecretItem i) =>
    LoginCategory.parse(i.category) ?? autoLoginCategory(i);
