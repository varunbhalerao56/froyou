import 'package:flutter/material.dart';

/// Typography scale, on SF Pro Rounded. Pure font + weight + size — colors are
/// intentionally omitted so the same style works for both light and dark
/// themes. Apply color via [TextStyle.copyWith] or a [DefaultTextStyle].
///
/// Sizes follow the iOS type scale. Tracking is what actually makes text read
/// as SF rather than as a generic geometric sans — don't drop it — but it is
/// **negative above body size and positive only at the smallest sizes**, which
/// is how optical sizing works: large type needs letters pulled together, small
/// type needs them opened up. Apple's published per-size tracking table says
/// the same thing, and the earlier values here had the sign flipped at the top
/// of the scale, which is what made headings and the Home caption read loose
/// and unconsidered.
///
/// SF Pro Rounded ships as a single optical family, so unlike SF Pro there is
/// no Text/Display split to switch on at 20pt — the tracking below is doing
/// that job by hand. Only the four weights declared in `pubspec.yaml` exist
/// (400/500/600/700); asking for anything heavier makes Flutter synthesize a
/// fake bold.
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'SFProRounded';

  // Large display titles (iOS large-title nav style).
  static const TextStyle largeTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  // Primary view title.
  static const TextStyle title1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );

  // Section title.
  static const TextStyle title2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  // Subsection title.
  static const TextStyle title3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.25,
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

  /// Past log entries. A notch above [body], with looser leading: these are
  /// read, not scanned, and they're the user's own words rather than UI.
  static const TextStyle logBody = TextStyle(
    fontFamily: fontFamily,
    fontSize: 19,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.4,
    height: 1.35,
  );

  /// The compose field. Bigger again — this is where you're actually looking
  /// while dictating or typing, often at arm's length.
  static const TextStyle composeInput = TextStyle(
    fontFamily: fontFamily,
    fontSize: 21,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.4,
    height: 1.35,
  );

  /// The Home caption, above the picture.
  ///
  /// Brought down from 30 and pulled tight. At 30 with open tracking it was
  /// the loudest thing on the screen and routinely wrapped to two lines, which
  /// left the prompt below the image looking like a footnote to it rather than
  /// the question the screen is actually asking.
  static const TextStyle quote = TextStyle(
    fontFamily: fontFamily,
    fontSize: 25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    height: 1.22,
  );

  /// The line under the picture — "How are you feeling?", or the follow-up.
  ///
  /// Identical to [quote]. The caption and the question are the only two
  /// pieces of text on Home; stepping the second one down even two points read
  /// as an annotation on the picture rather than as the thing being asked, so
  /// colour alone carries the hierarchy — which is a quieter way to say it
  /// than size or weight.
  static const TextStyle prompt = quote;

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
