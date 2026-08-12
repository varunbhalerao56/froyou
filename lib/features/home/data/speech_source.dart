import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/services/services.dart';

/// The slice of [SpeechService] the compose UI actually needs.
///
/// Exists so the recording flow can be built and iterated in the Simulator,
/// where `SpeechTranscriber.isAvailable` is false and live transcription is
/// simply impossible. Without this seam, every tweak to the expand animation,
/// the live text binding or the stop-and-save path costs a device build.
abstract interface class SpeechSource {
  Stream<SpeechTranscript> get transcripts;
  Stream<SpeechStatus> get status;
  Stream<SpeechDownloadProgress> get downloadProgress;

  bool get isListening;

  Future<bool> isSupported();
  Future<SpeechPermissions> requestPermissions();
  Future<SpeechModelStatus> modelStatus();
  Future<void> ensureModel();
  Future<void> start();
  Future<void> stop();

  /// Picks the real source when the device can transcribe, and the canned one
  /// in debug builds when it can't. A release build on an unsupported device
  /// gets the real source, so the user sees an honest error rather than fake
  /// words appearing in their journal.
  static Future<SpeechSource> resolve() async {
    final real = RealSpeechSource();
    if (await real.isSupported()) return real;
    if (kDebugMode) {
      AppLog.warn('Speech', 'transcription unavailable — using fake source');
      return FakeSpeechSource();
    }
    return real;
  }
}

class RealSpeechSource implements SpeechSource {
  final SpeechService _speech = SpeechService.instance;

  @override
  Stream<SpeechTranscript> get transcripts => _speech.transcripts;

  @override
  Stream<SpeechStatus> get status => _speech.status;

  @override
  Stream<SpeechDownloadProgress> get downloadProgress =>
      _speech.downloadProgress;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> isSupported() => _speech.isSupported();

  @override
  Future<SpeechPermissions> requestPermissions() =>
      _speech.requestPermissions();

  @override
  Future<SpeechModelStatus> modelStatus() => _speech.modelStatus();

  @override
  Future<void> ensureModel() => _speech.ensureModel();

  @override
  Future<void> start() => _speech.start();

  @override
  Future<void> stop() => _speech.stop();
}

/// Replays a canned journal entry word by word, at roughly speaking pace.
///
/// Debug-only. Deliberately emits volatile partials that grow and then settle
/// into a final per sentence, because that arrival pattern — not the text — is
/// what the compose UI has to handle correctly.
class FakeSpeechSource implements SpeechSource {
  static const List<String> _script = [
    'Today my manager moved the deadline forward again and I felt my chest tighten.',
    'I keep replaying that meeting and wondering whether I said something wrong.',
    'The walk home was cold and it actually helped a little.',
    'I want to be kinder to myself about work this week.',
  ];

  static const Duration _wordInterval = Duration(milliseconds: 150);

  /// Which word of each sentence arrives misheard before being corrected.
  ///
  /// A real recognizer revises its volatile tail as more audio arrives, and
  /// that is the arrival pattern most likely to be handled wrongly — a naive
  /// diff re-animates the whole line, or worse, appends the correction instead
  /// of replacing it. Growing text alone would never catch either.
  static const int _revisionWord = 4;

  final StreamController<SpeechTranscript> _transcripts =
      StreamController<SpeechTranscript>.broadcast();
  final StreamController<SpeechStatus> _status =
      StreamController<SpeechStatus>.broadcast();
  final StreamController<SpeechDownloadProgress> _downloads =
      StreamController<SpeechDownloadProgress>.broadcast();

  Timer? _timer;
  bool _isListening = false;
  int _sentenceIndex = 0;
  int _wordIndex = 0;
  Duration _elapsed = Duration.zero;

  @override
  Stream<SpeechTranscript> get transcripts => _transcripts.stream;

  @override
  Stream<SpeechStatus> get status => _status.stream;

  @override
  Stream<SpeechDownloadProgress> get downloadProgress => _downloads.stream;

  @override
  bool get isListening => _isListening;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<SpeechPermissions> requestPermissions() async =>
      const SpeechPermissions(
        microphone: SpeechPermissionStatus.granted,
        speechRecognition: SpeechPermissionStatus.granted,
      );

  @override
  Future<SpeechModelStatus> modelStatus() async => SpeechModelStatus.installed;

  @override
  Future<void> ensureModel() async {}

  @override
  Future<void> start() async {
    if (_isListening) return;
    _isListening = true;
    _sentenceIndex = 0;
    _wordIndex = 0;
    _elapsed = Duration.zero;
    _status.add(SpeechStatus.listening);

    _timer = Timer.periodic(_wordInterval, (_) => _tick());
  }

  void _tick() {
    if (_sentenceIndex >= _script.length) {
      unawaited(stop());
      return;
    }

    final words = _script[_sentenceIndex].split(' ');
    _wordIndex++;
    _elapsed += _wordInterval;

    final isSentenceComplete = _wordIndex >= words.length;

    final visible = words.take(_wordIndex).toList();
    if (!isSentenceComplete && _wordIndex == _revisionWord) {
      // Half-heard, as if the word were still being spoken. The next tick
      // emits it in full, which the receiver has to treat as a correction of
      // this word rather than as another one.
      final last = visible.last;
      if (last.length > 3) {
        visible[visible.length - 1] = last.substring(0, last.length - 2);
      }
    }

    _transcripts.add(
      SpeechTranscript(
        text: visible.join(' '),
        isFinal: isSentenceComplete,
        start: Duration.zero,
        end: _elapsed,
      ),
    );

    if (isSentenceComplete) {
      _sentenceIndex++;
      _wordIndex = 0;
    }
  }

  @override
  Future<void> stop() async {
    if (!_isListening) return;
    _timer?.cancel();
    _timer = null;
    _isListening = false;

    // Mirrors the real contract: any trailing final result reaches listeners
    // before this future completes, so callers can read the accumulated text
    // straight after awaiting stop().
    if (_wordIndex > 0 && _sentenceIndex < _script.length) {
      final words = _script[_sentenceIndex].split(' ');
      _transcripts.add(
        SpeechTranscript(
          text: words.take(_wordIndex).join(' '),
          isFinal: true,
          start: Duration.zero,
          end: _elapsed,
        ),
      );
    }
    _status.add(SpeechStatus.stopped);
  }
}
