import 'dart:math';

import 'package:flutter/material.dart';

/// Paints a static field of subtle low-opacity noise dots. Used to break up
/// gradient banding on large, low-contrast color transitions (dark skies,
/// flat backgrounds, etc). Cheap, self-contained — no external asset needed.
class _NoisePainter extends CustomPainter {
  _NoisePainter({required this.opacity, required this.density, this.seed = 7});

  final double opacity;
  final double density; // dots per 1000 px^2, roughly
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(seed);
    final area = size.width * size.height;
    final dotCount = (area / 1000 * density).clamp(200, 40000).toInt();

    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < dotCount; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = random.nextDouble() * size.height;
      // Randomize per-dot alpha and brightness so it reads as grain,
      // not a uniform dot pattern.
      final isLight = random.nextBool();
      final a = (random.nextDouble() * opacity * 255).clamp(0, 255).toInt();
      paint.color = (isLight ? Colors.white : Colors.black).withAlpha(a);
      canvas.drawCircle(Offset(dx, dy), 0.6, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NoisePainter oldDelegate) {
    return oldDelegate.opacity != opacity ||
        oldDelegate.density != density ||
        oldDelegate.seed != seed;
  }
}

/// Overlay widget that paints subtle noise across its bounds to prevent
/// visible gradient banding. Wrap this around (or stack on top of) any
/// large, low-contrast gradient area.
///
/// Wrap in a [RepaintBoundary] when it shares a layer with anything that
/// animates — `shouldRepaint` returns false for identical parameters, but that
/// only avoids re-running the painter, not re-rasterizing the layer.
class NoiseOverlay extends StatelessWidget {
  const NoiseOverlay({
    super.key,
    this.opacity = 0.035,
    this.density = 18,
    this.seed = 7,
  });

  /// How visible each grain speck is. Keep this small (0.02-0.05) —
  /// the goal is invisible dithering, not visible texture.
  final double opacity;

  /// Roughly how many grains per 1000px^2. Higher = finer grain.
  final double density;

  /// Fixed seed so the noise pattern doesn't change every rebuild/frame.
  final int seed;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _NoisePainter(opacity: opacity, density: density, seed: seed),
        size: Size.infinite,
      ),
    );
  }
}
