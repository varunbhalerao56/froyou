import 'dart:math';

import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/features/journal/journal.dart';

/// Fills the database with believable logs and working clusters.
///
/// Debug-only, and worth its length: contextual embeddings are unavailable in
/// the Simulator, so without synthetic vectors nothing ever clusters and the
/// logs list, cluster labels and analytics screen can only be seen on a
/// physical device. This also doubles as a demo dataset if the device path
/// misbehaves when it matters.
class DebugSeed {
  DebugSeed._();

  /// Each group shares an embedding direction, so its sentences cluster
  /// together the same way real ones would.
  static const List<List<String>> _topics = [
    [
      'My manager moved the deadline forward again and I felt my chest tighten.',
      'Work has been sitting on me all week and I keep checking email at night.',
      'I keep replaying that work meeting and wondering if I said something wrong.',
      'The deadline landed and work still feels like it is following me home.',
    ],
    [
      'I slept badly again and everything felt heavier because of it.',
      'Sleep has been broken for days now and I wake up before the alarm.',
      'I went to bed early but sleep did not come until very late.',
    ],
    [
      'Dinner with my sister was genuinely lovely and I laughed properly.',
      'My sister called and we talked for an hour about nothing important.',
      'Family weekend was warm and I did not want it to end.',
    ],
    [
      'The walk by the river was cold and it actually helped a little.',
      'I ran this morning and my head was quieter afterwards.',
    ],
  ];

  static const int _dimensions = JournalEntryDb.embeddingDimensions;

  /// Spread over the past few days so the "last 7 days" analytics window has
  /// something real to select on.
  static Future<int> run(JournalEntryDb db) async {
    final random = Random(11);
    var created = 0;
    final touchedClusters = <int>{};

    for (var topic = 0; topic < _topics.length; topic++) {
      final direction = _direction(topic);

      for (var i = 0; i < _topics[topic].length; i++) {
        final text = _topics[topic][i];
        // Interleave topics across days rather than writing one topic per day,
        // so trends look like a real week instead of a staircase.
        final daysAgo = (created * 5) % 7;
        final createdAt = DateTime.now().subtract(
          Duration(days: daysAgo, hours: created * 3),
        );

        final entry = JournalEntry()
          ..rawText = text
          ..keywords = ClusterLabeler.keywordsFor(text)
          ..moodScore = _moodFor(topic)
          ..createdAt = createdAt;
        entry.id = await db.putEntry(entry);

        final sentence = JournalSentence()
          ..text = text
          ..keywords = ClusterLabeler.keywordsFor(text)
          ..embedding = _jitter(direction, random, 0.06);
        await db.putSentenceInEntry(entry, sentence);

        final clusterId = sentence.clusterId;
        if (clusterId != null) touchedClusters.add(clusterId);
        created++;
      }
    }

    db.relabelClusters(touchedClusters);
    AppLog.info('DebugSeed', 'seeded $created entries');
    return created;
  }

  /// A unit vector along one axis. Distinct axes are near-orthogonal, so
  /// different topics stay well under the 0.70 join threshold.
  static List<double> _direction(int topic) {
    final values = List<double>.filled(_dimensions, 0);
    values[topic * 7] = 1;
    return values;
  }

  /// Small enough that same-topic vectors stay well above the join threshold.
  static List<double> _jitter(
    List<double> direction,
    Random random,
    double amount,
  ) {
    final values = [
      for (final value in direction)
        value + (random.nextDouble() - 0.5) * amount,
    ];
    final magnitude = sqrt(values.fold(0.0, (a, b) => a + b * b));
    return values.map((v) => v / magnitude).toList();
  }

  static double _moodFor(int topic) => switch (topic) {
    0 => -0.6,
    1 => -0.3,
    2 => 0.7,
    _ => 0.4,
  };
}
