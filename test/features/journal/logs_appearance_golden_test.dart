import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/analytics/data/analytics_service.dart';
import 'package:froyou/features/analytics/presentation/analytics_view.dart';
import 'package:froyou/features/home/presentation/compose_box.dart';
import 'package:froyou/features/home/presentation/compose_controller.dart';
import 'package:froyou/features/journal/journal.dart';
import 'package:froyou/features/journal/presentation/log_card.dart';

/// Renders the log and trend surfaces at real type sizes with the real bundled
/// font, so the styling can actually be judged rather than inferred.
///
/// Goldens here are about type size, weight and the absence of borders — not
/// pixel-exactness. Regenerate with `flutter test --update-goldens`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // flutter_test does not load the app's declared fonts, so text would
    // otherwise render in the fallback and tell us nothing about the scale.
    final loader = FontLoader(AppTypography.fontFamily);
    for (final weight in const [
      'Regular',
      'Medium',
      'Semibold',
      'Bold',
    ]) {
      final file = File('fonts/SF-Pro-Rounded-$weight.otf');
      if (!file.existsSync()) continue;
      loader.addFont(
        file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
    }
    await loader.load();
  });

  Widget frame(Widget child) {
    // A real derived palette, not `fallbackLight` — that one is the
    // boot-failure path and its shadows are flat constants, so it cannot show
    // whether card elevation reads correctly on a coloured page.
    final palette = AppPalette.fromSettings(
      const ThemeSettings(
        presetId: 'sage',
        brightnessMode: ThemeBrightnessMode.light,
      ),
      Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromPalette(palette),
      home: Scaffold(
        backgroundColor: palette.colors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: child,
          ),
        ),
      ),
    );
  }

  JournalEntry entry({
    required int id,
    required String text,
    String? keywords,
    double? mood,
  }) {
    return JournalEntry()
      ..id = id
      ..rawText = text
      ..keywords = keywords
      ..moodScore = mood
      // Fixed so the rendered date string never drifts with the clock.
      ..createdAt = DateTime(2026, 8, 8, 9, 41);
  }

  testWidgets('log list', (tester) async {
    tester.view.physicalSize = const Size(1179, 1400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      frame(
        ListView(
          children: [
            LogCard(
              entry: entry(
                id: 1,
                text:
                    'My manager moved the deadline forward again and I felt my '
                    'chest tighten for most of the afternoon.',
                keywords: 'deadline moved, manager, chest',
                mood: -0.6,
              ),
              onDelete: () async {},
            ),
            LogCard(
              entry: entry(
                id: 2,
                text: 'The walk by the river was cold and it actually helped.',
                keywords: 'river walk, cold',
                mood: 0.5,
              ),
              onDelete: () async {},
            ),
            LogCard(
              entry: entry(
                id: 3,
                text: 'Sleep has been broken for days now.',
                mood: -0.2,
              ),
              onDelete: () async {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ListView),
      matchesGoldenFile('goldens/log_list.png'),
    );
  });

  testWidgets('compose box sits on the background with no surface of its own', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1179, 700);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final compose = ComposeController(
      vsync: const TestVSync(),
      onSave: (_) async {},
    );
    addTearDown(compose.dispose);
    compose.text.text =
        'Today my manager moved the deadline forward again and I felt my chest tighten.';

    await tester.pumpWidget(frame(Center(child: ComposeBox(compose: compose))));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ComposeBox),
      matchesGoldenFile('goldens/compose_box.png'),
    );
  });

  testWidgets('analytics trends', (tester) async {
    tester.view.physicalSize = const Size(1179, 1000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      frame(
        ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          children: const [
            TrendRow(
              trend: ThemeTrend(
                clusterId: 1,
                label: 'deadline moved',
                occurrences: 4,
                representative:
                    'The deadline landed and work still feels like it is following me home.',
              ),
            ),
            AppGap.smV,
            TrendRow(
              trend: ThemeTrend(
                clusterId: 2,
                label: 'sleep',
                occurrences: 2,
                representative:
                    'Sleep has been broken for days now and I wake up before the alarm.',
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ListView),
      matchesGoldenFile('goldens/analytics_trends.png'),
    );
  });
}
