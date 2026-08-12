import 'package:flutter/material.dart';

import 'theme_presets.dart';

enum ThemeBrightnessMode {
  light,
  dark,

  /// Follow iOS. Re-resolved whenever the platform brightness changes.
  system;

  static ThemeBrightnessMode fromName(String? name) {
    for (final mode in values) {
      if (mode.name == name) return mode;
    }
    return system;
  }

  Brightness resolve(Brightness platformBrightness) => switch (this) {
    ThemeBrightnessMode.light => Brightness.light,
    ThemeBrightnessMode.dark => Brightness.dark,
    ThemeBrightnessMode.system => platformBrightness,
  };
}

/// Everything the user can choose about the app's appearance.
///
/// Small enough to persist as a few JSON fields and cheap enough to turn into a
/// full palette synchronously — which is what lets the first frame after launch
/// already be themed, with no async gap and so no flash of the wrong colours.
@immutable
class ThemeSettings {
  const ThemeSettings({
    // Neutral, and following the system's light/dark setting, so the app looks
    // right on first launch without anyone having chosen anything.
    this.presetId = 'paper',
    this.brightnessMode = ThemeBrightnessMode.system,
    this.backgroundTint = 0,
  });

  final String presetId;

  final ThemeBrightnessMode brightnessMode;

  /// -1 (deeper) to 1 (lighter). Nudges the surface lightness only; the
  /// derived colours re-resolve around it, so sliding this can't break
  /// contrast.
  final double backgroundTint;

  static const ThemeSettings defaults = ThemeSettings();

  /// How far [backgroundTint] can move the surface, in HSL lightness. Kept
  /// small on purpose — this is a nudge, not a second brightness control.
  static const double tintRange = 0.08;

  ThemePreset get preset => ThemePresets.byId(presetId);

  /// The accent for a given brightness. There is no user override: the preset
  /// *is* the choice, which is what keeps the row of swatches to one idea
  /// instead of a colour and then a second colour on top of it.
  Color accentFor(Brightness brightness) => preset.accentFor(brightness);

  ThemeSettings copyWith({
    String? presetId,
    ThemeBrightnessMode? brightnessMode,
    double? backgroundTint,
  }) {
    return ThemeSettings(
      presetId: presetId ?? this.presetId,
      brightnessMode: brightnessMode ?? this.brightnessMode,
      backgroundTint: backgroundTint ?? this.backgroundTint,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'presetId': presetId,
    'brightnessMode': brightnessMode.name,
    'backgroundTint': backgroundTint,
  };

  /// Tolerant by design — a malformed field falls back to its default rather
  /// than losing the user's whole theme.
  factory ThemeSettings.fromJson(Map<String, Object?> json) {
    // Checked with `is` rather than cast: `as String?` throws on a wrong-typed
    // value, which would take the whole theme down instead of falling back to
    // this one field's default.
    final presetId = json['presetId'];
    final mode = json['brightnessMode'];
    final tint = json['backgroundTint'];

    // A stored `accentOverride` from before the accent picker was removed is
    // simply ignored — the preset owns the accent now, and an unread key costs
    // nothing next time this is written.
    return ThemeSettings(
      presetId: presetId is String ? presetId : defaults.presetId,
      brightnessMode: ThemeBrightnessMode.fromName(
        mode is String ? mode : null,
      ),
      backgroundTint: tint is num ? tint.toDouble().clamp(-1.0, 1.0) : 0,
    );
  }
}
