import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:froyou/core/theme/theme.dart';

/// A slow wash of colour moving behind everything on Home.
///
/// The screen was a flat fill, which read as *stopped* — most visibly once
/// compose opens and the photo has vacated, leaving a rectangle of one colour.
/// Three soft blobs of the theme's own accent, drifting on long independent
/// paths, give it a pulse without ever becoming something to look at.
///
/// **It is meant to be felt, not seen.** Each blob peaks around a tenth of an
/// alpha over the background and the slowest one takes the better part of a
/// minute to cross, so at any given glance nothing appears to be moving.
///
/// **The motion is compositor-only.** Each blob is painted once behind a
/// `RepaintBoundary` and passed to `AnimatedBuilder` as its `child`, so the
/// per-frame work is a transform matrix on a cached layer rather than three
/// full-screen gradient fills — the same reason the backdrop's Ken Burns drift
/// transforms a boundary instead of re-rasterising its blur.
class LivingBackdrop extends HookWidget {
  const LivingBackdrop({required this.palette, this.animate = true, super.key});

  final AppPalette palette;

  /// Off in tests and anywhere a still frame is wanted. The widget still paints
  /// its blobs; they simply hold position.
  final bool animate;

  /// One full cycle. Every blob's path is an integer multiple of this, so the
  /// loop closes seamlessly and there is no jump at the wrap.
  static const Duration period = Duration(seconds: 48);

  /// The two knobs worth touching: `alpha` for how present the wash is, and
  /// [period] for how fast. Everything else is structural.
  static const List<_Blob> _blobs = [
    // Hue offsets rather than one flat accent: three tints of the same colour
    // read as depth, where three copies of one read as a smudge.
    // _Blob(hueShift: 0, alpha: 0.15, size: 1.15, freqX: 1, freqY: 2, phase: 0),
    // _Blob(hueShift: 38, alpha: 0.12, size: 0.95, freqX: 2, freqY: 3, phase: 0.33),
    // _Blob(hueShift: -32, alpha: 0.10, size: 1.3, freqX: 3, freqY: 1, phase: 0.66),
  ];

  @override
  Widget build(BuildContext context) {
    final drift = useAnimationController(duration: period);

    useEffect(() {
      // Nothing to move is a reason not to run. With the blob list emptied out
      // this would otherwise still schedule a frame every 16ms forever, so
      // switching the wash off would cost exactly as much battery as leaving
      // it on — and Home would never idle for no visible reason.
      if (animate && _blobs.isNotEmpty) {
        drift.repeat();
      } else {
        drift.stop();
      }
      return null;
    }, [animate, drift]);

    final accent = palette.colors.primary;

    return ColoredBox(
      color: palette.colors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final blob in _blobs)
            _DriftingBlob(
              drift: drift,
              blob: blob,
              color: _tint(accent, blob.hueShift, blob.alpha),
            ),
        ],
      ),
    );
  }

  /// Rotates the accent's hue while keeping its saturation and lightness, so
  /// every blob still belongs to the chosen theme.
  static Color _tint(Color accent, double hueShift, double alpha) {
    final hsl = HSLColor.fromColor(accent);
    return hsl
        .withHue((hsl.hue + hueShift) % 360)
        .toColor()
        .withValues(alpha: alpha);
  }
}

@immutable
class _Blob {
  const _Blob({
    required this.hueShift,
    required this.alpha,
    required this.size,
    required this.freqX,
    required this.freqY,
    required this.phase,
  });

  final double hueShift;
  final double alpha;

  /// Diameter as a fraction of the longest side. Deliberately over 1 for some
  /// of them: a blob smaller than the screen has a visible edge.
  final double size;

  /// Whole numbers only — a fractional rate would not return to its start when
  /// the controller wraps, and the seam would show once a minute.
  final int freqX;
  final int freqY;

  final double phase;
}

class _DriftingBlob extends StatelessWidget {
  const _DriftingBlob({
    required this.drift,
    required this.blob,
    required this.color,
  });

  final Animation<double> drift;
  final _Blob blob;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final diameter = constraints.biggest.longestSide * blob.size;
        final travelX = constraints.maxWidth * 0.36;
        final travelY = constraints.maxHeight * 0.3;

        return AnimatedBuilder(
          animation: drift,
          builder: (context, child) {
            final t = drift.value;
            return Transform.translate(
              offset: Offset(
                math.sin(2 * math.pi * (blob.freqX * t + blob.phase)) * travelX,
                math.cos(2 * math.pi * (blob.freqY * t + blob.phase)) * travelY,
              ),
              child: child,
            );
          },
          // Built once and handed through the builder untouched, which is what
          // keeps this off the paint path entirely.
          child: Center(
            child: RepaintBoundary(
              child: SizedBox.square(
                dimension: diameter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [color, color.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
