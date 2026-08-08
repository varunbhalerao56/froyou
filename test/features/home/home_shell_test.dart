import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/edge_glow_image.dart';
import 'package:froyou/features/home/presentation/compose_box.dart';
import 'package:froyou/features/home/presentation/home_shell.dart';
import 'package:froyou/features/journal/presentation/journal_controller.dart';
import 'package:froyou/features/journal/presentation/log_card.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/features/profile/data/user_profile.dart';
import 'package:froyou/features/profile/presentation/profile_controller.dart';
import 'package:froyou/generated/objectbox.g.dart';
import 'package:froyou/services/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the real Home shell against a real ObjectBox store.
///
/// The native NLP channels are absent here, so enrichment fails exactly the
/// way it does in the Simulator — which makes this a direct test of the
/// promise that a log is never lost when the on-device NLP is unavailable.
///
/// Note: `pumpAndSettle` is unusable after a save. The newest log card shows an
/// indeterminate progress indicator while enrichment runs, and an indeterminate
/// indicator never stops scheduling frames — so settling is by definition
/// impossible. Bounded pumps are the correct tool once one is on screen.
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
      directory: 'memory:home-shell-test-${counter++}',
    );
    db = AppDatabase.forTesting(store);
    journal = JournalController(db.journalEntryDb);
    profile = ProfileController(
      store: ProfileStore(await SharedPreferences.getInstance()),
      profile: const UserProfile(
        quote: 'Be Curious, Not Judgemental',
        onboarded: true,
      ),
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
      home: const HomeShell(),
    ),
  );

  testWidgets('shows the quote and the two compose controls at rest', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Be Curious, Not Judgemental'), findsOneWidget);
    expect(find.byTooltip('Record a log'), findsOneWidget);
    expect(find.byTooltip('Write a log'), findsOneWidget);
    expect(find.byType(ComposeBox), findsNothing);
  });

  testWidgets('the text control opens the compose box and shrinks the backdrop', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final backdropBefore = tester.getSize(find.byType(EdgeGlowImage)).height;

    await tester.tap(find.byTooltip('Write a log'));
    await tester.pumpAndSettle();

    final backdropAfter = tester.getSize(find.byType(EdgeGlowImage)).height;
    expect(
      backdropAfter,
      lessThan(backdropBefore),
      reason: 'the backdrop must give up height for the compose box',
    );

    expect(find.byType(ComposeBox), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // The field is focused, so the user can start typing straight away.
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(ComposeBox),
        matching: find.byType(TextField),
      ),
    );
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.readOnly, isFalse);
  });

  testWidgets('typing and saving persists the log and shows it in the list', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Write a log'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(ComposeBox),
        matching: find.byType(TextField),
      ),
      'Work has been sitting on me all week.',
    );
    await tester.pump();

    await tester.tap(find.text('Save'));
    await _pumpPastSave(tester);

    // Compose closed, entry persisted, list updated.
    expect(find.byType(ComposeBox), findsNothing);
    expect(db.journalEntryDb.countEntries(), 1);
    expect(journal.count, 1);
    expect(
      db.journalEntryDb.getAllEntries().single.rawText,
      'Work has been sitting on me all week.',
    );
  });

  testWidgets('the entry survives even though the NLP channels are absent', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Write a log'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(ComposeBox),
        matching: find.byType(TextField),
      ),
      'Nothing native is available in a widget test.',
    );
    await tester.pump(); // let canSave re-evaluate before tapping
    await tester.tap(find.text('Save'));
    await _pumpPastSave(tester);

    final entry = db.journalEntryDb.getAllEntries().single;
    expect(entry.rawText, 'Nothing native is available in a widget test.');
    // Phase 2 degraded: sentences stored, but unclustered and unembedded.
    expect(db.journalEntryDb.getAllThemeClusters(), isEmpty);
  });

  testWidgets('cancelling discards the draft without saving', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Write a log'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(ComposeBox),
        matching: find.byType(TextField),
      ),
      'second thoughts',
    );
    await tester.tap(find.text('Cancel'));
    await _pumpPastSave(tester);

    expect(find.byType(ComposeBox), findsNothing);
    expect(db.journalEntryDb.countEntries(), 0);
  });

  testWidgets('scrolling down reaches the logs bar and the saved logs', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await journal.save('An earlier thought about work.');
    await _pumpPastSave(tester);

    // Before scrolling, the logs bar is below the fold.
    expect(find.byType(LogCard), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await _pumpPastSave(tester);

    expect(find.textContaining('Your logs'), findsOneWidget);
    expect(find.byType(LogCard), findsOneWidget);
    expect(find.text('An earlier thought about work.'), findsOneWidget);
  });

  testWidgets('scrolling is locked while composing', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Write a log'));
    await tester.pumpAndSettle();

    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(scrollView.physics, isA<NeverScrollableScrollPhysics>());
  });
}

/// Advances past the expand/collapse animation and the settling scroll without
/// waiting for the enrichment spinner, which by design never stops.
Future<void> _pumpPastSave(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}
