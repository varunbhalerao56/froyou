import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/illustration.dart';
import 'package:froyou/features/onboarding/widgets/onboarding_page.dart';

import '../../support/test_fonts.dart';

/// How the intro's drawings actually sit on the page.
///
/// The recolouring has its own tests and they pass on numbers — no role left
/// behind, ink separated from the page. None of that says whether the result
/// looks like it belongs, which is the only question worth asking about
/// borrowed artwork.
///
/// **Both brightnesses go side by side, in one tree.** A duotone anchored to
/// the wrong end of the ramp is perfectly handsome in light mode and a smear in
/// dark, so reviewing either alone is how that ships.
///
/// **And all of it is one `testWidgets`, which is not tidiness.**
/// `vector_graphics` keeps a process-wide static cache of decoded pictures,
/// refcounted by widget lifetime. `testWidgets` disposes the binding between
/// tests without unmounting the tree, so a picture decoded by one test is left
/// in that cache with a live refcount, disposed along with the binding, and
/// then handed to the next test — which paints a disposed picture and draws
/// nothing at all. Silently, and only for whichever drawing the earlier test
/// happened to use, which is about as quiet as a failure gets.
///
/// Two things that look like they would fix that and do not: `svg.cache.clear`,
/// which holds decoded *bytes*, a layer above the pictures; and unmounting via
/// `addTearDown`, which runs too late to matter. Staying inside one binding
/// sidesteps it, and is also the arrangement the app actually has — several
/// drawings alive at once in one tree.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppFonts);

  AppPalette paletteFor(ThemeBrightnessMode mode) => AppPalette.fromSettings(
    ThemeSettings(brightnessMode: mode),
    Brightness.light,
  );

  /// One themed panel laid beside its opposite.
  Widget beside(Widget child) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Row(
      children: [
        for (final mode in ThemeBrightnessMode.values)
          if (mode != ThemeBrightnessMode.system)
            Expanded(
              child: Theme(
                data: AppTheme.fromPalette(paletteFor(mode)),
                // Material rather than a ColoredBox: without one in the
                // ancestry every Text falls back to MaterialApp's error style
                // and the golden comes out in yellow underlines.
                child: Material(
                  color: paletteFor(mode).colors.background,
                  child: child,
                ),
              ),
            ),
      ],
    ),
  );

  testWidgets('the intro artwork, light beside dark', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> capture(Size size, Widget child, String golden) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(beside(child));
      // The bundle read, then the cross-fade the drawing arrives on.
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(Row).first,
        matchesGoldenFile('goldens/$golden.png'),
      );
    }

    await capture(
      const Size(786, 800),
      const OnboardingPage(
        illustration: Illustration.reflection,
        title: 'Say what’s on your mind.',
        body:
            'Talk or type, whenever it helps. Froyou keeps what you say and '
            'notices what you keep coming back to — even when the words come '
            'out differently every time.',
      ),
      'onboarding_page',
    );

    // Eight pictures from eight distinct strings. This is where an asset that
    // quietly stopped resolving shows up as an empty cell, and where a cache
    // keyed on anything coarser than the SVG shows up as a repeated drawing.
    await capture(
      const Size(786, 620),
      Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          spacing: AppSpacing.md,
          children: [
            for (final art in Illustration.values)
              Expanded(child: IllustrationView(illustration: art)),
          ],
        ),
      ),
      'illustrations',
    );
  });
}
