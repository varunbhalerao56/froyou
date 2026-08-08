import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/color_utils.dart';
import 'package:froyou/features/profile/data/image_palette_service.dart';

/// Derives a palette from a real image file.
///
/// Everything here runs inside [WidgetTester.runAsync] because image decoding
/// is genuine async I/O — the fake clock a widget test normally runs under
/// would never let it complete.
void main() {
  group('contrastify', () {
    test('leaves an already-legible color alone', () {
      const background = Color(0xFFFFFFFF);
      const foreground = Color(0xFF102030);
      expect(contrastify(foreground, background), foreground);
    });

    test('darkens a light accent until it reads on a light background', () {
      const background = Color(0xFFF2EFE9);
      const accent = Color(0xFFFFE066); // pale yellow, unreadable as-is

      final fixed = contrastify(accent, background, targetRatio: 4.5);

      expect(contrastRatio(fixed, background), greaterThanOrEqualTo(4.5));
      // Hue is preserved — the point of contrastify over ensureContrast.
      expect(
        HSLColor.fromColor(fixed).hue,
        closeTo(HSLColor.fromColor(accent).hue, 1.0),
      );
    });

    test('lightens an accent on a dark background', () {
      const background = Color(0xFF14161A);
      const accent = Color(0xFF1A2B6B);

      final fixed = contrastify(accent, background, targetRatio: 4.5);

      expect(contrastRatio(fixed, background), greaterThanOrEqualTo(4.5));
      expect(fixed.computeLuminance(), greaterThan(accent.computeLuminance()));
    });
  });

  group('elevate', () {
    test('shifts lightness and clamps at the ends', () {
      expect(elevate(const Color(0xFF000000), -0.5), const Color(0xFF000000));
      expect(elevate(const Color(0xFFFFFFFF), 0.5), const Color(0xFFFFFFFF));
      expect(
        elevate(const Color(0xFF808080), 0.1).computeLuminance(),
        greaterThan(const Color(0xFF808080).computeLuminance()),
      );
    });
  });

  group('ImagePaletteService.derive', () {
    testWidgets('produces a legible palette from a real photo', (tester) async {
      final file = File('test/fixtures/backdrop.jpg');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'test fixture image is missing',
      );

      late AppPalette palette;
      await tester.runAsync(() async {
        palette = await ImagePaletteService.derive(file);
      });

      // Printed so the derived theme can be seeded into a simulator for a
      // visual check without going through the picker.
      // ignore: avoid_print
      print('DERIVED_PALETTE_JSON=${jsonEncode(palette.toJson())}');
      // ignore: avoid_print
      print(
        'bgLuminance=${palette.colors.background.computeLuminance()} '
        'brightness=${palette.brightness} '
        'textRatio=${contrastRatio(palette.colors.textPrimary, palette.colors.background)} '
        'primaryRatio=${contrastRatio(palette.colors.primary, palette.colors.background)}',
      );

      // Body text must clear WCAG AA for normal text against the surface it
      // actually sits on.
      expect(
        contrastRatio(palette.colors.textPrimary, palette.colors.background),
        greaterThanOrEqualTo(4.5),
      );
      // The accent has to be usable for buttons and links.
      expect(
        contrastRatio(palette.colors.primary, palette.colors.background),
        greaterThanOrEqualTo(4.5),
      );
      // Brightness and the resolved text colour must agree, or every Material
      // default (icons, dialogs, sheets) fights the text.
      final textIsLight =
          palette.colors.textPrimary.computeLuminance() >
          palette.colors.background.computeLuminance();
      expect(textIsLight, palette.brightness == Brightness.dark);

      // Surfaces are stepped off the background, not identical to it.
      expect(palette.colors.card, isNot(palette.colors.background));
      expect(palette.colors.textBox, isNot(palette.colors.background));
      expect(palette.colors.border, isNot(palette.colors.background));
      // Background comes from the image's lower edge, not from a default.
      expect(palette.colors.background, palette.bottomEdge);
      expect(palette.bottomEdge, isNot(AppColors.light.background));

      // Round-trips through preferences without losing anything.
      final restored = AppPalette.tryFromJson(
        Map<String, Object?>.from(
          jsonDecode(jsonEncode(palette.toJson())) as Map,
        ),
      );
      expect(restored, isNotNull);
      expect(restored!.colors.primary, palette.colors.primary);
      expect(restored.bottomEdge, palette.bottomEdge);
      expect(restored.brightness, palette.brightness);

      // Printed so the derived theme can be seeded into a simulator for a
      // visual check without going through the picker.
      // ignore: avoid_print
      print('DERIVED_PALETTE_JSON=${jsonEncode(palette.toJson())}');
    });

    testWidgets('falls back instead of throwing when the file is gone', (
      tester,
    ) async {
      late AppPalette palette;
      await tester.runAsync(() async {
        palette = await ImagePaletteService.derive(
          File('test/fixtures/does-not-exist.jpg'),
        );
      });

      expect(palette.colors.background, AppPalette.fallbackLight.colors.background);
    });
  });

  group('AppPalette.tryFromJson', () {
    test('rejects a payload from an older schema', () {
      final stale = AppPalette.fallbackLight.toJson()..['v'] = 0;
      expect(AppPalette.tryFromJson(stale), isNull);
    });

    test('rejects a malformed payload rather than throwing', () {
      expect(
        AppPalette.tryFromJson({'v': AppPalette.schemaVersion, 'primary': 'nope'}),
        isNull,
      );
    });
  });
}
