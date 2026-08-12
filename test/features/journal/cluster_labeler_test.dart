import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/features/journal/data/cluster_labeler.dart';

void main() {
  group('ClusterLabeler.labelAll', () {
    test('names each cluster by what makes it different from the others', () {
      // "work" appears in all three clusters. Frequency alone would name every
      // one of them "work"; class-based scoring has to reach past it for the
      // term that actually separates each cluster.
      final labels = ClusterLabeler.labelAll({
        1: [
          'Work and the deadline are crushing me.',
          'The deadline at work moved again.',
          'Another deadline landed at work today.',
        ],
        2: [
          'Work is fine but my sleep is broken.',
          'Sleep was bad again before work.',
          'I lost sleep worrying about work.',
        ],
        3: [
          'Dinner with my sister after work was lovely.',
          'My sister called me after work.',
          'Work aside, my sister makes me laugh.',
        ],
      });

      expect(labels[1], contains('deadline'));
      expect(labels[2], contains('sleep'));
      expect(labels[3], contains('sister'));
      // The word every cluster shares must not become anyone's label.
      expect(labels.values, everyElement(isNot('work')));
    });

    test('prefers a phrase over a bare word, so the label keeps context', () {
      final labels = ClusterLabeler.labelAll({
        1: [
          'The deadline moved forward and I panicked.',
          'The deadline moved again this morning.',
          'Another deadline moved without warning.',
        ],
        2: ['Sleep was broken.', 'Sleep is still broken.'],
      });

      expect(labels[1], 'deadline moved');
    });

    test('only pairs words the user actually said next to each other', () {
      // "work" and "deadline" are never adjacent here, so "work deadline"
      // must not be invented as a phrase.
      final labels = ClusterLabeler.labelAll({
        1: [
          'Work was a long slow deadline away.',
          'Work felt like a distant deadline.',
        ],
        2: ['Sleep was broken.', 'Sleep is still broken.'],
      });

      expect(labels[1], isNot(contains('work deadline')));
    });

    test('is stable across calls so labels do not churn between saves', () {
      final members = {
        1: ['Work and sleep both felt hard.', 'Sleep and work again today.'],
        2: ['The garden is coming along.', 'Garden work on Sunday.'],
      };
      expect(ClusterLabeler.labelAll(members), ClusterLabeler.labelAll(members));
    });

    test('returns nothing for clusters with no usable words', () {
      expect(ClusterLabeler.labelAll({}), isEmpty);
      expect(ClusterLabeler.labelAll({1: ['I am so is it to be']}), isEmpty);
      expect(ClusterLabeler.labelAll({1: ['']}), isEmpty);
    });

    test('handles a single cluster, where nothing is comparative', () {
      final labels = ClusterLabeler.labelAll({
        1: ['The deadline moved again.', 'Another deadline moved.'],
      });
      expect(labels[1], isNotNull);
      expect(labels[1], contains('deadline'));
    });
  });

  group('ClusterLabeler.keywordsFor', () {
    test('summarizes a single entry without repeating itself', () {
      final keywords = ClusterLabeler.keywordsFor(
        'My manager moved the deadline and the deadline stress is back.',
      );

      expect(keywords, isNotNull);
      expect(keywords, contains('deadline'));
      // "deadline stress" and "deadline" must not both appear.
      final terms = keywords!.split(', ');
      expect(terms.toSet(), hasLength(terms.length));
      for (var i = 0; i < terms.length; i++) {
        for (var j = i + 1; j < terms.length; j++) {
          expect(terms[i].contains(terms[j]), isFalse);
          expect(terms[j].contains(terms[i]), isFalse);
        }
      }
    });

    test('drops stopwords and spoken filler', () {
      expect(
        ClusterLabeler.keywordsFor(
          'I really think that I know what I mean about this budget.',
        ),
        contains('budget'),
      );
    });

    test('returns null when nothing survives filtering', () {
      expect(ClusterLabeler.keywordsFor('I am so is it to be'), isNull);
      expect(ClusterLabeler.keywordsFor(''), isNull);
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
}
