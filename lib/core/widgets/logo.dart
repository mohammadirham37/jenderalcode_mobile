import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Brand mark: a "JC" monogram (J inside an open C) on graphite with corner
/// ticks. Same artwork as `assets/brand/logo.svg` and the desktop's
/// `Logo.tsx`, cropped to the visible square (viewBox 100 100 824 824).
class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'JenderalCode',
        image: true,
        child: CustomPaint(size: Size.square(size), painter: const LogoPainter()),
      );
}

class LogoPainter extends CustomPainter {
  const LogoPainter();

  static const _bg = Color(0xFF0B0F0E);
  static const _tick = Color(0xFF2FC3A5);
  static const _c = Color(0xFF13A68B);
  static const _j = Color(0xFF7FF0D2);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 824;
    canvas
      ..save()
      ..scale(s)
      ..translate(-100, -100);

    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(100, 100, 824, 824), const Radius.circular(186)),
      Paint()..color = _bg,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(106, 106, 812, 812), const Radius.circular(180)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = _tick.withValues(alpha: 0.28),
    );

    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.square
      ..color = _tick.withValues(alpha: 0.9);
    for (final pts in const [
      [Offset(222, 262), Offset(222, 222), Offset(262, 222)],
      [Offset(762, 222), Offset(802, 222), Offset(802, 262)],
      [Offset(802, 762), Offset(802, 802), Offset(762, 802)],
      [Offset(262, 802), Offset(222, 802), Offset(222, 762)],
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(pts[0].dx, pts[0].dy)
          ..lineTo(pts[1].dx, pts[1].dy)
          ..lineTo(pts[2].dx, pts[2].dy),
        tick,
      );
    }

    canvas.translate(24, 0);
    Paint stroke(Color c, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = c;
    // C: open to the right, flat-cut ends.
    canvas.drawPath(
      Path()
        ..moveTo(682.8, 336.3)
        ..arcToPoint(const Offset(682.8, 687.7),
            radius: const Radius.circular(250), largeArc: true, clockwise: false),
      stroke(_c, 92),
    );
    // J: top bar, stem, hook.
    canvas.drawPath(Path()..moveTo(506, 372)..lineTo(632, 372), stroke(_j, 64));
    canvas.drawPath(
      Path()
        ..moveTo(600, 372)
        ..lineTo(600, 566)
        ..arcToPoint(const Offset(456, 566), radius: const Radius.circular(72), clockwise: true),
      stroke(_j, 64),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoPainter oldDelegate) => false;
}

/// "Jenderal" + mono "/code" in the accent colour, like the desktop's Wordmark.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.fontSize = 18});
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: 'Jenderal',
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
        TextSpan(
          text: '/code',
          style: TextStyle(
            fontFamily: monoFamily,
            fontSize: fontSize * 0.78,
            fontWeight: FontWeight.w500,
            color: cs.primary,
          ),
        ),
      ]),
      semanticsLabel: 'JenderalCode',
    );
  }
}
