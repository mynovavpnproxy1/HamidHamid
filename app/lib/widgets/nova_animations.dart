import 'dart:math' as math;

import 'package:flutter/material.dart';

const _novaColors = <Color>[
  Color(0xFF28D7FF),
  Color(0xFF397BFF),
  Color(0xFF8A5CFF),
  Color(0xFFE04DFF),
  Color(0xFF35F0C5),
  Color(0xFFFF5EB8),
];

/// Thousands of luminous particles converge into the NOVA wordmark.
class NovaParticleLogo extends StatefulWidget {
  const NovaParticleLogo({super.key, this.size = 220});

  final double size;

  @override
  State<NovaParticleLogo> createState() => _NovaParticleLogoState();
}

class _NovaParticleLogoState extends State<NovaParticleLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _NovaParticlesPainter(_controller.value),
        ),
      );
}

class _NovaParticlesPainter extends CustomPainter {
  _NovaParticlesPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final unit = side / 112;
    final random = math.Random(731);
    final points = <Offset>[];

    void line(double x1, double y1, double x2, double y2, int count) {
      for (var i = 0; i < count; i++) {
        final t = random.nextDouble();
        final jitter = (random.nextDouble() - .5) * 1.5;
        points.add(Offset(
          x1 + (x2 - x1) * t + jitter,
          y1 + (y2 - y1) * t + jitter,
        ));
      }
    }

    // N
    line(7, 25, 7, 87, 200);
    line(7, 25, 25, 87, 210);
    line(25, 87, 25, 25, 200);
    // O
    for (var i = 0; i < 460; i++) {
      final a = random.nextDouble() * math.pi * 2;
      points.add(Offset(43 + math.cos(a) * 12, 56 + math.sin(a) * 31));
    }
    // V
    line(61, 25, 75, 87, 220);
    line(75, 87, 89, 25, 220);
    // A
    line(92, 87, 101, 25, 200);
    line(101, 25, 110, 87, 200);
    line(95, 65, 107, 65, 130);

    final glowPaint = Paint()
      ..color = const Color(0xFF398CFF).withValues(alpha: .10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(center, side * .37, glowPaint);

    final phase = Curves.easeInOutCubic.transform(progress);
    for (var i = 0; i < points.length; i++) {
      final target = points[i];
      final angle = (i * 2.399) + progress * math.pi * 2;
      final spread = (1 - phase) * (8 + (i % 17) * .72);
      final wobble = math.sin(progress * math.pi * 2 + i * .13) * .8;
      final p = Offset(
        center.dx + (target.dx - 56) * unit + math.cos(angle) * spread * unit,
        center.dy + (target.dy - 56) * unit + math.sin(angle) * spread * unit,
      );
      final color = _novaColors[i % _novaColors.length];
      final radius = (.65 + (i % 5) * .13 + wobble.abs() * .12) * unit * .48;
      final paint = Paint()
        ..color = color.withValues(alpha: .70 + .30 * phase)
        ..maskFilter = i % 7 == 0
            ? const MaskFilter.blur(BlurStyle.normal, 2.2)
            : null;
      canvas.drawCircle(p, radius, paint);
    }

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF2ACFFF).withValues(alpha: .24);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: side * .92, height: side * .30),
      orbitPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _NovaParticlesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Bright, lightweight orbital animation for the connecting screen.
class NovaOrbitAnimation extends StatefulWidget {
  const NovaOrbitAnimation({super.key, this.size = 250});

  final double size;

  @override
  State<NovaOrbitAnimation> createState() => _NovaOrbitAnimationState();
}

class _NovaOrbitAnimationState extends State<NovaOrbitAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _NovaOrbitPainter(_controller.value),
        ),
      );
}

class _NovaOrbitPainter extends CustomPainter {
  _NovaOrbitPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .31;

    final coreGlow = Paint()
      ..color = const Color(0xFF287BFF).withValues(alpha: .20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
    canvas.drawCircle(center, radius * .92, coreGlow);

    final core = Paint()
      ..shader = const RadialGradient(
        colors: [
          Color(0xFF35F0D0),
          Color(0xFF287BFF),
          Color(0xFF603BDB),
          Color(0xFF111B42),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius * .72, core);

    final text = TextPainter(
      text: const TextSpan(
        text: 'NOVA',
        style: TextStyle(
          color: Color(0xFF42E5FF),
          fontSize: 25,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
          shadows: [
            Shadow(color: Color(0xFF2B8CFF), blurRadius: 16),
            Shadow(color: Color(0xFFB14DFF), blurRadius: 22),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));

    final rings = <({double rx, double ry, double tilt, Color color, double speed})>[
      (rx: 1.48, ry: .48, tilt: -.55, color: const Color(0xFF28D7FF), speed: 1),
      (rx: 1.62, ry: .62, tilt: .48, color: const Color(0xFFB34DFF), speed: -1.25),
      (rx: 1.34, ry: .76, tilt: 1.08, color: const Color(0xFF36F0C5), speed: .78),
    ];

    for (var index = 0; index < rings.length; index++) {
      final ring = rings[index];
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(ring.tilt);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: radius * ring.rx * 2,
        height: radius * ring.ry * 2,
      );
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..color = ring.color.withValues(alpha: .72);
      canvas.drawOval(rect, ringPaint);

      final angle = progress * math.pi * 2 * ring.speed + index * 1.9;
      final dot = Offset(
        math.cos(angle) * rect.width / 2,
        math.sin(angle) * rect.height / 2,
      );
      final dotGlow = Paint()
        ..color = ring.color.withValues(alpha: .55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
      canvas.drawCircle(dot, 8, dotGlow);
      canvas.drawCircle(dot, 3.3, Paint()..color = ring.color);
      canvas.restore();
    }

    final sparkle = Paint()..color = const Color(0xFF35DFFF).withValues(alpha: .8);
    for (var i = 0; i < 18; i++) {
      final angle = i * math.pi * 2 / 18 + progress * math.pi * 2;
      final distance = radius * (1.12 + .12 * math.sin(progress * math.pi * 4 + i));
      canvas.drawCircle(
        center + Offset(math.cos(angle) * distance, math.sin(angle) * distance),
        i.isEven ? 1.8 : 1.1,
        sparkle,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NovaOrbitPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
