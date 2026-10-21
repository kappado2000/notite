import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/notes_store.dart';
import '../models/attachment.dart';
import '../models/note.dart';
import '../services/file_opener.dart';
import '../models/note_template.dart';
import '../services/note_pdf.dart';
import '../services/pdf_builder.dart';
import '../services/scan_enhance.dart';
import '../services/scan_service.dart';
import '../utils/format.dart';
import '../widgets/attachment_image_embed.dart';
import 'qr_scan_screen.dart';
import '../widgets/identity_check.dart';
import '../widgets/note_links.dart';
import '../widgets/pickers.dart';

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    required this.noteId,
    this.startWithChecklist = false,
    this.startWithScan = false,
  });

  final String noteId;

  /// Acțiuni rapide de pe „Acasă”: listă de bifat sau scanare directă.
  final bool startWithChecklist;
  final bool startWithScan;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final NotesStore _store;
  late final Note _note;
  late final QuillController _controller;
  late final TextEditingController _title;
  final _editorFocus = FocusNode();
  final _editorScroll = ScrollController();
  StreamSubscription? _docSub;
  Timer? _debounce;
  bool _dirty = false;
  bool _busy = false;
  bool _editorHadFocus = false;

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _store = context.read<NotesStore>();
    _note = _store.note(widget.noteId)!;
    _title = TextEditingController(text: _note.title);
    _revealed = !_note.locked;
    if (!_revealed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
    Document doc;
    try {
      doc = Document.fromJson(jsonDecode(_note.contentJson) as List);
    } catch (_) {
      doc = Document()..insert(0, _note.plainText);
    }
    _controller = QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: _note.isTrashed,
    );
    _docSub = _controller.document.changes.listen((_) => _changed());
    _title.addListener(() {
      if (_title.text != _note.title) _changed();
    });
    _editorFocus.addListener(_onEditorFocus);
    if (widget.startWithChecklist) {
      _controller.formatSelection(Attribute.unchecked);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _editorFocus.requestFocus(),
      );
    } else if (widget.startWithScan) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    }
  }

  /// Bara de formatare apare doar cât timp scrii în corpul notiței.
  /// Ascunderea e amânată puțin: la apăsarea unui buton din bară focusul
  /// poate dispărea o clipă (pe web), iar bara nu trebuie să clipească.
  bool _toolbarVisible = false;
  Timer? _toolbarTimer;

  void _onEditorFocus() {
    _toolbarTimer?.cancel();
    if (_editorFocus.hasFocus) {
      if (!_toolbarVisible) setState(() => _toolbarVisible = true);
    } else {
      _toolbarTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted && !_editorFocus.hasFocus && _toolbarVisible) {
          setState(() => _toolbarVisible = false);
        }
      });
    }
  }

  /// Notița blocată se arată abia după Face ID / amprentă sau parolă.
  late bool _revealed;

  Future<void> _unlock() async {
    final ok = await confirmIdentity(context, reason: 'Deblochează notița');
    if (ok && mounted) setState(() => _revealed = true);
  }

  /// Notiță nouă și goală → arătăm rândul de șabloane.
  bool get _isBlank =>
      _title.text.trim().isEmpty &&
      _controller.document.toPlainText().trim().isEmpty &&
      _store.attachmentsOf(_note.id).isEmpty;
  late bool _blank = _isBlank;

  void _changed() {
    if (_isBlank != _blank) setState(() => _blank = _isBlank);
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _save);
  }

  Future<void> _save() async {
    _debounce?.cancel();
    if (!_dirty) return;
    _dirty = false;
    _note
      ..title = _title.text
      ..contentJson = jsonEncode(_controller.document.toDelta().toJson())
      ..plainText = _controller.document.toPlainText(const [
        AttachmentImageEmbedBuilder(),
      ]);
    await _store.saveNote(_note);
  }

  /// La ieșire: salvează, șterge imaginile scoase din text și
  /// renunță la notițele complet goale (ca Evernote).
  Future<void> _finalize() async {
    // Citim documentul sincron, înainte ca controller-ul să fie eliberat.
    final embedded = _embeddedImageIds();
    await _save();
    if (_store.note(_note.id) == null) return;
    for (final a in _store.attachmentsOf(_note.id)) {
      if (a.isImage && !embedded.contains(a.id)) {
        await _store.removeAttachment(a);
      }
    }
    final empty =
        _note.title.trim().isEmpty &&
        _note.plainText.replaceAll('￼', '').trim().isEmpty &&
        _store.attachmentsOf(_note.id).isEmpty &&
        !_note.hasReminder;
    if (empty && !_note.isTrashed) await _store.deleteForever(_note);
  }

  Set<String> _embeddedImageIds() {
    final ids = <String>{};
    for (final op in _controller.document.toDelta().toList()) {
      final data = op.data;
      if (data is Map && data[kAttachmentImageEmbed] is String) {
        ids.add(data[kAttachmentImageEmbed] as String);
      }
    }
    return ids;
  }

  @override
  void dispose() {
    _finalize();
    _docSub?.cancel();
    _toolbarTimer?.cancel();
    _editorFocus.removeListener(_onEditorFocus);
    _controller.dispose();
    _title.dispose();
    _editorFocus.dispose();
    _editorScroll.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ atașamente

  void _insertImage(String attachmentId) {
    final sel = _controller.selection;
    final len = _controller.document.length;
    final index = sel.isValid ? sel.baseOffset.clamp(0, len - 1) : len - 1;
    final replace = sel.isValid ? sel.extentOffset - sel.baseOffset : 0;
    _controller.replaceText(
      index,
      replace < 0 ? 0 : replace,
      attachmentImageEmbed(attachmentId),
      TextSelection.collapsed(offset: index + 1),
    );
  }

  Future<void> _addImageBytes(
    String name,
    Uint8List bytes, {
    String? ocr,
  }) async {
    final att = await _store.addAttachment(
      noteId: _note.id,
      name: name,
      bytes: bytes,
      ocrText: ocr ?? '',
    );
    _insertImage(att.id);
    // OCR în fundal pentru imaginile fără text deja recunoscut.
    if (ocr == null && ScanService.scanSupported) {
      ScanService.recognize(bytes).then((text) {
        if (text.isNotEmpty) _store.setOcrText(att, text);
      });
    }
  }

  Future<void> _pickImages({bool camera = false}) async {
    try {
      if (_isMobile) {
        final picker = ImagePicker();
        final files = camera
            ? [
                await picker.pickImage(
                  source: ImageSource.camera,
                  imageQuality: 85,
                  maxWidth: 2400,
                ),
              ].whereType<XFile>().toList()
            : await picker.pickMultiImage(imageQuality: 85, maxWidth: 2400);
        for (final f in files) {
          await _addImageBytes(f.name, await f.readAsBytes());
        }
      } else {
        final files = await FilePicker.pickFiles(type: FileType.image);
        for (final f in files) {
          await _addImageBytes(f.name, await f.readAsBytes());
        }
      }
    } catch (e) {
      _toast('Nu am putut adăuga imaginea: $e');
    }
  }

  Future<void> _scan() async {
    setState(() => _busy = true);
    try {
      final pages = await ScanService.scan();
      if (pages.isEmpty || !mounted) return;
      final result = await _askScanOutput(pages);
      if (result == null) return;
      final choice = result.output;
      // Filtrul de scaner (fundal alb, fără umbre) pentru PDF și imagini.
      final processed = choice == _ScanOutput.text
          ? <Uint8List>[]
          : [for (final p in pages) await enhanceScan(p.bytes, result.filter)];
      final text = pages
          .map((p) => p.text.trim())
          .where((t) => t.isNotEmpty)
          .join('\n\n');
      if (_title.text.trim().isEmpty) {
        _title.text = 'Scanare ${formatShortDate(DateTime.now())}';
      }
      if (choice == _ScanOutput.images) {
        for (var i = 0; i < pages.length; i++) {
          final name = pages[i].name.replaceAll(RegExp(r'\.\w+$'), '.jpg');
          await _addImageBytes(name, processed[i], ocr: pages[i].text);
        }
      }
      if (choice == _ScanOutput.pdf || choice == _ScanOutput.pdfAndText) {
        final name = '${_title.text.trim()}.pdf';
        final pdf = await buildPdfFromImages(
          processed,
          title: _title.text.trim(),
        );
        // Textul recunoscut rămâne căutabil și pentru PDF.
        await _store.addAttachment(
          noteId: _note.id,
          name: name,
          bytes: pdf,
          mime: 'application/pdf',
          ocrText: text,
        );
      }
      if (choice == _ScanOutput.text || choice == _ScanOutput.pdfAndText) {
        if (text.isEmpty) {
          _toast('Nu s-a găsit text în scanare');
        } else {
          _insertText('$text\n');
        }
      }
      if (mounted) setState(() {});
      _toast(switch (choice) {
        _ScanOutput.pdf => 'PDF atașat (${pages.length} pagini)',
        _ScanOutput.text => 'Text extras din ${pages.length} pagini',
        _ScanOutput.pdfAndText => 'PDF atașat și text extras',
        _ScanOutput.images => 'Imagini adăugate în notiță',
      });
    } catch (e) {
      _toast('Scanarea a eșuat: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// După scanare: filtrul de scaner și ce se salvează (PDF, text, …).
  Future<({_ScanOutput output, ScanFilter filter})?> _askScanOutput(
    List<ScannedPage> pages,
  ) => showModalBottomSheet<({_ScanOutput output, ScanFilter filter})>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ScanOutputSheet(pages: pages),
  );

  Future<void> _insertScannedCode() async {
    final code = await scanCode(context);
    if (code == null || !mounted) return;
    final sel = _controller.selection;
    final len = _controller.document.length;
    final index = sel.isValid ? sel.baseOffset.clamp(0, len - 1) : len - 1;
    final text = '${code.value}\n';
    _controller.replaceText(
      index,
      0,
      text,
      TextSelection.collapsed(offset: index + text.length),
    );
    final url = code.url;
    if (url != null) {
      _controller.formatText(
        index,
        code.value.length,
        LinkAttribute(url.toString()),
      );
    }
  }

  /// Inserează text la poziția cursorului (sau la final).
  void _insertText(String text) {
    final sel = _controller.selection;
    final len = _controller.document.length;
    final index = sel.isValid ? sel.baseOffset.clamp(0, len - 1) : len - 1;
    _controller.replaceText(
      index,
      0,
      text,
      TextSelection.collapsed(offset: index + text.length),
    );
  }

  Future<void> _pickFiles() async {
    try {
      final files = await FilePicker.pickFiles();
      for (final f in files) {
        final bytes = await f.readAsBytes();
        final mime = Attachment.mimeFromName(f.name);
        if (mime.startsWith('image/')) {
          await _addImageBytes(f.name, bytes);
        } else {
          await _store.addAttachment(
            noteId: _note.id,
            name: f.name,
            bytes: bytes,
            mime: mime,
          );
        }
      }
      setState(() {});
    } catch (e) {
      _toast('Nu am putut atașa fișierul: $e');
    }
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ScanService.scanSupported)
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('Scanează document'),
                subtitle: const Text(
                  'Din cameră sau dintr-o poză → PDF sau text',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _scan();
                },
              ),
            if (_isMobile)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Fotografie'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImages(camera: true);
                },
              ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Imagine din galerie'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Cod QR / de bare'),
              subtitle: const Text('Adaugă conținutul codului în notiță'),
              onTap: () {
                Navigator.pop(ctx);
                _insertScannedCode();
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('Fișier (PDF, document…)'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFiles();
              },
            ),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('Listă de bifat'),
              onTap: () {
                Navigator.pop(ctx);
                _controller.formatSelection(Attribute.unchecked);
                _editorFocus.requestFocus();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------ metadate notiță

  Future<void> _pickNotebook() async {
    final id = await pickNotebook(context, current: _note.notebookId);
    if (id != null && id != _note.notebookId) {
      _note.notebookId = id;
      await _store.saveNote(_note);
      setState(() {});
    }
  }

  Future<void> _editTags() async {
    final tags = await editTags(context, _note.tags);
    if (tags != null) {
      _note.tags = tags;
      await _store.saveNote(_note);
      setState(() {});
    }
  }

  Future<void> _editReminder() async {
    final result = await pickReminder(context, _note);
    if (result == null) return;
    if (result.remove) {
      await _store.setReminder(_note, null);
    } else if (result.toggleDone) {
      await _store.toggleReminderDone(_note);
    } else {
      await _store.setReminder(_note, result.at);
    }
    setState(() {});
  }

  Future<void> _share() async {
    await _save();
    final text = '${_note.displayTitle}\n\n${_note.plainText.trim()}'
        .replaceAll('￼', '');
    await SharePlus.instance.share(
      ShareParams(text: text, subject: _note.displayTitle),
    );
  }

  void _showInfo() {
    final atts = _store.attachmentsOf(_note.id);
    final words = RegExp(r'\S+').allMatches(_note.plainText).length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Informații notiță'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Creată: ${formatDateTime(_note.createdAt)}'),
            Text('Modificată: ${formatDateTime(_note.updatedAt)}'),
            Text('Carnet: ${_store.notebook(_note.notebookId)?.name ?? '-'}'),
            Text('Cuvinte: $words'),
            Text(
              'Atașamente: ${atts.length} '
              '(${formatSize(atts.fold(0, (s, a) => s + a.size))})',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Închide'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------ funcții noi

  /// Înlocuiește conținutul cu un șablon (se poate anula cu ↶).
  void _applyTemplate(NoteTemplate t) {
    final oldLength = _controller.document.length;
    final change = Delta.fromJson(jsonDecode(t.contentJson()) as List)
      ..delete(oldLength);
    _controller.compose(
      change,
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    if (_title.text.trim().isEmpty) _title.text = t.title(DateTime.now());
    _editorFocus.requestFocus();
  }

  /// Cuprinsul: titlurile din notiță; atingerea duce la titlul respectiv.
  void _showToc() {
    final headings = <({String text, int offset, int level})>[];
    for (final node in _controller.document.root.children) {
      final level = node.style.attributes[Attribute.header.key]?.value;
      final text = node.toPlainText().trim();
      if (level is int && text.isNotEmpty) {
        headings.add((text: text, offset: node.documentOffset, level: level));
      }
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: headings.isEmpty
            ? const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Text(
                  'Notița nu are titluri. Folosește stilul „Titlu” din bara '
                  'de formatare (meniul „Normal”) ca să apară în cuprins.',
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(
                    title: Text(
                      'Cuprins',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (final h in headings)
                    ListTile(
                      contentPadding: EdgeInsets.only(
                        left: 16.0 + 16 * (h.level - 1),
                        right: 16,
                      ),
                      title: Text(
                        h.text,
                        style: TextStyle(
                          fontWeight: h.level == 1
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _controller.updateSelection(
                          TextSelection.collapsed(offset: h.offset),
                          ChangeSource.local,
                        );
                        _editorFocus.requestFocus();
                      },
                    ),
                ],
              ),
      ),
    );
  }

  /// Inserează o legătură spre altă notiță, la cursor.
  Future<void> _insertNoteLink() async {
    final target = await pickNoteToLink(context, exceptId: _note.id);
    if (target == null || !mounted) return;
    final label = target.displayTitle;
    final sel = _controller.selection;
    final len = _controller.document.length;
    final index = sel.isValid ? sel.baseOffset.clamp(0, len - 1) : len - 1;
    _controller.replaceText(
      index,
      0,
      label,
      TextSelection.collapsed(offset: index + label.length),
    );
    _controller.formatText(
      index,
      label.length,
      LinkAttribute(noteLink(target.id)),
    );
  }

  /// Linkurile din notiță: cele spre alte notițe se deschid în aplicație,
  /// restul în browser.
  void _openLink(String url) {
    final id = noteIdFromLink(url);
    if (id != null) {
      if (_store.note(id) == null) {
        _toast('Notița legată nu mai există');
        return;
      }
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: id)));
      return;
    }
    final uri = Uri.tryParse(url.contains('://') ? url : 'https://$url');
    if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _toggleLock() async {
    final lock = !_note.locked;
    await _store.setLocked(_note, lock);
    if (!mounted) return;
    setState(() {});
    _toast(
      lock
          ? 'Notița e blocată: se deschide doar cu Face ID / amprentă sau parolă'
          : 'Notița nu mai e blocată',
    );
  }

  Future<void> _exportPdf() async {
    await _save();
    try {
      final bytes = await notesToPdf(
        [_note],
        _store,
        title: _note.displayTitle,
      );
      await FileOpener.share(
        '${_note.displayTitle}.pdf',
        'application/pdf',
        bytes,
      );
    } catch (e) {
      _toast('Exportul a eșuat: $e');
    }
  }

  Future<void> _moveToTrash() async {
    await _save();
    await _store.trash(_note);
    if (mounted) Navigator.pop(context);
  }

  /// Pe web, formatarea unui rând gol (listă, bifat) rupe legătura dintre
  /// editor și câmpul de text al browserului, iar tastele nu mai ajung.
  /// Refacem legătura după fiecare apăsare în bara de formatare.
  void _reconnectEditorOnWeb() {
    if (!kIsWeb || !_editorHadFocus) return;
    Future.delayed(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      final sel = _controller.selection;
      // Stilul pregătit (ex. bold pe un rând gol) se pierde la o schimbare
      // de selecție, așa că îl păstrăm și îl reaplicăm.
      final toggled = _controller.toggledStyle;
      _editorFocus.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _editorFocus.requestFocus();
        if (_controller.selection != sel) {
          _controller.updateSelection(sel, ChangeSource.local);
        }
        _controller.toggledStyle = toggled;
      });
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // -------------------------------------------------------------- interfață

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final scheme = Theme.of(context).colorScheme;
    final trashed = _note.isTrashed;
    final files = store
        .attachmentsOf(_note.id)
        .where((a) => !a.isImage)
        .toList();

    if (!_revealed) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 56, color: scheme.primary),
                const SizedBox(height: 12),
                Text(
                  _note.displayTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text('Notiță blocată', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _unlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Deblochează'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) => _save(),
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: ActionChip(
            avatar: const Icon(Icons.book_outlined, size: 18),
            label: Text(
              store.notebook(_note.notebookId)?.name ?? 'Carnet',
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: trashed ? null : _pickNotebook,
          ),
          actions: trashed
              ? null
              : [
                  IconButton(
                    tooltip: _note.pinned ? 'Anulează fixarea' : 'Fixează sus',
                    icon: Icon(
                      _note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    ),
                    onPressed: () async {
                      await store.togglePin(_note);
                      setState(() {});
                    },
                  ),
                  IconButton(
                    tooltip: 'Memento',
                    icon: Icon(
                      _note.hasReminder
                          ? Icons.alarm_on
                          : Icons.alarm_add_outlined,
                    ),
                    onPressed: _editReminder,
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'tags':
                          _editTags();
                        case 'share':
                          _share();
                        case 'info':
                          _showInfo();
                        case 'trash':
                          _moveToTrash();
                        case 'toc':
                          _showToc();
                        case 'link':
                          _insertNoteLink();
                        case 'lock':
                          _toggleLock();
                        case 'pdf':
                          _exportPdf();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'toc',
                        child: ListTile(
                          leading: Icon(Icons.toc),
                          title: Text('Cuprins'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'link',
                        child: ListTile(
                          leading: Icon(Icons.link),
                          title: Text('Legătură spre altă notiță'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'lock',
                        child: ListTile(
                          leading: Icon(
                            _note.locked
                                ? Icons.lock_open_outlined
                                : Icons.lock_outline,
                          ),
                          title: Text(
                            _note.locked
                                ? 'Deblochează notița'
                                : 'Blochează notița',
                          ),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'pdf',
                        child: ListTile(
                          leading: Icon(Icons.picture_as_pdf_outlined),
                          title: Text('Exportă ca PDF'),
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'tags',
                        child: ListTile(
                          leading: Icon(Icons.sell_outlined),
                          title: Text('Etichete'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'share',
                        child: ListTile(
                          leading: Icon(Icons.share_outlined),
                          title: Text('Partajează textul'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'info',
                        child: ListTile(
                          leading: Icon(Icons.info_outline),
                          title: Text('Informații'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'trash',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Mută în coș'),
                        ),
                      ),
                    ],
                  ),
                ],
        ),
        // Cât timp scrii, „+” stă în bara de formatare de jos.
        floatingActionButton: trashed || _toolbarVisible
            ? null
            : FloatingActionButton(
                tooltip: 'Adaugă',
                onPressed: _busy ? null : _showAddMenu,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.add),
              ),
        body: SafeArea(
          child: Column(
            children: [
              if (trashed)
                MaterialBanner(
                  content: const Text('Notița este în coș.'),
                  leading: const Icon(Icons.delete_outline),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        await store.restore(_note);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('Restaurează'),
                    ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  readOnly: trashed,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    hintText: 'Titlu',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _editorFocus.requestFocus(),
                ),
              ),
              if (_blank && !trashed)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Center(
                        child: Text(
                          'Șablon:  ',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      for (final t in noteTemplates)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Center(
                            child: ActionChip(
                              avatar: Icon(t.icon, size: 18),
                              label: Text(t.name),
                              onPressed: () => _applyTemplate(t),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              _MetaRow(
                note: _note,
                onTags: trashed ? null : _editTags,
                onReminder: trashed ? null : _editReminder,
              ),
              Expanded(
                child: QuillEditor(
                  controller: _controller,
                  focusNode: _editorFocus,
                  scrollController: _editorScroll,
                  config: QuillEditorConfig(
                    placeholder: 'Începe să scrii…',
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    expands: true,
                    embedBuilders: const [AttachmentImageEmbedBuilder()],
                    customLinkPrefixes: const [kNoteLinkPrefix],
                    // Legăturile spre notițe se deschid direct, fără meniu.
                    linkActionPickerDelegate: (ctx, link, node) =>
                        noteIdFromLink(link) != null
                        ? Future.value(LinkMenuAction.launch)
                        : defaultLinkActionPickerDelegate(ctx, link, node),
                    onLaunchUrl: _openLink,
                  ),
                ),
              ),
              if (!trashed && _toolbarVisible)
                Container(
                  decoration: BoxDecoration(
                    border: Border.symmetric(
                      horizontal: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Adaugă imagine, scanare, fișier…',
                        icon: Icon(Icons.add_circle, color: scheme.primary),
                        onPressed: _busy ? null : _showAddMenu,
                      ),
                      Expanded(
                        // Butoanele barei nu iau focusul, ca cursorul să rămână
                        // în editor după aplicarea unei formatări.
                        child: Listener(
                          onPointerDown: (_) =>
                              _editorHadFocus = _editorFocus.hasFocus,
                          onPointerUp: (_) => _reconnectEditorOnWeb(),
                          child: Focus(
                            canRequestFocus: false,
                            descendantsAreFocusable: false,
                            child: QuillSimpleToolbar(
                              controller: _controller,
                              config: const QuillSimpleToolbarConfig(
                                multiRowsDisplay: false,
                                showFontFamily: false,
                                showFontSize: false,
                                showSubscript: false,
                                showSuperscript: false,
                                showSearchButton: false,
                                showInlineCode: false,
                                showCodeBlock: false,
                                showDirection: false,
                                showAlignmentButtons: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (files.isNotEmpty)
                _FilesBar(
                  files: files,
                  onRemove: trashed
                      ? null
                      : (a) async {
                          await store.removeAttachment(a);
                          setState(() {});
                        },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ScanOutput { pdf, text, pdfAndText, images }

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.note, this.onTags, this.onReminder});

  final Note note;
  final VoidCallback? onTags;
  final VoidCallback? onReminder;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (note.hasReminder)
        InputChip(
          avatar: Icon(
            note.reminderDone ? Icons.check_circle : Icons.alarm,
            size: 18,
          ),
          label: Text(
            formatDate(note.reminderAt!),
            style: note.reminderDone
                ? const TextStyle(decoration: TextDecoration.lineThrough)
                : null,
          ),
          onPressed: onReminder,
        ),
      for (final t in note.tags)
        InputChip(
          avatar: const Icon(Icons.sell_outlined, size: 16),
          label: Text(t),
          onPressed: onTags,
        ),
      // Adăugarea de etichete stă în meniul ⋮; aici apare doar lângă
      // etichetele existente, ca ecranul să rămână aerisit.
      if (onTags != null && note.tags.isNotEmpty)
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: const Text('Adaugă'),
          onPressed: onTags,
        ),
    ];
    if (chips.isEmpty) return const SizedBox(height: 4);
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Center(child: chips[i]),
      ),
    );
  }
}

class _FilesBar extends StatelessWidget {
  const _FilesBar({required this.files, this.onRemove});

  final List<Attachment> files;
  final void Function(Attachment)? onRemove;

  IconData _icon(Attachment a) {
    if (a.mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (a.mime.contains('sheet') || a.mime.contains('excel')) {
      return Icons.table_chart_outlined;
    }
    if (a.mime.contains('word') || a.mime.startsWith('text/')) {
      return Icons.description_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<NotesStore>();
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 88, 8),
        itemCount: files.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final a = files[i];
          return InputChip(
            avatar: Icon(_icon(a), size: 20),
            label: Text('${a.name}  ·  ${formatSize(a.size)}'),
            onPressed: () {
              final bytes = store.bytesOf(a.id);
              if (bytes != null) FileOpener.open(a.name, a.mime, bytes);
            },
            onDeleted: onRemove == null
                ? null
                : () async {
                    final ok = await confirm(
                      context,
                      'Ștergi atașamentul „${a.name}”?',
                    );
                    if (ok) onRemove!(a);
                  },
          );
        },
      ),
    );
  }
}

/// Panoul de după scanare: alegerea filtrului (cu previzualizarea primei
/// pagini) și a rezultatului.
class _ScanOutputSheet extends StatefulWidget {
  const _ScanOutputSheet({required this.pages});
  final List<ScannedPage> pages;

  @override
  State<_ScanOutputSheet> createState() => _ScanOutputSheetState();
}

class _ScanOutputSheetState extends State<_ScanOutputSheet> {
  ScanFilter _filter = ScanFilter.document;
  final _previews = <ScanFilter, Uint8List>{};

  @override
  void initState() {
    super.initState();
    _preview(_filter);
  }

  Future<void> _preview(ScanFilter f) async {
    if (_previews.containsKey(f)) return;
    final bytes = await enhanceScan(widget.pages.first.bytes, f, maxSide: 900);
    if (mounted) setState(() => _previews[f] = bytes);
  }

  void _pick(_ScanOutput output) =>
      Navigator.pop(context, (output: output, filter: _filter));

  @override
  Widget build(BuildContext context) {
    final pages = widget.pages;
    final withText = pages.where((p) => p.text.trim().isNotEmpty).length;
    final scheme = Theme.of(context).colorScheme;
    final preview = _previews[_filter];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              pages.length == 1
                  ? 'Pagina scanată'
                  : '${pages.length} pagini scanate',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: preview == null
                  ? const CircularProgressIndicator()
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(preview, fit: BoxFit.contain),
                    ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ScanFilter>(
              showSelectedIcon: false,
              segments: [
                for (final f in ScanFilter.values)
                  ButtonSegment(value: f, label: Text(f.label)),
              ],
              selected: {_filter},
              onSelectionChanged: (s) {
                setState(() => _filter = s.first);
                _preview(s.first);
              },
            ),
            const SizedBox(height: 4),
            Text(
              withText > 0
                  ? 'Text recunoscut în $withText din ${pages.length} pagini'
                  : 'Nu s-a recunoscut text',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Salvează ca PDF'),
              subtitle: const Text('Un fișier cu toate paginile, atașat'),
              onTap: () => _pick(_ScanOutput.pdf),
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: const Text('Extrage doar textul'),
              subtitle: const Text('Textul recunoscut, editabil în notiță'),
              enabled: withText > 0,
              onTap: () => _pick(_ScanOutput.text),
            ),
            ListTile(
              leading: const Icon(Icons.library_add_outlined),
              title: const Text('PDF + text'),
              enabled: withText > 0,
              onTap: () => _pick(_ScanOutput.pdfAndText),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Imagini în notiță'),
              onTap: () => _pick(_ScanOutput.images),
            ),
          ],
        ),
      ),
    );
  }
}
