import 'dart:math';

/// Names theme clusters from the sentences that landed in them.
///
/// Uses **class-based TF-IDF**, the scoring BERTopic introduced for exactly
/// this job: collapse each cluster into a single document, then weight each
/// term by how much it distinguishes that cluster from the others. Plain
/// within-cluster frequency — what this used to do — cannot do that. If you
/// journal about work every day, "work" is the most frequent word in the sleep
/// cluster and the family cluster too, so every theme ends up named after it.
///
/// Two consequences of that choice shape the API:
///
/// * [labelAll] takes every cluster at once, because the scoring is comparative.
///   There is no meaningful way to label one cluster in isolation.
/// * Terms include adjacent word pairs, not just single words, and pairs are
///   given a bonus. "deadline moved" says something; "deadline" and "moved"
///   ranked separately say much less, and two unrelated top words ("work
///   sleep") read as noise.
///
/// This still only ever surfaces a short phrase. The sentence that best
/// represents a cluster is chosen separately, from the embeddings — see
/// `AnalyticsService`.
class ClusterLabeler {
  ClusterLabeler._();

  static const int _minTokenLength = 3;

  /// How much to favour a two-word phrase over a single word of equal score.
  /// Tuned by eye: high enough that phrases usually win, low enough that a
  /// genuinely dominant single word still gets through.
  static const double _phraseBonus = 1.4;

  /// Labels every cluster in one pass.
  ///
  /// Returns a label per cluster id; clusters whose text yields nothing usable
  /// are omitted, so callers can fall back to something human.
  static Map<int, String> labelAll(Map<int, List<String>> membersByCluster) {
    if (membersByCluster.isEmpty) return const {};

    // Step 1: each cluster becomes a single document.
    final termCountsByCluster = <int, Map<String, int>>{};
    // Frequency of each term across every cluster — the "class" denominator.
    final frequencyAcrossClusters = <String, int>{};
    var totalTerms = 0;

    for (final entry in membersByCluster.entries) {
      final counts = <String, int>{};
      for (final text in entry.value) {
        for (final term in _terms(text)) {
          counts.update(term, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      if (counts.isEmpty) continue;

      termCountsByCluster[entry.key] = counts;
      counts.forEach((term, count) {
        frequencyAcrossClusters.update(
          term,
          (n) => n + count,
          ifAbsent: () => count,
        );
        totalTerms += count;
      });
    }

    if (termCountsByCluster.isEmpty) return const {};

    final averageTermsPerCluster = totalTerms / termCountsByCluster.length;

    final labels = <int, String>{};
    for (final entry in termCountsByCluster.entries) {
      final counts = entry.value;
      final clusterTotal = counts.values.fold(0, (a, b) => a + b);
      if (clusterTotal == 0) continue;

      var bestTerm = '';
      var bestScore = 0.0;

      counts.forEach((term, count) {
        // Step 2: L1-normalize within the cluster, so a big cluster doesn't
        // outscore a small one purely on volume.
        final termFrequency = count / clusterTotal;

        // Step 3: log(1 + average terms per cluster / frequency across all
        // clusters). The +1 keeps this positive; the ratio is what punishes a
        // word that shows up everywhere.
        final inverseClassFrequency = log(
          1 + averageTermsPerCluster / frequencyAcrossClusters[term]!,
        );

        final score =
            termFrequency *
            inverseClassFrequency *
            (term.contains(' ') ? _phraseBonus : 1.0);

        // Ties broken alphabetically so labels don't churn between saves.
        if (score > bestScore ||
            (score == bestScore && term.compareTo(bestTerm) < 0)) {
          bestScore = score;
          bestTerm = term;
        }
      });

      if (bestTerm.isNotEmpty) labels[entry.key] = bestTerm;
    }

    return labels;
  }

  /// A short at-a-glance summary for a single entry, used on the log cards.
  ///
  /// Necessarily non-comparative — there is only one document — so this is
  /// plain frequency with the phrase bonus, not c-TF-IDF.
  static String? keywordsFor(String text, {int maxTerms = 3}) {
    final counts = <String, int>{};
    for (final term in _terms(text)) {
      counts.update(term, (n) => n + 1, ifAbsent: () => 1);
    }
    if (counts.isEmpty) return null;

    double score(String term) =>
        counts[term]! * (term.contains(' ') ? _phraseBonus : 1.0);

    final ranked = counts.keys.toList()
      ..sort((a, b) {
        final byScore = score(b).compareTo(score(a));
        return byScore != 0 ? byScore : a.compareTo(b);
      });

    // Drop any term already covered by a higher-ranked phrase, so the result
    // isn't "work deadline, work, deadline".
    final chosen = <String>[];
    for (final term in ranked) {
      if (chosen.length >= maxTerms) break;
      final overlaps = chosen.any(
        (kept) => kept.contains(term) || term.contains(kept),
      );
      if (!overlaps) chosen.add(term);
    }

    return chosen.isEmpty ? null : chosen.join(', ');
  }

  /// Last-ditch label when [labelAll] finds nothing usable — a truncated
  /// snippet still tells the user which thought this cluster is, which an empty
  /// string does not.
  static String snippet(String text, {int maxLength = 40}) {
    final collapsed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.length <= maxLength) return collapsed;
    return '${collapsed.substring(0, maxLength).trimRight()}…';
  }

  /// Single words plus adjacent word pairs.
  ///
  /// A pair is only formed from words that were genuinely next to each other
  /// and both carry meaning — filtering stopwords first and then pairing what
  /// survives would invent phrases like "work deadline" out of "work was a
  /// deadline away", which the user never said.
  static List<String> _terms(String text) {
    final tokens = text
        .toLowerCase()
        .split(RegExp(r"[^a-z']+"))
        .map((token) => token.replaceAll(RegExp(r"^'+|'+$"), ''))
        .toList();

    final terms = <String>[];
    for (var i = 0; i < tokens.length; i++) {
      if (!_isContentWord(tokens[i])) continue;
      terms.add(tokens[i]);
      if (i + 1 < tokens.length && _isContentWord(tokens[i + 1])) {
        terms.add('${tokens[i]} ${tokens[i + 1]}');
      }
    }
    return terms;
  }

  static bool _isContentWord(String token) =>
      token.length >= _minTokenLength && !_stopwords.contains(token);

  /// Common English function words, plus the filler that dominates spoken
  /// journal entries specifically ("like", "know", "think", "really") — those
  /// are the ones that actually win on frequency in transcribed speech and
  /// they say nothing about the theme.
  static const Set<String> _stopwords = {
    'about',
    'above',
    'after',
    'again',
    'against',
    'all',
    'also',
    'and',
    'any',
    'are',
    'aren',
    'because',
    'been',
    'before',
    'being',
    'below',
    'between',
    'both',
    'but',
    'can',
    'cannot',
    'could',
    'couldn',
    'did',
    'didn',
    'does',
    'doesn',
    'doing',
    'don',
    'down',
    'during',
    'each',
    'even',
    'ever',
    'every',
    'few',
    'for',
    'from',
    'further',
    'get',
    'got',
    'had',
    'hadn',
    'has',
    'hasn',
    'have',
    'haven',
    'having',
    'her',
    'here',
    'hers',
    'herself',
    'him',
    'himself',
    'his',
    'how',
    'however',
    'into',
    'isn',
    'its',
    'itself',
    'just',
    'kind',
    'know',
    'less',
    'let',
    'like',
    'lot',
    'made',
    'make',
    'many',
    'maybe',
    'mean',
    'might',
    'mine',
    'more',
    'most',
    'much',
    'must',
    'myself',
    'need',
    'never',
    'new',
    'not',
    'now',
    'off',
    'once',
    'one',
    'only',
    'onto',
    'other',
    'ought',
    'our',
    'ours',
    'ourselves',
    'out',
    'over',
    'own',
    'per',
    'quite',
    'rather',
    'really',
    'said',
    'same',
    'say',
    'see',
    'seem',
    'she',
    'should',
    'shouldn',
    'since',
    'some',
    'something',
    'still',
    'such',
    'sure',
    'take',
    'than',
    'that',
    'the',
    'their',
    'theirs',
    'them',
    'themselves',
    'then',
    'there',
    'these',
    'they',
    'thing',
    'things',
    'think',
    'this',
    'those',
    'though',
    'through',
    'thus',
    'too',
    'under',
    'until',
    'upon',
    'use',
    'used',
    'very',
    'want',
    'was',
    'wasn',
    'way',
    'well',
    'were',
    'weren',
    'what',
    'when',
    'where',
    'whether',
    'which',
    'while',
    'who',
    'whom',
    'why',
    'will',
    'with',
    'won',
    'would',
    'wouldn',
    'yes',
    'yet',
    'you',
    'your',
    'yours',
    'yourself',
    'yourselves',
  };
}
