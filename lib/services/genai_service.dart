import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Why the on-device model can't be used.
///
/// These demand different product responses, which is the whole reason they're
/// distinct: [deviceNotEligible] is permanent and should never be mentioned to
/// the user, [appleIntelligenceNotEnabled] is a setting they control, and
/// [modelNotReady] is temporary and worth retrying.
enum GenAiUnavailableReason {
  deviceNotEligible,
  appleIntelligenceNotEnabled,
  modelNotReady,

  /// The channel isn't there at all, or the OS reported a reason this build
  /// doesn't know about. Apple has said more will be added.
  unknown;

  static GenAiUnavailableReason _fromRaw(String? raw) => switch (raw) {
    'device_not_eligible' => GenAiUnavailableReason.deviceNotEligible,
    'apple_intelligence_not_enabled' =>
      GenAiUnavailableReason.appleIntelligenceNotEnabled,
    'model_not_ready' => GenAiUnavailableReason.modelNotReady,
    _ => GenAiUnavailableReason.unknown,
  };

  /// Whether pointing the user at Settings would actually help. Only true for
  /// the one case they can fix.
  bool get isUserFixable =>
      this == GenAiUnavailableReason.appleIntelligenceNotEnabled;
}

@immutable
class GenAiAvailability {
  const GenAiAvailability({required this.isAvailable, this.reason});

  final bool isAvailable;
  final GenAiUnavailableReason? reason;

  static const GenAiAvailability unknown = GenAiAvailability(
    isAvailable: false,
    reason: GenAiUnavailableReason.unknown,
  );
}

/// One named theme, as the model saw it.
@immutable
class GenAiThemeLabel {
  const GenAiThemeLabel({required this.clusterId, required this.label});

  final int clusterId;
  final String label;
}

/// Dart facade over the native `app/genai` MethodChannel, which wraps Apple's
/// Foundation Models framework.
///
/// Static like [NlpService] rather than an instance: every call is an
/// independent request→response with no session held across them.
///
/// **Nothing here is guaranteed to work.** The model is absent on ineligible
/// hardware, when Apple Intelligence is off, and while assets download. Callers
/// must have a path that works without it — for theme naming that's
/// `ClusterLabeler`; for the follow-up question it's showing no question at all.
class GenAiService {
  GenAiService._();

  @visibleForTesting
  static const MethodChannel channel = MethodChannel('app/genai');

  /// Generation is slower than a channel round-trip has any right to be, and a
  /// save must never hang on it.
  static const Duration defaultTimeout = Duration(seconds: 25);

  /// After this many consecutive generation failures, stop asking for the rest
  /// of the session.
  ///
  /// `availability` reporting `.available` is necessary but not sufficient:
  /// generation also needs Apple's safety classifier, and when *that* asset is
  /// missing every call fails with the model still advertised as present. The
  /// Simulator is exactly this case. Without a latch each save would pay a
  /// pointless failed inference forever.
  static const int _failureLatch = 2;

  static int _consecutiveFailures = 0;

  /// Resets the latch. Only for tests — in the app a relaunch is the retry.
  @visibleForTesting
  static void resetFailureLatch() => _consecutiveFailures = 0;

  /// Never throws. Availability is the one thing callers check before deciding
  /// whether to bother, so making it a question rather than an exception keeps
  /// every call site simple.
  static Future<GenAiAvailability> availability() async {
    if (_consecutiveFailures >= _failureLatch) {
      return GenAiAvailability.unknown;
    }
    try {
      final result = await channel.invokeMapMethod<String, Object?>(
        'availability',
      );
      if (result == null) return GenAiAvailability.unknown;
      if (result['status'] == 'available') {
        return const GenAiAvailability(isAvailable: true);
      }
      return GenAiAvailability(
        isAvailable: false,
        reason: GenAiUnavailableReason._fromRaw(result['reason'] as String?),
      );
    } on MissingPluginException {
      return GenAiAvailability.unknown;
    } on PlatformException {
      return GenAiAvailability.unknown;
    }
  }

  /// Names every cluster in one request.
  ///
  /// All of them together, not one at a time: the model can only make the names
  /// distinguish each other if it sees them side by side — and it keeps a save
  /// to a single inference.
  ///
  /// [clusters] maps a cluster id to its most representative sentences. Keep
  /// that list short; the prompt has to fit in the model's context.
  static Future<List<GenAiThemeLabel>> labelThemes(
    Map<int, List<String>> clusters, {
    Duration timeout = defaultTimeout,
  }) async {
    if (clusters.isEmpty) return const [];

    final result = await _invoke<Map<Object?, Object?>>('labelThemes', {
      'clusters': [
        for (final entry in clusters.entries)
          if (entry.value.isNotEmpty)
            {'id': entry.key, 'sentences': entry.value},
      ],
    }, timeout: timeout);

    final labels = result['labels'];
    if (labels is! List) return const [];

    return [
      for (final raw in labels)
        if (raw is Map)
          if (raw['id'] case final int id)
            if (raw['label'] case final String label)
              if (label.trim().isNotEmpty)
                GenAiThemeLabel(clusterId: id, label: label.trim()),
    ];
  }

  /// The few words shown under one log on its card.
  ///
  /// One entry per call, unlike [labelThemes], because these describe an entry
  /// on its own terms rather than against its neighbours — there is nothing to
  /// be gained from the model seeing them together.
  static Future<List<String>> entryKeywords(
    String text, {
    Duration timeout = defaultTimeout,
  }) async {
    if (text.trim().isEmpty) return const [];

    final result = await _invoke<Map<Object?, Object?>>('entryKeywords', {
      'text': text,
    }, timeout: timeout);

    final keywords = result['keywords'];
    if (keywords is! List) return const [];

    return [
      for (final raw in keywords)
        if (raw is String)
          if (raw.trim().isNotEmpty) raw.trim(),
    ];
  }

  /// A gentle question for the morning after.
  ///
  /// [tone] is `hard`, `good` or `steady` — the day's own character, which
  /// decides how the question is framed. A good day asked about as though it
  /// were a bad one reads as the app not having listened.
  static Future<String> followUpQuestion({
    required List<String> themes,
    required String excerpt,
    String tone = 'hard',
    Duration timeout = defaultTimeout,
  }) async {
    final result = await _invoke<Map<Object?, Object?>>('followUpQuestion', {
      'themes': themes,
      'excerpt': excerpt,
      'tone': tone,
    }, timeout: timeout);
    return (result['question'] as String? ?? '').trim();
  }

  /// The body of the daily reminder.
  static Future<String> reminderLine({
    required List<String> themes,
    Duration timeout = defaultTimeout,
  }) async {
    final result = await _invoke<Map<Object?, Object?>>('reminderLine', {
      'themes': themes,
    }, timeout: timeout);
    return (result['line'] as String? ?? '').trim();
  }

  static Future<T> _invoke<T>(
    String method,
    Map<String, Object?> arguments, {
    required Duration timeout,
  }) async {
    try {
      final result = await channel
          .invokeMethod<T>(method, arguments)
          .timeout(timeout);
      if (result == null) {
        throw const GenAiException._(
          GenAiException.internalFailure,
          'The model returned nothing.',
        );
      }
      _consecutiveFailures = 0;
      return result;
    } on MissingPluginException {
      _consecutiveFailures++;
      throw const GenAiException._(
        GenAiException.unavailable,
        'The generative channel is not registered on this platform.',
      );
    } on PlatformException catch (e) {
      _consecutiveFailures++;
      throw GenAiException._(e.code, e.message ?? 'Generation failed.');
    }
  }
}

class GenAiException implements Exception {
  /// No channel, or the model isn't usable on this device right now.
  static const String unavailable = 'genai_unavailable';

  /// The arguments didn't match what the native side expects.
  static const String badArguments = 'genai_bad_arguments';

  /// The model ran but produced nothing usable — a guardrail trip or a context
  /// overflow. Normal, and always recoverable by falling back.
  static const String generationFailed = 'genai_generation_failed';

  static const String internalFailure = 'genai_internal';

  final String code;
  final String message;

  const GenAiException._(this.code, this.message);

  bool get isUnavailable => code == unavailable;

  @override
  String toString() => 'GenAiException($code): $message';
}
