import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/services/genai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mock(Future<Object?>? Function(MethodCall call)? handler) {
    messenger.setMockMethodCallHandler(GenAiService.channel, handler);
  }

  setUp(GenAiService.resetFailureLatch);
  tearDown(() => mock(null));

  group('availability', () {
    test('maps each unavailable reason', () async {
      const cases = {
        'device_not_eligible': GenAiUnavailableReason.deviceNotEligible,
        'apple_intelligence_not_enabled':
            GenAiUnavailableReason.appleIntelligenceNotEnabled,
        'model_not_ready': GenAiUnavailableReason.modelNotReady,
      };

      for (final entry in cases.entries) {
        mock((_) async => {'status': 'unavailable', 'reason': entry.key});
        final availability = await GenAiService.availability();
        expect(availability.isAvailable, isFalse);
        expect(availability.reason, entry.value);
      }
    });

    test('reports available', () async {
      mock((_) async => {'status': 'available'});
      final availability = await GenAiService.availability();
      expect(availability.isAvailable, isTrue);
      expect(availability.reason, isNull);
    });

    test('a reason this build does not know is unavailable, not available', () async {
      // Apple has said more reasons are coming. Failing open here would mean
      // calling a model that isn't there on every future OS release.
      mock((_) async => {'status': 'unavailable', 'reason': 'something_new'});
      final availability = await GenAiService.availability();
      expect(availability.isAvailable, isFalse);
      expect(availability.reason, GenAiUnavailableReason.unknown);
    });

    test('never throws when the channel is missing', () async {
      mock((_) async => throw MissingPluginException());
      final availability = await GenAiService.availability();
      expect(availability.isAvailable, isFalse);
      expect(availability.reason, GenAiUnavailableReason.unknown);
    });

    test('never throws when the platform errors', () async {
      mock((_) async => throw PlatformException(code: 'genai_internal'));
      expect((await GenAiService.availability()).isAvailable, isFalse);
    });

    test('only Apple Intelligence being off is worth telling the user about', () {
      expect(GenAiUnavailableReason.appleIntelligenceNotEnabled.isUserFixable,
          isTrue);
      // Permanent, so nagging about it would be cruel and useless.
      expect(GenAiUnavailableReason.deviceNotEligible.isUserFixable, isFalse);
      expect(GenAiUnavailableReason.modelNotReady.isUserFixable, isFalse);
    });
  });

  group('labelThemes', () {
    test('sends every cluster in one call', () async {
      var calls = 0;
      List<Object?>? sent;
      mock((call) async {
        calls++;
        sent = (call.arguments as Map)['clusters'] as List;
        return {
          'labels': [
            {'id': 1, 'label': 'work deadlines'},
            {'id': 2, 'label': 'broken sleep'},
          ],
        };
      });

      final labels = await GenAiService.labelThemes({
        1: ['the deadline moved'],
        2: ['sleep was broken'],
      });

      // One inference for all clusters, not one per cluster — that's what lets
      // the model make the names distinguish each other.
      expect(calls, 1);
      expect(sent, hasLength(2));
      expect(labels.map((l) => l.label), ['work deadlines', 'broken sleep']);
    });

    test('skips clusters with no sentences rather than sending empties', () async {
      List<Object?>? sent;
      mock((call) async {
        sent = (call.arguments as Map)['clusters'] as List;
        return {'labels': <Object?>[]};
      });

      await GenAiService.labelThemes({
        1: ['something'],
        2: [],
      });

      expect(sent, hasLength(1));
    });

    test('does not call the channel at all for an empty map', () async {
      var called = false;
      mock((_) async {
        called = true;
        return {'labels': <Object?>[]};
      });

      expect(await GenAiService.labelThemes({}), isEmpty);
      expect(called, isFalse);
    });

    test('drops malformed and blank entries instead of failing', () async {
      mock((_) async => {
            'labels': [
              {'id': 1, 'label': 'work deadlines'},
              {'id': 'not-an-int', 'label': 'ignored'},
              {'id': 3},
              {'id': 4, 'label': '   '},
              'nonsense',
            ],
          });

      final labels = await GenAiService.labelThemes({
        1: ['a'],
      });

      expect(labels, hasLength(1));
      expect(labels.single.clusterId, 1);
      expect(labels.single.label, 'work deadlines');
    });

    test('surfaces a missing channel as an unavailable exception', () async {
      mock((_) async => throw MissingPluginException());
      await expectLater(
        GenAiService.labelThemes({
          1: ['a'],
        }),
        throwsA(
          isA<GenAiException>().having((e) => e.isUnavailable, 'isUnavailable',
              isTrue),
        ),
      );
    });

    test('preserves the native error code so callers can branch on it', () async {
      mock((_) async => throw PlatformException(
            code: GenAiException.generationFailed,
            message: 'guardrail',
          ));
      await expectLater(
        GenAiService.labelThemes({
          1: ['a'],
        }),
        throwsA(
          isA<GenAiException>()
              .having((e) => e.code, 'code', GenAiException.generationFailed),
        ),
      );
    });
  });

  group('failure latch', () {
    test('stops asking a model that keeps failing to generate', () async {
      // availability() can report `.available` while generation still fails —
      // the Simulator does exactly this, because the safety classifier asset
      // is missing. Without a latch every save would pay a doomed inference.
      var generateCalls = 0;
      mock((call) async {
        if (call.method == 'availability') return {'status': 'available'};
        generateCalls++;
        throw PlatformException(code: GenAiException.internalFailure);
      });

      expect((await GenAiService.availability()).isAvailable, isTrue);

      for (var i = 0; i < 2; i++) {
        await expectLater(
          GenAiService.labelThemes({
            1: ['a'],
          }),
          throwsA(isA<GenAiException>()),
        );
      }
      expect(generateCalls, 2);

      // Now availability reports false, so callers stop before the round trip.
      expect((await GenAiService.availability()).isAvailable, isFalse);
    });

    test('a success clears the count', () async {
      var shouldFail = true;
      mock((call) async {
        if (call.method == 'availability') return {'status': 'available'};
        if (shouldFail) {
          throw PlatformException(code: GenAiException.generationFailed);
        }
        return {'labels': <Object?>[]};
      });

      await expectLater(
        GenAiService.labelThemes({
          1: ['a'],
        }),
        throwsA(isA<GenAiException>()),
      );

      shouldFail = false;
      await GenAiService.labelThemes({
        1: ['a'],
      });

      // One earlier failure must not count toward a later latch.
      shouldFail = true;
      await expectLater(
        GenAiService.labelThemes({
          1: ['a'],
        }),
        throwsA(isA<GenAiException>()),
      );
      expect((await GenAiService.availability()).isAvailable, isTrue);
    });
  });

  group('followUpQuestion and reminderLine', () {
    test('trim what the model returns', () async {
      mock((call) async => switch (call.method) {
            'followUpQuestion' => {'question': '  How is that sitting today?  '},
            'reminderLine' => {'line': ' A moment to check in. '},
            _ => null,
          });

      expect(
        await GenAiService.followUpQuestion(themes: ['work'], excerpt: 'hi'),
        'How is that sitting today?',
      );
      expect(
        await GenAiService.reminderLine(themes: ['work']),
        'A moment to check in.',
      );
    });
  });
}
