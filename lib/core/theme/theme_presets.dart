import 'package:flutter/material.dart';

/// A calming starting point for the app's colours.
///
/// A preset carries four seeds — an accent and a surface for each brightness.
/// Everything else (cards, borders, text, placeholders) is derived from those
/// with guaranteed contrast, so no preset can produce unreadable text. That
/// guarantee is the whole reason this is a small seed rather than thirteen
/// colour pickers.
///
/// **The accent is per-brightness, and that is the point.** A single accent
/// cannot serve both: one dark enough to read on paper needs so much lightening
/// to clear 4.5:1 on a near-black surface that it arrives grey, and every theme
/// ends up looking like the same washed lilac. Naming both ends lets dark mode
/// keep its colour.
@immutable
class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.name,
    required this.lightAccent,
    required this.darkAccent,
    required this.lightSurface,
    required this.darkSurface,
  });

  /// Stable across releases — it's what gets persisted.
  final String id;

  final String name;

  /// Buttons, links, the emphasised part of a theme name.
  final Color lightAccent;
  final Color darkAccent;

  final Color lightSurface;
  final Color darkSurface;

  Color accentFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkAccent : lightAccent;

  Color surfaceFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkSurface : lightSurface;
}

/// The built-in presets.
///
/// Quiet by design — this is an app people open when they're ruminating, and a
/// loud background is the wrong room to do that in. But quiet is not the same
/// as colourless, and the first pass conflated the two: the light surfaces sat
/// a couple of points off white, so every theme read as the same sheet of paper
/// with a differently-tinted button on it.
///
/// So each surface now carries its hue properly at both ends — deep enough in
/// light mode to be a colour rather than a suggestion of one, and light enough
/// in dark mode to be recognisable as *that* colour rather than as black. The
/// accents follow the same rule; see [ThemePreset].
class ThemePresets {
  ThemePresets._();

  /// The default, and the least opinionated one.
  ///
  /// First launch shouldn't ask anyone to pick a colour before they've written
  /// anything — so the app starts here and follows the system's light/dark
  /// setting, and the presets are there for whenever they feel like looking.
  /// Neutral, but not grey: a flat charcoal surface with a grey accent is the
  /// one combination that reads as unfinished rather than as calm.
  static const ThemePreset paper = ThemePreset(
    id: 'paper',
    name: 'Paper',
    lightAccent: Color(0xFF54637A),
    darkAccent: Color(0xFF9DB4D4),
    lightSurface: Color(0xFFF2EFE9),
    darkSurface: Color(0xFF16181D),
  );

  static const ThemePreset sand = ThemePreset(
    id: 'sand',
    name: 'Sand',
    lightAccent: Color(0xFFA9714B),
    darkAccent: Color(0xFFE0AC80),
    lightSurface: Color(0xFFF5E7D2),
    darkSurface: Color(0xFF1E1917),
  );

  static const ThemePreset sage = ThemePreset(
    id: 'sage',
    name: 'Sage',
    lightAccent: Color(0xFF5A7F5F),
    darkAccent: Color(0xFF97C79E),
    lightSurface: Color(0xFFE5EFDE),
    darkSurface: Color(0xFF161C17),
  );

  static const ThemePreset mist = ThemePreset(
    id: 'mist',
    name: 'Mist',
    lightAccent: Color(0xFF44738F),
    darkAccent: Color(0xFF88BCDC),
    lightSurface: Color(0xFFDEEAF4),
    darkSurface: Color(0xFF141A21),
  );

  static const ThemePreset dusk = ThemePreset(
    id: 'dusk',
    name: 'Dusk',
    lightAccent: Color(0xFF6A5CA8),
    darkAccent: Color(0xFFAEA0EE),
    lightSurface: Color(0xFFE9E2F6),
    darkSurface: Color(0xFF1A1626),
  );

  static const ThemePreset clay = ThemePreset(
    id: 'clay',
    name: 'Clay',
    lightAccent: Color(0xFFB05B56),
    darkAccent: Color(0xFFEE9E96),
    lightSurface: Color(0xFFF8E5DD),
    darkSurface: Color(0xFF211818),
  );

  static const ThemePreset moss = ThemePreset(
    id: 'moss',
    name: 'Moss',
    lightAccent: Color(0xFF667044),
    darkAccent: Color(0xFFBCC885),
    lightSurface: Color(0xFFE9EED6),
    darkSurface: Color(0xFF181A13),
  );

  static const List<ThemePreset> all = [
    paper,
    sand,
    sage,
    mist,
    dusk,
    clay,
    moss,
  ];

  static const ThemePreset fallback = paper;

  /// Falls back rather than throwing: a preset id can outlive the preset if one
  /// is ever renamed or dropped, and a missing theme should never be fatal.
  static ThemePreset byId(String? id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return fallback;
  }
}
