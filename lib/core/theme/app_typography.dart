import 'package:flutter/material.dart';

/// Typography scale, on SF Pro Rounded. Pure font + weight + size — colors are
/// intentionally omitted so the same style works for both light and dark
/// themes. Apply color via [TextStyle.copyWith] or a [DefaultTextStyle].
///
/// The sizes and `letterSpacing` values are Apple's own tracking for the iOS
/// type scale. The tracking is what actually makes text read as SF rather than
/// as a generic geometric sans — don't drop it.
///
/// SF Pro Rounded ships as a single optical family, so unlike SF Pro there is
/// no Text/Display split to switch on at 20pt. Only the four weights declared
/// in `pubspec.yaml` exist (400/500/600/700); asking for anything heavier makes
/// Flutter synthesize a fake bold.
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'SFProRounded';

  // Large display titles (iOS large-title nav style).
  static const TextStyle largeTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.37,
  );

  // Primary view title.
  static const TextStyle title1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.36,
  );

  // Section title.
  static const TextStyle title2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.35,
  );

  // Subsection title.
  static const TextStyle title3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.38,
  );

  // Emphasized in-content heading.
  static const TextStyle headline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.41,
  );

  // Default body.
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.41,
  );

  static const TextStyle bodyBold = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.41,
  );

  // Emphasized short text.
  static const TextStyle callout = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.32,
  );

  // Secondary text.
  static const TextStyle subheadline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.24,
  );

  static const TextStyle subheadlineBold = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.24,
  );

  // Auxiliary information.
  static const TextStyle footnote = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.08,
  );

  // Labels and annotations.
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle captionBold = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle caption2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.07,
  );

  /// The Home hero quote. Larger and looser than [largeTitle] because it sits
  /// alone on the image with nothing to compete with.
  static const TextStyle quote = TextStyle(
    fontFamily: fontFamily,
    fontSize: 30,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.36,
    height: 1.2,
  );

  /// Builds the Material [TextTheme] from this scale. Wired into [ThemeData]
  /// in `app_theme.dart`.
  static const TextTheme textTheme = TextTheme(
    displayLarge: largeTitle,
    displayMedium: title1,
    displaySmall: title2,
    headlineLarge: title3,
    headlineMedium: title3,
    headlineSmall: headline,
    titleLarge: title3,
    titleMedium: callout,
    titleSmall: bodyBold,
    bodyLarge: body,
    bodyMedium: subheadline,
    bodySmall: footnote,
    labelLarge: footnote,
    labelMedium: caption,
    labelSmall: caption2,
  );
}
