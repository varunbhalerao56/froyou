import 'dart:io';

import 'package:flutter/material.dart';
import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/color_utils.dart';
import 'package:palette_generator_master/palette_generator_master.dart';

/// Turns the user's chosen image into a full app theme.
///
/// Deliberately never called on the boot path — a decode plus a color
/// quantization pass is far too slow for that, and the result would arrive a
/// frame or two late as a visible color flash. Derivation happens exactly
/// twice: when onboarding saves, and when settings saves. Everything else
/// reads the persisted [AppPalette].
class ImagePaletteService {
  ImagePaletteService._();

  /// Every sample decodes at this width. This is the single most important
  /// guard in the file: `PaletteGeneratorMaster`'s own `size:` parameter only
  /// feeds an [ImageConfiguration], which [FileImage] ignores outright — so
  /// without an explicit [ResizeImage] a 4032x3024 photo becomes a ~48MB RGBA
  /// buffer inside `toByteData`, twice.
  static const int _sampleWidth = 220;

  /// Whether the theme should be a dark one for this background.
  ///
  /// Decided by which text colour actually wins on contrast, not by a
  /// luminance threshold. A threshold can disagree with the text colour the
  /// contrast walk then picks — a mid-tone background around 0.3 luminance
  /// reads as "dark" to a 0.45 cutoff, but black text beats white on it by
  /// more than two to one. That disagreement matters beyond the text itself:
  /// [Brightness] drives every Material default, so getting it wrong gives
  /// light icons and dialogs on a light-text-hostile surface.
  static bool _prefersDarkTheme(Color background) {
    return contrastRatio(const Color(0xFFFFFFFF), background) >
        contrastRatio(const Color(0xFF000000), background);
  }

  static final Map<String, AppPalette> _cache = <String, AppPalette>{};

  /// Derives a palette from [file]. Falls back to a neutral palette rather
  /// than throwing — a theme is never worth failing a save over.
  static Future<AppPalette> derive(File file) async {
    final cacheKey = await _cacheKey(file);
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    try {
      final small = ResizeImage(
        FileImage(file),
        width: _sampleWidth,
        allowUpscaling: false,
      );

      // The glow colors, and — via the bottom edge — the app background.
      final topEdge = await sampleEdgeColor(
        small,
        top: true,
        stripFraction: 0.10,
      );
      final bottomEdge = await sampleEdgeColor(
        small,
        top: false,
        stripFraction: 0.10,
      );

      final palette = _build(
        topEdge: topEdge,
        bottomEdge: bottomEdge,
        accentSeed: await _accentSeed(small, fallback: topEdge),
      );

      if (cacheKey != null) _cache[cacheKey] = palette;
      return palette;
    } catch (e, stackTrace) {
      AppLog.error('Palette', 'derivation failed for ${file.path}', e, stackTrace);
      return AppPalette.fallbackLight;
    }
  }

  /// The most characterful color in the image, for the accent.
  ///
  /// Note the package's default filter discards near-black and near-white, so
  /// on a very dark or very washed-out photo every swatch can come back null —
  /// hence the fallback rather than a bang.
  static Future<Color> _accentSeed(
    ImageProvider image, {
    required Color fallback,
  }) async {
    try {
      final generator = await PaletteGeneratorMaster.fromImageProvider(
        image,
        maximumColorCount: 12,
        timeout: const Duration(seconds: 6),
      );
      final swatch =
          generator.vibrantColor ??
          generator.lightVibrantColor ??
          generator.darkVibrantColor ??
          generator.mutedColor ??
          generator.dominantColor;
      return swatch?.color ?? fallback;
    } catch (e) {
      AppLog.warn('Palette', 'quantization failed, using edge color: $e');
      return fallback;
    }
  }

  static AppPalette _build({
    required Color topEdge,
    required Color bottomEdge,
    required Color accentSeed,
  }) {
    // Brightness comes from the bottom edge, not the image as a whole: that is
    // the color the quote, the log list and every control actually sit on. A
    // bright sky over a dark forest should still give us a dark theme.
    final background = bottomEdge;
    final isDark = _prefersDarkTheme(background);
    final reference = isDark ? AppColors.dark : AppColors.light;

    final textPrimary = contrastify(
      isDark ? const Color(0xFFF6F5F2) : const Color(0xFF14161A),
      background,
      targetRatio: 7.0,
    );
    final accent = contrastify(accentSeed, background, targetRatio: 4.5);

    return AppPalette(
      brightness: isDark ? Brightness.dark : Brightness.light,
      topEdge: topEdge,
      bottomEdge: bottomEdge,
      colors: AppColors(
        primary: accent,
        background: background,
        card: elevate(background, isDark ? 0.06 : -0.04),
        textBox: elevate(background, isDark ? 0.10 : -0.07),
        border: elevate(background, isDark ? 0.16 : -0.12),
        textPrimary: textPrimary,
        textSecondary: Color.alphaBlend(
          textPrimary.withValues(alpha: 0.68),
          background,
        ),
        placeholder: Color.alphaBlend(
          textPrimary.withValues(alpha: 0.40),
          background,
        ),
        // Left as constants on purpose. A destructive action must read as red
        // whatever photo the user picked; deriving these would eventually
        // produce a green "error".
        error: reference.error,
        success: reference.success,
        logo: accent,
        shadow: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
        cardShadow: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
      ),
    );
  }

  /// Keyed on path *and* mtime so re-picking the same file after an edit still
  /// re-derives. Null (uncacheable) if the file has vanished.
  static Future<String?> _cacheKey(File file) async {
    try {
      final stat = await file.stat();
      return '${file.path}:${stat.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }
}
