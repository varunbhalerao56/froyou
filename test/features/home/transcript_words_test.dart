import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/features/home/data/transcript_words.dart';
import 'package:froyou/services/services.dart';

/// A volatile result — the recognizer is still revising this range.
SpeechTranscript partial(String text) => SpeechTranscript(
  text: text,
  isFinal: false,
  start: Duration.zero,
  end: Duration.zero,
);

/// A final result — this range is settled and will never change again.
SpeechTranscript settled(String text) => SpeechTranscript(
  text: text,
  isFinal: true,
  start: Duration.zero,
  end: Duration.zero,
);

List<int> idsOf(TranscriptWords words) =>
    words.words.map((word) => word.id).toList();

List<String> textOf(TranscriptWords words) =>
    words.words.map((word) => word.text).toList();

void main() {
  late TranscriptWords words;

  setUp(() => words = TranscriptWords());

  group('growth', () {
    test('a growing partial only gives new identities to new words', () {
      words.ingest(partial('I felt'));
      final before = idsOf(words);

      words.ingest(partial('I felt my'));

      expect(textOf(words), ['I', 'felt', 'my']);
      // The two words already on screen keep their ids, so they don't re-fade.
      expect(idsOf(words).take(2), before);
      expect(idsOf(words).last, isNot(anyOf(before)));
    });

    test('word by word, every arrival adds exactly one identity', () {
      words.ingest(partial('Today'));
      words.ingest(partial('Today my'));
      words.ingest(partial('Today my manager'));

      expect(idsOf(words), [0, 1, 2]);
    });
  });

  group('revision', () {
    test('a revised tail keeps the unchanged prefix', () {
      words.ingest(partial('my chest tight'));
      final before = idsOf(words);

      words.ingest(partial('my chest tighten'));

      expect(textOf(words), ['my', 'chest', 'tighten']);
      expect(idsOf(words).take(2), before.take(2));
      // "tight" became "tighten" — different text, so it is genuinely new.
      expect(idsOf(words).last, isNot(before.last));
    });

    test('a shrinking partial drops the tail and keeps survivors', () {
      words.ingest(partial('one two three four'));
      final before = idsOf(words);

      words.ingest(partial('one two'));

      expect(textOf(words), ['one', 'two']);
      expect(idsOf(words), before.take(2));
    });

    test('a final revising the volatile keeps unchanged words settled', () {
      words.ingest(partial('I felt my chest tight'));
      final before = idsOf(words);

      words.ingest(settled('I felt my chest tighten.'));

      expect(textOf(words), ['I', 'felt', 'my', 'chest', 'tighten.']);
      // This is the case the watermark exists for: reconciling before settling
      // means only the word that actually changed animates.
      expect(idsOf(words).take(4), before.take(4));
      expect(idsOf(words).last, isNot(anyOf(before)));
      expect(words.settledCount, 5);
    });

    test('a settled range is never revised by a later result', () {
      words.ingest(settled('First sentence.'));
      final before = idsOf(words);

      // A new volatile range starts fresh; it must not reconcile against — or
      // truncate — the sentence already committed.
      words.ingest(partial('Second'));

      expect(textOf(words), ['First', 'sentence.', 'Second']);
      expect(idsOf(words).take(2), before);
      expect(words.settledCount, 2);
    });
  });

  group('finals', () {
    test('consecutive finals accumulate', () {
      words.ingest(settled('First sentence.'));
      words.ingest(settled('Second sentence.'));

      expect(words.joined, 'First sentence. Second sentence.');
      expect(words.settledCount, 4);
    });

    test('an empty final settles whatever was pending', () {
      words.ingest(partial('trailing words'));
      expect(words.settledCount, 0);

      words.ingest(settled(''));

      expect(textOf(words), ['trailing', 'words']);
      expect(words.settledCount, 2);
    });

    test('an empty partial changes nothing', () {
      words.ingest(partial('something'));
      final before = idsOf(words);

      words.ingest(partial(''));

      expect(idsOf(words), before);
      expect(words.settledCount, 0);
    });
  });

  group('joined', () {
    test('normalises whitespace across segment boundaries', () {
      words.ingest(settled('Hello   there.'));
      words.ingest(settled('  How are you?  '));

      expect(words.joined, 'Hello there. How are you?');
    });

    test('is empty before anything arrives', () {
      expect(words.joined, isEmpty);
      expect(words.isEmpty, isTrue);
    });
  });

  group('clear', () {
    test('empties the transcript and the watermark', () {
      words.ingest(settled('Something.'));
      words.clear();

      expect(words.isEmpty, isTrue);
      expect(words.settledCount, 0);
      expect(words.joined, isEmpty);
    });

    test('does not reuse identities from before the clear', () {
      words.ingest(settled('one two'));
      final before = idsOf(words);
      words.clear();

      words.ingest(partial('one two'));

      // Same text, but a view still mounted from the previous session must not
      // mistake these for words it has already faded in.
      expect(idsOf(words).toSet().intersection(before.toSet()), isEmpty);
    });
  });
}
