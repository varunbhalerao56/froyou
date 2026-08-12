import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/edge_glow_image.dart';
import 'package:froyou/features/home/presentation/compose_box.dart';
import 'package:froyou/features/home/presentation/home_shell.dart';
import 'package:froyou/features/home/presentation/transcript_view.dart';
import 'package:froyou/features/journal/presentation/journal_controller.dart';
import 'package:froyou/features/journal/presentation/log_card.dart';
import 'package:froyou/features/profile/data/backdrop.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/features/profile/data/user_profile.dart';
import 'package:froyou/features/profile/presentation/profile_controller.dart';
import 'package:froyou/features/reminders/data/reminder_service.dart';
import 'package:froyou/generated/objectbox.g.dart';
import 'package:froyou/services/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/genai_mock.dart';
import '../../support/reminder_mock.dart';
import '../../support/speech_mock.dart';

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
  late ReminderService reminders;
  int counter = 0;

  setUp(() async {
    // Fallback labelling, deterministically and without a round trip.
    mockGenAi(available: false);
    // Unsupported, so the debug build routes to the canned speech source.
    mockSpeech(supported: false);
    mockNotifications();
    SharedPreferences.setMockInitialValues({});
    store = Store(
      getObjectBoxModel(),
      directory: 'memory:home-shell-test-${counter++}',
    );
    db = AppDatabase.forTesting(store);
    journal = JournalController(db.journalEntryDb);
    final profileStore = ProfileStore(await SharedPreferences.getInstance());
    // Never initialised here: Home doesn't touch it, and leaving it inert
    // keeps this suite off the notification channel entirely.
    reminders = ReminderService(store: profileStore, db: db.journalEntryDb);
    profile = ProfileController(
      store: profileStore,
      profile: const UserProfile(
        onboarded: true,
        backdrops: [
          // The path deliberately doesn't resolve; EdgeGlowImage falls back to
          // its themed placeholder, which is what we want under test anyway.
          Backdrop(
            imagePath: 'missing.jpg',
            caption: 'Be Curious, Not Judgemental',
          ),
        ],
      ),
      themeSettings: ThemeSettings.defaults,
      platformBrightness: Brightness.light,
    );
  });

  tearDown(() {
    unmockGenAi();
    unmockSpeech();
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
      home: const HomeShell(),
    ),
  );

  testWidgets('shows the caption, the prompt and the two controls at rest', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await _pumpHome(tester);

    expect(find.text('Be Curious, Not Judgemental'), findsOneWidget);
    expect(find.text(JournalController.defaultPrompt), findsOneWidget);
    expect(find.byTooltip('Record a log'), findsOneWidget);
    expect(find.byTooltip('Write a log'), findsOneWidget);
    expect(find.byType(ComposeBox), findsNothing);
  });

  testWidgets('the text control opens the compose box and clears the backdrop', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await _pumpHome(tester);

    expect(find.byType(EdgeGlowImage), findsWidgets);
    expect(find.text('Be Curious, Not Judgemental'), findsOneWidget);

    await tester.tap(find.byTooltip('Write a log'));
    await _pumpHome(tester);

    // The backdrop and its caption clear out completely rather than shrinking:
    // the point is to give the text the whole pane to breathe in, and a
    // half-collapsed photo still competes with it.
    expect(
      find.byType(EdgeGlowImage),
      findsNothing,
      reason: 'the backdrop must clear out entirely for the compose field',
    );
    expect(find.text('Be Curious, Not Judgemental'), findsNothing);
    expect(find.text(JournalController.defaultPrompt), findsNothing);

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

  testWidgets('recording shows the live transcript and hands off on stop', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await _pumpHome(tester);

    // The native speech channel is absent here, so `SpeechSource.resolve`
    // falls to the canned source in debug — which makes this the real voice
    // path, timers and all.
    await tester.tap(find.byTooltip('Record a log'));
    await _pumpHome(tester);

    expect(find.byType(TranscriptView), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ComposeBox),
        matching: find.byType(TextField),
      ),
      findsNothing,
      reason: 'the editable field is out of the tree while recording',
    );

    await tester.tap(find.text('Stop'));
    await _pumpHome(tester);

    expect(find.byType(TranscriptView), findsNothing);

    // Nothing is transferred at the seam: the controller has been writing the
    // field's value all along, so the dictated words are simply already there.
    final dictated = tester.widget<TextField>(
      find.descendant(
        of: find.byType(ComposeBox),
        matching: find.byType(TextField),
      ),
    );
    expect(dictated.readOnly, isFalse);
    expect(dictated.controller!.text, isNotEmpty);
  });

  testWidgets('the guided first log opens the recorder on arrival', (
    tester,
  ) async {
    // What finishing onboarding with "Record my first log" leaves behind.
    await profile.completeOnboarding(startRecording: true);

    await tester.pumpWidget(harness());
    await _pumpHome(tester);

    // The permission prompt lands seconds after the page that explained it,
    // rather than cold on a screen the user hasn't seen yet.
    expect(find.byType(TranscriptView), findsOneWidget);

    // End the session: the canned source drives a periodic timer, and leaving
    // it running trips the binding's pending-timer check at teardown.
    await tester.tap(find.text('Stop'));
    await _pumpHome(tester);
  });

  testWidgets('an ordinary launch does not open the recorder', (tester) async {
    await tester.pumpWidget(harness());
    await _pumpHome(tester);

    expect(find.byType(TranscriptView), findsNothing);
    expect(find.byType(ComposeBox), findsNothing);
  });

  testWidgets('typing and saving persists the log and shows it in the list', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await _pumpHome(tester);

    await tester.tap(find.byTooltip('Write a log'));
    await _pumpHome(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(ComposeBox),
        matching: find.byType(TextField),
      ),
      'Work has been sitting on me all week.',
    );
    await tester.pump();

    await tester.tap(find.text('Save'));
    await _pumpHome(tester);

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
    await _pumpHome(tester);

    await tester.tap(find.byTooltip('Write a log'));
    await _pumpHome(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(ComposeBox),
        matching: find.byType(TextField),
      ),
      'Nothing native is available in a widget test.',
    );
    await tester.pump(); // let canSave re-evaluate before tapping
    await tester.tap(find.text('Save'));
    await _pumpHome(tester);

    final entry = db.journalEntryDb.getAllEntries().single;
    expect(entry.rawText, 'Nothing native is available in a widget test.');
    // Phase 2 degraded: sentences stored, but unclustered and unembedded.
    expect(db.journalEntryDb.getAllThemeClusters(), isEmpty);
  });

  testWidgets('cancelling discards the draft without saving', (tester) async {
    await tester.pumpWidget(harness());
    await _pumpHome(tester);

    await tester.tap(find.byTooltip('Write a log'));
    await _pumpHome(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(ComposeBox),
        matching: find.byType(TextField),
      ),
      'second thoughts',
    );
    await tester.tap(find.text('Cancel'));
    await _pumpHome(tester);

    expect(find.byType(ComposeBox), findsNothing);
    expect(db.journalEntryDb.countEntries(), 0);
  });

  testWidgets('scrolling down reaches the logs bar and the saved logs', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await _pumpHome(tester);

    await journal.save('An earlier thought about work.');
    await _pumpHome(tester);

    // Before scrolling, the logs bar is below the fold.
    expect(find.byType(LogCard), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await _pumpHome(tester);

    expect(find.textContaining('Your logs'), findsOneWidget);
    expect(find.byType(LogCard), findsOneWidget);
    expect(find.text('An earlier thought about work.'), findsOneWidget);
  });

  testWidgets('the compose field survives the whole open, keyboard and all', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await _pumpHome(tester);

    await tester.tap(find.byTooltip('Write a log'));

    // The field's own state object, not the focus node — the node belongs to
    // the controller and survives anything. What the keyboard is actually tied
    // to is the EditableText: dispose it and the platform input connection
    // goes with it, so the keyboard slides back down mid-open having only just
    // arrived. That is what happened when the pane swapped its root widget
    // from a Stack to the bare column once the chrome finished collapsing.
    int? first;
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      final editable = find.byType(EditableText).evaluate();
      if (editable.isEmpty) continue;
      final state = (editable.single as StatefulElement).state;
      first ??= identityHashCode(state);
      expect(
        identityHashCode(state),
        first,
        reason: 'the field was rebuilt mid-open, which drops the keyboard',
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
    }
    expect(first, isNotNull, reason: 'the field never appeared');
  });

  testWidgets('scrolling is locked while composing', (tester) async {
    await tester.pumpWidget(harness());
    await _pumpHome(tester);

    await tester.tap(find.byTooltip('Write a log'));
    await _pumpHome(tester);

    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(scrollView.physics, isA<NeverScrollableScrollPhysics>());
  });
}

/// Advances past the expand/collapse animation and the settling scroll.
///
/// `pumpAndSettle` is unusable anywhere on Home. Two animations here never
/// stop by design — the backdrop's Ken Burns drift, and the enrichment
/// indicator on the newest log card — so there is no frame at which the
/// scheduler goes idle. Bounded pumps are the correct tool.
Future<void> _pumpHome(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}
