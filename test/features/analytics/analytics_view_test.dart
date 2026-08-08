import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/analytics/data/analytics_service.dart';
import 'package:froyou/features/analytics/presentation/analytics_view.dart';
import 'package:froyou/features/debug/data/seed_data.dart';
import 'package:froyou/features/journal/journal.dart';
import 'package:froyou/features/journal/presentation/journal_controller.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/features/profile/data/user_profile.dart';
import 'package:froyou/features/profile/presentation/profile_controller.dart';
import 'package:froyou/generated/objectbox.g.dart';
import 'package:froyou/services/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Store store;
  late AppDatabase db;
  late JournalController journal;
  late ProfileController profile;
  int counter = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = Store(
      getObjectBoxModel(),
      directory: 'memory:analytics-test-${counter++}',
    );
    db = AppDatabase.forTesting(store);
    journal = JournalController(db.journalEntryDb);
    profile = ProfileController(
      store: ProfileStore(await SharedPreferences.getInstance()),
      profile: const UserProfile(quote: 'q', onboarded: true),
      palette: AppPalette.fallbackLight,
    );
  });

  tearDown(() {
    journal.dispose();
    profile.dispose();
    store.close();
  });

  Widget harness() => AppScope(
    db: db,
    profile: profile,
    journal: journal,
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

  testWidgets('five logs with nothing clustered explains why there are no themes', (
    tester,
  ) async {
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
  });

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
