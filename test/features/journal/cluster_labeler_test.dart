import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/features/journal/data/cluster_labeler.dart';

void main() {
  group('ClusterLabeler.label', () {
    test('picks the word shared across members over a locally frequent one', () {
      // "deadline" appears 4 times but only in one member; "work" appears
      // across three. Document frequency should win — that is what makes a
      // theme a theme rather than one rambling sentence.
      final label = ClusterLabeler.label([
        'The deadline deadline deadline deadline is moving again.',
        'Work has been heavy this week.',
        'I keep thinking about work when I get home.',
        'Work stress followed me into the weekend.',
      ], maxTokens: 1);

      expect(label, 'work');
    });

    test('drops stopwords and spoken filler', () {
      final label = ClusterLabeler.label([
        'I really think that I know what I mean about this thing.',
        'I really think that I know what I mean about this budget.',
      ], maxTokens: 1);

      expect(label, 'budget');
    });

    test('returns null when nothing survives filtering', () {
      expect(ClusterLabeler.label(['I am so is it to be']), isNull);
      expect(ClusterLabeler.label(['']), isNull);
      expect(ClusterLabeler.label([]), isNull);
    });

    test('is stable across calls so labels do not churn between saves', () {
      final members = [
        'Work and sleep both felt hard.',
        'Sleep and work again today.',
      ];
      expect(ClusterLabeler.label(members), ClusterLabeler.label(members));
    });

    test('returns at most maxTokens words', () {
      final label = ClusterLabeler.label([
        'Work sleep money family health.',
        'Work sleep money family health.',
      ], maxTokens: 2);

      expect(label!.split(' '), hasLength(2));
    });
  });

  group('ClusterLabeler.snippet', () {
    test('collapses whitespace and truncates with an ellipsis', () {
      final snippet = ClusterLabeler.snippet(
        '  I have  been\nthinking about this for a very long time indeed  ',
        maxLength: 20,
      );

      expect(snippet.length, lessThanOrEqualTo(21)); // 20 + the ellipsis
      expect(snippet, endsWith('…'));
      expect(snippet, startsWith('I have been'));
    });

    test('leaves short text untouched', () {
      expect(ClusterLabeler.snippet('Short one.'), 'Short one.');
    });
  });

  group('ClusterLabeler.keywordsFor', () {
    test('summarizes a single entry', () {
      final keywords = ClusterLabeler.keywordsFor(
        'My manager moved the deadline and the deadline stress is back.',
      );

      expect(keywords, isNotNull);
      expect(keywords, contains('deadline'));
    });
  });
}
