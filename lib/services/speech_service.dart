import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart facade over the native speech channels, which wrap iOS 26's
/// `SpeechAnalyzer` / `SpeechTranscriber`.
///
/// Two channels rather than one, because transcription has two shapes: an
/// [EventChannel] for the continuous stream of partial and final results, and a
/// [MethodChannel] for start/stop and the capability queries around them.
///
/// Unlike [NlpService] this is an *instance* rather than a static class,
/// because it genuinely holds state: the event-channel subscription, the
/// derived broadcast streams, and the current listening flag. Use
/// [SpeechService.instance] unless you're writing a test that wants isolation.
///
/// **iOS 26+ only.** Elsewhere [isSupported] returns false and the other
/// methods throw [SpeechException] with [SpeechException.unavailable].
///
/// Typical flow:
///
/// ```dart
/// final speech = SpeechService.instance;
/// if (!await speech.isSupported()) return;
/// await speech.requestPermissions();
/// if (await speech.modelStatus() != SpeechModelStatus.installed) {
///   await speech.ensureModel();          // can be slow on a cold device
/// }
/// speech.transcripts.listen((t) => setState(() => _text = t.text));
/// await speech.start();
/// // ...
/// await speech.stop();
/// ```
class SpeechService {
  /// Shared instance. The native side owns a single session, so sharing one
  /// Dart object keeps [isListening] honest across the app.
  static final SpeechService instance = SpeechService();

  @visibleForTesting
  static const String methodChannelName = 'app/speech/methods';

  /// Distinct from [methodChannelName] on purpose: a binary messenger keys
  /// handlers by channel name, so registering a method handler and a stream
  /// handler under one name would have the second silently replace the first.
  @visibleForTesting
  static const String eventChannelName = 'app/speech';

  @visibleForTesting
  static const MethodChannel methodChannel = MethodChannel(methodChannelName);

  @visibleForTesting
  static const EventChannel eventChannel = EventChannel(eventChannelName);

  /// Default locale used when a call doesn't name one.
  static const String defaultLocale = 'en-US';

  final StreamController<SpeechTranscript> _transcripts =
      StreamController<SpeechTranscript>.broadcast();
  final StreamController<SpeechStatus> _status =
      StreamController<SpeechStatus>.broadcast();
  final StreamController<SpeechDownloadProgress> _downloads =
      StreamController<SpeechDownloadProgress>.broadcast();

  StreamSubscription<dynamic>? _subscription;
  bool _isListening = false;

  /// Partial and final transcription results, in arrival order.
  ///
  /// Subscribing here is what triggers the native `onListen`, so touch this
  /// before calling [start] if you don't want to miss the first result. [start]
  /// also ensures it, so in practice you rarely need to think about it.
  Stream<SpeechTranscript> get transcripts {
    _ensureSubscribed();
    return _transcripts.stream;
  }

  /// Session lifecycle, including *why* listening stopped.
  ///
  /// Prefer this over [listeningState] when the difference between a
  /// user-initiated stop and a system interruption matters — e.g. to show
  /// "paused for a call" rather than silently going idle.
  Stream<SpeechStatus> get status {
    _ensureSubscribed();
    return _status.stream;
  }

  /// Emits `true` when capture begins and `false` when it ends, collapsing
  /// [SpeechStatus.stopped] and [SpeechStatus.interrupted] into one signal.
  Stream<bool> get listeningState {
    return status.map((s) => s == SpeechStatus.listening).distinct();
  }

  /// Model-download progress from `0.0` to `1.0`, emitted while [ensureModel]
  /// runs.
  ///
  /// Always ends on `1.0`, including when nothing needed downloading — so a
  /// determinate bar driven off this doesn't need to special-case the common
  /// instant-return path.
  Stream<SpeechDownloadProgress> get downloadProgress {
    _ensureSubscribed();
    return _downloads.stream;
  }

  /// Whether a session is currently running.
  bool get isListening => _isListening;

  // ---------------------------------------------------------------------------
  // Capability + permissions
  // ---------------------------------------------------------------------------

  /// Whether this device can transcribe on-device at all.
  ///
  /// Returns `false` rather than throwing on non-iOS platforms and on devices
  /// where the transcriber isn't available — iOS 26 does not imply support.
  Future<bool> isSupported() async {
    try {
      return await methodChannel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Current permission status, without prompting.
  Future<SpeechPermissions> permissions() async {
    final result = await _invoke<Map<Object?, Object?>>('permissions');
    return SpeechPermissions._fromMap(result);
  }

  /// Prompts for microphone, then speech recognition, and reports both.
  ///
  /// Safe to call repeatedly: iOS only shows each dialog once, so subsequent
  /// calls just return the current status.
  Future<SpeechPermissions> requestPermissions() async {
    final result = await _invoke<Map<Object?, Object?>>('requestPermissions');
    return SpeechPermissions._fromMap(result);
  }

  // ---------------------------------------------------------------------------
  // Locales + models
  // ---------------------------------------------------------------------------

  /// Every locale the transcriber supports, as BCP-47 identifiers.
  ///
  /// Supported is not the same as installed — see [modelStatus].
  Future<List<String>> supportedLocales() async {
    final result = await _invoke<List<Object?>>('supportedLocales');
    return result.cast<String>();
  }

  /// Maps a loose identifier (`'en'`) to a concrete supported one (`'en-US'`),
  /// or `null` if there's no equivalent.
  Future<String?> resolveLocale(String localeIdentifier) async {
    try {
      return await methodChannel.invokeMethod<String>('resolveLocale', {
        'localeIdentifier': localeIdentifier,
      });
    } on MissingPluginException {
      throw const SpeechException._(
        SpeechException.unavailable,
        'Speech transcription is only available on iOS 26 or later.',
      );
    } on PlatformException catch (error) {
      throw SpeechException._(
        error.code,
        error.message ?? 'resolveLocale failed.',
      );
    }
  }

  /// Whether the on-device model for [localeIdentifier] is installed,
  /// downloadable, currently downloading, or unsupported.
  Future<SpeechModelStatus> modelStatus({
    String localeIdentifier = defaultLocale,
  }) async {
    final result = await _invoke<String>('modelStatus', {
      'localeIdentifier': localeIdentifier,
    });
    return SpeechModelStatus._fromRaw(result);
  }

  /// Downloads and installs the model for [localeIdentifier] if needed.
  ///
  /// Frequently returns immediately — the device's own language usually shares
  /// assets with system dictation. On a cold device for a different language it
  /// can take a long time and may require Wi-Fi, so show an indeterminate
  /// spinner rather than assuming it's fast.
  Future<void> ensureModel({String localeIdentifier = defaultLocale}) async {
    // Progress arrives on the event channel, so make sure we're attached to it
    // before the download starts or the early updates are lost.
    _ensureSubscribed();
    await _invokeVoid('ensureModel', {'localeIdentifier': localeIdentifier});
  }

  // ---------------------------------------------------------------------------
  // Session control
  // ---------------------------------------------------------------------------

  /// Begins capturing and transcribing.
  ///
  /// Throws [SpeechException] with:
  /// - [SpeechException.permissionDenied] if the microphone isn't granted,
  /// - [SpeechException.modelMissing] if the locale's model isn't installed
  ///   (call [ensureModel] first — this fails fast rather than silently
  ///   blocking for the length of a download),
  /// - [SpeechException.alreadyRunning] if a session is already active.
  Future<void> start({String localeIdentifier = defaultLocale}) async {
    _ensureSubscribed();
    await _invokeVoid('start', {'localeIdentifier': localeIdentifier});
  }

  /// Stops capture and flushes the recognizer.
  ///
  /// The trailing final result is delivered to [transcripts] *before* this
  /// future completes, so it's safe to read the accumulated text right after
  /// awaiting.
  ///
  /// Safe to call when not running.
  Future<void> stop() async {
    await _invokeVoid('stop');
  }

  /// Tears down the event-channel subscription and closes the derived streams.
  ///
  /// Only needed if you constructed your own [SpeechService]; the shared
  /// [instance] lives for the life of the app.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _transcripts.close();
    await _status.close();
    await _downloads.close();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Attaches to the event channel on first use. Idempotent.
  void _ensureSubscribed() {
    _subscription ??= eventChannel.receiveBroadcastStream().listen(
      _onEvent,
      onError: _onError,
    );
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;

    switch (event['type']) {
      case 'result':
        if (_transcripts.isClosed) return;
        _transcripts.add(SpeechTranscript._fromMap(event));
      case 'status':
        _setStatus(SpeechStatus._fromRaw(event['state'] as String?));
      case 'download':
        if (_downloads.isClosed) return;
        _downloads.add(SpeechDownloadProgress._fromMap(event));
    }
  }

  void _onError(Object error) {
    // A mid-session native failure. Surface it on the transcript stream so a
    // single listener sees both results and failures, and mark us stopped —
    // the native side has already torn the session down.
    _setStatus(SpeechStatus.stopped);
    if (_transcripts.isClosed) return;

    if (error is PlatformException) {
      _transcripts.addError(
        SpeechException._(error.code, error.message ?? 'Transcription failed.'),
      );
    } else {
      _transcripts.addError(error);
    }
  }

  void _setStatus(SpeechStatus value) {
    final listening = value == SpeechStatus.listening;
    // Dedup on the *derived* flag, not the status itself: a `stopped` after an
    // `interrupted` is real information about what happened, even though both
    // mean "not listening".
    if (_isListening == listening && value != SpeechStatus.interrupted) return;
    _isListening = listening;
    if (!_status.isClosed) _status.add(value);
  }

  Future<T> _invoke<T>(String method, [Map<String, Object?>? arguments]) async {
    final result = await _guard(
      () => methodChannel.invokeMethod<T>(method, arguments),
      method,
    );
    if (result == null) {
      throw SpeechException._(
        SpeechException.internalFailure,
        'Native method "$method" returned null.',
      );
    }
    return result;
  }

  Future<void> _invokeVoid(String method, [Map<String, Object?>? arguments]) {
    return _guard(
      () => methodChannel.invokeMethod<void>(method, arguments),
      method,
    );
  }

  /// Single funnel for error translation, so every method reports the same
  /// exception type with the native code preserved.
  Future<T?> _guard<T>(Future<T?> Function() body, String method) async {
    try {
      return await body();
    } on MissingPluginException {
      throw const SpeechException._(
        SpeechException.unavailable,
        'Speech transcription is only available on iOS 26 or later.',
      );
    } on PlatformException catch (error) {
      throw SpeechException._(
        error.code,
        error.message ?? 'Native call "$method" failed.',
      );
    }
  }
}

/// Why the session is in the state it's in.
enum SpeechStatus {
  /// Capturing and transcribing.
  listening,

  /// Not capturing — either never started, or stopped normally.
  stopped,

  /// The system took the audio route away mid-session: an incoming call, Siri,
  /// or another app claiming the microphone.
  ///
  /// The session is fully torn down by the time this arrives. Nothing resumes
  /// automatically — call [SpeechService.start] again if you want to continue,
  /// ideally after asking the user.
  interrupted;

  static SpeechStatus _fromRaw(String? raw) {
    switch (raw) {
      case 'listening':
        return SpeechStatus.listening;
      case 'interrupted':
        return SpeechStatus.interrupted;
      default:
        return SpeechStatus.stopped;
    }
  }
}

/// A model-download progress update from [SpeechService.ensureModel].
@immutable
class SpeechDownloadProgress {
  /// Which locale's model is downloading.
  final String localeIdentifier;

  /// `0.0` to `1.0`.
  final double fraction;

  const SpeechDownloadProgress({
    required this.localeIdentifier,
    required this.fraction,
  });

  factory SpeechDownloadProgress._fromMap(Map<Object?, Object?> map) {
    final raw = map['progress'];
    final value = raw is num ? raw.toDouble() : 0.0;
    return SpeechDownloadProgress(
      localeIdentifier: map['localeIdentifier'] as String? ?? '',
      // `Progress.fractionCompleted` can exceed 1.0 or go non-finite if the
      // total unit count is revised mid-flight; clamp so a progress bar can
      // consume this directly.
      fraction: value.isFinite ? value.clamp(0.0, 1.0) : 0.0,
    );
  }

  /// Whether the download has finished.
  bool get isComplete => fraction >= 1.0;

  @override
  String toString() =>
      'SpeechDownloadProgress($localeIdentifier: '
      '${(fraction * 100).toStringAsFixed(0)}%)';
}

/// One transcription result.
@immutable
class SpeechTranscript {
  /// The recognized text for this segment.
  final String text;

  /// `false` for a *volatile* result the recognizer may still revise, `true`
  /// once it has settled. Partials arriving while the user is still speaking is
  /// the expected behaviour, not a bug.
  final bool isFinal;

  /// Where this segment sits in the audio stream, measured from session start.
  final Duration start;
  final Duration end;

  const SpeechTranscript({
    required this.text,
    required this.isFinal,
    required this.start,
    required this.end,
  });

  factory SpeechTranscript._fromMap(Map<Object?, Object?> map) {
    return SpeechTranscript(
      text: map['text'] as String? ?? '',
      isFinal: map['isFinal'] as bool? ?? false,
      start: _duration(map['start']),
      end: _duration(map['end']),
    );
  }

  /// Seconds-as-double to [Duration], clamping the non-finite cases.
  ///
  /// The native side already guards against `CMTime.invalid` producing NaN, but
  /// a NaN reaching `Duration` would throw here rather than merely be wrong, so
  /// it's worth checking on both sides of the channel.
  static Duration _duration(Object? seconds) {
    if (seconds is! num) return Duration.zero;
    final value = seconds.toDouble();
    if (!value.isFinite || value < 0) return Duration.zero;
    return Duration(
      microseconds: (value * Duration.microsecondsPerSecond).round(),
    );
  }

  @override
  String toString() =>
      'SpeechTranscript(${isFinal ? 'final' : 'partial'}: "$text" '
      '${start.inMilliseconds}-${end.inMilliseconds}ms)';
}

/// Status of a single iOS permission.
enum SpeechPermissionStatus {
  /// Not asked yet — a prompt will be shown.
  undetermined,
  granted,

  /// Refused. iOS won't prompt again; the user must go to Settings.
  denied,

  /// Blocked by policy (parental controls, MDM). Not user-fixable in Settings.
  restricted;

  static SpeechPermissionStatus _fromRaw(String? raw) {
    switch (raw) {
      case 'granted':
        return SpeechPermissionStatus.granted;
      case 'undetermined':
        return SpeechPermissionStatus.undetermined;
      case 'restricted':
        return SpeechPermissionStatus.restricted;
      default:
        return SpeechPermissionStatus.denied;
    }
  }
}

/// The two permissions transcription touches.
@immutable
class SpeechPermissions {
  final SpeechPermissionStatus microphone;
  final SpeechPermissionStatus speechRecognition;

  const SpeechPermissions({
    required this.microphone,
    required this.speechRecognition,
  });

  factory SpeechPermissions._fromMap(Map<Object?, Object?> map) {
    return SpeechPermissions(
      microphone: SpeechPermissionStatus._fromRaw(map['microphone'] as String?),
      speechRecognition: SpeechPermissionStatus._fromRaw(
        map['speechRecognition'] as String?,
      ),
    );
  }

  /// Whether [SpeechService.start] can succeed. The microphone is the only hard
  /// gate — whether `SpeechAnalyzer` also enforces speech-recognition
  /// authorization is unclear, so we request it but don't block on it.
  bool get canRecord => microphone == SpeechPermissionStatus.granted;

  /// Whether prompting again is pointless and the user must be sent to
  /// Settings.
  bool get isPermanentlyBlocked =>
      microphone == SpeechPermissionStatus.denied ||
      microphone == SpeechPermissionStatus.restricted;

  @override
  String toString() =>
      'SpeechPermissions(microphone: ${microphone.name}, '
      'speechRecognition: ${speechRecognition.name})';
}

/// Availability of a locale's on-device transcription model.
enum SpeechModelStatus {
  /// No model exists for this locale on this device.
  unsupported,

  /// Available to download, but not present yet.
  supported,

  /// Download in progress.
  downloading,

  /// Ready to use.
  installed;

  static SpeechModelStatus _fromRaw(String raw) {
    switch (raw) {
      case 'supported':
        return SpeechModelStatus.supported;
      case 'downloading':
        return SpeechModelStatus.downloading;
      case 'installed':
        return SpeechModelStatus.installed;
      default:
        return SpeechModelStatus.unsupported;
    }
  }
}

/// Raised by [SpeechService] when a native call fails.
///
/// Match on [code] — the codes are the stable contract with the Swift side.
@immutable
class SpeechException implements Exception {
  /// Not running on a platform with the channel registered.
  static const String unavailable = 'speech_unavailable';

  /// The device or OS can't transcribe on-device.
  static const String unsupported = 'speech_unsupported';

  /// The microphone permission hasn't been granted.
  static const String permissionDenied = 'speech_permission_denied';

  /// The locale's model isn't installed — call [SpeechService.ensureModel].
  static const String modelMissing = 'speech_model_missing';

  /// [SpeechService.start] was called with a session already running.
  static const String alreadyRunning = 'speech_already_running';

  /// Audio session or engine failure.
  static const String audio = 'speech_audio';

  /// Anything else the Speech framework threw.
  static const String internalFailure = 'speech_internal';

  final String code;
  final String message;

  const SpeechException._(this.code, this.message);

  @override
  String toString() => 'SpeechException($code): $message';
}
