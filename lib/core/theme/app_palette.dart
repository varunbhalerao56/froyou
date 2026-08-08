import 'package:flutter/material.dart';

import 'app_colors.dart';

/// A complete theme derived from the user's chosen backdrop image.
///
/// Wraps [AppColors] (which drives every widget through `ThemeData.extensions`)
/// with the two edge colors the Home backdrop dissolves into, plus the
/// brightness the rest of the theme was built for.
///
/// Serialized into preferences whole, so a relaunch can theme the first frame
/// synchronously. Deriving this from an image costs an image decode and a
/// color quantization pass — far too slow to sit on the boot path, and it would
/// show as a visible color flash.
@immutable
class AppPalette {
  const AppPalette({
    required this.colors,
    required this.topEdge,
    required this.bottomEdge,
    required this.brightness,
  });

  final AppColors colors;

  /// Average color of the image's top strip. The background gradient starts
  /// here so the image's upper edge has nothing to hand off to.
  final Color topEdge;

  /// Average color of the image's bottom strip, and the background color the
  /// quote, the log list and every control actually sit on.
  final Color bottomEdge;

  final Brightness brightness;

  static const AppPalette fallbackLight = AppPalette(
    colors: AppColors.light,
    topEdge: Color(0xFFFAFAF6),
    bottomEdge: Color(0xFFFAFAF6),
    brightness: Brightness.light,
  );

  static const AppPalette fallbackDark = AppPalette(
    colors: AppColors.dark,
    topEdge: Color(0xFF0E0F14),
    bottomEdge: Color(0xFF0E0F14),
    brightness: Brightness.dark,
  );

  /// Bumped whenever the derivation algorithm or this shape changes, so a
  /// stored palette from an older build is discarded rather than misread.
  static const int schemaVersion = 1;

  Map<String, Object?> toJson() => <String, Object?>{
    'v': schemaVersion,
    'brightness': brightness == Brightness.dark ? 'dark' : 'light',
    'topEdge': topEdge.toARGB32(),
    'bottomEdge': bottomEdge.toARGB32(),
    'primary': colors.primary.toARGB32(),
    'background': colors.background.toARGB32(),
    'card': colors.card.toARGB32(),
    'textBox': colors.textBox.toARGB32(),
    'border': colors.border.toARGB32(),
    'textPrimary': colors.textPrimary.toARGB32(),
    'textSecondary': colors.textSecondary.toARGB32(),
    'placeholder': colors.placeholder.toARGB32(),
    'error': colors.error.toARGB32(),
    'success': colors.success.toARGB32(),
    'logo': colors.logo.toARGB32(),
    'shadow': colors.shadow.toARGB32(),
    'cardShadow': colors.cardShadow.toARGB32(),
  };

  /// Returns null when the stored payload is from an older schema or is
  /// malformed — the caller falls back to [fallbackLight] rather than crashing
  /// the app on boot over a theme.
  static AppPalette? tryFromJson(Map<String, Object?> json) {
    if (json['v'] != schemaVersion) return null;
    try {
      Color read(String key) => Color(json[key]! as int);
      return AppPalette(
        brightness: json['brightness'] == 'dark'
            ? Brightness.dark
            : Brightness.light,
        topEdge: read('topEdge'),
        bottomEdge: read('bottomEdge'),
        colors: AppColors(
          primary: read('primary'),
          background: read('background'),
          card: read('card'),
          textBox: read('textBox'),
          border: read('border'),
          textPrimary: read('textPrimary'),
          textSecondary: read('textSecondary'),
          placeholder: read('placeholder'),
          error: read('error'),
          success: read('success'),
          logo: read('logo'),
          shadow: read('shadow'),
          cardShadow: read('cardShadow'),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
