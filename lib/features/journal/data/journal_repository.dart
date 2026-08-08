import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/features/journal/journal.dart';
import 'package:froyou/services/services.dart';

/// The save pipeline, in two deliberately separated phases.
///
/// Phase 1 persists the raw text and returns. Phase 2 — sentiment, sentence
/// embeddings, clustering — runs unawaited afterwards. The split is the whole
/// point: the on-device NLP can be slow, unavailable, or missing its model
/// assets entirely, and none of that is allowed to cost the user the words
/// they just said.
class JournalRepository {
  JournalRepository(this._db, {this.onChanged});

  final JournalEntryDb _db;

  /// Fired after phase 1 commits and again when phase 2 finishes, so the log
  /// list shows the entry immediately and then fills in its derived data.
  final VoidCallback? onChanged;

  /// Generous, because the very first `embedSentences` call on a device also
  /// downloads the contextual-embedding model assets.
  static const Duration _enrichTimeout = Duration(seconds: 30);

  int _enrichingCount = 0;
  bool get isEnriching => _enrichingCount > 0;

  List<JournalEntry> allEntries() => _db.getAllEntries();

  int countEntries() => _db.countEntries();

  Future<int> save(String text) async {
    final trimmed = text.trim();

    final entry = JournalEntry()
      ..rawText = trimmed
      ..keywords = ClusterLabeler.keywordsFor(trimmed)
      ..createdAt = DateTime.now();

    final id = await _db.putEntry(entry);
    entry.id = id; // putAsync does not write the id back onto the instance
    onChanged?.call();

    unawaited(_enrich(entry));
    return id;
  }

  Future<void> deleteEntry(JournalEntry entry) async {
    await _db.deleteEntry(entry);
    onChanged?.call();
  }

  Future<void> _enrich(JournalEntry entry) async {
    final text = entry.rawText;
    if (text == null || text.isEmpty) return;

    _enrichingCount++;
    onChanged?.call();

    // Sentiment is independent of the embedding pass — worth keeping even when
    // the contextual-embedding assets are missing, which is the normal state in
    // the Simulator.
    try {
      entry.moodScore = await NlpService.sentimentScore(text);
      await _db.putEntry(entry);
    } catch (e) {
      AppLog.warn('Journal', 'sentiment unavailable for ${entry.id}: $e');
    }

    try {
      // normalize: true is required, not cosmetic. Cosine similarity is
      // scale-invariant, but the cluster centroid is maintained as a running
      // raw sum — so unnormalized vectors would let long sentences dominate it.
      final embedded = await NlpService.embedSentences(
        text,
        normalize: true,
      ).timeout(_enrichTimeout);

      final touchedClusters = <int>{};
      for (final embedding in embedded) {
        final sentence = JournalSentence()
          ..text = embedding.sentence
          ..keywords = ClusterLabeler.keywordsFor(embedding.sentence)
          ..embedding = embedding.vector.toList();

        await _db.putSentenceInEntry(entry, sentence);

        final clusterId = sentence.clusterId;
        if (clusterId != null) touchedClusters.add(clusterId);
      }

      _db.relabelClusters(touchedClusters);
    } on NlpException catch (e) {
      AppLog.warn(
        'Journal',
        'embedding unavailable (${e.code}); entry ${entry.id} kept unclustered',
      );
      await _saveUnclusteredSentences(entry, text);
    } on TimeoutException {
      AppLog.warn(
        'Journal',
        'embedding timed out; entry ${entry.id} kept unclustered',
      );
      await _saveUnclusteredSentences(entry, text);
    } catch (e, stackTrace) {
      AppLog.error('Journal', 'enrich failed for ${entry.id}', e, stackTrace);
    } finally {
      _enrichingCount--;
      onChanged?.call();
    }
  }

  /// Fallback when embeddings aren't available: still split the entry into
  /// sentences and store them, just without vectors. They won't cluster — but
  /// the entry reads correctly, and a later re-enrich could fill them in.
  Future<void> _saveUnclusteredSentences(JournalEntry entry, String text) async {
    List<String> sentences;
    try {
      sentences = await NlpService.splitSentences(text);
    } catch (_) {
      sentences = [text]; // NLTokenizer gone too — keep the entry as one unit
    }

    for (final sentence in sentences) {
      if (sentence.trim().isEmpty) continue;
      await _db.putSentenceInEntry(
        entry,
        JournalSentence()
          ..text = sentence
          ..keywords = ClusterLabeler.keywordsFor(sentence),
      );
    }
  }
}
