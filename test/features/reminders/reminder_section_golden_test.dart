import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/features/reminders/data/reminder_service.dart';
import 'package:froyou/features/reminders/presentation/reminder_section.dart';
import 'package:froyou/generated/objectbox.g.dart';
import 'package:froyou/services/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/reminder_mock.dart';
import '../../support/test_fonts.dart';

/// Pins the reminders section.
///
/// It is the one place in Settings built on borrowed controls — a Cupertino
/// time picker and a hand-rolled pill row — so "does it still look like this
/// app" is exactly the question a golden should be answering.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadAppFonts);

  late Store store;
  late AppDatabase db;
  late ProfileStore profileStore;
  int counter = 0;

  setUp(() async {
    mockNotifications();
    SharedPreferences.setMockInitialValues({});
    store = Store(
      getObjectBoxModel(),
      directory: 'memory:reminder-golden-${counter++}',
    );
    db = AppDatabase.forTesting(store);
    profileStore = ProfileStore(await SharedPreferences.getInstance());
  });

  tearDown(() {
    unmockNotifications();
    store.close();
  });

  /// The platform override is scoped to `init` alone, and undone before the
  /// test body ends — the binding asserts that no foundation debug variable
  /// outlives a test, and a `tearDown` runs too late to satisfy it. Nothing
  /// after `init` needs it: readiness is already a plain bool by then.
  Future<ReminderService> serviceWith({required bool enabled}) async {
    if (enabled) {
      await profileStore.setString(
        ReminderService.settingsKey,
        jsonEncode(const {'enabled': true, 'minutesFromMidnight': 21 * 60}),
      );
    }
    useIosNotificationPlatform();
    final reminders = ReminderService(
      store: profileStore,
      db: db.journalEntryDb,
    );
    await reminders.init();
    debugDefaultTargetPlatformOverride = null;
    return reminders;
  }

  Widget frame(ReminderService reminders) {
    final palette = AppPalette.fromSettings(
      const ThemeSettings(brightnessMode: ThemeBrightnessMode.light),
      Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromPalette(palette),
      home: Scaffold(
        backgroundColor: palette.colors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ReminderSection(reminders: reminders),
          ),
        ),
      ),
    );
  }

  for (final (name, enabled) in [('off', false), ('on', true)]) {
    testWidgets('reminders $name', (tester) async {
      // Tall enough for the section at its fullest — reminders on, with the
      // follow-up row and its copy below. Settings itself scrolls; this frame
      // does not, so it has to fit the whole thing or overflow.
      tester.view.physicalSize = const Size(1179, 1200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final reminders = await serviceWith(enabled: enabled);
      addTearDown(reminders.dispose);

      await tester.pumpWidget(frame(reminders));
      await tester.pumpAndSettle();

      expect(find.text('Daily'), findsOneWidget);
      // Two 'Off' cells once reminders are on — the daily nudge's, and the
      // follow-up's own pill row underneath it.
      expect(find.text('Off'), enabled ? findsNWidgets(2) : findsOneWidget);
      expect(
        find.text('Morning follow-up'),
        enabled ? findsOneWidget : findsNothing,
      );
      // The time only appears once reminders are on — an inert time row above
      // an off switch is the kind of dead control this section avoids.
      expect(find.text('Time'), enabled ? findsOneWidget : findsNothing);

      await expectLater(
        find.byType(ReminderSection),
        matchesGoldenFile('goldens/reminder_section_$name.png'),
      );
    });
  }
}
