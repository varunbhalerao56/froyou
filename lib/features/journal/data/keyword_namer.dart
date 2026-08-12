import 'dart:async';

import 'package:froyou/core/config/label_mode.dart';
import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/features/journal/data/cluster_labeler.dart';
import 'package:froyou/services/services.dart';

/// The words shown under one log, preferring the on-device language model.
///
/// The same arrangement as `ClusterNamer` and for a sharper version of the same
/// reason. [ClusterLabeler.keywordsFor] can only return words that literally
/// appear in the entry, and it ranks them by how often they appear — which
/// works when there is a corpus to be distinctive against and collapses when
/// there isn't. A single short entry uses almost every word once, so the scores
/// tie at one and the alphabetical tie-break decides: an entry about carrying
/// shame came out as "better, deal", because b and d sort before s.
///
/// The model reads the entry instead of counting it. It is absent on ineligible
/// hardware and whenever Apple Intelligence is off, so the statistical path
/// stays as the floor rather than being replaced.
class KeywordNamer {
  KeywordNamer._();

  /// The comma-joined keywords for [text], or null if there is nothing to say.
  ///
  /// Never throws and never returns worse than the statistical answer: every
  /// failure path falls through to [ClusterLabeler.keywordsFor], which is what
  /// the entry was already showing.
  static Future<String?> forEntry(String text) async {
    final generated = await _fromModel(text);
    if (generated != null) return generated;
    // Blank rather than the frequency count, so "did the model run" is
    // answerable by looking at the card. See [kModelOnlyLabels].
    return kModelOnlyLabels ? null : ClusterLabeler.keywordsFor(text);
  }

  static Future<String?> _fromModel(String text) async {
    try {
      final availability = await GenAiService.availability();
      if (!availability.isAvailable) {
        AppLog.warn(
          'KeywordNamer',
          'model unavailable (${availability.reason?.name}) — no keywords',
        );
        return null;
      }

      final keywords = await GenAiService.entryKeywords(text);
      if (keywords.isEmpty) {
        AppLog.warn('KeywordNamer', 'model returned no keywords');
        return null;
      }

      // Deduplicated the same way the statistical path does it — a keyword
      // already covered by a longer one it overlaps says nothing twice.
      final chosen = <String>[];
      for (final keyword in keywords.map((k) => k.toLowerCase().trim())) {
        if (keyword.isEmpty) continue;
        final overlaps = chosen.any(
          (kept) => kept.contains(keyword) || keyword.contains(kept),
        );
        if (!overlaps) chosen.add(keyword);
      }

      return chosen.isEmpty ? null : chosen.join(', ');
    } on GenAiException catch (e) {
      AppLog.warn('KeywordNamer', 'model unusable (${e.code}): ${e.message}');
      return null;
    } on TimeoutException {
      AppLog.warn('KeywordNamer', 'model timed out');
      return null;
    } catch (e, stackTrace) {
      AppLog.error('KeywordNamer', 'model keywords failed', e, stackTrace);
      return null;
    }
  }
}
