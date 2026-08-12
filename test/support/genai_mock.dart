import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/services/genai_service.dart';

/// Stubs the `app/genai` channel for widget tests.
///
/// Not optional hygiene. Anything that saves a log or seeds data reaches
/// `ClusterNamer`, which asks the model whether it is available. Left
/// unmocked, that call never completes under a widget test's fake clock and
/// the test hangs until its timeout — so every suite that touches the save
/// path has to say what the model is doing.
void mockGenAi({
  bool available = false,
  Map<int, String> labels = const {},
  String question = 'How is that sitting today?',
  String reminder = 'A moment to check in.',
  List<String> keywords = const ['shame', 'doing better'],
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(GenAiService.channel, (call) async {
        switch (call.method) {
          case 'availability':
            return available
                ? {'status': 'available'}
                : {'status': 'unavailable', 'reason': 'device_not_eligible'};
          case 'labelThemes':
            return {
              'labels': [
                for (final entry in labels.entries)
                  {'id': entry.key, 'label': entry.value},
              ],
            };
          case 'entryKeywords':
            return {'keywords': keywords};
          case 'followUpQuestion':
            return {'question': question};
          case 'reminderLine':
            return {'line': reminder};
          default:
            return null;
        }
      });
}

void unmockGenAi() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(GenAiService.channel, null);
  GenAiService.resetFailureLatch();
}
