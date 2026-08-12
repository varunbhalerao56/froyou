import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/illustration.dart';

/// The contract between `assets/illustrations/` and the resolver.
///
/// These drawings are fetched from unDraw and rewritten by
/// `tool/fetch_illustrations.sh`, so the assets can change without any Dart
/// changing with them. Both halves of that seam fail quietly if they drift: an
/// unmapped role reaches flutter_svg as `fill="__SOMETHING__"`, which it
/// discards silently, and a role the assets stopped using is simply dead. So
/// the walk below is over the files on disk rather than over a fixture.
///
/// The other reason this is worth pinning is that one asset has to serve seven
/// presets in two brightnesses. Nothing about that is visible on the screen the
/// developer happens to be looking at — a ramp anchored to the wrong end is
/// perfectly legible in light mode and invisible in dark.
void main() {
  final assets = {
    for (final art in Illustration.values)
      art: File(art.asset).readAsStringSync(),
  };

  final tokenPattern = RegExp(r'__[A-Z_]+__');
  final hexPattern = RegExp(r'#[0-9a-fA-F]{3,6}\b');

  Iterable<(String, AppColors)> everyPalette() sync* {
    for (final preset in ThemePresets.all) {
      for (final mode in [
        ThemeBrightnessMode.light,
        ThemeBrightnessMode.dark,
      ]) {
        yield (
          '${preset.id}/${mode.name}',
          AppPalette.fromSettings(
            ThemeSettings(presetId: preset.id, brightnessMode: mode),
            Brightness.light,
          ).colors,
        );
      }
    }
  }

  group('the assets', () {
    test('every one is present and tokenized', () {
      for (final MapEntry(key: art, value: svg) in assets.entries) {
        expect(
          tokenPattern.hasMatch(svg),
          isTrue,
          reason:
              '${art.asset} has no roles in it — it is probably a raw unDraw '
              'download that skipped tool/fetch_illustrations.sh',
        );
      }
    });

    test('use no role the resolver does not know', () {
      for (final MapEntry(key: art, value: svg) in assets.entries) {
        final used = tokenPattern.allMatches(svg).map((m) => m[0]!).toSet();
        expect(
          used.difference(IllustrationView.roles),
          isEmpty,
          reason:
              '${art.asset} uses a role with no entry in the ramp — add it to '
              'both PALETTE in tool/fetch_illustrations.sh and _ramp in '
              'lib/core/ui/illustration.dart',
        );
      }
    });

    test('carry no literal colour left over from unDraw', () {
      // A literal survives a theme change unchanged, so #6c63ff on a Sand
      // background is exactly the clash the tokenizing exists to prevent.
      for (final MapEntry(key: art, value: svg) in assets.entries) {
        expect(
          hexPattern.allMatches(svg).map((m) => m[0]).toSet(),
          isEmpty,
          reason: '${art.asset} still contains hard-coded colour(s)',
        );
      }
    });
  });

  group('resolve', () {
    test('leaves no role behind on any preset or brightness', () {
      for (final (label, colors) in everyPalette()) {
        for (final MapEntry(key: art, value: svg) in assets.entries) {
          expect(
            tokenPattern.hasMatch(IllustrationView.resolve(svg, colors)),
            isFalse,
            reason: '${art.name} kept a role under $label',
          );
        }
      }
    });

    test('writes only six-digit hex, which is all SVG fill accepts', () {
      for (final (label, colors) in everyPalette()) {
        for (final svg in assets.values) {
          for (final match in hexPattern.allMatches(
            IllustrationView.resolve(svg, colors),
          )) {
            expect(
              match[0],
              matches(RegExp(r'^#[0-9a-f]{6}$')),
              reason: 'malformed colour under $label',
            );
          }
        }
      }
    });

    test('separates ink from the page it sits on, in both brightnesses', () {
      // The one thing a ramp anchored to the wrong end would break, and the one
      // thing that is invisible until someone opens the app in the other mode.
      for (final (label, colors) in everyPalette()) {
        final ink = _colorOf(IllustrationView.resolve('__INK__', colors));
        final page = _colorOf(
          IllustrationView.resolve('__SURFACE_HI__', colors),
        );
        expect(
          (ink.computeLuminance() - page.computeLuminance()).abs(),
          greaterThan(0.15),
          reason: 'the darkest and lightest tones collapsed under $label',
        );
      }
    });
  });

  testWidgets('renders in both brightnesses without throwing', (tester) async {
    for (final mode in [ThemeBrightnessMode.light, ThemeBrightnessMode.dark]) {
      for (final art in Illustration.values) {
        final palette = AppPalette.fromSettings(
          ThemeSettings(brightnessMode: mode),
          Brightness.light,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.fromPalette(palette),
            home: Center(
              child: SizedBox(
                width: 300,
                height: 200,
                child: IllustrationView(illustration: art),
              ),
            ),
          ),
        );
        // Once for the bundle read, then past the cross-fade.
        await tester.pumpAndSettle();

        expect(
          find.byType(SvgPicture),
          findsOneWidget,
          reason: '${art.name} did not resolve in ${mode.name}',
        );
      }
    }
  });
}

Color _colorOf(String hex) =>
    Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
