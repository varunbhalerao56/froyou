import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:froyou/core/config/label_mode.dart';
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
  JournalRepository(this._db, {this.onChanged, this.onEnriched});

  final JournalEntryDb _db;

  /// Fired after phase 1 commits and again when phase 2 finishes, so the log
  /// list shows the entry immediately and then fills in its derived data.
  final VoidCallback? onChanged;

  /// Fired once at the end of phase 2, after the clusters have been renamed.
  ///
  /// Distinct from [onChanged] on purpose: this is for work that depends on
  /// the *derived* data being current — the reminder body, which is written
  /// from the theme labels — so it must not fire on a plain save, a delete or
  /// a clear, none of which produce new labels.
  final VoidCallback? onEnriched;

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
      // The statistical answer, synchronously, so the card is never blank.
      // `KeywordNamer` replaces it with the model's during enrichment — phase 1
      // of a save cannot wait on an inference, and must not fail with one.
      ..keywords = kModelOnlyLabels ? null : ClusterLabeler.keywordsFor(trimmed)
      ..createdAt = DateTime.now();

    final id = await _db.putEntry(entry);
    entry.id = id; // putAsync does not write the id back onto the instance
    onChanged?.call();

    unawaited(_enrich(entry));
    return id;
  }

  Future<void> deleteEntry(JournalEntry entry) async {
    await _db.deleteEntry(entry);
    // Removing a sentence changes what's distinctive about the clusters that
    // remain, so the surviving labels need rescoring too.
    await ClusterNamer.relabelAll(_db);
    onChanged?.call();
  }

  Future<void> clearAll() async {
    _db.clearAll();
    onChanged?.call();
  }

  Future<void> _enrich(JournalEntry entry) async {
    final text = entry.rawText;
    if (text == null || text.isEmpty) return;

    _enrichingCount++;
    onChanged?.call();

    // The input, once, before anything derived from it — so every line that
    // follows can be read against the words that produced it.
    AppLog.info(
      'Journal',
      'enriching entry ${entry.id} · "${text.length <= 120 ? text : '${text.substring(0, 120).trimRight()}…'}"',
    );

    // Sentiment is independent of the embedding pass — worth keeping even when
    // the contextual-embedding assets are missing, which is the normal state in
    // the Simulator.
    try {
      entry.moodScore = await NlpService.sentimentScore(text);
      await _db.putEntry(entry);
      AppLog.info('Journal', 'entry ${entry.id} · mood ${entry.moodScore}');
    } catch (e) {
      AppLog.warn('Journal', 'sentiment unavailable for ${entry.id}: $e');
    }

    // Upgrades what `save` already wrote. Independent of the embedding pass on
    // purpose: these are what the card shows, and they are worth having on a
    // device where the contextual-embedding assets never arrive.
    final keywords = await KeywordNamer.forEntry(text);
    AppLog.info('Journal', 'entry ${entry.id} · keywords: ${keywords ?? '—'}');
    if (keywords != entry.keywords) {
      entry.keywords = keywords;
      await _db.putEntry(entry);
      onChanged?.call();
    }

    try {
      // normalize: true is required, not cosmetic. Cosine similarity is
      // scale-invariant, but the cluster centroid is maintained as a running
      // raw sum — so unnormalized vectors would let long sentences dominate it.
      final embedded = await NlpService.embedSentences(
        text,
        normalize: true,
      ).timeout(_enrichTimeout);

      for (final embedding in embedded) {
        await _db.putSentenceInEntry(
          entry,
          JournalSentence()
            ..text = embedding.sentence
            ..keywords = kModelOnlyLabels
                ? null
                : ClusterLabeler.keywordsFor(embedding.sentence)
            ..embedding = embedding.vector.toList(),
        );
      }

      // Every theme, from every sentence, but only when that would come out
      // different — see `maybeRecluster`. The earliest sentences were placed
      // before the common direction could be estimated, so they do need
      // redoing; they just don't need redoing on every save forever.
      final themes = _db.maybeRecluster();
      AppLog.info(
        'Journal',
        'entry ${entry.id} · ${embedded.length} sentences embedded · '
            '$themes themes',
      );

      await ClusterNamer.relabelAll(_db);
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
      // In the `finally`, so it runs on the degraded paths too — a save whose
      // embeddings failed still has the previous labels worth reminding from.
      // Outside the `try` above on purpose: a listener throwing here must not
      // be caught and reported as an embedding failure.
      onEnriched?.call();
    }
  }

  /// Fallback when embeddings aren't available: still split the entry into
  /// sentences and store them, just without vectors. They won't cluster — but
  /// the entry reads correctly, and a later re-enrich could fill them in.
  Future<void> _saveUnclusteredSentences(
    JournalEntry entry,
    String text,
  ) async {
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
          ..keywords = kModelOnlyLabels
              ? null
              : ClusterLabeler.keywordsFor(sentence),
      );
    }
  }
}
