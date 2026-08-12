import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/home/data/transcript_words.dart';
import 'package:froyou/features/home/presentation/transcript_view.dart';
import 'package:froyou/services/services.dart';

import '../../support/test_fonts.dart';

const TextStyle _style = TextStyle(
  fontSize: 16,
  height: 1.35,
  color: Color(0xFF102030),
);

SpeechTranscript partial(String text) => SpeechTranscript(
  text: text,
  isFinal: false,
  start: Duration.zero,
  end: Duration.zero,
);

Widget harness(TranscriptWords words) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 320,
        child: TranscriptView(
          words: words,
          style: _style,
          accent: const Color(0xFF4488FF),
          hintColor: const Color(0xFF999999),
          minHeight: 64,
        ),
      ),
    ),
  ),
);

/// The spans that actually carry text, in order.
///
/// Walks rather than indexing: `Text.rich` wraps the span it is given in
/// another one carrying the widget-level style, so the words sit a level
/// deeper than they are written.
List<TextSpan> wordSpans(WidgetTester tester) {
  final richText = tester.widget<RichText>(
    find.descendant(
      of: find.byType(TranscriptView),
      matching: find.byType(RichText),
    ),
  );

  final found = <TextSpan>[];
  void walk(InlineSpan span) {
    if (span is! TextSpan) return;
    if (span.text != null) found.add(span);
    for (final child in span.children ?? const <InlineSpan>[]) {
      walk(child);
    }
  }

  walk(richText.text);
  return found;
}

/// Per-word opacity, read straight off the spans the paragraph was built from.
List<double> alphas(WidgetTester tester) =>
    wordSpans(tester).map((span) => span.style!.color!.a).toList();

List<String> texts(WidgetTester tester) =>
    wordSpans(tester).map((span) => span.text!.trim()).toList();

void main() {
  // The gradient repeats forever by design, so there is never an idle frame.
  // Every pump here is bounded; pumpAndSettle would hang to its timeout.
  late TranscriptWords words;

  setUp(() => words = TranscriptWords());

  testWidgets('shows the hint until the first word arrives', (tester) async {
    await tester.pumpWidget(harness(words));
    await tester.pump();

    expect(find.text('Listening…'), findsOneWidget);
  });

  testWidgets('a newly arrived word starts transparent and fades in', (
    tester,
  ) async {
    await tester.pumpWidget(harness(words));
    await tester.pump();

    words.ingest(partial('Today'));
    await tester.pumpWidget(harness(words));
    await tester.pump();

    expect(texts(tester), ['Today']);
    expect(alphas(tester).single, lessThan(0.2));

    await tester.pump(const Duration(milliseconds: 260));
    expect(alphas(tester).single, 1.0);
  });

  testWidgets('words already on screen do not fade again when one arrives', (
    tester,
  ) async {
    await tester.pumpWidget(harness(words));
    await tester.pump();

    words.ingest(partial('Today my'));
    await tester.pumpWidget(harness(words));
    await tester.pump(const Duration(milliseconds: 400));
    expect(alphas(tester), [1.0, 1.0]);

    words.ingest(partial('Today my manager'));
    await tester.pumpWidget(harness(words));
    await tester.pump();

    // This is the whole point of the stable identities: the settled words hold
    // full opacity while only the new one animates.
    final current = alphas(tester);
    expect(current.take(2), [1.0, 1.0]);
    expect(current.last, lessThan(0.2));
  });

  testWidgets('a revised word fades in while its prefix stays put', (
    tester,
  ) async {
    await tester.pumpWidget(harness(words));
    await tester.pump();

    words.ingest(partial('my chest tight'));
    await tester.pumpWidget(harness(words));
    await tester.pump(const Duration(milliseconds: 400));
    expect(alphas(tester), [1.0, 1.0, 1.0]);

    words.ingest(partial('my chest tighten'));
    await tester.pumpWidget(harness(words));
    await tester.pump();

    expect(texts(tester), ['my', 'chest', 'tighten']);
    final current = alphas(tester);
    expect(current.take(2), [1.0, 1.0]);
    expect(current.last, lessThan(0.2));
  });

  testWidgets('a batch of words staggers rather than flashing in together', (
    tester,
  ) async {
    await tester.pumpWidget(harness(words));
    await tester.pump();

    words.ingest(partial('one two three four'));
    await tester.pumpWidget(harness(words));
    await tester.pump(const Duration(milliseconds: 120));

    final current = alphas(tester);
    // Each word is offset from the one before, so the line reveals left to
    // right instead of appearing as a block.
    for (var i = 1; i < current.length; i++) {
      expect(
        current[i],
        lessThan(current[i - 1]),
        reason: 'word $i should trail word ${i - 1}',
      );
    }
  });

  group('appearance', () {
    setUpAll(loadAppFonts);

    /// The real type and the real accent, caught mid-fade — the one frame that
    /// shows both the trailing words still arriving and the wash behind them.
    testWidgets('mid-dictation, with the speaking gradient', (tester) async {
      tester.view.physicalSize = const Size(1179, 700);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final palette = AppPalette.fromSettings(
        const ThemeSettings(brightnessMode: ThemeBrightnessMode.light),
        Brightness.light,
      );

      Widget frame() => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.fromPalette(palette),
        home: Scaffold(
          backgroundColor: palette.colors.background,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TranscriptView(
                words: words,
                accent: palette.colors.primary,
                hintColor: palette.colors.placeholder,
                minHeight: 85,
                style: AppTypography.composeInput.copyWith(
                  color: palette.colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(frame());
      await tester.pump();

      words.ingest(partial('Today my manager moved the deadline forward again'));
      await tester.pumpWidget(frame());
      // Far enough in that the early words have settled and the tail has not.
      await tester.pump(const Duration(milliseconds: 200));

      await expectLater(
        find.byType(TranscriptView),
        matchesGoldenFile('goldens/transcript_view_speaking.png'),
      );
    });
  });
}
