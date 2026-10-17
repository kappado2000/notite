import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/notes_store.dart';
import '../models/attachment.dart';
import '../models/note.dart';
import '../services/file_opener.dart';
import '../services/scan_service.dart';
import '../utils/format.dart';
import '../widgets/attachment_image_embed.dart';
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
    if (widget.startWithChecklist) {
      _controller.formatSelection(Attribute.unchecked);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _editorFocus.requestFocus(),
      );
    } else if (widget.startWithScan) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    }
  }

  void _changed() {
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
      for (final p in pages) {
        await _addImageBytes(p.name, p.bytes, ocr: p.text);
      }
      if (pages.isNotEmpty) {
        final withText = pages.where((p) => p.text.isNotEmpty).length;
        _toast(
          withText > 0
              ? 'Text recunoscut în $withText din ${pages.length} pagini — '
                    'e inclus în căutare'
              : 'Document scanat (nu s-a găsit text)',
        );
      }
    } catch (e) {
      _toast('Scanarea a eșuat: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                subtitle: const Text('Cu recunoaștere text (OCR)'),
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
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'tags',
                        child: ListTile(
                          leading: Icon(Icons.sell_outlined),
                          title: Text('Etichete'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'share',
                        child: ListTile(
                          leading: Icon(Icons.share_outlined),
                          title: Text('Partajează textul'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'info',
                        child: ListTile(
                          leading: Icon(Icons.info_outline),
                          title: Text('Informații'),
                        ),
                      ),
                      PopupMenuItem(
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
        floatingActionButton: trashed
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
              _MetaRow(
                note: _note,
                onTags: trashed ? null : _editTags,
                onReminder: trashed ? null : _editReminder,
              ),
              if (!trashed)
                Container(
                  decoration: BoxDecoration(
                    border: Border.symmetric(
                      horizontal: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
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
              Expanded(
                child: QuillEditor(
                  controller: _controller,
                  focusNode: _editorFocus,
                  scrollController: _editorScroll,
                  config: const QuillEditorConfig(
                    placeholder: 'Începe să scrii…',
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 96),
                    expands: true,
                    embedBuilders: [AttachmentImageEmbedBuilder()],
                  ),
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
      if (onTags != null)
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: Text(note.tags.isEmpty ? 'Etichetă' : 'Adaugă'),
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
