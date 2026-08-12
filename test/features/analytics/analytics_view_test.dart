import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/core/config/label_mode.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/analytics/data/analytics_service.dart';
import 'package:froyou/features/analytics/presentation/analytics_view.dart';
import 'package:froyou/features/debug/data/seed_data.dart';
import 'package:froyou/features/journal/journal.dart';
import 'package:froyou/features/journal/presentation/journal_controller.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/features/profile/data/user_profile.dart';
import 'package:froyou/features/profile/presentation/profile_controller.dart';
import 'package:froyou/features/reminders/data/reminder_service.dart';
import 'package:froyou/generated/objectbox.g.dart';
import 'package:froyou/services/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/genai_mock.dart';
import '../../support/reminder_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Store store;
  late AppDatabase db;
  late JournalController journal;
  late ProfileController profile;
  late ReminderService reminders;
  int counter = 0;

  setUp(() async {
    // Both of these seed data and then assert on cluster labels, so they need
    // the statistical labeler that [kModelOnlyLabels] currently switches off
    // while the model path is being eyeballed on device.
    kModelOnlyLabels = false;
    // Fallback labelling, deterministically and without a round trip.
    mockGenAi(available: false);
    mockNotifications();
    SharedPreferences.setMockInitialValues({});
    store = Store(
      getObjectBoxModel(),
      directory: 'memory:analytics-test-${counter++}',
    );
    db = AppDatabase.forTesting(store);
    journal = JournalController(db.journalEntryDb);
    final profileStore = ProfileStore(await SharedPreferences.getInstance());
    reminders = ReminderService(store: profileStore, db: db.journalEntryDb);
    profile = ProfileController(
      store: profileStore,
      profile: const UserProfile(onboarded: true),
      themeSettings: ThemeSettings.defaults,
      platformBrightness: Brightness.light,
    );
  });

  tearDown(() {
    kModelOnlyLabels = true;
    unmockGenAi();
    unmockNotifications();
    journal.dispose();
    profile.dispose();
    reminders.dispose();
    store.close();
  });

  Widget harness() => AppScope(
    db: db,
    profile: profile,
    journal: journal,
    reminders: reminders,
    child: MaterialApp(
      theme: AppTheme.fromPalette(AppPalette.fallbackLight),
      home: const AnalyticsView(),
    ),
  );

  /// An entry with no embedding — what every Simulator log looks like.
  Future<void> addUnclustered(String text) async {
    final entry = JournalEntry()..rawText = text;
    entry.id = await db.journalEntryDb.putEntry(entry);
    await db.journalEntryDb.putSentenceInEntry(
      entry,
      JournalSentence()..text = text,
    );
  }

  testWidgets('under five logs asks for more instead of showing numbers', (
    tester,
  ) async {
    await addUnclustered('one');
    await addUnclustered('two');

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('No data yet. Please enter more logs'), findsOneWidget);
    expect(find.text('3 more to go.'), findsOneWidget);
    expect(find.textContaining('You talked about'), findsNothing);
  });

  testWidgets(
    'five logs with nothing clustered explains why there are no themes',
    (tester) async {
      for (var i = 0; i < 5; i++) {
        await addUnclustered('an unclustered thought number $i');
      }

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('No repeating themes yet'), findsOneWidget);
      expect(find.textContaining("You've logged 5 times"), findsOneWidget);
      // The log count is still shown — that part is real data.
      expect(find.text('5'), findsOneWidget);
      expect(find.text('logs so far'), findsOneWidget);
    },
  );

  testWidgets('renders real cluster labels, never a null one', (tester) async {
    final seeded = await DebugSeed.run(db.journalEntryDb);
    expect(seeded, greaterThanOrEqualTo(AnalyticsSnapshot.minimumLogs));

    // Data first: this is the failure the whole labeler exists to prevent.
    // ThemeCluster.label was only ever seeded from JournalSentence.keywords,
    // which nothing wrote — so every label was null and this screen read
    // "you talked about 'null' N times".
    final snapshot = AnalyticsService(db.journalEntryDb).compute();
    expect(snapshot.trends, isNotEmpty);
    for (final trend in snapshot.trends) {
      expect(trend.label.trim(), isNotEmpty);
      expect(trend.label, isNot('null'));
      expect(trend.occurrences, greaterThanOrEqualTo(2));
    }
    // The seed writes four distinct topics; "work" is the largest.
    expect(snapshot.trends.first.label, contains('work'));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // findRichText, because the trend rows emphasize the label with a nested
    // TextSpan rather than a plain Text.
    expect(
      find.textContaining('You talked about', findRichText: true),
      findsWidgets,
    );
    expect(find.text('$seeded'), findsOneWidget);
    expect(find.textContaining('null', findRichText: true), findsNothing);
  });

  testWidgets('each theme carries the user\'s own most central sentence', (
    tester,
  ) async {
    await DebugSeed.run(db.journalEntryDb);

    final snapshot = AnalyticsService(db.journalEntryDb).compute();
    expect(snapshot.trends, isNotEmpty);

    final allSentences = db.journalEntryDb
        .sentencesSince(DateTime(2000))
        .map((sentence) => sentence.text?.trim())
        .whereType<String>()
        .toSet();

    for (final trend in snapshot.trends) {
      // A two-word label is lossy by construction; this is what gives the
      // theme its context back, so it must always be there — and it must be
      // something the user actually wrote, not a synthesized summary.
      expect(trend.representative, isNotNull);
      expect(allSentences, contains(trend.representative));
    }

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(
      find.textContaining(snapshot.trends.first.representative!),
      findsOneWidget,
    );
  });

  testWidgets('counts distinct entries rather than sentences', (tester) async {
    // Two sentences about the same theme inside ONE entry is one *time* the
    // user talked about it, not two.
    final entry = JournalEntry()..rawText = 'two sentences, one entry';
    entry.id = await db.journalEntryDb.putEntry(entry);

    final vector = List<double>.filled(JournalEntryDb.embeddingDimensions, 0.0)
      ..[0] = 1.0;
    for (final text in ['work was heavy', 'work again later']) {
      await db.journalEntryDb.putSentenceInEntry(
        entry,
        JournalSentence()
          ..text = text
          ..embedding = List<double>.from(vector),
      );
    }

    final snapshot = AnalyticsService(db.journalEntryDb).compute();
    // One entry means one occurrence, which is below the "that's a pattern"
    // floor — so it should not be reported as a trend at all.
    expect(snapshot.trends, isEmpty);
  });
}
