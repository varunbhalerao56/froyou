import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/home/presentation/backdrop_carousel.dart';
import 'package:froyou/features/home/presentation/compose_controller.dart';
import 'package:froyou/features/home/presentation/home_layout.dart';
import 'package:froyou/features/home/presentation/home_pane.dart';
import 'package:froyou/features/profile/data/backdrop.dart';

import '../../support/test_fonts.dart';

/// Pins the Home pane's layout at both ends of the compose animation.
///
/// Specifically here to catch the two things that went wrong on device and
/// that no assertion would have caught: the caption sliding under the status
/// bar, and the compose field parking at the top of its region instead of the
/// middle. Regenerate with `flutter test --update-goldens`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppFonts);

  /// A realistic iPhone status-bar inset. The shell runs edge to edge on
  /// purpose, so the pane has to inset its own content — this is what proves
  /// it does.
  const topInset = 59.0;

  Widget frame({
    required ComposeController compose,
    required double height,
    HomeLayout layout = HomeLayout.classic,
    ImageProvider provider = const AssetImage('missing.jpg'),
    String prompt = 'How are you feeling?',
  }) {
    final palette = AppPalette.fromSettings(
      const ThemeSettings(brightnessMode: ThemeBrightnessMode.light),
      Brightness.light,
    );

    const backdrops = [
      Backdrop(
        // Doesn't resolve on purpose: EdgeGlowImage falls back to its themed
        // placeholder, which keeps the golden about layout rather than about
        // whatever photo happened to be around.
        imagePath: 'missing.jpg',
        caption: 'Be curious, not judgemental',
      ),
    ];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromPalette(palette),
      home: MediaQuery(
        // The size matters as well as the inset: the pane measures the prompt
        // against the screen's width to decide how many lines to reserve for
        // it, and a zero-size MediaQuery makes that question unanswerable.
        data: const MediaQueryData(
          size: Size(393, 852),
          padding: EdgeInsets.only(top: topInset),
        ),
        child: Scaffold(
          backgroundColor: palette.colors.background,
          body: HomePane(
            height: height,
            compose: compose,
            palette: palette,
            backdrops: backdrops,
            providerFor: (_) => provider,
            rotation: BackdropRotation(
              index: 0,
              count: 1,
              next: () {},
              previous: () {},
            ),
            prompt: prompt,
            chromeOpacity: ValueNotifier<double>(1),
            layout: layout,
            // The backdrop's slow scale never reaches a resting frame, and a
            // golden is a resting frame.
            breathe: false,
          ),
        ),
      ),
    );
  }

  /// The drift animation never stops by design, so settling is impossible.
  Future<void> pump(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('at rest: caption above the image, prompt below', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final compose = ComposeController(
      vsync: const TestVSync(),
      onSave: (_) async {},
    );
    addTearDown(compose.dispose);

    await tester.pumpWidget(frame(compose: compose, height: 852));
    await pump(tester);

    // The caption must clear the status bar rather than run under the clock.
    expect(
      tester.getTopLeft(find.text('Be curious, not judgemental')).dy,
      greaterThanOrEqualTo(topInset),
    );

    await expectLater(
      find.byType(HomePane),
      matchesGoldenFile('goldens/home_pane_idle.png'),
    );
  });

  testWidgets(
    'composing: chrome gone, field centred and below the status bar',
    (tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final compose = ComposeController(
        vsync: const TestVSync(),
        onSave: (_) async {},
      );
      addTearDown(compose.dispose);
      compose.expand.value = 1;

      await tester.pumpWidget(frame(compose: compose, height: 852));
      await pump(tester);

      // Everything that competes with the text is gone.
      expect(find.text('Be curious, not judgemental'), findsNothing);
      expect(find.text('How are you feeling?'), findsNothing);

      final field = find.byType(TextField);
      expect(field, findsOneWidget);

      final top = tester.getTopLeft(field).dy;
      final bottom = tester.getBottomLeft(field).dy;

      expect(top, greaterThan(topInset), reason: 'must clear the status bar');
      // Roughly centred in the pane rather than pinned to the top — the bug was
      // an unbounded OverflowBox leaving the centre undefined.
      expect(
        (top + bottom) / 2,
        closeTo(852 / 2, 140),
        reason: 'the field should sit near the middle of the pane',
      );

      await expectLater(
        find.byType(HomePane),
        matchesGoldenFile('goldens/home_pane_composing.png'),
      );
    },
  );

  /// The edge dissolve, against an actual photograph.
  ///
  /// Every other golden here uses an unresolvable path so the themed
  /// placeholder renders, which keeps them about layout — but a flat gradient
  /// cannot show whether the picture melts into the page or stops at a line,
  /// and stopping at a line is exactly the bug this pins.
  testWidgets('a real photo dissolves into the page at both edges', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final compose = ComposeController(
      vsync: const TestVSync(),
      onSave: (_) async {},
    );
    addTearDown(compose.dispose);

    final photo = FileImage(File('test/fixtures/backdrop.jpg'));
    // Decoding is real async work that the fake clock cannot advance, so it
    // has to happen outside the test's zone or the image never arrives and
    // the golden captures an empty frame.
    await tester.runAsync(() async {
      await precacheImage(photo, tester.binding.rootElement!);
    });

    for (final layout in [HomeLayout.classic]) {
      await tester.pumpWidget(
        frame(compose: compose, height: 852, provider: photo, layout: layout),
      );
      await pump(tester);

      await expectLater(
        find.byType(HomePane),
        matchesGoldenFile('goldens/home_pane_photo_${layout.name}.png'),
      );
    }
  });

  testWidgets('a long follow-up takes a third line rather than an ellipsis', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final compose = ComposeController(
      vsync: const TestVSync(),
      onSave: (_) async {},
    );
    addTearDown(compose.dispose);

    // Long enough to need three lines at the prompt's size, which a real
    // generated follow-up regularly is.
    const long =
        'You came back to the deadline again tonight — is it the work '
        'itself that feels heavy, or the way it keeps landing on the same '
        'evening every week?';

    await tester.pumpWidget(frame(compose: compose, height: 852));
    await pump(tester);
    final withShort = tester.getSize(find.byType(BackdropCarousel)).height;

    await tester.pumpWidget(frame(compose: compose, height: 852, prompt: long));
    await pump(tester);
    final withLong = tester.getSize(find.byType(BackdropCarousel)).height;

    // Three lines of it, not two and an ellipsis.
    expect(tester.widget<Text>(find.text(long)).maxLines, 3);
    expect(
      tester.getSize(find.text(long)).height,
      greaterThan(80),
      reason: 'two lines of this style is about 59 points',
    );

    // The slot grew to hold it and the picture gave up the difference, which
    // is the only place the room can come from — the pane owes its height
    // whatever is in it.
    expect(withLong, lessThan(withShort));
    expect(tester.getSize(find.byType(HomePane)).height, 852);
  });

  // One per variant, at rest. The invariants asserted here are the ones every
  // arrangement owes regardless of how it looks: the pane is exactly its given
  // height, and nothing runs under the status bar.
  for (final layout in HomeLayout.values) {
    testWidgets('layout: ${layout.label}', (tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final compose = ComposeController(
        vsync: const TestVSync(),
        onSave: (_) async {},
      );
      addTearDown(compose.dispose);

      await tester.pumpWidget(
        frame(compose: compose, height: 852, layout: layout),
      );
      await pump(tester);

      expect(
        tester.getSize(find.byType(HomePane)).height,
        852,
        reason: 'every variant owes the pane-height invariant',
      );

      // centred draws no image at all, and typeFirst puts the prompt above it,
      // so the caption is the only text common to all five.
      if (layout != HomeLayout.typeFirst) {
        expect(
          tester.getTopLeft(find.text('Be curious, not judgemental')).dy,
          greaterThanOrEqualTo(topInset),
          reason: 'content must clear the status bar',
        );
      }

      await expectLater(
        find.byType(HomePane),
        matchesGoldenFile('goldens/home_pane_${layout.name}.png'),
      );
    });
  }
}
