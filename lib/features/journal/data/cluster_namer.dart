import 'dart:async';

import 'package:froyou/core/config/label_mode.dart';
import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/features/journal/journal.dart';
import 'package:froyou/services/services.dart';

/// Names every theme cluster, preferring the on-device language model.
///
/// The statistical labeler can only return words that literally appear in the
/// text, so it cannot tell that "my manager pushed the date again" and "the
/// timeline slipped" are one worry. The model can. But it is absent on
/// ineligible hardware and whenever Apple Intelligence is off, so
/// [ClusterLabeler] stays as the floor rather than being replaced.
///
/// Always *every* cluster, never just the ones that changed: both strategies
/// score names against each other, so one new sentence shifts what counts as
/// distinctive everywhere.
class ClusterNamer {
  ClusterNamer._();

  /// How many of each cluster's most central sentences go into the prompt.
  /// Enough to show the model the shape of a theme, few enough that a dozen
  /// clusters still fit in its context.
  static const int sentencesPerCluster = 6;

  /// Returns true if the model did the naming, false if the fallback did.
  /// Callers mostly ignore this; it exists so tests and the debug seed can say
  /// which path ran.
  static Future<bool> relabelAll(JournalEntryDb db) async {
    if (await _labelWithModel(db)) return true;
    // Themes stay unnamed rather than falling to c-TF-IDF. See
    // [kModelOnlyLabels].
    if (kModelOnlyLabels) return false;
    db.relabelAllClusters();
    return false;
  }

  static Future<bool> _labelWithModel(JournalEntryDb db) async {
    try {
      final availability = await GenAiService.availability();
      if (!availability.isAvailable) {
        AppLog.warn(
          'ClusterNamer',
          'model unavailable (${availability.reason?.name}) — themes unnamed',
        );
        return false;
      }

      final members = db.centralSentencesByCluster(
        perCluster: sentencesPerCluster,
      );
      if (members.isEmpty) return false;

      final labels = await GenAiService.labelThemes(members);
      if (labels.isEmpty) {
        AppLog.warn('ClusterNamer', 'model returned no theme names');
        return false;
      }

      db.applyClusterLabels({
        for (final label in labels) label.clusterId: label.label,
      });
      AppLog.info(
        'ClusterNamer',
        'named ${labels.length} themes: '
            '${labels.map((l) => l.label).join(" | ")}',
      );
      return true;
    } on GenAiException catch (e) {
      AppLog.warn('ClusterNamer', 'model unusable (${e.code}): ${e.message}');
      return false;
    } on TimeoutException {
      AppLog.warn('ClusterNamer', 'model timed out');
      return false;
    } catch (e, stackTrace) {
      AppLog.error('ClusterNamer', 'model labeling failed', e, stackTrace);
      return false;
    }
  }
}
