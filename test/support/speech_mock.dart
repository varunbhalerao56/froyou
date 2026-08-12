import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/services/speech_service.dart';

/// Stubs the `app/speech` method channel for widget tests.
///
/// The same trap as the genai mock, on a different channel: `SpeechSource
/// .resolve` asks `isSupported` before it can pick a source, and an unmocked
/// method channel never answers under a widget test's fake clock. The compose
/// controller then sits forever on `await SpeechSource.resolve()` — recording
/// looks like it started, but Stop does nothing, because the source it would
/// stop was never assigned.
///
/// Answering `false` is the useful default: it is what a Simulator reports,
/// and it routes the debug build to `FakeSpeechSource`, so a test drives the
/// real compose path against canned words.
void mockSpeech({bool supported = false}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SpeechService.methodChannel, (call) async {
        switch (call.method) {
          case 'isSupported':
            return supported;
          case 'permissions':
          case 'requestPermissions':
            return {'microphone': 'granted', 'speechRecognition': 'granted'};
          case 'modelStatus':
            return 'installed';
          default:
            return null;
        }
      });
}

void unmockSpeech() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SpeechService.methodChannel, null);
}
