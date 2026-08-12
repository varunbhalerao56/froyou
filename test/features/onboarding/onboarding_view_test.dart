import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/journal/presentation/journal_controller.dart';
import 'package:froyou/features/onboarding/onboarding_view.dart';
import 'package:froyou/features/profile/data/backdrop.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/features/profile/data/user_profile.dart';
import 'package:froyou/features/profile/presentation/profile_controller.dart';
import 'package:froyou/features/profile/presentation/widgets/backdrop_manager.dart';
import 'package:froyou/features/reminders/data/reminder_service.dart';
import 'package:froyou/generated/objectbox.g.dart';
import 'package:froyou/services/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/genai_mock.dart';
import '../../support/reminder_mock.dart';

/// Drives the paged intro.
///
/// The image step is seeded rather than exercised through the picker:
/// `addBackdrop` reaches `path_provider` for the app-support directory, and
/// that channel isn't there under test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Store store;
  late AppDatabase db;
  late JournalController journal;
  late ReminderService reminders;
  int counter = 0;

  setUp(() async {
    mockGenAi(available: false);
    mockNotifications();
    SharedPreferences.setMockInitialValues({});
    store = Store(
      getObjectBoxModel(),
      directory: 'memory:onboarding-test-${counter++}',
    );
    db = AppDatabase.forTesting(store);
    journal = JournalController(db.journalEntryDb);
    reminders = ReminderService(
      store: ProfileStore(await SharedPreferences.getInstance()),
      db: db.journalEntryDb,
    );
  });

  tearDown(() {
    unmockGenAi();
    unmockNotifications();
    journal.dispose();
    reminders.dispose();
    store.close();
  });

  Future<ProfileController> controllerFor(UserProfile profile) async {
    return ProfileController(
      store: ProfileStore(await SharedPreferences.getInstance()),
      profile: profile,
      themeSettings: ThemeSettings.defaults,
      platformBrightness: Brightness.light,
    );
  }

  Widget harness(ProfileController profile) => AppScope(
    db: db,
    profile: profile,
    journal: journal,
    reminders: reminders,
    child: MaterialApp(
      theme: AppTheme.fromPalette(AppPalette.fallbackLight),
      home: const OnboardingView(),
    ),
  );

  Future<void> advance(WidgetTester tester) async {
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }

  Finder continueButton() => find.widgetWithText(FilledButton, 'Continue');

  testWidgets('walks the value screens to the image step', (tester) async {
    final profile = await controllerFor(const UserProfile());
    addTearDown(profile.dispose);

    await tester.pumpWidget(harness(profile));
    await tester.pumpAndSettle();

    expect(find.text('Say what’s on your mind.'), findsOneWidget);
    await advance(tester);
    expect(find.text('Everything stays on this device.'), findsOneWidget);
    await advance(tester);
    expect(find.text('A companion, not a replacement.'), findsOneWidget);
    await advance(tester);

    // The same control Settings uses, so setup and editing can't drift apart.
    expect(find.byType(BackdropManager), findsOneWidget);
  });

  testWidgets('the image step blocks both the button and the swipe', (
    tester,
  ) async {
    final profile = await controllerFor(const UserProfile());
    addTearDown(profile.dispose);

    await tester.pumpWidget(harness(profile));
    await tester.pumpAndSettle();
    await advance(tester);
    await advance(tester);
    await advance(tester);

    expect(tester.widget<FilledButton>(continueButton()).onPressed, isNull);

    // Swiping must be blocked too, or the one required step is bypassed by a
    // gesture and the last page offers to record over an unconfigured home.
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropManager), findsOneWidget);
  });

  testWidgets('with an image, the last step offers the guided log', (
    tester,
  ) async {
    final profile = await controllerFor(
      const UserProfile(backdrops: [Backdrop(imagePath: 'missing.jpg')]),
    );
    addTearDown(profile.dispose);

    await tester.pumpWidget(harness(profile));
    await tester.pumpAndSettle();
    await advance(tester);
    await advance(tester);
    await advance(tester);

    expect(tester.widget<FilledButton>(continueButton()).onPressed, isNotNull);
    await advance(tester);

    expect(find.text('Try your first log.'), findsOneWidget);
    expect(find.text('Record my first log'), findsOneWidget);
    expect(find.text('Maybe later'), findsOneWidget);
  });

  testWidgets('recording the first log finishes and asks Home to open voice', (
    tester,
  ) async {
    final profile = await controllerFor(
      const UserProfile(backdrops: [Backdrop(imagePath: 'missing.jpg')]),
    );
    addTearDown(profile.dispose);

    await tester.pumpWidget(harness(profile));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await advance(tester);
    }

    await tester.tap(find.text('Record my first log'));
    await tester.pumpAndSettle();

    expect(profile.profile.onboarded, isTrue);
    expect(profile.profile.guidedLogDone, isTrue);
    expect(profile.consumeGuidedLogRequest(), isTrue);
    // Single-shot: a rebuild must not reopen the recorder over someone who has
    // already started typing.
    expect(profile.consumeGuidedLogRequest(), isFalse);
  });

  testWidgets('skipping finishes without asking Home to record', (tester) async {
    final profile = await controllerFor(
      const UserProfile(backdrops: [Backdrop(imagePath: 'missing.jpg')]),
    );
    addTearDown(profile.dispose);

    await tester.pumpWidget(harness(profile));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await advance(tester);
    }

    await tester.tap(find.text('Maybe later'));
    await tester.pumpAndSettle();

    expect(profile.profile.onboarded, isTrue);
    expect(profile.profile.guidedLogDone, isTrue);
    expect(profile.consumeGuidedLogRequest(), isFalse);
  });

  group('guidedLogDone', () {
    test('defaults to onboarded for records written before the flag', () {
      // Nobody already using the app should be ambushed with a first-run
      // prompt on the launch after an update.
      final existing = UserProfile.fromJson(const {
        'backdrops': <Object?>[],
        'onboarded': true,
      });
      expect(existing.guidedLogDone, isTrue);

      final fresh = UserProfile.fromJson(const {'backdrops': <Object?>[]});
      expect(fresh.guidedLogDone, isFalse);
    });

    test('round-trips once written', () {
      const profile = UserProfile(onboarded: true, guidedLogDone: false);
      expect(UserProfile.fromJson(profile.toJson()).guidedLogDone, isFalse);
    });
  });
}
