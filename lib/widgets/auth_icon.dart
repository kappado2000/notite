import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Iconița „Auth” (Autentificator): un lacăt în formă de scut, cu un om în
/// interior, în culoarea dată (implicit verdele aplicației).
class AuthIcon extends StatelessWidget {
  const AuthIcon({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _AuthPainter(color ?? Theme.of(context).colorScheme.primary),
    ),
  );
}

class _AuthPainter extends CustomPainter {
  _AuthPainter(this.color);
  final Color color;

  Color _shade(double lightness) {
    final h = HSLColor.fromColor(color);
    return h.withLightness(lightness.clamp(0.0, 1.0)).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final base = HSLColor.fromColor(color).lightness;
    final dark = _shade(base - 0.12);
    final light = _shade(base + 0.18);
    final lighter = _shade(base + 0.32);

    // toarta lacătului
    final shackle = Paint()
      ..color = dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.11
      ..strokeCap = StrokeCap.butt;
    final arc = Rect.fromCenter(
      center: Offset(s * 0.5, s * 0.30),
      width: s * 0.44,
      height: s * 0.40,
    );
    canvas.drawArc(arc, math.pi, math.pi, false, shackle);
    canvas.drawLine(
      Offset(arc.left, arc.center.dy),
      Offset(arc.left, s * 0.42),
      shackle,
    );
    canvas.drawLine(
      Offset(arc.right, arc.center.dy),
      Offset(arc.right, s * 0.42),
      shackle,
    );

    // scutul (corpul lacătului), cu degrade de sus în jos
    final top = s * 0.34;
    final shield = Path()
      ..moveTo(s * 0.5, top)
      ..cubicTo(
        s * 0.70,
        top,
        s * 0.86,
        top + s * 0.02,
        s * 0.88,
        top + s * 0.06,
      )
      ..cubicTo(s * 0.92, s * 0.62, s * 0.80, s * 0.86, s * 0.5, s * 0.98)
      ..cubicTo(
        s * 0.20,
        s * 0.86,
        s * 0.08,
        s * 0.62,
        s * 0.12,
        top + s * 0.06,
      )
      ..cubicTo(s * 0.14, top + s * 0.02, s * 0.30, top, s * 0.5, top)
      ..close();
    canvas.drawPath(
      shield,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [dark, color, light],
        ).createShader(Rect.fromLTWH(0, top, s, s - top)),
    );

    // omul: capul și umerii, decupați în interiorul scutului
    canvas.save();
    canvas.clipPath(shield);
    final person = Paint()..color = lighter;
    canvas.drawCircle(Offset(s * 0.5, s * 0.55), s * 0.11, person);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s * 0.5, s * 0.92),
        width: s * 0.52,
        height: s * 0.38,
      ),
      person,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AuthPainter old) => old.color != color;
}
