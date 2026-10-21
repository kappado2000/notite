import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Un șablon de notiță: titlu + conținut gata structurat (Delta Quill).
class NoteTemplate {
  const NoteTemplate(this.name, this.icon, this.title, this.build);

  final String name;
  final IconData icon;

  /// Titlul propus (poate conține data curentă).
  final String Function(DateTime now) title;

  /// Rândurile șablonului.
  final List<TemplateLine> Function() build;

  String contentJson() {
    final ops = <Map<String, dynamic>>[];
    for (final l in build()) {
      if (l.text.isNotEmpty) ops.add({'insert': l.text});
      ops.add({
        'insert': '\n',
        if (l.attributes.isNotEmpty) 'attributes': l.attributes,
      });
    }
    return jsonEncode(ops);
  }

  String plainText() => build().map((l) => l.text).join('\n');
}

/// Un rând al șablonului: text + atributele rândului (titlu, listă).
class TemplateLine {
  const TemplateLine(this.text, [this.attributes = const {}]);
  final String text;
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
      _todo(''),
    ],
  ),
  NoteTemplate(
    'Ședință',
    Icons.groups_outlined,
    (now) => 'Ședință — ${_day(now)}',
    () => [
      _p('Participanți: '),
      _p('Loc: '),
      _h('Agenda'),
      _li(''),
      _h('Discuții'),
      _p(''),
      _h('Decizii'),
      _li(''),
      _h('De făcut'),
      _todo(''),
    ],
  ),
  NoteTemplate(
    'Jurnal',
    Icons.auto_stories_outlined,
    (now) => 'Jurnal — ${_day(now)}',
    () => [
      _h('Cum a fost ziua'),
      _p(''),
      _h('Recunoștință'),
      _num(''),
      _num(''),
      _num(''),
      _h('Mâine'),
      _todo(''),
    ],
  ),
  NoteTemplate(
    'Rețetă',
    Icons.restaurant_outlined,
    (_) => 'Rețetă',
    () => [
      _p('Porții: '),
      _p('Timp de preparare: '),
      _h('Ingrediente'),
      _li(''),
      _h('Preparare'),
      _num(''),
    ],
  ),
  NoteTemplate(
    'De făcut',
    Icons.checklist,
    (now) => 'De făcut — ${_day(now)}',
    () => [_h('Important'), _todo(''), _h('Când am timp'), _todo('')],
  ),
  NoteTemplate(
    'Călătorie',
    Icons.luggage_outlined,
    (_) => 'Călătorie',
    () => [
      _p('Destinație: '),
      _p('Perioada: '),
      _h('Rezervări'),
      _li('Transport: '),
      _li('Cazare: '),
      _h('Bagaj'),
      _todo('Acte de identitate'),
      _todo('Încărcător telefon'),
      _todo('Medicamente'),
      _todo(''),
      _h('Itinerariu'),
      _num(''),
    ],
  ),
];
