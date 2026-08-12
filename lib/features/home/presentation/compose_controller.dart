import 'dart:async';

import 'package:flutter/material.dart';
import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/features/home/data/speech_source.dart';
import 'package:froyou/features/home/data/transcript_words.dart';
import 'package:froyou/services/services.dart';

enum ComposeMode {
  /// Nothing open. The backdrop is at full height.
  idle,

  /// Recording. The editable field is out of the tree entirely; the live
  /// transcript renders in its place.
  voice,

  /// Typing, or editing what was just dictated.
  text,

  /// Write in flight.
  saving,
}

/// Drives the Home compose interaction: the expand animation, the text field,
/// and the live transcription feeding it.
///
/// Owns a single [AnimationController] rather than leaning on implicit
/// animations. Three things move on different intervals here — the backdrop's
/// height, the quote's fade, the box's slide — and three `AnimatedContainer`s
/// would run on three independent tickers that visibly desync at exactly the
/// seam this design depends on. The shell also needs to read the animation's
/// status to lock scrolling.
class ComposeController extends ChangeNotifier {
  ComposeController({required TickerProvider vsync, required this._onSave})
    : expand = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 320),
      ) {
    // Republish the text field's own changes. [canSave] is derived from the
    // field's contents, and listeners subscribe to this controller — not to
    // the TextEditingController — so without this the Save button never
    // notices that the user has typed something.
    text.addListener(notifyListeners);
  }

  final Future<void> Function(String text) _onSave;

  /// 0 = closed (backdrop at full height), 1 = open (backdrop collapsed).
  final AnimationController expand;

  /// Eased view of [expand], driving the backdrop's height and blur.
  ///
  /// Built once and held here rather than per-build in the widget:
  /// [CurvedAnimation] holds a listener on its parent and has to be disposed,
  /// so constructing one inside `build` leaks a listener every frame.
  late final CurvedAnimation expandCurve = CurvedAnimation(
    parent: expand,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// The compose box arrives on the back half of the animation, after the
  /// backdrop has already started giving up its height — so the space is
  /// visibly cleared *before* anything moves into it.
  late final CurvedAnimation boxReveal = CurvedAnimation(
    parent: expand,
    curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic),
    reverseCurve: const Interval(0.35, 1.0, curve: Curves.easeIn),
  );

  final TextEditingController text = TextEditingController();
  final FocusNode focusNode = FocusNode();
  final ScrollController textScroll = ScrollController();

  /// Awaited before opening, so the shell can scroll back to the top first.
  Future<void> Function()? beforeOpen;

  ComposeMode _mode = ComposeMode.idle;
  String? _error;
  bool _errorIsPermissions = false;
  double? _downloadFraction;

  SpeechSource? _speech;
  StreamSubscription<SpeechTranscript>? _transcriptSub;
  StreamSubscription<SpeechStatus>? _statusSub;
  StreamSubscription<SpeechDownloadProgress>? _downloadSub;

  /// The live transcript, word by word. Holds the settled/in-flight split that
  /// keeps a revised partial from overwriting sentences the recognizer already
  /// committed, and gives each word the stable identity [TranscriptView] needs
  /// to fade in only what is new.
  final TranscriptWords words = TranscriptWords();

  ComposeMode get mode => _mode;
  bool get isOpen => _mode != ComposeMode.idle;
  bool get isRecording => _mode == ComposeMode.voice;
  bool get isSaving => _mode == ComposeMode.saving;
  String? get error => _error;
  bool get errorIsPermissions => _errorIsPermissions;

  /// Non-null only while a speech model is downloading.
  double? get downloadFraction => _downloadFraction;

  bool get canSave =>
      _mode != ComposeMode.saving && text.text.trim().isNotEmpty;

  @override
  void dispose() {
    _cancelSpeechSubscriptions();
    expandCurve.dispose();
    boxReveal.dispose();
    expand.dispose();
    text.removeListener(notifyListeners);
    text.dispose();
    focusNode.dispose();
    textScroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Opening
  // ---------------------------------------------------------------------------

  Future<void> openText() async {
    if (isOpen) return;
    await beforeOpen?.call();

    _setMode(ComposeMode.text);
    expand.forward();
    // Focus after starting the expand, so the keyboard's inset animation and
    // the backdrop collapse begin on the same frame and travel together.
    focusNode.requestFocus();
  }

  Future<void> openVoice() async {
    if (isOpen) return;
    await beforeOpen?.call();

    _clearError();
    _setMode(ComposeMode.voice);
    expand.forward();
    // Deliberately no focus: leaving the keyboard down gives the live
    // transcript the full lower half of the screen.

    try {
      final speech = _speech ??= await SpeechSource.resolve();
      _listenToSpeech(speech);
      await _preflight(speech);
      await speech.start();
    } on SpeechException catch (e) {
      _failVoice(_messageForSpeechCode(e.code), isPermissions: false);
    } on _PermissionRefused catch (e) {
      _failVoice(e.message, isPermissions: e.openSettings);
    } catch (e, stackTrace) {
      AppLog.error('Compose', 'could not start recording', e, stackTrace);
      _failVoice('Recording could not start. You can type instead.');
    }
  }

  /// Drops out of recording into editing so the user can fix the transcript
  /// before saving, rather than closing the box out from under them.
  void _failVoice(String message, {bool isPermissions = false}) {
    _cancelSpeechSubscriptions();
    _error = message;
    _errorIsPermissions = isPermissions;
    _setMode(ComposeMode.text);
    _scrollTranscriptToEnd();
  }

  Future<void> _preflight(SpeechSource speech) async {
    final permissions = await speech.requestPermissions();
    if (!permissions.canRecord) {
      throw _PermissionRefused(
        permissions.isPermanentlyBlocked
            ? 'Microphone access is off for Froyou. Turn it on in Settings to record.'
            : 'Froyou needs the microphone to record what you say.',
        openSettings: permissions.isPermanentlyBlocked,
      );
    }

    if (await speech.modelStatus() != SpeechModelStatus.installed) {
      // First run on a cold device downloads the on-device model. Progress
      // arrives on the event stream and is rendered by the compose box.
      await speech.ensureModel();
    }
  }

  // ---------------------------------------------------------------------------
  // Live transcription
  // ---------------------------------------------------------------------------

  void _listenToSpeech(SpeechSource speech) {
    _cancelSpeechSubscriptions();
    words.clear();

    _transcriptSub = speech.transcripts.listen(
      _onTranscript,
      onError: (Object e) => _failVoice(
        e is SpeechException
            ? _messageForSpeechCode(e.code)
            : 'Recording stopped unexpectedly.',
      ),
    );

    _statusSub = speech.status.listen((status) {
      if (status == SpeechStatus.interrupted && _mode == ComposeMode.voice) {
        // Distinct from a user-initiated stop on purpose: the session is gone
        // and nothing resumes by itself, so say so rather than going quiet.
        _failVoice('Paused — the system took the microphone.');
      }
    });

    _downloadSub = speech.downloadProgress.listen((progress) {
      _downloadFraction = progress.isComplete ? null : progress.fraction;
      notifyListeners();
    });
  }

  void _onTranscript(SpeechTranscript transcript) {
    words.ingest(transcript);

    // The field is unmounted while recording, but keep writing it anyway: that
    // is what makes the handoff free — nothing is transferred at the seam, the
    // editable field simply takes over an already-current value.
    final joined = words.joined;
    text.value = TextEditingValue(
      text: joined,
      selection: TextSelection.collapsed(offset: joined.length),
    );

    notifyListeners();
  }

  /// Called at the handoff, not per transcript: while recording, the field is
  /// not in the tree at all, so [textScroll] has no clients to scroll.
  /// [TranscriptView] follows its own tail; this catches the field up to it.
  void _scrollTranscriptToEnd() {
    // Post-frame, because the field hasn't laid out the new line yet and
    // maxScrollExtent is still the previous value.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!textScroll.hasClients) return;
      textScroll.jumpTo(textScroll.position.maxScrollExtent);
    });
  }

  /// Ends recording and leaves the transcript editable.
  Future<void> stopVoice() async {
    final speech = _speech;
    if (speech == null || _mode != ComposeMode.voice) return;

    try {
      // The trailing final result is delivered to `transcripts` before this
      // future completes, so the text field is already up to date afterwards —
      // no arbitrary settling delay needed.
      await speech.stop();
    } catch (e) {
      AppLog.warn('Compose', 'stop failed: $e');
    }

    _cancelSpeechSubscriptions();
    _downloadFraction = null;
    // Deliberately no focus request: raising the keyboard the instant you stop
    // talking re-lays-out the whole pane on top of the widget swap. The static
    // caret carries the "you can edit this" affordance instead.
    _setMode(ComposeMode.text);
    _scrollTranscriptToEnd();
  }

  // ---------------------------------------------------------------------------
  // Saving and closing
  // ---------------------------------------------------------------------------

  Future<void> save() async {
    if (_mode == ComposeMode.voice) await stopVoice();
    final value = text.text.trim();
    if (value.isEmpty) return;

    _setMode(ComposeMode.saving);
    try {
      await _onSave(value);
      await close();
    } catch (e, stackTrace) {
      AppLog.error('Compose', 'save failed', e, stackTrace);
      _error = 'That did not save. Your words are still here — try again.';
      _setMode(ComposeMode.text);
    }
  }

  Future<void> close() async {
    if (_speech?.isListening ?? false) {
      try {
        await _speech!.stop();
      } catch (_) {
        // Closing regardless; a failed stop must not trap the user in compose.
      }
    }
    _cancelSpeechSubscriptions();

    focusNode.unfocus();
    text.clear();
    words.clear();
    _downloadFraction = null;
    _clearError();

    _setMode(ComposeMode.idle);
    await expand.reverse();
  }

  void dismissError() {
    _clearError();
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    _errorIsPermissions = false;
  }

  void _cancelSpeechSubscriptions() {
    _transcriptSub?.cancel();
    _statusSub?.cancel();
    _downloadSub?.cancel();
    _transcriptSub = null;
    _statusSub = null;
    _downloadSub = null;
  }

  void _setMode(ComposeMode mode) {
    _mode = mode;
    notifyListeners();
  }

  static String _messageForSpeechCode(String code) {
    switch (code) {
      case SpeechException.unavailable:
      case SpeechException.unsupported:
        return 'Voice notes need an iPhone running iOS 26. You can type instead.';
      case SpeechException.permissionDenied:
        return 'Microphone access is off for Froyou. Turn it on in Settings to record.';
      case SpeechException.modelMissing:
        return 'The speech model is still downloading. Try again in a moment.';
      case SpeechException.alreadyRunning:
        return 'Already recording.';
      case SpeechException.audio:
        return 'Something else is using the microphone right now.';
      default:
        return 'Recording could not start. You can type instead.';
    }
  }
}

/// Internal signal that preflight refused before any native call was made.
class _PermissionRefused implements Exception {
  const _PermissionRefused(this.message, {required this.openSettings});

  final String message;
  final bool openSettings;
}
