import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:intl/intl.dart';

/// Un șablon de notiță: structura (titluri, liste, bife) cu texte-exemplu.
/// Textele-exemplu apar gri doar pe rândurile goale și dispar când scrii;
/// nu fac parte din notiță (nu se salvează ca text, nu apar la căutare).
class NoteTemplate {
  const NoteTemplate(this.name, this.icon, this.title, this.build);

  final String name;
  final IconData icon;

  /// Titlul-exemplu (poate conține data curentă); devine titlul notiței
  /// doar dacă rămâne necompletat și notița are conținut.
  final String Function(DateTime now) title;

  /// Rândurile șablonului.
  final List<TemplateLine> Function() build;

  String contentJson() {
    final ops = <Map<String, dynamic>>[];
    for (final l in build()) {
      final attrs = {
        ...l.attributes,
        if (l.hint.isNotEmpty) lineHintKey: l.hint,
      };
      ops.add({'insert': '\n', if (attrs.isNotEmpty) 'attributes': attrs});
    }
    return jsonEncode(ops);
  }
}

/// Un rând gol al șablonului: textul-exemplu + atributele rândului.
class TemplateLine {
  const TemplateLine(this.hint, [this.attributes = const {}]);
  final String hint;
  final Map<String, dynamic> attributes;
}

TemplateLine _h(String t) => TemplateLine(t, {'header': 2});
TemplateLine _p(String t) => TemplateLine(t);
TemplateLine _li(String t) => TemplateLine(t, {'list': 'bullet'});
TemplateLine _num(String t) => TemplateLine(t, {'list': 'ordered'});
TemplateLine _todo(String t) => TemplateLine(t, {'list': 'unchecked'});

String _day(DateTime d) => DateFormat('d MMMM y', 'ro').format(d);

final noteTemplates = <NoteTemplate>[
  NoteTemplate(
    'Cumpărături',
    Icons.shopping_cart_outlined,
    (_) => 'Cumpărături',
    () => [
      _todo('Pâine'),
      _todo('Lapte'),
      _todo('Ouă'),
      _todo('Fructe'),
      _todo('Legume'),
    ],
  ),
  NoteTemplate(
    'Ședință',
    Icons.groups_outlined,
    (now) => 'Ședință — ${_day(now)}',
    () => [
      _p('Participanți'),
      _p('Locul'),
      _h('Agenda'),
      _li('Primul subiect'),
      _h('Discuții'),
      _p('Ce s-a discutat'),
      _h('Decizii'),
      _li('Ce s-a hotărât'),
      _h('De făcut'),
      _todo('Cine ce face'),
    ],
  ),
  NoteTemplate(
    'Jurnal',
    Icons.auto_stories_outlined,
    (now) => 'Jurnal — ${_day(now)}',
    () => [
      _h('Cum a fost ziua'),
      _p('Ce s-a întâmplat azi'),
      _h('Recunoștință'),
      _num('Un lucru bun'),
      _num('Încă unul'),
      _num('Și încă unul'),
      _h('Mâine'),
      _todo('Ce am de făcut'),
    ],
  ),
  NoteTemplate(
    'Rețetă',
    Icons.restaurant_outlined,
    (_) => 'Rețetă',
    () => [
      _p('Porții'),
      _p('Timp de preparare'),
      _h('Ingrediente'),
      _li('Ingredient și cantitate'),
      _h('Preparare'),
      _num('Primul pas'),
    ],
  ),
  NoteTemplate(
    'De făcut',
    Icons.checklist,
    (now) => 'De făcut — ${_day(now)}',
    () => [
      _h('Important'),
      _todo('Sarcină importantă'),
      _h('Când am timp'),
      _todo('Altă sarcină'),
    ],
  ),
  NoteTemplate(
    'Călătorie',
    Icons.luggage_outlined,
    (_) => 'Călătorie',
    () => [
      _p('Destinația'),
      _p('Perioada'),
      _h('Rezervări'),
      _li('Transport'),
      _li('Cazare'),
      _h('Bagaj'),
      _todo('Acte de identitate'),
      _todo('Încărcător telefon'),
      _todo('Medicamente'),
      _h('Itinerariu'),
      _num('Prima zi'),
    ],
  ),
];

/// Scoate textul-exemplu de pe rândurile pe care s-a scris (altfel Enter
/// l-ar copia pe rândul nou, iar golirea rândului l-ar arăta din nou).
void dropFilledHints(Document doc) {
  final change = Delta();
  var last = 0;
  var offset = 0;
  void visit(Iterable<Node> nodes) {
    for (final n in nodes) {
      if (n is Line) {
        final end = offset + n.length - 1;
        if (n.length > 1 && n.style.attributes.containsKey(lineHintKey)) {
          change
            ..retain(end - last)
            ..retain(1, {lineHintKey: null});
          last = end + 1;
        }
        offset += n.length;
      } else if (n is Block) {
        visit(n.children);
      }
    }
  }

  visit(doc.root.children);
  if (change.isEmpty) return;
  try {
    doc.compose(change, ChangeSource.silent);
  } catch (_) {}
}
