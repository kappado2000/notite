import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/notes_store.dart';
import '../services/receipt.dart';
import '../services/receipt_totals.dart';
import '../widgets/note_actions.dart';

/// Perioada aleasă pentru totaluri.
enum _Period {
  thisMonth('Luna aceasta'),
  lastMonth('Luna trecută'),
  thisYear('Anul acesta'),
  all('Tot'),
  custom('Interval…');

  const _Period(this.label);
  final String label;
}

/// „Totaluri bonuri”: cât a consumat fiecare participant și totalul
/// bonurilor salvate, pe perioada aleasă.
class ReceiptTotalsScreen extends StatefulWidget {
  const ReceiptTotalsScreen({super.key});

  @override
  State<ReceiptTotalsScreen> createState() => _ReceiptTotalsScreenState();
}

class _ReceiptTotalsScreenState extends State<ReceiptTotalsScreen> {
  _Period _period = _Period.thisMonth;
  DateTimeRange? _custom;

  /// Bonurile debifate (nu intră în totaluri).
  final Set<String> _excluded = {};

  (DateTime?, DateTime?) get _range {
    final now = DateTime.now();
    return switch (_period) {
      _Period.thisMonth => (
        DateTime(now.year, now.month),
        DateTime(now.year, now.month + 1, 0),
      ),
      _Period.lastMonth => (
        DateTime(now.year, now.month - 1),
        DateTime(now.year, now.month, 0),
      ),
      _Period.thisYear => (DateTime(now.year), DateTime(now.year, 12, 31)),
      _Period.all => (null, null),
      _Period.custom => (_custom?.start, _custom?.end),
    };
  }

  String get _periodText {
    final (from, to) = _range;
    final f = DateFormat('d MMM y', 'ro');
    return switch (_period) {
      _Period.thisMonth ||
      _Period.lastMonth => DateFormat('MMMM y', 'ro').format(from!),
      _Period.thisYear => '${from!.year}',
      _Period.all => 'toate bonurile',
      _Period.custom =>
        from == null
            ? 'alege intervalul'
            : '${f.format(from)} – ${f.format(to!)}',
    };
  }

  Future<void> _pick(_Period p) async {
    if (p == _Period.custom) {
      final now = DateTime.now();
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 1),
        initialDateRange:
            _custom ??
            DateTimeRange(start: DateTime(now.year, now.month), end: now),
        helpText: 'Alege intervalul',
      );
      if (r == null) return;
      setState(() {
        _custom = r;
        _period = p;
      });
      return;
    }
    setState(() => _period = p);
  }

  String _summary(ReceiptTotals t) {
    final b = StringBuffer()
      ..writeln('Bonuri – $_periodText')
      ..writeln(
        'Total: ${formatLei(t.total)} lei din ${t.entries.length} '
        '${t.entries.length == 1 ? 'bon' : 'bonuri'}',
      );
    for (final p in t.ranked) {
      b.writeln(
        '${p.name}: ${formatLei(p.sum)} lei '
        '(${p.entries.length} ${p.entries.length == 1 ? 'bon' : 'bonuri'})',
      );
    }
    if (t.unassigned.abs() >= 0.01) {
      b.writeln('Nealocat: ${formatLei(t.unassigned)} lei');
    }
    return b.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final scheme = Theme.of(context).colorScheme;
    final (from, to) = _range;
    final inPeriod = receiptsIn(store.activeNotes, from: from, to: to);
    // doar bonurile bifate intră în totaluri
    final t = ReceiptTotals([
      for (final e in inPeriod)
        if (!_excluded.contains(e.note.id)) e,
    ]);
    final checked = t.entries.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Totaluri bonuri'),
        actions: [
          IconButton(
            tooltip: 'Copiază rezumatul',
            icon: const Icon(Icons.copy),
            onPressed: t.entries.isEmpty
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: _summary(t)));
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Rezumatul a fost copiat')),
                    );
                  },
          ),
          IconButton(
            tooltip: 'Trimite (WhatsApp, email…)',
            icon: const Icon(Icons.ios_share),
            onPressed: t.entries.isEmpty
                ? null
                : () =>
                      SharePlus.instance.share(ShareParams(text: _summary(t))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                for (final p in _Period.values) ...[
                  ChoiceChip(
                    label: Text(p.label),
                    selected: _period == p,
                    onSelected: (_) => _pick(p),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _periodText,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatLei(t.total)} lei',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    t.entries.isEmpty
                        ? 'Niciun bon în această perioadă'
                        : 'din ${t.entries.length} '
                              '${t.entries.length == 1 ? 'bon' : 'bonuri'}'
                              '${t.unassigned.abs() >= 0.01 ? ' · nealocat ${formatLei(t.unassigned)} lei' : ''}',
                  ),
                ],
              ),
            ),
          ),
          if (t.persons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                'Pe participanți',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          for (final p in t.ranked)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase()),
              ),
              title: Text(p.name),
              subtitle: Text(
                '${p.entries.length} ${p.entries.length == 1 ? 'bon' : 'bonuri'}',
              ),
              trailing: Text(
                '${formatLei(p.sum)} lei',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => _personSheet(p),
            ),
          if (inPeriod.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Bonurile ($checked din ${inPeriod.length} bifate)',
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: checked == inPeriod.length
                        ? null
                        : () => setState(
                            () => _excluded.removeAll(
                              inPeriod.map((e) => e.note.id),
                            ),
                          ),
                    child: const Text('Toate'),
                  ),
                  TextButton(
                    onPressed: checked == 0
                        ? null
                        : () => setState(
                            () => _excluded.addAll(
                              inPeriod.map((e) => e.note.id),
                            ),
                          ),
                    child: const Text('Niciunul'),
                  ),
                ],
              ),
            ),
            for (final e in inPeriod)
              _entryTile(
                e,
                e.total,
                checked: !_excluded.contains(e.note.id),
                onChecked: (v) => setState(
                  () => v
                      ? _excluded.remove(e.note.id)
                      : _excluded.add(e.note.id),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _entryTile(
    ReceiptEntry e,
    double amount, {
    bool? checked,
    ValueChanged<bool>? onChecked,
  }) => ListTile(
    leading: checked == null
        ? const Icon(Icons.receipt_long_outlined)
        : Checkbox(
            value: checked,
            onChanged: (v) => onChecked?.call(v ?? false),
          ),
    title: Text(
      e.merchant.isEmpty ? 'Bon' : e.merchant,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(DateFormat('d MMM y', 'ro').format(e.date)),
    trailing: Text(
      '${formatLei(amount)} lei',
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
    ),
    onTap: () => openNote(context, e.note),
  );

  void _personSheet(PersonTotal p) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, scroll) => ListView(
        controller: scroll,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '${p.name} – ${formatLei(p.sum)} lei · $_periodText',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          for (final (e, v) in p.entries) _entryTile(e, v),
        ],
      ),
    ),
  );
}
