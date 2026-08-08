/// Names a theme cluster from the sentences that landed in it.
///
/// The schema always intended these labels to come from YAKE, but no
/// maintained pure-Dart port of it exists and `NlpService` exposes no
/// tokenizer to build one on. Without something here every `ThemeCluster.label`
/// is null and the analytics screen reads "you talked about 'null' 3 times",
/// so this is the pragmatic stand-in: document frequency across cluster
/// members, which is a decent proxy for "what this cluster is about" and costs
/// nothing.
///
/// Replaceable wholesale by real keyword extraction later — nothing else
/// depends on how it works, only on what it returns.
class ClusterLabeler {
  ClusterLabeler._();

  static const int _minTokenLength = 3;

  /// Labels a cluster from its member sentences.
  ///
  /// Scores document frequency (how many distinct members contain the token)
  /// well above raw term frequency, because a word appearing across many
  /// members is what "theme" actually means — term frequency alone would let
  /// one rambling sentence name the whole cluster after saying "work" six
  /// times in a row.
  ///
  /// Returns null when nothing survives filtering; callers should fall back to
  /// something human rather than rendering an empty label.
  static String? label(List<String> memberTexts, {int maxTokens = 2}) {
    if (memberTexts.isEmpty) return null;

    final termFrequency = <String, int>{};
    final documentFrequency = <String, int>{};

    for (final text in memberTexts) {
      final tokens = _tokenize(text);
      if (tokens.isEmpty) continue;
      for (final token in tokens) {
        termFrequency.update(token, (n) => n + 1, ifAbsent: () => 1);
      }
      for (final token in tokens.toSet()) {
        documentFrequency.update(token, (n) => n + 1, ifAbsent: () => 1);
      }
    }

    if (termFrequency.isEmpty) return null;

    final ranked = termFrequency.keys.toList()
      ..sort((a, b) {
        final scoreA = _score(a, termFrequency, documentFrequency);
        final scoreB = _score(b, termFrequency, documentFrequency);
        if (scoreA != scoreB) return scoreB.compareTo(scoreA);
        return a.compareTo(b); // stable, so labels don't churn between saves
      });

    return ranked.take(maxTokens).join(' ');
  }

  /// A short at-a-glance summary for a single entry, used on the log cards.
  static String? keywordsFor(String text, {int maxTokens = 3}) =>
      label([text], maxTokens: maxTokens);

  /// Last-ditch label when [label] finds nothing usable — a truncated snippet
  /// still tells the user which thought this cluster is, which an empty string
  /// does not.
  static String snippet(String text, {int maxLength = 40}) {
    final collapsed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.length <= maxLength) return collapsed;
    return '${collapsed.substring(0, maxLength).trimRight()}…';
  }

  static int _score(String token, Map<String, int> tf, Map<String, int> df) =>
      (df[token] ?? 0) * 2 + (tf[token] ?? 0);

  static List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r"[^a-z']+"))
        .map((token) => token.replaceAll(RegExp(r"^'+|'+$"), ''))
        .where(
          (token) =>
              token.length >= _minTokenLength && !_stopwords.contains(token),
        )
        .toList();
  }

  /// Common English function words, plus the filler that dominates spoken
  /// journal entries specifically ("like", "know", "think", "really") — those
  /// are the ones that actually win on frequency in transcribed speech and
  /// they say nothing about the theme.
  static const Set<String> _stopwords = {
    'about', 'above', 'after', 'again', 'against', 'all', 'also', 'and', 'any',
    'are', 'aren', 'because', 'been', 'before', 'being', 'below', 'between',
    'both', 'but', 'can', 'cannot', 'could', 'couldn', 'did', 'didn', 'does',
    'doesn', 'doing', 'don', 'down', 'during', 'each', 'even', 'ever', 'every',
    'few', 'for', 'from', 'further', 'get', 'got', 'had', 'hadn', 'has',
    'hasn', 'have', 'haven', 'having', 'her', 'here', 'hers', 'herself', 'him',
    'himself', 'his', 'how', 'however', 'into', 'isn', 'its', 'itself', 'just',
    'kind', 'know', 'less', 'let', 'like', 'lot', 'made', 'make', 'many',
    'maybe', 'mean', 'might', 'mine', 'more', 'most', 'much', 'must', 'myself',
    'need', 'never', 'new', 'not', 'now', 'off', 'once', 'one', 'only', 'onto',
    'other', 'ought', 'our', 'ours', 'ourselves', 'out', 'over', 'own',
    'per', 'quite', 'rather', 'really', 'said', 'same', 'say', 'see', 'seem',
    'she', 'should', 'shouldn', 'since', 'some', 'something', 'still', 'such',
    'sure', 'take', 'than', 'that', 'the', 'their', 'theirs', 'them',
    'themselves', 'then', 'there', 'these', 'they', 'thing', 'things', 'think',
    'this', 'those', 'though', 'through', 'thus', 'too', 'under', 'until',
    'upon', 'use', 'used', 'very', 'want', 'was', 'wasn', 'way', 'well',
    'were', 'weren', 'what', 'when', 'where', 'whether', 'which', 'while',
    'who', 'whom', 'why', 'will', 'with', 'won', 'would', 'wouldn', 'yes',
    'yet', 'you', 'your', 'yours', 'yourself', 'yourselves',
  };
}
