import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'theme_settings.dart';
import '../ui/color_utils.dart';

/// The app's resolved colours.
///
/// Built from [ThemeSettings] — a preset, a brightness and a tint — rather than
/// stored. Deriving is cheap enough to do synchronously on the boot path, which
/// is what lets the very first frame be correctly themed with no flash.
///
/// Two seeds are user-controlled; the other eleven colours are derived through
/// [contrastify] and [elevate]. That is deliberate: it means no combination of
/// preset, brightness and tint can produce text that fails contrast, which
/// exposing thirteen colour pickers absolutely would.
@immutable
class AppPalette {
  const AppPalette({
    required this.colors,
    required this.brightness,
    required this.accent,
  });

  final AppColors colors;
  final Brightness brightness;

  /// The preset's accent for this brightness, before contrast correction. Kept
  /// for the settings UI, which should show the swatch as authored rather than
  /// the adjusted one it renders as.
  final Color accent;

  bool get isDark => brightness == Brightness.dark;

  /// The colour the Home backdrop dissolves into, top and bottom.
  ///
  /// Both edges are simply the background: photos no longer drive the theme,
  /// so an image should melt into the surface it sits on rather than drag its
  /// own colours into the page.
  Color get glow => colors.background;

  static const AppPalette fallbackLight = AppPalette(
    colors: AppColors.light,
    brightness: Brightness.light,
    accent: Color(0xFFA9714B),
  );

  static AppPalette fromSettings(
    ThemeSettings settings,
    Brightness platformBrightness,
  ) {
    final brightness = settings.brightnessMode.resolve(platformBrightness);
    final isDark = brightness == Brightness.dark;
    final reference = isDark ? AppColors.dark : AppColors.light;

    final background = elevate(
      settings.preset.surfaceFor(brightness),
      settings.backgroundTint * ThemeSettings.tintRange,
    );

    // 7:1 for body text, 4.5:1 for the accent — AAA and AA respectively. The
    // walk preserves the accent's hue and saturation, so a preset's colour
    // stays recognisably itself even when it has to move to stay legible.
    final textPrimary = contrastify(
      isDark ? const Color(0xFFF6F5F2) : const Color(0xFF14161A),
      background,
      targetRatio: 7,
    );
    // Per-brightness, so the walk starts from a colour that is already close to
    // legible. Correcting one mid-tone accent up onto a near-black surface is
    // what used to drain every dark theme to the same pale grey.
    final seedAccent = settings.accentFor(brightness);
    final accent = contrastify(seedAccent, background, targetRatio: 4.5);

    // Deep enough to read as shade, but still the page's own hue. Dark themes
    // are already near the floor, so there is almost nowhere left to go — which
    // is why their shadows lean on alpha instead.
    final shadowBase = elevate(background, isDark ? -0.06 : -0.55);

    return AppPalette(
      brightness: brightness,
      accent: seedAccent,
      colors: AppColors(
        primary: accent,
        background: background,
        // Dark surfaces are already near the floor, so a proportional step is
        // almost invisible — cards and borders need a bigger nudge there to
        // separate at all.
        card: elevate(background, isDark ? 0.09 : -0.04),
        textBox: elevate(background, isDark ? 0.13 : -0.07),
        border: elevate(background, isDark ? 0.19 : -0.12),
        textPrimary: textPrimary,
        textSecondary: Color.alphaBlend(
          textPrimary.withValues(alpha: 0.68),
          background,
        ),
        placeholder: Color.alphaBlend(
          textPrimary.withValues(alpha: 0.40),
          background,
        ),
        // Constants on purpose: a destructive action has to read as red
        // whatever theme is active.
        error: reference.error,
        success: reference.success,
        logo: accent,
        // A shadow on a coloured surface has to be a darker version of *that
        // colour*. Black desaturates whatever it falls on, so on a sage or
        // sand page it lands as grey — which reads as dirt in the gaps between
        // stacked cards rather than as anything being lifted off the page.
        shadow: shadowBase.withValues(alpha: isDark ? 0.45 : 0.16),
        cardShadow: shadowBase.withValues(alpha: isDark ? 0.30 : 0.10),
      ),
    );
  }
}
