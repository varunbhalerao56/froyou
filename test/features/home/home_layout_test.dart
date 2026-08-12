import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/home/presentation/home_layout.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/features/profile/data/user_profile.dart';
import 'package:froyou/features/profile/presentation/profile_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fromName', () {
    test('round-trips every variant', () {
      for (final layout in HomeLayout.values) {
        expect(HomeLayout.fromName(layout.name), layout);
      }
    });

    test('falls back to the shipped default rather than throwing', () {
      // A value written by a build whose variants have since been renamed must
      // not take the app down on the next launch.
      expect(HomeLayout.fromName('somethingElse'), HomeLayout.fullBleed);
      expect(HomeLayout.fromName(null), HomeLayout.fullBleed);
      expect(HomeLayout.fromName(''), HomeLayout.fullBleed);
    });
  });

  group('ProfileController', () {
    Future<ProfileController> build() async {
      final store = ProfileStore(await SharedPreferences.getInstance());
      return ProfileController(
        store: store,
        profile: const UserProfile(onboarded: true),
        themeSettings: ThemeSettings.defaults,
        platformBrightness: Brightness.light,
      );
    }

    test('defaults to full bleed on a fresh install', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = await build();
      addTearDown(controller.dispose);

      expect(controller.homeLayout, HomeLayout.fullBleed);
    });

    test('persists the choice and reads it back on the next launch', () async {
      SharedPreferences.setMockInitialValues({});
      final first = await build();
      addTearDown(first.dispose);

      var notified = 0;
      first.addListener(() => notified++);
      await first.setHomeLayout(HomeLayout.centred);

      // Notifies before persisting, so the shell recomposes immediately —
      // that is what makes switching from the debug menu feel live.
      expect(notified, 1);
      expect(first.homeLayout, HomeLayout.centred);

      // The constructor reads preferences directly, so a fresh controller over
      // the same store sees it without anything being threaded through boot.
      final second = await build();
      addTearDown(second.dispose);
      expect(second.homeLayout, HomeLayout.centred);
    });

    test('setting the current layout again does not notify', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = await build();
      addTearDown(controller.dispose);

      var notified = 0;
      controller.addListener(() => notified++);
      await controller.setHomeLayout(HomeLayout.fullBleed);

      expect(notified, 0);
    });

    test('an unknown stored value falls back without throwing', () async {
      SharedPreferences.setMockInitialValues({'home.layout': 'retiredVariant'});
      final controller = await build();
      addTearDown(controller.dispose);

      expect(controller.homeLayout, HomeLayout.fullBleed);
    });
  });
}
