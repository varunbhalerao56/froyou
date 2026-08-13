import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/backdrop_photo.dart';
import 'package:froyou/core/ui/edge_glow_image.dart';
import 'package:froyou/features/profile/data/backdrop.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/features/profile/data/user_profile.dart';
import 'package:froyou/features/profile/presentation/profile_controller.dart';
import 'package:froyou/features/profile/presentation/widgets/backdrop_framing_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // A phone-shaped pane and a square photograph, which is all it takes to show
  // why this exists.
  const pane = Size(393, 852);
  const square = Size(1600, 1600);

  group('placement', () {
    test('filling the pane overflows sideways and not at all downward', () {
      final rect = backdropPlacement(
        image: square,
        box: pane,
        fit: BoxFit.cover,
        zoom: 1,
        offset: Offset.zero,
      );

      // This is the whole bug the framing editor replaced. The pane is far
      // taller than it is wide, so covering it is decided by the *height* —
      // and the photo then hangs over the sides by 459 points and over the top
      // and bottom by nothing. An Alignment, which was the only control there
      // used to be, moves an image within its overflow. There wasn't any.
      expect(rect.height, pane.height);
      expect(rect.top, 0);
      expect(rect.bottom, pane.height);
      expect(rect.width, greaterThan(pane.width));
      expect(rect.left, lessThan(0));
    });

    test('the whole picture leaves the gap the extended blur fills', () {
      final rect = backdropPlacement(
        image: square,
        box: pane,
        fit: BoxFit.contain,
        zoom: 1,
        offset: Offset.zero,
      );

      expect(rect.width, pane.width);
      expect(rect.height, pane.width);
      expect(rect.top, greaterThan(0));
      expect(rect.bottom, lessThan(pane.height));
    });

    test('zoom multiplies the baseline', () {
      final once = backdropPlacement(
        image: square,
        box: pane,
        fit: BoxFit.contain,
        zoom: 1,
        offset: Offset.zero,
      );
      final twice = backdropPlacement(
        image: square,
        box: pane,
        fit: BoxFit.contain,
        zoom: 2,
        offset: Offset.zero,
      );

      expect(twice.width, once.width * 2);
      expect(twice.height, once.height * 2);
      expect(twice.center, once.center, reason: 'zoom is about the centre');
    });

    test('the whole picture is fitted to what stays sharp', () {
      // Tall enough that the height binds, which is when it matters.
      const tall = Size(600, 800);
      final fadeTop = pane.height * EdgeGlowImage.defaultTopBlurFadeEnd;
      final fadeBottom =
          pane.height * EdgeGlowImage.defaultBottomBlurFadeStart;

      final toThePane = backdropPlacement(
        image: tall,
        box: pane,
        fit: BoxFit.contain,
        zoom: 1,
        offset: Offset.zero,
      );
      final toTheSharpBand = backdropPlacement(
        image: tall,
        box: pane,
        fit: BoxFit.contain,
        zoom: 1,
        offset: Offset.zero,
        sharpInsets: EdgeGlowImage.defaultSharpInsets,
      );

      // Fitted to the pane, both ends of the picture run into the dissolve —
      // all of it is there and its ends are washed out, which is not what
      // "the whole picture" says.
      expect(toThePane.top, lessThan(fadeTop));
      expect(toThePane.bottom, greaterThan(fadeBottom));

      expect(toTheSharpBand.top, closeTo(fadeTop, 0.01));
      expect(toTheSharpBand.bottom, closeTo(fadeBottom, 0.01));
    });

    test('filling still fills — the sharp band is not its business', () {
      final framed = backdropPlacement(
        image: square,
        box: pane,
        fit: BoxFit.cover,
        zoom: 1,
        offset: Offset.zero,
        sharpInsets: EdgeGlowImage.defaultSharpInsets,
      );

      expect(framed.top, 0);
      expect(framed.bottom, pane.height);
    });

    test('the offsets are fractions of the pane, not of the picture', () {
      final moved = backdropPlacement(
        image: square,
        box: pane,
        fit: BoxFit.cover,
        zoom: 1,
        offset: const Offset(0.25, -0.1),
      );

      expect(moved.center.dx, closeTo(pane.width / 2 + 0.25 * 393, 0.001));
      expect(moved.center.dy, closeTo(pane.height / 2 - 0.1 * 852, 0.001));
    });
  });

  group('storage', () {
    test('framing round-trips through JSON', () {
      const backdrop = Backdrop(
        imagePath: 'backdrop_1.jpg',
        caption: 'A window',
        framing: BackdropFraming(
          fit: BackdropFit.whole,
          zoom: 1.8,
          offsetX: -0.2,
          offsetY: 0.35,
        ),
      );

      final restored = Backdrop.tryFromJson(backdrop.toJson())!;

      expect(restored.framing, backdrop.framing);
      expect(restored.caption, 'A window');
    });

    test('a backdrop stored before framing existed gets the old behaviour', () {
      // Exactly what older builds wrote, focusY and all. Fill, centred, at the
      // baseline is what every backdrop already did, so these defaults are not
      // a choice — they are the absence of one.
      final restored = Backdrop.tryFromJson({
        'imagePath': 'backdrop_1.jpg',
        'caption': null,
        'fit': 'fill',
        'focusY': -0.6,
      })!;

      expect(restored.framing, BackdropFraming.initial);
    });

    test('an unknown fit falls back rather than throwing', () {
      final restored = Backdrop.tryFromJson({
        'imagePath': 'backdrop_1.jpg',
        'fit': 'someFutureMode',
      })!;

      expect(restored.framing.fit, BackdropFit.fill);
    });

    test('values out of range are clamped, not trusted', () {
      final restored = Backdrop.tryFromJson({
        'imagePath': 'backdrop_1.jpg',
        'zoom': 0.2,
        'offsetX': 42,
        'offsetY': double.nan,
      })!;

      expect(restored.framing.zoom, 1, reason: 'below the baseline is nowhere');
      expect(restored.framing.offsetX, BackdropFraming.maxOffset);
      expect(restored.framing.offsetY, 0);
    });

    test('naming a picture leaves how it sits alone', () async {
      // Captions used to be written by rebuilding the Backdrop from its path,
      // which silently reset the framing with it.
      SharedPreferences.setMockInitialValues({});
      final controller = ProfileController(
        store: ProfileStore(await SharedPreferences.getInstance()),
        profile: const UserProfile(
          backdrops: [
            Backdrop(
              imagePath: 'a.jpg',
              framing: BackdropFraming(fit: BackdropFit.whole, zoom: 2.5),
            ),
          ],
        ),
        themeSettings: ThemeSettings.defaults,
        platformBrightness: Brightness.light,
      );
      addTearDown(controller.dispose);

      await controller.setCaption(0, 'A window');

      expect(controller.backdrops.first.caption, 'A window');
      expect(controller.backdrops.first.framing.zoom, 2.5);
      expect(controller.backdrops.first.framing.fit, BackdropFit.whole);
    });
  });

  group('the editor', () {
    // Resolved in setUp, which runs outside the fake clock. Awaiting the
    // preferences channel *inside* a testWidgets body deadlocks: the reply
    // needs the event loop turned, and nothing turns it until the first pump,
    // which is on the other side of the await.
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    ProfileController controllerWith(BackdropFraming framing) {
      return ProfileController(
        // With no backdrop directory resolved — there isn't one under test —
        // the store hands back the name it was given, so this reads the
        // fixture straight from the repo.
        store: ProfileStore(prefs),
        profile: UserProfile(
          backdrops: [
            Backdrop(imagePath: 'test/fixtures/backdrop.jpg', framing: framing),
          ],
        ),
        themeSettings: ThemeSettings.defaults,
        platformBrightness: Brightness.light,
      );
    }

    // The theme is fixed across both pumps on purpose. Swapping a bare
    // MaterialApp for a themed one animates between them, and Material's own
    // labelLarge carries `inherit: false` — which asserts halfway through the
    // lerp, before any of this gets a chance to be tested.
    Widget harness(Widget home) => MaterialApp(
      theme: AppTheme.fromPalette(AppPalette.fallbackLight),
      home: home,
    );

    /// Decoding is real async work the fake clock cannot advance, so it has to
    /// happen outside the test's zone or the editor never learns how big the
    /// picture is and has nothing to clamp against.
    ///
    /// It also has to happen **before** the editor is on screen. Mounting it
    /// first starts the same load inside the fake zone, and awaiting that from
    /// a `runAsync` block deadlocks: finishing the decode needs a pump, and
    /// the pump is on the far side of the await.
    Future<void> settle(WidgetTester tester, ProfileController profile) async {
      // A phone, not the 800×600 landscape default. The preview takes the
      // screen's own proportions, and on a wide one a square photo overflows
      // in both directions — which is the one shape that hides the bug.
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(harness(const SizedBox.shrink()));
      await tester.runAsync(() async {
        await precacheImage(
          profile.providerFor(profile.backdrops.first),
          tester.binding.rootElement!,
        );
      });
      await tester.pumpWidget(
        harness(BackdropFramingView(profile: profile, index: 0)),
      );
      await tester.pump();
    }

    testWidgets('dragging moves the picture and stores it on lift', (
      tester,
    ) async {
      final profile = controllerWith(BackdropFraming.initial);
      addTearDown(profile.dispose);
      await settle(tester, profile);

      final preview = find.byType(BackdropFramingView);
      await tester.timedDrag(
        preview,
        const Offset(-80, 0),
        const Duration(milliseconds: 200),
      );
      await tester.pump();

      final framing = profile.backdrops.first.framing;
      expect(
        framing.offsetX,
        lessThan(0),
        reason: 'dragging left shows what was off the right edge',
      );
      expect(framing.zoom, 1, reason: 'one finger does not zoom');
    });

    testWidgets('a drag stops where the picture does', (tester) async {
      // Filling the pane with a square photo leaves nothing hanging over the
      // top or the bottom, so there is nothing to drag into vertically — and
      // the clamp has to say so rather than sliding the picture off the pane.
      final profile = controllerWith(BackdropFraming.initial);
      addTearDown(profile.dispose);
      await settle(tester, profile);

      await tester.timedDrag(
        find.byType(BackdropFramingView),
        const Offset(0, -400),
        const Duration(milliseconds: 200),
      );
      await tester.pump();

      expect(profile.backdrops.first.framing.offsetY, 0);
    });

    testWidgets('a picture that falls short can still be nudged', (
      tester,
    ) async {
      // The other side of the same rule. Under "Whole picture" there is empty
      // pane above and below, and the extended blur is what fills it — so
      // letting the picture sit a little high costs nothing and is often the
      // composition someone wants.
      final profile = controllerWith(
        const BackdropFraming(fit: BackdropFit.whole),
      );
      addTearDown(profile.dispose);
      await settle(tester, profile);

      await tester.timedDrag(
        find.byType(BackdropFramingView),
        const Offset(0, -400),
        const Duration(milliseconds: 200),
      );
      await tester.pump();

      expect(profile.backdrops.first.framing.offsetY, lessThan(0));
      expect(profile.backdrops.first.framing.offsetY, greaterThan(-0.2));
    });

    testWidgets('choosing a baseline starts over', (tester) async {
      final profile = controllerWith(
        const BackdropFraming(zoom: 2.2, offsetX: 0.4),
      );
      addTearDown(profile.dispose);
      await settle(tester, profile);

      await tester.tap(find.text(BackdropFit.whole.label));
      await tester.pump();

      expect(
        profile.backdrops.first.framing,
        const BackdropFraming(fit: BackdropFit.whole),
      );
    });
  });
}
