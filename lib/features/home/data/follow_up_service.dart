import 'dart:convert';

import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/features/journal/journal.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/services/services.dart';

/// The question that replaces "How are you feeling?" the morning after a rough
/// day.
///
/// Three rules shape this, and they're all about not being annoying:
///
/// * It only appears the **day after**, never in the moment. Asking someone how
///   a bad day is sitting while they're still in it isn't reflection, it's
///   nagging.
/// * It triggers on the **day's average** mood, not any single low entry — one
///   passing grumble inside an otherwise fine day shouldn't summon a check-in.
/// * It clears the moment they log today. It has done its job, and leaving it
///   up would keep re-raising something already addressed.
///
/// The generated text is cached against the date it was made for, so Home never
/// waits on the model.
class FollowUpService {
  /// Callers pass `store:` and `db:` — the private names are initializing
  /// formals, which Dart maps to their public form.
  FollowUpService({required this._store, required this._db});

  final ProfileStore _store;
  final JournalEntryDb _db;

  static const String _cacheKey = 'home.followUp';

  /// Below this, yesterday counts as a hard day. Not 0: everyday writing skews
  /// slightly negative, and a threshold at neutral would fire almost daily.
  static const double moodThreshold = -0.15;

  /// Sentences handed to the model as context. Enough to ground the question,
  /// short enough to stay well inside the prompt budget.
  static const int _themeCount = 3;

  /// Returns the pending question, or null when there shouldn't be one.
  ///
  /// Never throws: this decorates the home screen, and no failure here is worth
  /// showing the user anything at all.
  Future<String?> pendingQuestion({DateTime? now}) async {
    try {
      final today = _startOfDay(now ?? DateTime.now());

      // Rule three, checked first because it's the cheapest and the most
      // common exit.
      if (_hasEntriesOn(today)) {
        await _clearCache();
        return null;
      }

      final cached = _readCache(today);
      if (cached != null) return cached;

      final yesterday = today.subtract(const Duration(days: 1));
      final entries = _entriesOn(yesterday);
      if (entries.isEmpty) return null;

      final scored = entries
          .map((entry) => entry.moodScore)
          .whereType<double>()
          .toList();
      if (scored.isEmpty) return null;

      final average = scored.reduce((a, b) => a + b) / scored.length;
      if (average >= moodThreshold) return null;

      if (!(await GenAiService.availability()).isAvailable) return null;

      final question = await GenAiService.followUpQuestion(
        themes: _recentThemes(yesterday),
        excerpt: _excerptFrom(entries),
      );
      if (question.isEmpty) return null;

      await _writeCache(today, question);
      return question;
    } catch (e) {
      AppLog.warn('FollowUp', 'skipped: $e');
      return null;
    }
  }

  /// Called after a log saves, so the prompt reverts to its default without
  /// waiting for the next launch.
  Future<void> clear() => _clearCache();

  /// The same question, generated on demand from the most recent log.
  ///
  /// For the debug menu only. [pendingQuestion] answers "should there be a
  /// question right now", which is almost always no — it needs yesterday to
  /// have been a rough day and today to be empty — so there is otherwise no way
  /// to see this working without waiting a day and feeling bad first. This
  /// skips the timing and the mood gate, keeps the prompt identical, and
  /// returns the context alongside the answer so it is visible what the model
  /// was actually given.
  Future<FollowUpPreview> preview() async {
    final entries = _db.getAllEntries();
    if (entries.isEmpty) {
      return const FollowUpPreview(error: 'No logs yet — write one first.');
    }

    final availability = await GenAiService.availability();
    if (!availability.isAvailable) {
      return FollowUpPreview(
        error: 'The model is unavailable (${availability.reason?.name}).',
      );
    }

    // The newest entry rather than the lowest-mood one, unlike the real path:
    // for a demonstration, "the last thing you wrote" is the thing whose
    // follow-up you can actually judge.
    final latest = entries.first;
    final themes = _recentThemes(
      (latest.createdAt ?? DateTime.now()).subtract(const Duration(days: 1)),
    );
    final excerpt = _excerptFrom([latest]);

    try {
      final question = await GenAiService.followUpQuestion(
        themes: themes,
        excerpt: excerpt,
      );
      return FollowUpPreview(
        themes: themes,
        excerpt: excerpt,
        question: question.isEmpty ? null : question,
        error: question.isEmpty ? 'The model returned nothing.' : null,
      );
    } catch (e) {
      return FollowUpPreview(themes: themes, excerpt: excerpt, error: '$e');
    }
  }

  // ---------------------------------------------------------------------------

  List<JournalEntry> _entriesOn(DateTime day) {
    final start = _startOfDay(day);
    final end = start.add(const Duration(days: 1));
    return _db
        .getAllEntries()
        .where(
          (entry) =>
              entry.createdAt != null &&
              !entry.createdAt!.isBefore(start) &&
              entry.createdAt!.isBefore(end),
        )
        .toList();
  }

  bool _hasEntriesOn(DateTime day) => _entriesOn(day).isNotEmpty;

  /// The themes yesterday actually touched, most-recent-first.
  List<String> _recentThemes(DateTime day) {
    final start = _startOfDay(day);
    final clusterIds = <int>{
      for (final sentence in _db.sentencesSince(start))
        if (sentence.clusterId case final int id) id,
    };

    return [
      for (final id in clusterIds)
        if (_db.getThemeCluster(id)?.label case final String label)
          if (label.trim().isNotEmpty) label.trim(),
    ].take(_themeCount).toList();
  }

  /// The most negative entry's text, truncated. The lowest one rather than the
  /// latest: it is the thing most worth asking about.
  String _excerptFrom(List<JournalEntry> entries) {
    final withMood = entries.where((e) => e.moodScore != null).toList()
      ..sort((a, b) => a.moodScore!.compareTo(b.moodScore!));
    final source = withMood.isEmpty ? entries.first : withMood.first;
    return ClusterLabeler.snippet(source.rawText ?? '', maxLength: 220);
  }

  String? _readCache(DateTime today) {
    final raw = _store.getString(_cacheKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      // Keyed by date so yesterday's question can never resurface today.
      if (decoded['date'] != _dateKey(today)) return null;
      final question = decoded['question'];
      return question is String && question.isNotEmpty ? question : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(DateTime today, String question) => _store.setString(
    _cacheKey,
    jsonEncode({'date': _dateKey(today), 'question': question}),
  );

  Future<void> _clearCache() => _store.remove(_cacheKey);

  static DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dateKey(DateTime value) =>
      '${value.year}-${value.month}-${value.day}';
}

/// What the model was given, and what it gave back. Debug-menu only.
class FollowUpPreview {
  const FollowUpPreview({
    this.themes = const [],
    this.excerpt,
    this.question,
    this.error,
  });

  /// The theme labels handed over as context — the same ones the real path
  /// sends, which is why an unnamed theme shows up here as an empty list.
  final List<String> themes;

  /// The words from the log itself, truncated exactly as the real path does.
  final String? excerpt;

  final String? question;
  final String? error;
}
