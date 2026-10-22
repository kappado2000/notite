import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Desenarea semnăturii cu degetul. Întoarce PNG-ul (fundal transparent,
/// decupat la conturul semnăturii) și dacă trebuie ținută minte.
Future<({Uint8List bytes, bool remember})?> drawSignature(
  BuildContext context, {
  Uint8List? saved,
}) => showModalBottomSheet<({Uint8List bytes, bool remember})>(
  context: context,
  isScrollControlled: true,
  enableDrag: false,
  builder: (_) => _SignatureSheet(saved: saved),
);

class _SignatureSheet extends StatefulWidget {
  const _SignatureSheet({this.saved});
  final Uint8List? saved;

  @override
  State<_SignatureSheet> createState() => _SignatureSheetState();
}

class _SignatureSheetState extends State<_SignatureSheet> {
  final _strokes = <List<Offset>>[];
  bool _remember = true;
  Size _size = Size.zero;

  Future<void> _done() async {
    if (_strokes.every((s) => s.isEmpty)) return;
    final png = await signaturePng(_strokes, _size);
    if (mounted) Navigator.pop(context, (bytes: png, remember: _remember));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Semnătura', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (widget.saved != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.history),
                label: const Text('Folosește semnătura salvată'),
                onPressed: () => Navigator.pop(context, (
                  bytes: widget.saved!,
                  remember: true,
                )),
              ),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 2.2,
              child: LayoutBuilder(
                builder: (context, box) {
                  _size = box.biggest;
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: GestureDetector(
                      onPanStart: (d) =>
                          setState(() => _strokes.add([d.localPosition])),
                      onPanUpdate: (d) =>
                          setState(() => _strokes.last.add(d.localPosition)),
                      child: CustomPaint(
                        painter: _SignaturePainter(_strokes),
                        child: Stack(
                          children: [
                            if (_strokes.isEmpty)
                              const Center(
                                child: Text(
                                  'Semnează aici cu degetul',
                                  style: TextStyle(color: Colors.black38),
                                ),
                              ),
                            Positioned(
                              left: 24,
                              right: 24,
                              bottom: 28,
                              child: Container(
                                height: 1,
                                color: Colors.black26,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _remember,
              onChanged: (v) => setState(() => _remember = v ?? true),
              title: const Text('Ține minte semnătura pe acest telefon'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(_strokes.clear),
                    child: const Text('Șterge'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _strokes.isEmpty ? null : _done,
                    child: const Text('Gata'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const _ink = Color(0xFF14247A); // albastru de pix

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) => paintStrokes(canvas, strokes, 2.6);

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}

void paintStrokes(Canvas canvas, List<List<Offset>> strokes, double width) {
  final paint = Paint()
    ..color = _ink
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  for (final s in strokes) {
    if (s.length == 1) {
      canvas.drawCircle(s.first, width / 2, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
      continue;
    }
    // curbă netedă prin mijloacele segmentelor
    final path = Path()..moveTo(s.first.dx, s.first.dy);
    for (var i = 1; i < s.length - 1; i++) {
      final mid = (s[i] + s[i + 1]) / 2;
      path.quadraticBezierTo(s[i].dx, s[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(s.last.dx, s.last.dy);
    canvas.drawPath(path, paint);
  }
}

/// PNG transparent al semnăturii, la rezoluție triplă, decupat la contur.
Future<Uint8List> signaturePng(List<List<Offset>> strokes, Size size) async {
  const scale = 3.0, pad = 8.0, stroke = 2.6;
  final points = strokes.expand((s) => s);
  var left = points.map((p) => p.dx).reduce(math.min) - pad;
  var top = points.map((p) => p.dy).reduce(math.min) - pad;
  var right = points.map((p) => p.dx).reduce(math.max) + pad;
  var bottom = points.map((p) => p.dy).reduce(math.max) + pad;
  left = math.max(0, left);
  top = math.max(0, top);
  right = math.min(size.width, right);
  bottom = math.min(size.height, bottom);
  final w = math.max(1.0, right - left), h = math.max(1.0, bottom - top);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(scale)
    ..translate(-left, -top);
  paintStrokes(canvas, strokes, stroke);
  final image = await recorder.endRecording().toImage(
    (w * scale).ceil(),
    (h * scale).ceil(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
