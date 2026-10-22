import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../data/notes_store.dart';
import '../models/attachment.dart';
import '../widgets/signature_pad.dart';

/// Rezoluția paginilor în PDF-ul semnat.
const _dpi = 200.0;

/// O semnătură plasată pe o pagină, în coordonate relative (0…1).
class _Placed {
  _Placed(this.page, this.png, this.aspect);
  final int page;
  final Uint8List png;

  /// lățime / înălțime ale imaginii semnăturii
  final double aspect;
  double x = 0.55, y = 0.78, w = 0.32;
}

/// Semnarea unui PDF atașat: semnătură desenată cu degetul, plasată pe
/// pagini, salvată ca PDF nou („… - semnat.pdf”) atașat la aceeași notiță.
class PdfSignScreen extends StatefulWidget {
  const PdfSignScreen({super.key, required this.attachment});
  final Attachment attachment;

  @override
  State<PdfSignScreen> createState() => _PdfSignScreenState();
}

class _PdfSignScreenState extends State<PdfSignScreen> {
  final _pages = <({Uint8List png, int width, int height})>[];
  final _placed = <_Placed>[];
  final _pageController = PageController();
  int _current = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = context.read<NotesStore>().bytesOf(widget.attachment.id);
      if (bytes == null) throw StateError('Fișierul lipsește');
      await for (final page in Printing.raster(bytes, dpi: _dpi)) {
        _pages.add((
          png: await page.toPng(),
          width: page.width,
          height: page.height,
        ));
        if (mounted) setState(() {});
      }
      if (_pages.isEmpty) throw StateError('PDF-ul nu are pagini');
    } catch (e) {
      _error = 'PDF-ul nu a putut fi deschis: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addSignature() async {
    final store = context.read<NotesStore>();
    final png = await drawSignature(context, saved: store.savedSignature);
    if (png == null || !mounted) return;
    final img = await decodeImageFromList(png.bytes);
    if (png.remember) await store.saveSignature(png.bytes);
    setState(
      () => _placed.add(_Placed(_current, png.bytes, img.width / img.height)),
    );
  }

  Future<void> _save() async {
    if (_placed.isEmpty) return;
    setState(() => _saving = true);
    final store = context.read<NotesStore>();
    try {
      final doc = pw.Document(creator: 'Notițe');
      for (var i = 0; i < _pages.length; i++) {
        final p = _pages[i];
        // dimensiunea paginii în puncte PDF (1/72 inch)
        final format = PdfPageFormat(p.width * 72 / _dpi, p.height * 72 / _dpi);
        final signs = _placed.where((s) => s.page == i);
        doc.addPage(
          pw.Page(
            pageFormat: format,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.Image(pw.MemoryImage(p.png), fit: pw.BoxFit.fill),
                ),
                for (final s in signs)
                  pw.Positioned(
                    left: s.x * format.width,
                    top: s.y * format.height,
                    child: pw.SizedBox(
                      width: s.w * format.width,
                      height: s.w * format.width / s.aspect,
                      child: pw.Image(pw.MemoryImage(s.png)),
                    ),
                  ),
              ],
            ),
          ),
        );
      }
      final out = await doc.save();
      final base = widget.attachment.name.replaceAll(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      await store.addAttachment(
        noteId: widget.attachment.noteId,
        name: '$base - semnat.pdf',
        bytes: out,
        mime: 'application/pdf',
        ocrText: widget.attachment.ocrText,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Salvat: $base - semnat.pdf')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Salvarea a eșuat: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerHigh,
      appBar: AppBar(
        title: Text(
          _pages.isEmpty
              ? 'Semnează PDF'
              : 'Pagina ${_current + 1} din ${_pages.length}',
        ),
        actions: [
          TextButton(
            onPressed: _placed.isEmpty || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Salvează'),
          ),
        ],
      ),
      floatingActionButton: _pages.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _addSignature,
              icon: const Icon(Icons.draw_outlined),
              label: const Text('Semnătură'),
            ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : _pages.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: _pageController,
              itemCount: _pages.length,
              // Paginile se schimbă din butoane: glisarea s-ar confunda
              // cu mutarea semnăturii.
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) => _page(i),
            ),
      bottomNavigationBar: _loading || _pages.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Pagina anterioară',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _current > 0
                          ? () => _goTo(_current - 1)
                          : null,
                    ),
                    Expanded(
                      child: Text(
                        _placed.isEmpty
                            ? 'Apasă „Semnătură”, desenează, apoi trage '
                                  'semnătura unde vrei.'
                            : 'Trage semnătura ca s-o muți; colțul o '
                                  'mărește, × o șterge.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Pagina următoare',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _current < _pages.length - 1
                          ? () => _goTo(_current + 1)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  void _goTo(int page) => _pageController.animateToPage(
    page,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  Widget _page(int i) {
    final p = _pages[i];
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: AspectRatio(
          aspectRatio: p.width / p.height,
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth, h = box.maxHeight;
              return Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(blurRadius: 8, color: Colors.black26),
                        ],
                      ),
                      child: Image.memory(p.png, fit: BoxFit.fill),
                    ),
                  ),
                  for (final s in _placed.where((s) => s.page == i))
                    _signature(s, w, h),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _signature(_Placed s, double pageW, double pageH) {
    final sw = s.w * pageW, sh = sw / s.aspect;
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: s.x * pageW,
      top: s.y * pageH,
      width: sw,
      height: sh,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          s.x = (s.x + d.delta.dx / pageW).clamp(0.0, 1 - s.w);
          s.y = (s.y + d.delta.dy / pageH).clamp(0.0, 1 - sh / pageH);
        }),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.primary, width: 1.2),
                ),
                child: Image.memory(s.png, fit: BoxFit.contain),
              ),
            ),
            // ștergere
            Positioned(
              left: -14,
              top: -14,
              child: _handle(
                Icons.close,
                scheme.error,
                onTap: () => setState(() => _placed.remove(s)),
              ),
            ),
            // redimensionare din colț
            Positioned(
              right: -14,
              bottom: -14,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() {
                  s.w = (s.w + d.delta.dx / pageW).clamp(0.08, 1 - s.x);
                }),
                child: _handle(Icons.open_in_full, scheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _handle(IconData icon, Color color, {VoidCallback? onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      );
}
