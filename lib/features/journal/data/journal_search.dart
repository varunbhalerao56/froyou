import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/features/journal/journal.dart';
import 'package:froyou/services/services.dart';

/// One entry that matched, and why.
class JournalSearchHit {
  const JournalSearchHit({
    required this.entry,
    required this.score,
    required this.byMeaning,
  });

  final JournalEntry entry;

  /// Higher is better. Not comparable across the two kinds of match — it only
  /// orders hits of the same kind.
  final double score;

  /// True when the embedding found this rather than the letters. Surfaced so
  /// the UI can say so: an entry that never says "sleep" turning up under
  /// "sleep" looks like a bug unless it's labelled.
  final bool byMeaning;
}

/// Keyword and meaning search over the journal.
///
/// Both, and always both. Keyword alone misses the entry that says "I couldn't
/// switch off last night" when you search "sleep"; meaning alone misses the
/// entry that names a person or a place, because a name carries almost no
/// semantic weight. They fail in opposite directions, so the results are merged
/// with literal matches first — if the word is actually there, that is the more
/// certain answer.
class JournalSearch {
  JournalSearch(this._db);

  final JournalEntryDb _db;

  /// Below this a sentence is not a match, it is just the nearest thing.
  ///
  /// Measured on centred vectors, like everything else here, and set at the
  /// same four-sigma floor the clusterer uses for the same reason: below it,
  /// a score is indistinguishable from two unrelated sentences.
  static const double _minSimilarity = 0.18;

  static const int _maxHits = 30;

  /// Never throws. Search failing should return nothing, not take the screen
  /// down — and the semantic half is unavailable whenever the NLP model is.
  Future<List<JournalSearchHit>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final literal = _keywordHits(trimmed);
    final matched = {for (final hit in literal) hit.entry.id};

    final semantic = await _semanticHits(trimmed);
    return [
      ...literal,
      for (final hit in semantic)
        if (!matched.contains(hit.entry.id)) hit,
    ].take(_maxHits).toList();
  }

  /// Substring, case-insensitive, over the text and its keywords. Ranked by
  /// where the match lands: the words the model chose to describe an entry are
  /// a stronger signal than the same letters buried mid-sentence.
  List<JournalSearchHit> _keywordHits(String query) {
    final needle = query.toLowerCase();
    final hits = <JournalSearchHit>[];

    for (final entry in _db.getAllEntries()) {
      final text = (entry.rawText ?? '').toLowerCase();
      final keywords = (entry.keywords ?? '').toLowerCase();

      final score = keywords.contains(needle)
          ? 2.0
          : text.contains(needle)
          ? 1.0
          : 0.0;
      if (score > 0) {
        hits.add(
          JournalSearchHit(entry: entry, score: score, byMeaning: false),
        );
      }
    }

    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits;
  }

  Future<List<JournalSearchHit>> _semanticHits(String query) async {
    try {
      final embedded = await NlpService.embedSentences(query, normalize: true);
      if (embedded.isEmpty) return const [];

      final mean = _db.corpusMean();
      final queryVector = _db.centred(embedded.first.vector.toList(), mean);
      // Without a mean there is not enough journal yet for centring, and raw
      // cosine cannot tell these embeddings apart at all — so rather than
      // return confident nonsense, the semantic half sits this one out.
      if (queryVector == null) return const [];

      final best = <int, double>{};
      for (final sentence in _db.sentencesWithEmbeddings()) {
        final vector = _db.centred(sentence.embedding!, mean);
        if (vector == null) continue;
        final score = _db.similarity(queryVector, vector);
        if (score < _minSimilarity) continue;

        final entryId = sentence.entry.targetId;
        // An entry is as relevant as its single best sentence, not the average
        // of them — a long log about three things should still surface for the
        // one of them you searched for.
        if (score > (best[entryId] ?? -1)) best[entryId] = score;
      }

      final byId = {for (final entry in _db.getAllEntries()) entry.id: entry};
      final hits = [
        for (final match in best.entries)
          if (byId[match.key] case final JournalEntry entry)
            JournalSearchHit(entry: entry, score: match.value, byMeaning: true),
      ]..sort((a, b) => b.score.compareTo(a.score));
      return hits;
    } catch (e) {
      AppLog.warn('Search', 'meaning search unavailable: $e');
      return const [];
    }
  }
}
