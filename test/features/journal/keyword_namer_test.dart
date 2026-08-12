import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/core/config/label_mode.dart';
import 'package:froyou/features/journal/data/cluster_labeler.dart';
import 'package:froyou/features/journal/data/keyword_namer.dart';

import '../../support/genai_mock.dart';

/// The entry that made this necessary, near enough verbatim.
///
/// Every content word in it appears once, so the statistical path scores them
/// all at one and the alphabetical tie-break picks the winners — which is how
/// an entry about shame came out labelled "better, deal".
const _entry =
    'So there is some interesting things that are happening. And I am not '
    'really sure how I can deal with those things. I am feeling a lot of '
    'shame. And I hope that in the future I can do things better.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The fallback is switched off app-wide while the model path is being
  // eyeballed on device — see [kModelOnlyLabels]. These two cases are about
  // what happens when it is on, so they pin it rather than inherit it.
  setUp(() => kModelOnlyLabels = false);
  tearDown(() {
    kModelOnlyLabels = true;
    unmockGenAi();
  });

  test('with fallbacks off, no model means no keywords', () async {
    kModelOnlyLabels = true;
    mockGenAi(available: false);

    expect(await KeywordNamer.forEntry(_entry), isNull);
  });

  test('the statistical path really does fail on a single short entry', () {
    // Pinned rather than assumed. If this ever starts surfacing 'shame' on its
    // own, the model path has stopped being the only way to get there and this
    // whole class is worth re-reading.
    final fallback = ClusterLabeler.keywordsFor(_entry);
    expect(fallback, isNotNull);
    expect(
      fallback,
      isNot(contains('shame')),
      reason: 'frequency ranking cannot find the subject of a one-off entry',
    );
  });

  test('the model names what the entry is about', () async {
    mockGenAi(available: true, keywords: ['shame', 'uncertainty']);

    expect(await KeywordNamer.forEntry(_entry), 'shame, uncertainty');
  });

  test('drops a keyword already covered by one it overlaps', () async {
    mockGenAi(available: true, keywords: ['work', 'work deadline', 'dread']);

    expect(await KeywordNamer.forEntry(_entry), 'work, dread');
  });

  test(
    'falls back to the statistical answer when the model is absent',
    () async {
      mockGenAi(available: false);

      expect(
        await KeywordNamer.forEntry(_entry),
        ClusterLabeler.keywordsFor(_entry),
      );
    },
  );

  test('falls back when the model returns nothing usable', () async {
    mockGenAi(available: true, keywords: ['', '   ']);

    expect(
      await KeywordNamer.forEntry(_entry),
      ClusterLabeler.keywordsFor(_entry),
    );
  });

  test('an empty entry has nothing to say either way', () async {
    mockGenAi(available: true, keywords: ['shame']);

    // Guarded before the channel, so this is not the model declining — there is
    // simply no text, and a card with no words needs no words under it.
    expect(await KeywordNamer.forEntry('   '), isNull);
  });
}
