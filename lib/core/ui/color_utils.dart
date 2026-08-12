import 'package:flutter/material.dart';

/// WCAG relative-luminance contrast ratio, from 1.0 (identical) to 21.0.
double contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Returns a monochrome tint *of [background] itself* that reads against it.
///
/// Because the result is derived from the background's own hue, this is the
/// right tool for text sitting directly on an image or on its glow — it stays
/// in the same color family instead of introducing a second one. When you need
/// to make a *specific* color legible, use [contrastify] instead.
Color ensureContrast(Color background, {double targetRatio = 2.5}) {
  final hsl = HSLColor.fromColor(background);
  final bgLuminance = background.computeLuminance();

  // Decide whether to go darker or lighter
  final goDarker = bgLuminance > 0.5;

  HSLColor adjusted = hsl;
  for (
    double l = hsl.lightness;
    goDarker ? l >= 0 : l <= 1;
    l += goDarker ? -0.02 : 0.02
  ) {
    adjusted = hsl.withLightness(l.clamp(0.0, 1.0));
    final ratio = contrastRatio(background, adjusted.toColor());
    if (ratio >= targetRatio) break;
  }

  return adjusted.toColor();
}

/// Walks [foreground]'s HSL lightness — preserving its hue and saturation —
/// until it reaches [targetRatio] against [background].
///
/// Unlike [ensureContrast], this keeps the color you asked for. That matters
/// for the user's chosen accent: a vibrant blue should stay recognizably that
/// blue on a beige background, not collapse into a beige tint.
///
/// Tries the direction away from the background's luminance first, since
/// darkening a color on a light background preserves far more of its character
/// than lightening it does. Falls back to black or white if neither direction
/// can reach the target.
Color contrastify(
  Color foreground,
  Color background, {
  double targetRatio = 4.5,
}) {
  if (contrastRatio(foreground, background) >= targetRatio) return foreground;

  const black = Color(0xFF000000);
  const white = Color(0xFFFFFFFF);

  // Which extreme actually contrasts better, rather than guessing from a
  // luminance threshold. That guess is wrong for mid-tone backgrounds, and it
  // used to make the fallback below return the *worse* of the two — producing
  // white text on a mid-grey surface at a ratio near 3:1.
  final darkerIsBetter =
      contrastRatio(black, background) >= contrastRatio(white, background);

  final hsl = HSLColor.fromColor(foreground);

  // Try the better direction first: it needs less travel, so more of the
  // original hue and saturation survives.
  for (final goDarker
      in darkerIsBetter ? const [true, false] : const [false, true]) {
    for (double step = 0.02; step <= 1.0; step += 0.02) {
      final lightness = goDarker ? hsl.lightness - step : hsl.lightness + step;
      if (lightness < 0.0 || lightness > 1.0) break;
      final candidate = hsl.withLightness(lightness).toColor();
      if (contrastRatio(candidate, background) >= targetRatio) return candidate;
    }
  }

  // Nothing in the hue reached the target — take the best available. For any
  // background at all, one of black or white clears 4.5:1; very high targets
  // (7:1 on a mid-tone surface) are simply unreachable, and this is the
  // closest honest answer.
  return darkerIsBetter ? black : white;
}

/// Shifts [color]'s HSL lightness by [delta] (positive lightens).
///
/// How card, text-box and border surfaces are stepped off the background so
/// they keep a consistent elevation hierarchy under any preset, accent or
/// tint.
Color elevate(Color color, double delta) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
}
