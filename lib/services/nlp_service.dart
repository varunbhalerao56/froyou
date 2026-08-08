import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart facade over the native `app/nlp` MethodChannel, which wraps Apple's
/// NaturalLanguage framework.
///
/// All four methods are plain request→response, so this is a static-only class
/// with a private constructor — matching the convention used by `AppTypography`
/// and `AppTheme` in `lib/theme/`. There is no state worth holding.
///
/// **iOS only.** On other platforms every call throws
/// [NlpException] with [NlpException.unavailable].
///
/// ```dart
/// final sentences = await NlpService.splitSentences(transcript);
/// final mood = await NlpService.sentimentScore(transcript);
/// ```
class NlpService {
  NlpService._();

  @visibleForTesting
  static const MethodChannel channel = MethodChannel('app/nlp');

  /// Error code the native side uses when no embedding model exists for the
  /// requested (or detected) language.
  static const String unsupportedLanguageCode = 'nlp_unsupported_language';

  /// Error code for when the embedding model's assets could not be downloaded.
  static const String assetsUnavailableCode = 'nlp_assets_unavailable';

  /// Splits [text] into sentences using `NLTokenizer`.
  ///
  /// Handles the cases a naive split on `.` cannot — abbreviations
  /// ("Dr. Smith went to Washington." is one sentence), decimals, ellipses.
  /// Returned sentences are trimmed; empty ones are dropped.
  static Future<List<String>> splitSentences(String text) async {
    if (text.isEmpty) return const [];

    final result = await _invoke<List<Object?>>('splitSentences', {
      'text': text,
    });
    return result.cast<String>();
  }

  /// Scores the overall sentiment of [text] from `-1.0` (negative) through
  /// `0.0` (neutral) to `1.0` (positive).
  ///
  /// Returns `0.0` both for genuinely neutral text and for text the tagger has
  /// no opinion about — the underlying API does not distinguish the two.
  static Future<double> sentimentScore(String text) async {
    if (text.isEmpty) return 0.0;

    return _invoke<double>('sentimentScore', {'text': text});
  }

  /// Extracts people, places and organizations from [text] using `NLTagger`.
  ///
  /// Entity offsets index into [text] directly, so
  /// `text.substring(e.start, e.end) == e.text` holds — including for text
  /// containing emoji, because the native side converts through `NSRange`
  /// (UTF-16), which is exactly how Dart indexes strings.
  static Future<List<NlpEntity>> extractEntities(String text) async {
    if (text.isEmpty) return const [];

    final result = await _invoke<List<Object?>>('extractEntities', {
      'text': text,
    });
    return result
        .cast<Map<Object?, Object?>>()
        .map(NlpEntity._fromMap)
        .toList(growable: false);
  }

  /// Produces a single embedding vector for [text] via
  /// `NLContextualEmbedding`, mean-pooled across tokens natively.
  ///
  /// [language] is a BCP-47 code. When omitted the native side detects the
  /// dominant language, which can fail on very short or ambiguous input — pass
  /// it explicitly if you already know it.
  ///
  /// When [normalize] is true the vector is scaled to unit length, so a plain
  /// dot product between two results gives cosine similarity.
  ///
  /// Unlike speech, this has no separate "ensure model" step: if the model's
  /// assets aren't on the device this call downloads them and waits, which can
  /// be slow on the first call for a given language.
  static Future<Float64List> embed(
    String text, {
    String? language,
    bool normalize = false,
  }) async {
    if (text.isEmpty) return Float64List(0);

    final result = await _invoke<List<Object?>>('embed', {
      'text': text,
      'language': ?language,
      'normalize': normalize,
    });
    return Float64List.fromList(result.cast<double>());
  }

  /// One embedding per sentence, with the split done natively.
  ///
  /// Prefer this over calling [splitSentences] and then [embed] in a loop: it's
  /// one channel round-trip instead of N+1, and the language is detected once
  /// over the whole text rather than per sentence — detection on a single short
  /// sentence is unreliable.
  ///
  /// Each sentence is embedded **independently**, so a sentence's vector does
  /// not depend on its neighbours. That matters if you're storing these to
  /// compare across entries: `NLContextualEmbedding` is contextual, so
  /// embedding a whole paragraph in one pass would make the same sentence
  /// produce different vectors depending on what surrounded it, which quietly
  /// degrades similarity search. Isolating each sentence keeps sentence→vector
  /// a pure function.
  ///
  /// Offsets index into [text], so `text.substring(s.start, s.end) == s.sentence`.
  static Future<List<NlpSentenceEmbedding>> embedSentences(
    String text, {
    String? language,
    bool normalize = false,
  }) async {
    if (text.isEmpty) return const [];

    final result = await _invoke<List<Object?>>('embedSentences', {
      'text': text,
      'language': ?language,
      'normalize': normalize,
    });
    return result
        .cast<Map<Object?, Object?>>()
        .map(NlpSentenceEmbedding._fromMap)
        .toList(growable: false);
  }

  /// Single funnel for channel calls so error translation lives in one place.
  ///
  /// [MissingPluginException] means we're not on iOS (or the channel wasn't
  /// registered); everything else is a genuine native failure carrying one of
  /// the `nlp_*` codes.
  static Future<T> _invoke<T>(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final result = await channel.invokeMethod<T>(method, arguments);
      if (result == null) {
        throw NlpException._(
          'nlp_internal',
          'Native method "$method" returned null.',
        );
      }
      return result;
    } on MissingPluginException {
      throw NlpException._(
        NlpException.unavailable,
        'Natural-language processing is only available on iOS.',
      );
    } on PlatformException catch (error) {
      throw NlpException._(
        error.code,
        error.message ?? 'Native call "$method" failed.',
      );
    }
  }
}

/// One sentence and its embedding, from [NlpService.embedSentences].
@immutable
class NlpSentenceEmbedding {
  /// The sentence text, whitespace-trimmed.
  final String sentence;

  /// The mean-pooled embedding. Unit length when `normalize: true` was passed,
  /// in which case a dot product against another such vector is cosine
  /// similarity.
  final Float64List vector;

  /// Start offset into the source string, inclusive.
  final int start;

  /// End offset into the source string, exclusive.
  final int end;

  const NlpSentenceEmbedding({
    required this.sentence,
    required this.vector,
    required this.start,
    required this.end,
  });

  factory NlpSentenceEmbedding._fromMap(Map<Object?, Object?> map) {
    final raw = map['vector'] as List<Object?>? ?? const [];
    return NlpSentenceEmbedding(
      sentence: map['sentence'] as String? ?? '',
      vector: Float64List.fromList(raw.cast<double>()),
      start: map['start'] as int? ?? 0,
      end: map['end'] as int? ?? 0,
    );
  }

  @override
  String toString() =>
      'NlpSentenceEmbedding("$sentence", ${vector.length}d @ $start-$end)';
}

/// The kinds of entity `NLTagger`'s `.nameType` scheme reports.
enum NlpEntityType {
  personalName,
  placeName,
  organizationName,

  /// Anything the native side reported that we don't have a case for. Mapping
  /// to this rather than throwing keeps a future OS adding a tag type from
  /// breaking the app.
  other;

  static NlpEntityType _fromRaw(String? raw) {
    switch (raw) {
      case 'PersonalName':
        return NlpEntityType.personalName;
      case 'PlaceName':
        return NlpEntityType.placeName;
      case 'OrganizationName':
        return NlpEntityType.organizationName;
      default:
        return NlpEntityType.other;
    }
  }
}

/// A named entity found in a piece of text.
@immutable
class NlpEntity {
  /// The matched substring.
  final String text;

  /// What kind of thing it is.
  final NlpEntityType type;

  /// Start offset into the source string, inclusive.
  final int start;

  /// End offset into the source string, exclusive.
  final int end;

  const NlpEntity({
    required this.text,
    required this.type,
    required this.start,
    required this.end,
  });

  factory NlpEntity._fromMap(Map<Object?, Object?> map) {
    return NlpEntity(
      text: map['text'] as String? ?? '',
      type: NlpEntityType._fromRaw(map['type'] as String?),
      start: map['start'] as int? ?? 0,
      end: map['end'] as int? ?? 0,
    );
  }

  @override
  String toString() => 'NlpEntity(${type.name}: "$text" @ $start-$end)';

  @override
  bool operator ==(Object other) =>
      other is NlpEntity &&
      other.text == text &&
      other.type == type &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(text, type, start, end);
}

/// Raised by every [NlpService] method when a native call fails.
///
/// Match on [code] rather than [message] — the codes are the stable contract
/// with the Swift side.
@immutable
class NlpException implements Exception {
  /// The channel isn't registered, which in practice means "not running on iOS".
  static const String unavailable = 'nlp_unavailable';

  final String code;
  final String message;

  const NlpException._(this.code, this.message);

  /// Whether this platform has no NLP support at all.
  bool get isUnavailable => code == unavailable;

  /// Whether the failure was a language the models don't cover.
  bool get isUnsupportedLanguage => code == NlpService.unsupportedLanguageCode;

  @override
  String toString() => 'NlpException($code): $message';
}
