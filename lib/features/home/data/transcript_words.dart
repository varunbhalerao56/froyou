import 'dart:collection';

import 'package:froyou/services/services.dart';

/// One word of a live transcript, carrying a stable identity.
class TranscriptWord {
  const TranscriptWord(this.id, this.text);

  /// Monotonic for the lifetime of the owning [TranscriptWords], assigned once
  /// and never reused — not even across [TranscriptWords.clear].
  ///
  /// The view keys each word's fade-in on this. Position won't do: the
  /// recognizer revises its tail, so a word can shift index without being new.
  /// Text won't do either: words repeat.
  final int id;

  final String text;

  @override
  bool operator ==(Object other) =>
      other is TranscriptWord && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);

  @override
  String toString() => 'TranscriptWord($id, "$text")';
}

/// The live transcript, as a flat list of individually-identified words.
///
/// Replaces the older finals-list-plus-partial-string pair. The split is still
/// here — [settledCount] is the watermark — but as an index into one list
/// rather than two structures, because the view needs a single ordered
/// sequence and the diff needs to reconcile a sublist.
///
/// **Why a diff at all.** The native side emits one event per
/// `SpeechTranscriber.Result`, and within an unfinalized range successive
/// volatile results are cumulative *and revisable* — "chest tight" can become
/// "chest tighten" — with a final that may itself revise the volatile text it
/// settles. Re-fading every word on every event would strobe. So each event is
/// reconciled against what is already on screen, and only genuinely-new words
/// get new identities.
///
/// Deliberately free of Flutter, clocks and streams: the fade timing lives in
/// the view, which makes this a pure unit test.
class TranscriptWords {
  final List<TranscriptWord> _words = [];

  /// Read-only view over the live list — a wrapper, not a copy, so the widget
  /// can read it every frame without allocating.
  late final List<TranscriptWord> words = UnmodifiableListView(_words);

  int _settledCount = 0;
  int _nextId = 0;

  /// Words in `[0, settledCount)` have been finalized by the recognizer and are
  /// never revised again.
  int get settledCount => _settledCount;

  bool get isEmpty => _words.isEmpty;
  bool get isNotEmpty => _words.isNotEmpty;

  /// The whole transcript as text, for the editable field to take over.
  String get joined => _words.map((word) => word.text).join(' ');

  void ingest(SpeechTranscript transcript) {
    final incoming = _tokenize(transcript.text);

    if (incoming.isEmpty) {
      // An empty *final* still settles whatever is pending — that is how a
      // trailing result from stop() behaves when the last range was volatile.
      if (transcript.isFinal) _settledCount = _words.length;
      return;
    }

    // Reconcile only the volatile tail. Finalized ranges are immutable by the
    // SpeechTranscriber contract, and re-fading them would undo the point.
    var index = _settledCount;
    var offset = 0;
    while (index < _words.length &&
        offset < incoming.length &&
        _words[index].text == incoming[offset]) {
      index++;
      offset++;
    }

    // Everything past the common prefix is genuinely different text, so it
    // gets fresh identities and fades in. Survivors keep theirs and stay put.
    if (index < _words.length) _words.removeRange(index, _words.length);
    for (; offset < incoming.length; offset++) {
      _words.add(TranscriptWord(_nextId++, incoming[offset]));
    }

    // After reconciling, never before: settling first would freeze the old
    // volatile words and force the final's revision to append rather than
    // replace, which is exactly the double-text bug this ordering avoids.
    if (transcript.isFinal) _settledCount = _words.length;
  }

  /// Known limitation: a *prefix* revision ("chest tight" → "my chest tighten")
  /// shares no common prefix, so the whole tail re-fades. Rare with a
  /// suffix-anchored recognizer, and those words have all moved position
  /// anyway, so re-animating them is honest rather than wrong.
  void clear() {
    _words.clear();
    _settledCount = 0;
    // _nextId deliberately not reset: a view still mounted from the previous
    // session would otherwise match old ids to new words and skip their fade.
  }

  static final RegExp _whitespace = RegExp(r'\s+');

  static List<String> _tokenize(String text) =>
      text.split(_whitespace).where((token) => token.isNotEmpty).toList();
}
