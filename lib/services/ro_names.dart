/// Corectarea numelor citite greșit de OCR (ex. „KARIA” → „MARIA”,
/// „ADRIAK” → „ADRIAN”): fontul în relief al cardurilor și rândurile cu
/// „<<<” de pe buletin fac ca litere să fie citite ca „K”.
///
/// Un cuvânt e corectat doar dacă NU e un nume cunoscut și există un
/// singur nume cunoscut la o literă distanță. Numele rare, corecte, rămân
/// neatinse dacă nu sunt la o literă de un nume uzual.
String fixNameOcr(String name) {
  if (name.trim().isEmpty) return name;
  // Rândurile MRZ: „<” de umplutură citit ca „K” la final („MARIAKKK”).
  var s = name.trim().replaceAll(RegExp(r'(?<=[A-ZĂÂÎȘŞȚŢ]{3})[K<]{2,}$'), '');
  return s.replaceAllMapped(
    RegExp(r"[A-Za-zĂÂÎȘŞȚŢăâîșşțţ']+"),
    (m) => _fixWord(m[0]!),
  );
}

String _fold(String s) {
  const from = 'ăâîșşțţĂÂÎȘŞȚŢ';
  const to = 'AAISSTTAAISSTT';
  var r = s.toUpperCase();
  for (var i = 0; i < from.length; i++) {
    r = r.replaceAll(from[i], to[i]);
  }
  return r;
}

String _fixWord(String word) {
  final w = _fold(word);
  if (w.length < 3 || _known.contains(w)) return word;
  // Cel mai mic „cost”; la egalitate nu ghicim.
  String? best;
  var bestCost = 99;
  var tie = false;
  for (final n in _known) {
    final c = _editCost(w, n);
    if (c < bestCost) {
      best = n;
      bestCost = c;
      tie = false;
    } else if (c == bestCost) {
      tie = true;
    }
  }
  if (best == null || bestCost > 1 || tie) return word;
  final fixed = best;
  // Păstrăm scrierea: majuscule rămân majuscule, altfel prima literă mare.
  return word == word.toUpperCase()
      ? fixed
      : fixed[0] + fixed.substring(1).toLowerCase();
}

/// Litere pe care OCR-ul le confundă des (citit → real).
const _confusable = {
  'K': 'MNHRX',
  'H': 'NMK',
  'N': 'HMK',
  'M': 'NHK',
  'I': 'LJT1',
  'L': 'IJ',
  'O': 'DQC0',
  'D': 'O',
  'C': 'GO',
  'G': 'C',
  'U': 'VO',
  'V': 'U',
  'E': 'F',
  'F': 'E',
  'B': 'R8',
  'R': 'BK',
};

/// Se corectează doar la cost 1 (confuzie tipică de OCR).
/// Costul unei singure diferențe între ce s-a citit ([a]) și un nume ([b]):
/// 1 = literă confundabilă, 2 = altă literă / literă în plus sau lipsă,
/// 99 = mai mult de o diferență.
int _editCost(String a, String b) {
  if ((a.length - b.length).abs() > 1) return 99;
  if (a.length == b.length) {
    var at = -1;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        if (at >= 0) return 99;
        at = i;
      }
    }
    if (at < 0) return 0;
    return (_confusable[a[at]] ?? '').contains(b[at]) ? 1 : 2;
  }
  final (long, short) = a.length > b.length ? (a, b) : (b, a);
  for (var i = 0; i < long.length; i++) {
    if (long.substring(0, i) + long.substring(i + 1) == short) return 2;
  }
  return 99;
}

/// Prenume și nume de familie românești frecvente (fără diacritice).
const _knownList = [
  // prenume feminine
  'MARIA', 'ELENA', 'IOANA', 'ANA', 'ANDREEA', 'MIHAELA', 'ALEXANDRA',
  'CRISTINA', 'GABRIELA', 'DANIELA', 'ADRIANA', 'RALUCA', 'ALINA',
  'NICOLETA', 'MONICA', 'GEORGIANA', 'DIANA', 'IULIANA', 'ROXANA', 'LAURA',
  'CORINA', 'CARMEN', 'LILIANA', 'MIRELA', 'SIMONA', 'CAMELIA', 'LUMINITA',
  'RODICA', 'GEORGETA', 'VASILICA', 'MARIANA', 'FLORENTINA', 'FLORICA',
  'ANGELA', 'VIORICA', 'VALENTINA', 'DOINA', 'IRINA', 'OANA', 'ANCA',
  'ADINA', 'BIANCA', 'DENISA', 'ALEXIA', 'SOFIA', 'ANTONIA', 'DARIA',
  'IRIS', 'EVA', 'CLARA', 'DELIA', 'EMILIA', 'LARISA', 'TEODORA', 'PATRICIA',
  'ANAMARIA', 'CLAUDIA', 'LOREDANA', 'MADALINA', 'CATALINA', 'ALEXANDRINA',
  'PAULA', 'SILVIA', 'SORINA', 'CRINA', 'CORNELIA', 'MARINELA', 'GINA',
  'LENUTA', 'MARICICA', 'ECATERINA', 'EUGENIA', 'VERONICA', 'VICTORIA',
  'ZOE', 'NATALIA', 'OLGA', 'TATIANA', 'ILEANA', 'AURELIA', 'AURA', 'LIVIA',
  'LUCIA', 'CRISTIANA', 'DORINA', 'STEFANIA', 'SANDA', 'SABINA', 'RAMONA',
  'RUXANDRA', 'MARIUCA', 'ALESIA', 'AMALIA', 'ANDRA', 'BEATRICE', 'CEZARA',
  'CRISTIANA', 'DACIANA', 'DORA', 'ELISA', 'ELIZA', 'EMMA', 'GEANINA',
  'IASMINA', 'ILINCA', 'ISABELA', 'KARINA', 'LAVINIA', 'LIANA', 'MALINA',
  'MARA', 'MELANIA', 'NARCISA', 'NADIA', 'OTILIA', 'PETRONELA', 'ROBERTA',
  'SARA', 'SORANA', 'TEREZA', 'VANESA', 'VIVIANA', 'ZINA', 'MARCELA',
  'NICOLETA', 'VIOLETA', 'VALERIA', 'STELA', 'MARGARETA', 'MAGDALENA',
  // prenume masculine
  'ION', 'IOAN', 'GHEORGHE', 'VASILE', 'CONSTANTIN', 'NICOLAE', 'ALEXANDRU',
  'MIHAI', 'ANDREI', 'STEFAN', 'DUMITRU', 'ADRIAN', 'DANIEL', 'CRISTIAN',
  'GABRIEL', 'MARIUS', 'FLORIN', 'IONUT', 'COSTEL', 'MARIAN', 'PETRU',
  'PETRE', 'GEORGE', 'GEORGIAN', 'DAN', 'DORIN', 'SORIN', 'LUCIAN',
  'CATALIN', 'BOGDAN', 'RAZVAN', 'VLAD', 'RADU', 'TUDOR', 'LUCA', 'DAVID',
  'MATEI', 'ROBERT', 'VALENTIN', 'CIPRIAN', 'CLAUDIU', 'EMIL', 'EUGEN',
  'IULIAN', 'LIVIU', 'OVIDIU', 'SILVIU', 'TRAIAN', 'VIOREL', 'VALERIU',
  'AUREL', 'AURELIAN', 'CORNEL', 'CORNELIU', 'DRAGOS', 'EDUARD', 'FLORIAN',
  'GRIGORE', 'HORIA', 'IACOB', 'ILIE', 'LAURENTIU', 'LIVIU', 'MARCEL',
  'MIRCEA', 'MUGUR', 'NELU', 'OCTAVIAN', 'PAUL', 'PAVEL', 'ROMEO', 'SEBASTIAN',
  'SERGIU', 'SIMION', 'SIMON', 'TEODOR', 'TIBERIU', 'TOMA', 'VICTOR',
  'VIRGIL', 'ALIN', 'ANDY', 'ARMAND', 'BENIAMIN', 'CARLO', 'CEZAR', 'COSMIN',
  'DARIUS', 'DENIS', 'DORU', 'ELIAS', 'ERIC', 'FABIAN', 'FELIX', 'GELU',
  'IONEL', 'IRINEL', 'LAURENTIU', 'LEONARD', 'MANUEL', 'MATEI', 'MIHAITA',
  'NARCIS', 'NICUSOR', 'NICU', 'PETRISOR', 'RARES', 'REMUS', 'RICARDO',
  'SAMUEL', 'SANDU', 'SEVER', 'SILVIU', 'TIMOTEI', 'VASILICA', 'ZAHARIA',
  'AUGUSTIN', 'BOGDAN', 'CALIN', 'CRISTI', 'DECEBAL', 'DIMITRIE', 'EMANUEL',
  'FILIP', 'GAVRIL', 'IOSIF', 'LAURIAN', 'MARIN', 'MATEI', 'NECULAI',
  'NICOLAIE', 'PANTELIMON', 'ROMULUS', 'SORINEL', 'STELIAN', 'TITUS',
  'VALERICA', 'VIRGILIU',
  // nume de familie frecvente
  'POP', 'POPA', 'POPESCU', 'RADU', 'IONESCU', 'DUMITRU', 'STAN', 'STOICA',
  'GHEORGHE', 'MATEI', 'CONSTANTIN', 'RUSU', 'MIHAI', 'SERBAN', 'MARIN',
  'LUCA', 'DINU', 'NISTOR', 'TUDOR', 'DOBRE', 'BARBU', 'NEAGU', 'ENACHE',
  'MOLDOVAN', 'MUNTEANU', 'OPREA', 'VOICU', 'DRAGOMIR', 'CIOBANU', 'ISTRATE',
  'CRISTEA', 'TOMA', 'STANCIU', 'ANDREI', 'MOCANU', 'LUPU', 'ILIE', 'NEACSU',
  'ROTARU', 'NICOLAE', 'COSTEA', 'GAVRILA', 'BALAN', 'CONSTANTINESCU',
  'GEORGESCU', 'STANESCU', 'DUMITRESCU', 'PETRESCU', 'MARINESCU', 'NEGRU',
  'ALBU', 'SANDU', 'APOSTOL', 'ANGHEL', 'BUCUR', 'CRACIUN', 'DIACONU',
  'FLOREA', 'GRIGORE', 'IORDACHE', 'MANEA', 'MIHAILA', 'NEDELCU', 'PAUN',
  'PREDA', 'SIMION', 'SURDU', 'TANASE', 'URSU', 'VASILE', 'ZAHARIA', 'BOGDAN',
  'COJOCARU', 'DAVID', 'DRAGAN', 'FILIP', 'GHITA', 'IONITA', 'LAZAR',
  'MANOLE', 'NITU', 'OLARU', 'PETRE', 'SAVA', 'SUCIU', 'TOADER', 'VLAD',
  'ZAMFIR', 'BURLACU', 'CHIRILA', 'CIOCAN', 'CRISTESCU', 'DOBRESCU',
  'DUMITRASCU', 'HOLBAN', 'IONESCU', 'MIRON', 'MORARU', 'OANCEA', 'PAVEL',
  'POPOVICI', 'RADULESCU', 'SAVU', 'STOIAN', 'TATARU', 'TIMOFTE', 'UNGUREANU',
];

final Set<String> _known = {..._knownList};
