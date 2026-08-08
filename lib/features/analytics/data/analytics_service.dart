import 'package:flutter/foundation.dart';
import 'package:froyou/features/journal/journal.dart';

/// One recurring theme and how often it came up.
@immutable
class ThemeTrend {
  const ThemeTrend({
    required this.clusterId,
    required this.label,
    required this.occurrences,
    this.lastSeen,
  });

  final int clusterId;
  final String label;

  /// Distinct *entries* that touched this theme, not sentences.
  final int occurrences;

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
                // Guarded even though relabelClusters should have filled this:
                // rendering the word "null" back at someone describing their
                // week is the worst possible failure here.
                label: (label == null || label.isEmpty)
                    ? 'a recurring thought'
                    : label,
                occurrences: entry.value.length,
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
}
