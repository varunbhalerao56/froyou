import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/journal/presentation/journal_controller.dart';
import 'package:froyou/features/profile/data/backdrop.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/features/profile/data/user_profile.dart';
import 'package:froyou/features/profile/presentation/profile_controller.dart';
import 'package:froyou/features/profile/presentation/settings_view.dart';
import 'package:froyou/features/reminders/data/reminder_service.dart';
import 'package:froyou/generated/objectbox.g.dart';
import 'package:froyou/services/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/genai_mock.dart';
import '../../support/reminder_mock.dart';
import '../../support/test_fonts.dart';

/// Pins Settings in both brightnesses.
///
/// Two things here only a rendered image can check: that each setting reads as
/// its own card rather than as one undifferentiated column, and that dark mode
/// has actual colour in it — the failure being a page of near-black cards on a
/// near-black background with a grey accent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppFonts);

  late Store store;
  late AppDatabase db;
  late ProfileStore profileStore;
  int counter = 0;

  setUp(() async {
    mockGenAi(available: false);
    mockNotifications();
    SharedPreferences.setMockInitialValues({});
    store = Store(
      getObjectBoxModel(),
      directory: 'memory:settings-golden-${counter++}',
    );
    db = AppDatabase.forTesting(store);
    profileStore = ProfileStore(await SharedPreferences.getInstance());
  });

  tearDown(() {
    unmockGenAi();
    unmockNotifications();
    store.close();
  });

  for (final mode in [ThemeBrightnessMode.light, ThemeBrightnessMode.dark]) {
    testWidgets('settings, ${mode.name}', (tester) async {
      tester.view.physicalSize = const Size(1179, 3000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await profileStore.setString(
        ReminderService.settingsKey,
        jsonEncode(const {'enabled': true, 'minutesFromMidnight': 21 * 60}),
      );

      // Scoped to init and undone before the body ends — the binding asserts
      // that no foundation debug variable outlives a test.
      useIosNotificationPlatform();
      final reminders = ReminderService(
        store: profileStore,
        db: db.journalEntryDb,
      );
      await reminders.init();
      debugDefaultTargetPlatformOverride = null;
      addTearDown(reminders.dispose);

      final profile = ProfileController(
        store: profileStore,
        profile: const UserProfile(
          onboarded: true,
          backdrops: [
            Backdrop(
              imagePath: 'missing.jpg',
              caption: 'Be curious, not judgemental',
            ),
          ],
        ),
        themeSettings: ThemeSettings(presetId: 'dusk', brightnessMode: mode),
        platformBrightness: Brightness.light,
      );
      addTearDown(profile.dispose);

      final journal = JournalController(db.journalEntryDb);
      addTearDown(journal.dispose);

      await tester.pumpWidget(
        AppScope(
          db: db,
          profile: profile,
          journal: journal,
          reminders: reminders,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.fromPalette(profile.palette),
            home: const SettingsView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(SettingsView),
        matchesGoldenFile('goldens/settings_${mode.name}.png'),
      );
    });
  }
}
