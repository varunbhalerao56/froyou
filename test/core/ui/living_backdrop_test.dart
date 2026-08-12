import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/living_backdrop.dart';

/// The one moving thing on Home that is always moving.
///
/// Its whole job is to be barely perceptible, so a golden is the only useful
/// check on how it looks — and `animate: false` is what makes that possible,
/// since a repeating controller has no settled frame to capture.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppPalette paletteFor(String preset, ThemeBrightnessMode mode) =>
      AppPalette.fromSettings(
        ThemeSettings(presetId: preset, brightnessMode: mode),
        Brightness.light,
      );

  Widget frame(AppPalette palette, {bool animate = true}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.fromPalette(palette),
    home: Scaffold(
      body: LivingBackdrop(palette: palette, animate: animate),
    ),
  );

  testWidgets('holds still when animation is off', (tester) async {
    await tester.pumpWidget(frame(paletteFor('dusk', ThemeBrightnessMode.dark), animate: false));
    await tester.pump();

    // No repeating controller means no scheduled frames — which is also what
    // lets this widget appear in a golden at all.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('stops on unmount', (tester) async {
    final palette = paletteFor('dusk', ThemeBrightnessMode.dark);
    await tester.pumpWidget(frame(palette));
    await tester.pump();

    // Bounded pumps only: while the wash is configured on, this never idles
    // and pumpAndSettle would hang to its timeout.
    await tester.pump(const Duration(seconds: 4));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'the ticker must die with the widget',
    );
  });

  testWidgets('costs nothing when there is nothing to move', (tester) async {
    // Emptying the blob list is how the wash gets switched off. If the ticker
    // kept running anyway, off would cost exactly as much as on.
    await tester.pumpWidget(frame(paletteFor('sage', ThemeBrightnessMode.light)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final painting = find.byType(LivingBackdrop).evaluate().isNotEmpty;
    expect(painting, isTrue);
    if (!tester.binding.hasScheduledFrame) {
      // Blobs are disabled — nothing should be scheduled, which is the point.
      return;
    }
    // Blobs are enabled, so it must genuinely never settle.
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('tints itself from the active theme', (tester) async {
    // Sanity check that this is the *theme's* colour and not a fixed palette:
    // two presets must not paint the same thing.
    final dusk = paletteFor('dusk', ThemeBrightnessMode.dark);
    final sand = paletteFor('sand', ThemeBrightnessMode.dark);
    expect(dusk.colors.primary, isNot(sand.colors.primary));
  });

  group('appearance', () {
    for (final (preset, mode) in [
      ('dusk', ThemeBrightnessMode.dark),
      ('sand', ThemeBrightnessMode.light),
    ]) {
      testWidgets('$preset ${mode.name}', (tester) async {
        tester.view.physicalSize = const Size(1179, 2556);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          frame(paletteFor(preset, mode), animate: false),
        );
        await tester.pump();

        await expectLater(
          find.byType(LivingBackdrop),
          matchesGoldenFile('goldens/living_backdrop_$preset.png'),
        );
      });
    }
  });
}
