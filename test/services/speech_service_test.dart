import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/services/speech_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// The event channel is driven through a `MethodChannel` of the same name —
  /// that's how Flutter models `listen` / `cancel` under the hood.
  const eventControl = MethodChannel(SpeechService.eventChannelName);
  const codec = StandardMethodCodec();

  late SpeechService speech;
  late List<MethodCall> calls;

  void mockMethods(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(SpeechService.methodChannel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  /// Pushes an event as if the native side had emitted it.
  Future<void> emit(Map<String, Object?> event) {
    return messenger.handlePlatformMessage(
      SpeechService.eventChannelName,
      codec.encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  setUp(() {
    calls = [];
    speech = SpeechService();
    // Accept the `listen` / `cancel` handshake so subscribing succeeds.
    messenger.setMockMethodCallHandler(eventControl, (_) async => null);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(SpeechService.methodChannel, null);
    messenger.setMockMethodCallHandler(eventControl, null);
    await speech.dispose();
  });

  group('transcript stream', () {
    test('decodes partial and final results', () async {
      final received = <SpeechTranscript>[];
      speech.transcripts.listen(received.add);

      await emit({
        'type': 'result',
        'text': 'hello',
        'isFinal': false,
        'start': 0.0,
        'end': 0.5,
      });
      await emit({
        'type': 'result',
        'text': 'hello world',
        'isFinal': true,
        'start': 0.0,
        'end': 1.25,
      });
      await pumpEventQueue();

      expect(received, hasLength(2));
      expect(received.first.isFinal, isFalse);
      expect(received.first.end, const Duration(milliseconds: 500));
      expect(received.last.isFinal, isTrue);
      expect(received.last.text, 'hello world');
      expect(received.last.end, const Duration(milliseconds: 1250));
    });

    test('clamps non-finite and negative timings to zero', () async {
      final received = <SpeechTranscript>[];
      speech.transcripts.listen(received.add);

      await emit({
        'type': 'result',
        'text': 'x',
        'isFinal': true,
        // What an unguarded CMTime.invalid would produce.
        'start': double.nan,
        'end': -1.0,
      });
      await pumpEventQueue();

      expect(received.single.start, Duration.zero);
      expect(received.single.end, Duration.zero);
    });

    test('surfaces a native stream error as SpeechException', () async {
      final errors = <Object>[];
      speech.transcripts.listen((_) {}, onError: errors.add);

      await messenger.handlePlatformMessage(
        SpeechService.eventChannelName,
        codec.encodeErrorEnvelope(
          code: SpeechException.audio,
          message: 'mic lost',
        ),
        (_) {},
      );
      await pumpEventQueue();

      expect(
        errors.single,
        isA<SpeechException>().having(
          (e) => e.code,
          'code',
          SpeechException.audio,
        ),
      );
    });
  });

  group('listening state', () {
    test('tracks status events', () async {
      final states = <bool>[];
      speech.listeningState.listen(states.add);

      expect(speech.isListening, isFalse);

      await emit({'type': 'status', 'state': 'listening'});
      await pumpEventQueue();
      expect(speech.isListening, isTrue);

      await emit({'type': 'status', 'state': 'stopped'});
      await pumpEventQueue();
      expect(speech.isListening, isFalse);

      expect(states, [true, false]);
    });

    test('does not emit duplicates for a repeated status', () async {
      final states = <bool>[];
      speech.listeningState.listen(states.add);

      await emit({'type': 'status', 'state': 'listening'});
      await emit({'type': 'status', 'state': 'listening'});
      await pumpEventQueue();

      expect(states, [true]);
    });

    test('reports an interruption distinctly from a normal stop', () async {
      final statuses = <SpeechStatus>[];
      final listening = <bool>[];
      speech.status.listen(statuses.add);
      speech.listeningState.listen(listening.add);

      await emit({'type': 'status', 'state': 'listening'});
      await emit({'type': 'status', 'state': 'interrupted'});
      await pumpEventQueue();

      expect(statuses, [SpeechStatus.listening, SpeechStatus.interrupted]);
      expect(speech.isListening, isFalse);
      // The coarse stream still sees a plain stop...
      expect(listening, [true, false]);
    });

    test(
      'an interruption survives dedup even when already not listening',
      () async {
        final statuses = <SpeechStatus>[];
        speech.status.listen(statuses.add);

        // Never started, so `isListening` is already false. An interruption is
        // still real information and must not be swallowed.
        await emit({'type': 'status', 'state': 'interrupted'});
        await pumpEventQueue();

        expect(statuses, [SpeechStatus.interrupted]);
      },
    );

    test('an unknown state degrades to stopped', () async {
      final statuses = <SpeechStatus>[];
      speech.status.listen(statuses.add);

      await emit({'type': 'status', 'state': 'listening'});
      await emit({'type': 'status', 'state': 'something-new'});
      await pumpEventQueue();

      expect(statuses.last, SpeechStatus.stopped);
    });
  });

  group('download progress', () {
    test('decodes and clamps progress events', () async {
      final updates = <SpeechDownloadProgress>[];
      speech.downloadProgress.listen(updates.add);

      await emit({
        'type': 'download',
        'localeIdentifier': 'fr-FR',
        'progress': 0.25,
      });
      // Progress can overshoot if the total unit count is revised mid-flight.
      await emit({
        'type': 'download',
        'localeIdentifier': 'fr-FR',
        'progress': 1.4,
      });
      await emit({
        'type': 'download',
        'localeIdentifier': 'fr-FR',
        'progress': double.nan,
      });
      await pumpEventQueue();

      expect(updates.map((u) => u.fraction), [0.25, 1.0, 0.0]);
      expect(updates.first.localeIdentifier, 'fr-FR');
      expect(updates.first.isComplete, isFalse);
      expect(updates[1].isComplete, isTrue);
    });

    test('progress events do not disturb the transcript stream', () async {
      final transcripts = <SpeechTranscript>[];
      speech.transcripts.listen(transcripts.add);

      await emit({
        'type': 'download',
        'localeIdentifier': 'en-US',
        'progress': 0.5,
      });
      await pumpEventQueue();

      expect(transcripts, isEmpty);
    });
  });

  group('method calls', () {
    test('start forwards the locale and defaults to en-US', () async {
      mockMethods((_) async => null);

      await speech.start();
      expect(calls.single.method, 'start');
      expect(calls.single.arguments, {
        'localeIdentifier': SpeechService.defaultLocale,
      });

      await speech.start(localeIdentifier: 'fr-FR');
      expect(calls.last.arguments, {'localeIdentifier': 'fr-FR'});
    });

    test('start rethrows a missing model with its code intact', () async {
      mockMethods(
        (_) async => throw PlatformException(
          code: SpeechException.modelMissing,
          message: 'not installed',
        ),
      );

      await expectLater(
        speech.start(),
        throwsA(
          isA<SpeechException>().having(
            (e) => e.code,
            'code',
            SpeechException.modelMissing,
          ),
        ),
      );
    });

    test(
      'isSupported reports false instead of throwing when unavailable',
      () async {
        // No handler registered — MissingPluginException territory.
        expect(await speech.isSupported(), isFalse);
      },
    );

    test(
      'other methods throw unavailable when the channel is missing',
      () async {
        await expectLater(
          speech.permissions(),
          throwsA(
            isA<SpeechException>().having(
              (e) => e.code,
              'code',
              SpeechException.unavailable,
            ),
          ),
        );
      },
    );

    test('modelStatus decodes every status, unknown included', () async {
      for (final entry in {
        'installed': SpeechModelStatus.installed,
        'downloading': SpeechModelStatus.downloading,
        'supported': SpeechModelStatus.supported,
        'unsupported': SpeechModelStatus.unsupported,
        'something-new': SpeechModelStatus.unsupported,
      }.entries) {
        mockMethods((_) async => entry.key);
        expect(await speech.modelStatus(), entry.value, reason: entry.key);
      }
    });
  });

  group('permissions', () {
    test('decodes both fields', () async {
      mockMethods(
        (_) async => {
          'microphone': 'granted',
          'speechRecognition': 'restricted',
        },
      );

      final permissions = await speech.permissions();

      expect(permissions.microphone, SpeechPermissionStatus.granted);
      expect(permissions.speechRecognition, SpeechPermissionStatus.restricted);
      expect(permissions.canRecord, isTrue);
      expect(permissions.isPermanentlyBlocked, isFalse);
    });

    test('canRecord gates on the microphone only', () {
      const undetermined = SpeechPermissions(
        microphone: SpeechPermissionStatus.undetermined,
        speechRecognition: SpeechPermissionStatus.undetermined,
      );
      expect(undetermined.canRecord, isFalse);
      expect(
        undetermined.isPermanentlyBlocked,
        isFalse,
        reason: 'undetermined still prompts, so Settings is not the answer yet',
      );

      // Speech recognition denied but the mic granted still records — whether
      // SpeechAnalyzer enforces the speech gate is unclear, so we do not block.
      const micOnly = SpeechPermissions(
        microphone: SpeechPermissionStatus.granted,
        speechRecognition: SpeechPermissionStatus.denied,
      );
      expect(micOnly.canRecord, isTrue);

      const blocked = SpeechPermissions(
        microphone: SpeechPermissionStatus.denied,
        speechRecognition: SpeechPermissionStatus.granted,
      );
      expect(blocked.canRecord, isFalse);
      expect(blocked.isPermanentlyBlocked, isTrue);
    });
  });
}
