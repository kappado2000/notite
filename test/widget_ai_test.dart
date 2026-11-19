import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notite/models/note.dart';
import 'package:notite/services/home_widget_sync.dart';
import 'package:notite/services/on_device_ai.dart';

Note _note(
  String id,
  String title,
  List<Map<String, Object?>> ops, {
  int day = 1,
  bool locked = false,
  String plain = '',
}) => Note(
  id: id,
  notebookId: 'nb',
  title: title,
  contentJson: jsonEncode(ops),
  plainText: plain,
  createdAt: DateTime(2026, 1, day),
  updatedAt: DateTime(2026, 1, day),
  locked: locked,
);

void main() {
  test('rândurile listei de bifat se citesc din Delta', () {
    final n = _note('a', 'Cumpărături', [
      {'insert': 'Titlu de secțiune\n'},
      {'insert': 'Lapte'},
      {
        'insert': '\n',
        'attributes': {'list': 'unchecked'},
      },
      {'insert': 'Pâine'},
      {
        'insert': '\n',
        'attributes': {'list': 'checked'},
      },
      {'insert': 'Ouă'},
      {
        'insert': '\n',
        'attributes': {'list': 'unchecked'},
      },
      {
        'insert': {'attimg': 'x'},
      },
      {'insert': '\n'},
    ]);
    final items = HomeWidgetSync.checklistOf(n);
    expect(items.map((i) => i.text), ['Lapte', 'Pâine', 'Ouă']);
    expect(items.map((i) => i.done), [false, true, false]);
  });

  test('widgetul: lista aleasă, altfel cea mai recentă cu nebifate', () {
    List<Map<String, Object?>> list(List<(String, bool)> rows) => [
      for (final (t, d) in rows) ...[
        {'insert': t},
        {
          'insert': '\n',
          'attributes': {'list': d ? 'checked' : 'unchecked'},
        },
      ],
    ];
    final veche = _note('v', 'Veche', list([('a', false)]), day: 1);
    final noua = _note('n', 'Nouă', list([('x', true), ('y', false)]), day: 5);
    final gata = _note('g', 'Gata', list([('z', true)]), day: 9);
    final blocata = _note(
      'b',
      'Secretă',
      list([('s', false)]),
      day: 10,
      locked: true,
    );
    final notes = [veche, noua, gata, blocata];

    var p = HomeWidgetSync.payloadFor(notes, null)['list'] as Map;
    expect(p['id'], 'n');
    // nebifatele întâi
    expect((p['items'] as List).first, {'t': 'y', 'd': false});
    expect(p['open'], 1);
    expect(p['total'], 2);

    p = HomeWidgetSync.payloadFor(notes, 'v')['list'] as Map;
    expect(p['id'], 'v');
    // o notiță blocată nu ajunge niciodată pe widget
    p = HomeWidgetSync.payloadFor(notes, 'b')['list'] as Map;
    expect(p['id'], 'n');
    expect(HomeWidgetSync.payloadFor([gata], null)['list'], isNull);
  });

  test('AI: lista de sarcini și notițele potrivite pentru întrebare', () {
    expect(
      OnDeviceAI.parseList(
        '- Sună la bancă\n• Plătește RCA\n2. Ia pâine\nNIMIC\n',
      ),
      ['Sună la bancă', 'Plătește RCA', 'Ia pâine'],
    );
    expect(OnDeviceAI.parseList('NIMIC'), isEmpty);

    final rca = _note(
      'r',
      'Asigurare RCA mașină',
      const [],
      plain: 'Polița expiră pe 12.03.2027',
    );
    final reteta = _note('t', 'Rețetă clătite', const [], plain: 'făină, ouă');
    final secret = _note(
      's',
      'RCA secret',
      const [],
      plain: 'RCA',
      locked: true,
    );
    final r = OnDeviceAI.relevantNotes('Când expiră RCA-ul?', [
      reteta,
      rca,
      secret,
    ]);
    expect(r.map((n) => n.id), ['r']);
    expect(OnDeviceAI.relevantNotes('ce?', [rca]), isEmpty);
  });
}
