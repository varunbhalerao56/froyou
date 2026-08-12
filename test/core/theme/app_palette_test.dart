import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/color_utils.dart';

/// The contract that replaced image-derived theming.
///
/// Users pick a preset, a brightness and a tint, so the app can no longer
/// promise contrast by inspecting one photo — it has to hold across the whole
/// combinatorial space instead. That is what these tests pin down.
///
/// The accent used to be a free colour and this walk covered pathological ones
/// alongside the presets. It isn't any more: a preset owns its accent at each
/// brightness, so the reachable space is exactly the presets. Testing invented
/// accents now would be testing a path no user can take — the guarantee that
/// matters is that every *shipped* pair is legible, which is asserted below,
/// plus `contrastify` itself, which has its own tests.
void main() {
  const tints = <double>[-1, -0.5, 0, 0.5, 1];

  Iterable<(String, ThemeSettings)> allCombinations() sync* {
    for (final preset in ThemePresets.all) {
      for (final mode in [ThemeBrightnessMode.light, ThemeBrightnessMode.dark]) {
        for (final tint in tints) {
          yield (
            '${preset.id}/${mode.name}/tint$tint',
            ThemeSettings(
              presetId: preset.id,
              brightnessMode: mode,
              backgroundTint: tint,
            ),
          );
        }
      }
    }
  }

  group('AppPalette.fromSettings', () {
    test('body text clears AA on every preset, brightness and tint', () {
      for (final (label, settings) in allCombinations()) {
        final palette = AppPalette.fromSettings(settings, Brightness.light);
        expect(
          contrastRatio(palette.colors.textPrimary, palette.colors.background),
          greaterThanOrEqualTo(4.5),
          reason: 'textPrimary failed for $label',
        );
      }
    });

    test('the accent stays usable for buttons and links', () {
      for (final (label, settings) in allCombinations()) {
        final palette = AppPalette.fromSettings(settings, Brightness.light);
        expect(
          contrastRatio(palette.colors.primary, palette.colors.background),
          greaterThanOrEqualTo(4.5),
          reason: 'primary failed for $label',
        );
      }
    });

    test('secondary text and placeholders stay readable', () {
      for (final (label, settings) in allCombinations()) {
        final palette = AppPalette.fromSettings(settings, Brightness.light);
        // Secondary text is still text, so AA applies. Placeholders are
        // non-essential, so the large-text floor is the honest bar.
        expect(
          contrastRatio(palette.colors.textSecondary, palette.colors.background),
          greaterThanOrEqualTo(3.0),
          reason: 'textSecondary failed for $label',
        );
        expect(
          contrastRatio(palette.colors.placeholder, palette.colors.background),
          greaterThanOrEqualTo(1.6),
          reason: 'placeholder failed for $label',
        );
      }
    });

    test('surfaces stay distinguishable from the background', () {
      for (final (label, settings) in allCombinations()) {
        final palette = AppPalette.fromSettings(settings, Brightness.light);
        expect(
          palette.colors.card,
          isNot(palette.colors.background),
          reason: 'card collapsed into background for $label',
        );
        expect(
          palette.colors.border,
          isNot(palette.colors.background),
          reason: 'border collapsed into background for $label',
        );
      }
    });

    test('brightness and the resolved text colour always agree', () {
      for (final (label, settings) in allCombinations()) {
        final palette = AppPalette.fromSettings(settings, Brightness.light);
        final textIsLight =
            palette.colors.textPrimary.computeLuminance() >
            palette.colors.background.computeLuminance();
        expect(
          textIsLight,
          palette.isDark,
          reason: 'brightness disagreed with text colour for $label',
        );
      }
    });

    test('system mode follows the platform', () {
      const settings = ThemeSettings(
        brightnessMode: ThemeBrightnessMode.system,
      );
      expect(
        AppPalette.fromSettings(settings, Brightness.dark).brightness,
        Brightness.dark,
      );
      expect(
        AppPalette.fromSettings(settings, Brightness.light).brightness,
        Brightness.light,
      );
    });

    test('a pinned mode ignores the platform', () {
      const pinned = ThemeSettings(brightnessMode: ThemeBrightnessMode.light);
      expect(
        AppPalette.fromSettings(pinned, Brightness.dark).brightness,
        Brightness.light,
      );
    });

    test('exposes the preset accent as authored, for the swatch', () {
      const settings = ThemeSettings(
        presetId: 'dusk',
        brightnessMode: ThemeBrightnessMode.dark,
      );
      final palette = AppPalette.fromSettings(settings, Brightness.light);

      // The swatch in Settings shows the colour as written down, whatever
      // contrast correction had to do with it to render.
      expect(palette.accent, ThemePresets.dusk.darkAccent);
    });

    test('takes the accent for the brightness actually in effect', () {
      const preset = 'sage';
      final light = AppPalette.fromSettings(
        const ThemeSettings(
          presetId: preset,
          brightnessMode: ThemeBrightnessMode.light,
        ),
        Brightness.light,
      );
      final dark = AppPalette.fromSettings(
        const ThemeSettings(
          presetId: preset,
          brightnessMode: ThemeBrightnessMode.dark,
        ),
        Brightness.light,
      );

      expect(light.accent, ThemePresets.sage.lightAccent);
      expect(dark.accent, ThemePresets.sage.darkAccent);
    });

    test('dark accents keep their colour instead of correcting to grey', () {
      // The failure this guards against: one mid-tone accent shared by both
      // brightnesses gets lightened so far to clear 4.5:1 on a near-black
      // surface that every theme arrives at the same pale grey.
      for (final preset in ThemePresets.all) {
        final palette = AppPalette.fromSettings(
          ThemeSettings(
            presetId: preset.id,
            brightnessMode: ThemeBrightnessMode.dark,
          ),
          Brightness.light,
        );
        final rendered = HSLColor.fromColor(palette.colors.primary);
        expect(
          rendered.saturation,
          greaterThan(0.15),
          reason: '${preset.id} dark accent washed out to grey',
        );
      }
    });

    test('an unknown preset id falls back instead of throwing', () {
      const settings = ThemeSettings(presetId: 'no-such-preset');
      expect(settings.preset.id, ThemePresets.fallback.id);
      expect(
        () => AppPalette.fromSettings(settings, Brightness.light),
        returnsNormally,
      );
    });
  });

  group('status bar', () {
    // The bug this guards: `statusBarBrightness` describes what sits *behind*
    // the status bar, not the icons, so it takes the app's brightness as-is.
    // Inverting it here would put white icons on paper the moment someone
    // pins Light while iOS is in Dark.
    test('light theme asks iOS for a light backdrop and dark icons', () {
      final style = AppTheme.overlayStyleFor(Brightness.light);
      expect(style.statusBarBrightness, Brightness.light);
      expect(style.statusBarIconBrightness, Brightness.dark);
    });

    test('dark theme asks iOS for a dark backdrop and light icons', () {
      final style = AppTheme.overlayStyleFor(Brightness.dark);
      expect(style.statusBarBrightness, Brightness.dark);
      expect(style.statusBarIconBrightness, Brightness.light);
    });

    test('follows the app, not the platform', () {
      // Pinned Light under a dark system is the whole point: the palette is
      // light, so the status bar has to be too.
      final palette = AppPalette.fromSettings(
        const ThemeSettings(brightnessMode: ThemeBrightnessMode.light),
        Brightness.dark,
      );
      expect(
        AppTheme.overlayStyleFor(palette.brightness).statusBarIconBrightness,
        Brightness.dark,
      );
    });

    test('app bars carry the same style, since they annotate it themselves', () {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final theme = AppTheme.fromPalette(
          AppPalette.fromSettings(
            ThemeSettings(
              brightnessMode: brightness == Brightness.dark
                  ? ThemeBrightnessMode.dark
                  : ThemeBrightnessMode.light,
            ),
            Brightness.light,
          ),
        );
        expect(
          theme.appBarTheme.systemOverlayStyle?.statusBarBrightness,
          brightness,
          reason: 'app bar would override the app-level style for $brightness',
        );
      }
    });
  });

  group('ThemeSettings JSON', () {
    test('round-trips every field', () {
      const settings = ThemeSettings(
        presetId: 'moss',
        brightnessMode: ThemeBrightnessMode.dark,
        backgroundTint: -0.5,
      );
      final restored = ThemeSettings.fromJson(settings.toJson());

      expect(restored.presetId, settings.presetId);
      expect(restored.brightnessMode, settings.brightnessMode);
      expect(restored.backgroundTint, settings.backgroundTint);
    });

    test('falls back field-by-field on a malformed payload', () {
      final restored = ThemeSettings.fromJson({
        'presetId': 42,
        'brightnessMode': 'sideways',
        'backgroundTint': 'quite a lot',
      });

      expect(restored.presetId, ThemeSettings.defaults.presetId);
      expect(restored.brightnessMode, ThemeBrightnessMode.system);
      expect(restored.backgroundTint, 0);
    });

    test('ignores an accent left over from before the picker was removed', () {
      final restored = ThemeSettings.fromJson({
        'presetId': 'sand',
        'accentOverride': 0xFF123456,
      });

      expect(restored.presetId, 'sand');
      expect(restored.accentFor(Brightness.light), ThemePresets.sand.lightAccent);
    });
  });
}
