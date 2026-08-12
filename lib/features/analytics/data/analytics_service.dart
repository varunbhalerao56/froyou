import 'package:flutter/foundation.dart';
import 'package:froyou/features/journal/journal.dart';

/// One recurring theme and how often it came up.
@immutable
class ThemeTrend {
  const ThemeTrend({
    required this.clusterId,
    required this.label,
    required this.occurrences,
    this.representative,
    this.examples = const [],
    this.lastSeen,
  });

  final int clusterId;

  /// A short distinguishing phrase, from class-based TF-IDF across clusters.
  final String label;

  /// Distinct *entries* that touched this theme, not sentences.
  final int occurrences;

  /// The user's own sentence that sits closest to the cluster's centre.
  ///
  /// A two-word label is necessarily lossy — "deadline moved" is a handle, not
  /// a thought. Showing the most central thing the user actually wrote gives
  /// the theme back its context, in their words rather than the app's.
  final String? representative;

  /// The rest of what the person wrote under this theme, most typical first
  /// and [representative] excluded.
  ///
  /// A count on its own is a claim — "you talked about this five times" — and
  /// a claim about someone's own week should be checkable. These are the
  /// sentences the count is counting.
  final List<String> examples;

  final DateTime? lastSeen;
}

@immutable
class AnalyticsSnapshot {
  const AnalyticsSnapshot({
    required this.logCount,
    required this.trends,
    required this.windowDays,
  });

  final int logCount;
  final List<ThemeTrend> trends;
  final int windowDays;

  /// Below this there simply isn't enough to say anything honest.
  static const int minimumLogs = 5;

  bool get hasEnoughLogs => logCount >= minimumLogs;
  int get logsRemaining => minimumLogs - logCount;
}

/// Computes what the analytics screen shows.
class AnalyticsService {
  const AnalyticsService(this._db);

  final JournalEntryDb _db;

  static const int _windowDays = 7;
  static const int _maxTrends = 5;

  /// A theme mentioned once isn't a pattern, it's a sentence.
  static const int _minOccurrences = 2;

  /// Beyond the one already shown as the representative. Enough to make the
  /// count checkable without turning a summary back into the logs list.
  static const int _maxExamples = 4;

  AnalyticsSnapshot compute() {
    final logCount = _db.countEntries();
    final since = DateTime.now().subtract(const Duration(days: _windowDays));

    // Counting distinct entries rather than sentences is the whole point:
    // three sentences about work inside one log is one *time* you talked
    // about work, not three.
    final entriesByCluster = <int, Set<int>>{};
    for (final sentence in _db.sentencesSince(since)) {
      final clusterId = sentence.clusterId;
      if (clusterId == null) continue;
      entriesByCluster
          .putIfAbsent(clusterId, () => <int>{})
          // Reads the relation's id without loading the entry itself.
          .add(sentence.entry.targetId);
    }

    final clusters = {
      for (final cluster in _db.getAllThemeClusters()) cluster.id: cluster,
    };

    final trends =
        entriesByCluster.entries
            .where((entry) => entry.value.length >= _minOccurrences)
            .map((entry) {
              final cluster = clusters[entry.key];
              final label = cluster?.label?.trim();
              return ThemeTrend(
                clusterId: entry.key,
                // Guarded even though relabelAllClusters should have filled
                // this: rendering the word "null" back at someone describing
                // their week is the worst possible failure here.
                label: (label == null || label.isEmpty)
                    ? 'a recurring thought'
                    : label,
                occurrences: entry.value.length,
                representative: cluster == null
                    ? null
                    : _representativeSentence(cluster),
                examples: cluster == null
                    ? const []
                    : _examples(cluster, since),
                lastSeen: cluster?.lastSeen,
              );
            })
            .toList()
          ..sort((a, b) => b.occurrences.compareTo(a.occurrences));

    return AnalyticsSnapshot(
      logCount: logCount,
      trends: trends.take(_maxTrends).toList(),
      windowDays: _windowDays,
    );
  }

  /// The theme's members from the window, ranked by how typical they are and
  /// with the medoid dropped — it is already shown as [ThemeTrend.representative].
  List<String> _examples(ThemeCluster cluster, DateTime since) {
    final centroid = cluster.centroid;
    if (centroid == null) return const [];

    final scored = <(double, String)>[];
    for (final sentence in _db.getSentencesInClusterSince(cluster.id, since)) {
      final embedding = sentence.embedding;
      final text = sentence.text?.trim();
      if (text == null || text.isEmpty) continue;

      var similarity = 0.0;
      if (embedding != null && embedding.length == centroid.length) {
        for (var i = 0; i < centroid.length; i++) {
          similarity += centroid[i] * embedding[i];
        }
      }
      scored.add((similarity, text));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));

    final seen = <String>{};
    return [
      for (final entry in scored)
        if (seen.add(entry.$2)) entry.$2,
    ].skip(1).take(_maxExamples).toList();
  }

  /// The cluster's medoid: the member sentence whose embedding sits closest to
  /// the centroid, and therefore the one most typical of the whole theme.
  ///
  /// Both the centroid and the stored embeddings are unit-normalized, so the
  /// dot product *is* the cosine similarity — no magnitudes needed.
  String? _representativeSentence(ThemeCluster cluster) {
    final centroid = cluster.centroid;
    if (centroid == null) return null;

    String? best;
    var bestSimilarity = double.negativeInfinity;

    for (final sentence in _db.sentencesInCluster(cluster.id)) {
      final embedding = sentence.embedding;
      final text = sentence.text;
      if (embedding == null || text == null || text.trim().isEmpty) continue;
      if (embedding.length != centroid.length) continue;

      var similarity = 0.0;
      for (var i = 0; i < centroid.length; i++) {
        similarity += centroid[i] * embedding[i];
      }

      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        best = text.trim();
      }
    }

    return best;
  }
}
