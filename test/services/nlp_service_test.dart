import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/services/nlp_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Records every call so tests can assert on what did — and didn't — reach
  /// the platform side.
  late List<MethodCall> calls;

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(NlpService.channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() => calls = []);
  tearDown(() => messenger.setMockMethodCallHandler(NlpService.channel, null));

  group('splitSentences', () {
    test('returns the native list as strings', () async {
      mockChannel((_) async => <Object?>['One.', 'Two.']);

      expect(await NlpService.splitSentences('One. Two.'), ['One.', 'Two.']);
      expect(calls.single.method, 'splitSentences');
      expect(calls.single.arguments, {'text': 'One. Two.'});
    });

    test(
      'short-circuits on empty input without touching the channel',
      () async {
        mockChannel((_) async => fail('channel should not be invoked'));

        expect(await NlpService.splitSentences(''), isEmpty);
        expect(calls, isEmpty);
      },
    );
  });

  group('sentimentScore', () {
    test('passes the native double through', () async {
      mockChannel((_) async => -0.75);
      expect(await NlpService.sentimentScore('awful'), -0.75);
    });

    test('returns 0.0 for empty input without touching the channel', () async {
      mockChannel((_) async => fail('channel should not be invoked'));

      expect(await NlpService.sentimentScore(''), 0.0);
      expect(calls, isEmpty);
    });
  });

  group('extractEntities', () {
    test('offsets index into the source string', () async {
      // Emoji prefix on purpose: the native side converts through NSRange
      // (UTF-16), which is how Dart indexes strings. A conversion via Swift's
      // Character-based String.Index would be off by one here.
      const source = '🎉 Tim Cook visited Berlin';
      const start = 3;
      const end = 11;
      expect(source.substring(start, end), 'Tim Cook');

      mockChannel(
        (_) async => <Object?>[
          {
            'text': 'Tim Cook',
            'type': 'PersonalName',
            'start': start,
            'end': end,
          },
        ],
      );

      final entities = await NlpService.extractEntities(source);
      final entity = entities.single;

      expect(entity.type, NlpEntityType.personalName);
      expect(source.substring(entity.start, entity.end), entity.text);
    });

    test('maps every known tag and falls back to other', () async {
      mockChannel(
        (_) async => <Object?>[
          {'text': 'a', 'type': 'PersonalName', 'start': 0, 'end': 1},
          {'text': 'b', 'type': 'PlaceName', 'start': 1, 'end': 2},
          {'text': 'c', 'type': 'OrganizationName', 'start': 2, 'end': 3},
          // An unknown tag must not throw — a future OS adding a type should
          // degrade, not crash the app.
          {'text': 'd', 'type': 'SomethingNew', 'start': 3, 'end': 4},
        ],
      );

      final types = (await NlpService.extractEntities(
        'abcd',
      )).map((e) => e.type);
      expect(types, [
        NlpEntityType.personalName,
        NlpEntityType.placeName,
        NlpEntityType.organizationName,
        NlpEntityType.other,
      ]);
    });
  });

  group('embed', () {
    test('returns a Float64List and forwards options', () async {
      mockChannel((_) async => <Object?>[0.5, -0.5]);

      final vector = await NlpService.embed(
        'hi',
        language: 'en',
        normalize: true,
      );

      expect(vector, isA<Float64List>());
      expect(vector, [0.5, -0.5]);
      expect(calls.single.arguments, {
        'text': 'hi',
        'language': 'en',
        'normalize': true,
      });
    });

    test('omits language when not supplied', () async {
      mockChannel((_) async => <Object?>[1.0]);

      await NlpService.embed('hi');

      expect(
        (calls.single.arguments as Map).containsKey('language'),
        isFalse,
        reason: 'the native side detects the language when we omit it',
      );
    });

    test('returns an empty vector for empty input', () async {
      mockChannel((_) async => fail('channel should not be invoked'));

      expect(await NlpService.embed(''), isEmpty);
      expect(calls, isEmpty);
    });
  });

  group('embedSentences', () {
    test('decodes sentences with offsets that index into the source', () async {
      const source =
          'Today my boss was very annoying and what he said hurt me. '
          'On the bright side I had some really nice food today.';
      const first = 'Today my boss was very annoying and what he said hurt me.';
      final secondStart = source.indexOf('On the bright');

      mockChannel(
        (_) async => <Object?>[
          {
            'sentence': first,
            'vector': <Object?>[1.0, 0.0],
            'start': 0,
            'end': first.length,
          },
          {
            'sentence': source.substring(secondStart),
            'vector': <Object?>[0.0, 1.0],
            'start': secondStart,
            'end': source.length,
          },
        ],
      );

      final results = await NlpService.embedSentences(source, normalize: true);

      expect(results, hasLength(2));
      for (final r in results) {
        expect(
          source.substring(r.start, r.end),
          r.sentence,
          reason: 'offsets must index into the source string directly',
        );
        expect(r.vector, isA<Float64List>());
      }
      expect(calls.single.method, 'embedSentences');
    });

    test(
      'returns empty for empty input without touching the channel',
      () async {
        mockChannel((_) async => fail('channel should not be invoked'));

        expect(await NlpService.embedSentences(''), isEmpty);
        expect(calls, isEmpty);
      },
    );

    test('tolerates a missing vector rather than throwing', () async {
      // Defensive: a sentence whose token count exceeded the model's
      // maximumSequenceLength could come back without a vector.
      mockChannel(
        (_) async => <Object?>[
          {'sentence': 'Hi.', 'start': 0, 'end': 3},
        ],
      );

      final results = await NlpService.embedSentences('Hi.');
      expect(results.single.vector, isEmpty);
    });
  });

  group('error translation', () {
    test('preserves the native code on a PlatformException', () async {
      mockChannel(
        (_) async => throw PlatformException(
          code: NlpService.unsupportedLanguageCode,
          message: 'nope',
        ),
      );

      await expectLater(
        NlpService.embed('bonjour'),
        throwsA(
          isA<NlpException>()
              .having((e) => e.code, 'code', NlpService.unsupportedLanguageCode)
              .having(
                (e) => e.isUnsupportedLanguage,
                'isUnsupportedLanguage',
                isTrue,
              ),
        ),
      );
    });

    test('maps a missing plugin to unavailable', () async {
      // No mock handler registered at all — this is what a non-iOS platform
      // looks like from Dart.
      await expectLater(
        NlpService.sentimentScore('hello'),
        throwsA(
          isA<NlpException>()
              .having((e) => e.code, 'code', NlpException.unavailable)
              .having((e) => e.isUnavailable, 'isUnavailable', isTrue),
        ),
      );
    });
  });
}
