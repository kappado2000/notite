import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/notes_store.dart';
import '../models/attachment.dart';
import '../services/receipt.dart';
import '../services/scan_service.dart';
import '../widgets/pickers.dart';
import 'note_editor_screen.dart';

/// Deschide împărțirea unui bon (restaurant, cumpărături).
Future<void> openReceiptSplit(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ReceiptSplitScreen()));

/// Bonul scanat: produsele cu cantități și prețuri. Fiecare persoană își
/// bifează ce a consumat (ex. 1 bere din 2) și vede cât are de plătit.
class ReceiptSplitScreen extends StatefulWidget {
  const ReceiptSplitScreen({super.key});

  @override
  State<ReceiptSplitScreen> createState() => _ReceiptSplitScreenState();
}

class _ReceiptSplitScreenState extends State<ReceiptSplitScreen> {
  ReceiptSplit? _split;
  String _person = 'Eu';
  bool _reading = false;

  /// Pozele / PDF-ul bonului, atașate la notiță la salvare.
  final _files = <(String, Uint8List, String)>[];

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  // ------------------------------------------------------------ citire

  Future<void> _read(String source) async {
    if (!ScanService.scanSupported) {
      _toast(
        'Citirea bonului din poză merge pe telefon. Aici poți adăuga '
        'produsele manual.',
      );
      return;
    }
    setState(() => _reading = true);
    try {
      final images = <Uint8List>[];
      _files.clear();
      switch (source) {
        case 'scan':
          for (final p in await ScanService.scan()) {
            images.add(p.bytes);
            _files.add(('Bon.jpg', p.bytes, 'image/jpeg'));
          }
        case 'image':
          for (final f in await FilePicker.pickFiles(type: FileType.image)) {
            final b = await f.readAsBytes();
            images.add(b);
            _files.add((f.name, b, Attachment.mimeFromName(f.name)));
          }
        case 'pdf':
          final picked = await FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: const ['pdf'],
          );
          for (final f in picked) {
            final b = await f.readAsBytes();
            _files.add((f.name, b, 'application/pdf'));
            await for (final page in Printing.raster(b, dpi: 250)) {
              images.add(await page.toPng());
            }
          }
      }
      if (images.isEmpty || !mounted) return;
      final rows = <String>[];
      for (final img in images) {
        rows.addAll(await ScanService.recognizeRows(img));
      }
      final receipt = parseReceipt(rows);
      if (!mounted) return;
      setState(() {
        _split = ReceiptSplit(receipt);
        _person = 'Eu';
      });
      if (receipt.items.isEmpty) {
        _toast(
          'Nu am găsit produse pe bon. Fă poza dreaptă, cu tot bonul, sau '
          'adaugă produsele manual.',
        );
      }
    } catch (e) {
      if (mounted) _toast('Nu am putut citi bonul: $e');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _startManual() => setState(() {
    _split = ReceiptSplit(Receipt());
    _person = 'Eu';
  });

  // ---------------------------------------------------------- persoane

  Future<void> _addPerson() async {
    final name = await promptText(
      context,
      title: 'Persoană nouă',
      hint: 'Nume',
      action: 'Adaugă',
    );
    final n = name?.trim() ?? '';
    if (n.isEmpty || !mounted) return;
    setState(() {
      _split!.addPerson(n);
      _person = n;
    });
  }

  Future<void> _personMenu(String p) async {
    if (_split!.persons.length == 1) return;
    if (await confirm(
      context,
      'Scoți pe „$p” din împărțire? Ce a ales devine din nou liber.',
      action: 'Scoate',
    )) {
      setState(() {
        _split!.removePerson(p);
        if (_person == p) _person = _split!.persons.first;
      });
    }
  }

  // ----------------------------------------------------------- produse

  void _tapItem(int i) {
    final s = _split!;
    final mine = s.taken(_person, i);
    final free = s.remaining(i);
    final single = s.receipt.items[i].units == 1;
    // Atingerea doar adaugă (o atingere în plus nu șterge din greșeală);
    // scoaterea se face cu „−”. La produsele de o bucată e o bifă.
    if (free > 0) {
      setState(() => s.set(_person, i, mine + 1));
    } else if (single && mine > 0) {
      setState(() => s.set(_person, i, 0));
    }
  }

  Future<void> _editItem(int? index) async {
    final s = _split!;
    final item = index == null ? null : s.receipt.items[index];
    final result = await showDialog<Object>(
      context: context,
      builder: (_) => _ItemDialog(item: item),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (result == 'delete' && index != null) {
        s.removeItem(index);
      } else if (result is ReceiptItem) {
        if (index == null) {
          s.receipt.items.add(result);
        } else {
          s.receipt.items[index] = result;
          s.clampItem(index);
        }
      }
    });
  }

  // ------------------------------------------------------------ rezultat

  Future<void> _saveNote() async {
    final s = _split!;
    final store = context.read<NotesStore>();
    final note = await store.createNote();
    final d = s.receipt.date ?? DateTime.now();
    final title = [
      'Bon',
      if (s.receipt.merchant.isNotEmpty) s.receipt.merchant,
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}',
    ].join(' · ');
    final text = s.summary();
    note
      ..title = title
      ..contentJson = _deltaFor(text, s.persons)
      ..plainText = text
      ..tags = ['bonuri'];
    await store.saveNote(note);
    for (final (name, bytes, mime) in _files) {
      await store.addAttachment(
        noteId: note.id,
        name: name,
        bytes: bytes,
        mime: mime,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: note.id)),
    );
  }

  /// Rezumatul ca text de notiță; rândurile cu numele persoanelor îngroșate.
  static String _deltaFor(String text, List<String> persons) {
    final ops = <Map<String, dynamic>>[];
    for (final line in text.split('\n')) {
      final bold =
          persons.any((p) => line.startsWith('$p: ')) ||
          line.startsWith('Total bon:');
      ops.add(
        bold
            ? {
                'insert': line,
                'attributes': {'bold': true},
              }
            : {'insert': line},
      );
      ops.add({'insert': '\n'});
    }
    return jsonEncode(ops.where((o) => o['insert'] != '').toList());
  }

  void _share() =>
      SharePlus.instance.share(ShareParams(text: _split!.summary()));

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _split!.summary()));
    _toast('Rezumatul a fost copiat');
  }

  // --------------------------------------------------------------- ecran

  @override
  Widget build(BuildContext context) {
    final s = _split;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Împarte bonul'),
        actions: [
          if (s != null && s.receipt.items.isNotEmpty) ...[
            IconButton(
              tooltip: 'Copiază rezumatul',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: _copy,
            ),
            IconButton(
              tooltip: 'Trimite',
              icon: const Icon(Icons.share_outlined),
              onPressed: _share,
            ),
            TextButton(onPressed: _saveNote, child: const Text('Salvează')),
          ],
        ],
      ),
      body: s == null ? _start() : _body(s),
      bottomNavigationBar: s == null || s.receipt.items.isEmpty
          ? null
          : _totals(s),
    );
  }

  Widget _start() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 56,
                color: scheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Împarte un bon',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Scanează bonul de la restaurant sau de la cumpărături. Fiecare '
                'își alege ce a consumat — de ex. 1 bere din 2 — și vede cât '
                'are de plătit.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              if (_reading)
                const Center(child: CircularProgressIndicator())
              else ...[
                FilledButton.icon(
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Fotografiază bonul'),
                  onPressed: () => _read('scan'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text('Alege o poză'),
                  onPressed: () => _read('image'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Alege un PDF'),
                  onPressed: () => _read('pdf'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _startManual,
                  child: const Text('Introdu produsele manual'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ReceiptSplit s) {
    final scheme = Theme.of(context).colorScheme;
    final r = s.receipt;
    final missing = r.missing;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // Cine alege acum.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Cine alege',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final p in s.persons)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Center(
                    child: GestureDetector(
                      onLongPress: () => _personMenu(p),
                      child: ChoiceChip(
                        label: Text('$p · ${formatLei(s.personTotal(p))}'),
                        selected: _person == p,
                        onSelected: (_) => setState(() => _person = p),
                      ),
                    ),
                  ),
                ),
              Center(
                child: ActionChip(
                  avatar: const Icon(Icons.person_add_alt, size: 18),
                  label: const Text('Persoană'),
                  onPressed: _addPerson,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Atinge un produs ca să-l alegi pentru $_person; la produsele '
            'cu mai multe bucăți, fiecare atingere mai adaugă una, iar „−” '
            'scoate una.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ),
        if (missing != null && missing.abs() >= 0.01)
          Card(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            color: scheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(
                'Produsele găsite fac ${formatLei(r.itemsTotal)} lei, '
                'iar pe bon TOTAL e ${formatLei(r.printedTotal!)} lei.',
              ),
              subtitle: const Text(
                'Verifică produsele sau adaugă ce lipsește.',
              ),
            ),
          ),
        const Divider(height: 1),
        for (var i = 0; i < r.items.length; i++) _itemTile(s, i),
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Adaugă produs'),
            onPressed: () => _editItem(null),
          ),
        ),
      ],
    );
  }

  Widget _itemTile(ReceiptSplit s, int i) {
    final scheme = Theme.of(context).colorScheme;
    final item = s.receipt.items[i];
    final mine = s.taken(_person, i);
    final others = [
      for (final p in s.persons)
        if (p != _person && s.taken(p, i) > 0) '$p ${s.taken(p, i)}',
    ];
    final free = s.remaining(i);
    final qty = item.qty == item.qty.roundToDouble()
        ? item.qty.round().toString()
        : item.qty.toString().replaceAll('.', ',');
    return ListTile(
      onTap: free > 0 || (item.units == 1 && mine > 0)
          ? () => _tapItem(i)
          : null,
      onLongPress: () => _editItem(i),
      leading: item.units == 1
          ? Checkbox(
              value: mine > 0,
              onChanged: free > 0 || mine > 0 ? (_) => _tapItem(i) : null,
            )
          : CircleAvatar(
              radius: 18,
              backgroundColor: mine > 0
                  ? scheme.primary
                  : scheme.surfaceContainerHigh,
              foregroundColor: mine > 0 ? scheme.onPrimary : scheme.onSurface,
              child: Text('$mine'),
            ),
      title: Text(item.name),
      subtitle: Text(
        [
          '$qty × ${formatLei(item.unitPrice)} = ${formatLei(item.total)} lei',
          if (others.isNotEmpty) others.join(', '),
          if (free == 0 && mine == 0) 'ales în întregime',
        ].join('\n'),
      ),
      isThreeLine: others.isNotEmpty || (free == 0 && mine == 0),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.units > 1 && mine > 0)
            IconButton(
              tooltip: 'Una mai puțin',
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => setState(() => s.set(_person, i, mine - 1)),
            ),
          Text(
            mine > 0 ? '${formatLei(round2(mine * item.unitShare))} lei' : '',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          IconButton(
            tooltip: 'Modifică produsul',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _editItem(i),
          ),
        ],
      ),
    );
  }

  Widget _totals(ReceiptSplit s) {
    final scheme = Theme.of(context).colorScheme;
    final rest = s.unassignedTotal;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_person: ${formatLei(s.personTotal(_person))} lei',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      'Total bon ${formatLei(s.receipt.itemsTotal)} lei',
                      if (rest.abs() >= 0.01) 'nealocat ${formatLei(rest)} lei',
                    ].join('  ·  '),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modificare / adăugare produs. Întoarce produsul sau „delete”.
class _ItemDialog extends StatefulWidget {
  const _ItemDialog({this.item});
  final ReceiptItem? item;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _qty = TextEditingController(
    text: widget.item == null ? '1' : _num(widget.item!.qty),
  );
  late final _price = TextEditingController(
    text: widget.item == null ? '' : formatLei(widget.item!.unitPrice),
  );
  String? _error;

  static String _num(double v) => v == v.roundToDouble()
      ? v.round().toString()
      : v.toString().replaceAll('.', ',');

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  void _ok() {
    final qty = double.tryParse(_qty.text.trim().replaceAll(',', '.'));
    final price = parseAmount(_price.text);
    if (_name.text.trim().isEmpty || qty == null || qty <= 0 || price == null) {
      setState(() => _error = 'Completează denumirea, cantitatea și prețul.');
      return;
    }
    Navigator.pop(
      context,
      ReceiptItem(name: _name.text.trim(), qty: qty, unitPrice: price),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Produs nou' : 'Modifică produsul'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.item == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Denumire'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qty,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Cantitate'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Preț / buc.',
                      suffixText: 'lei',
                    ),
                    onSubmitted: (_) => _ok(),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.item != null)
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Șterge'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Anulează'),
        ),
        FilledButton(onPressed: _ok, child: const Text('Gata')),
      ],
    );
  }
}
