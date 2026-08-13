import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/features/home/data/follow_up_service.dart';
import 'package:froyou/features/journal/journal.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/generated/objectbox.g.dart';
import 'package:froyou/services/genai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Store store;
  late JournalEntryDb db;
  late ProfileStore profileStore;
  late FollowUpService service;
  int counter = 0;
  int questionCalls = 0;
  String? lastTone;

  /// The model answers, so any null result is the *rules* declining rather than
  /// the model being absent.
  void mockModelAvailable({String question = 'How is that sitting today?'}) {
    messenger.setMockMethodCallHandler(GenAiService.channel, (call) async {
      switch (call.method) {
        case 'availability':
          return {'status': 'available'};
        case 'followUpQuestion':
          questionCalls++;
          lastTone = (call.arguments as Map)['tone'] as String?;
          return {'question': question};
        default:
          return null;
      }
    });
  }

  void mockModelUnavailable() {
    messenger.setMockMethodCallHandler(GenAiService.channel, (call) async {
      if (call.method == 'availability') {
        return {'status': 'unavailable', 'reason': 'device_not_eligible'};
      }
      questionCalls++;
      return {'question': 'should never be asked for'};
    });
  }

  setUp(() async {
    questionCalls = 0;
    lastTone = null;
    SharedPreferences.setMockInitialValues({});
    store = Store(
      getObjectBoxModel(),
      directory: 'memory:follow-up-test-${counter++}',
    );
    db = JournalEntryDb(store);
    profileStore = ProfileStore(await SharedPreferences.getInstance());
    service = FollowUpService(store: profileStore, db: db);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(GenAiService.channel, null);
    store.close();
  });

  final today = DateTime(2026, 8, 12, 9);
  final yesterday = today.subtract(const Duration(days: 1));

  Future<void> addEntry(DateTime when, double mood, [String? text]) async {
    final entry = JournalEntry()
      ..rawText = text ?? 'an entry'
      ..moodScore = mood
      ..createdAt = when;
    entry.id = await db.putEntry(entry);
  }

  test('asks the morning after a negative day', () async {
    mockModelAvailable();
    await addEntry(yesterday, -0.6, 'Work crushed me today.');

    expect(await service.pendingQuestion(now: today), isNotNull);
    expect(questionCalls, 1);
  });

  test(
    'a day that averaged out fine is asked about as an ordinary one',
    () async {
      mockModelAvailable();
      // One rough moment inside an otherwise good day is not a hard day. It used
      // to silence the question entirely; now it only decides the framing.
      await addEntry(yesterday, -0.7);
      await addEntry(yesterday, 0.6);
      await addEntry(yesterday, 0.5);

      expect(await service.pendingQuestion(now: today), isNotNull);
      expect(lastTone, 'steady');
    },
  );

  test('a good day still gets a question, framed as a good one', () async {
    mockModelAvailable();
    await addEntry(yesterday, 0.7);

    expect(await service.pendingQuestion(now: today), isNotNull);
    expect(
      lastTone,
      'good',
      reason:
          'a journal that only speaks up after bad days teaches you it is '
          'the bad-news app',
    );
  });

  test('a hard day is still framed as a hard one', () async {
    mockModelAvailable();
    await addEntry(yesterday, -0.8);

    expect(await service.pendingQuestion(now: today), isNotNull);
    expect(lastTone, 'hard');
  });

  test('stays quiet when there was no yesterday', () async {
    mockModelAvailable();
    expect(await service.pendingQuestion(now: today), isNull);
  });

  test('never asks in the moment, only the day after', () async {
    mockModelAvailable();
    // A rough entry written *today* must not immediately summon a check-in.
    await addEntry(today, -0.9);

    expect(await service.pendingQuestion(now: today), isNull);
    expect(questionCalls, 0);
  });

  test('goes quiet once something is logged today', () async {
    mockModelAvailable();
    await addEntry(yesterday, -0.6);
    expect(await service.pendingQuestion(now: today), isNotNull);

    await addEntry(today, 0.1);
    expect(await service.pendingQuestion(now: today), isNull);
  });

  test('generates once a day and serves the cache after that', () async {
    mockModelAvailable();
    await addEntry(yesterday, -0.6);

    final first = await service.pendingQuestion(now: today);
    final second = await service.pendingQuestion(now: today);

    expect(second, first);
    // Home can be rebuilt any number of times; only one inference happens.
    expect(questionCalls, 1);
  });

  test("yesterday's cached question never resurfaces tomorrow", () async {
    mockModelAvailable();
    await addEntry(yesterday, -0.6);
    await service.pendingQuestion(now: today);

    // The next day, with nothing rough logged in between, there is no question
    // — the cache must not be reused just because it's present.
    final tomorrow = today.add(const Duration(days: 1));
    expect(await service.pendingQuestion(now: tomorrow), isNull);
  });

  test('clear() drops the pending question', () async {
    mockModelAvailable();
    await addEntry(yesterday, -0.6);
    expect(await service.pendingQuestion(now: today), isNotNull);

    await service.clear();
    questionCalls = 0;
    // Regenerates rather than serving a stale cache.
    expect(await service.pendingQuestion(now: today), isNotNull);
    expect(questionCalls, 1);
  });

  test('shows nothing at all when the model is unavailable', () async {
    mockModelUnavailable();
    await addEntry(yesterday, -0.9);

    expect(await service.pendingQuestion(now: today), isNull);
    expect(questionCalls, 0, reason: 'must not call a model it cannot use');
  });

  test('survives a model that errors, rather than breaking Home', () async {
    messenger.setMockMethodCallHandler(GenAiService.channel, (call) async {
      if (call.method == 'availability') return {'status': 'available'};
      throw PlatformException(code: GenAiException.generationFailed);
    });
    await addEntry(yesterday, -0.9);

    expect(await service.pendingQuestion(now: today), isNull);
  });

  test('ignores entries with no sentiment at all', () async {
    mockModelAvailable();
    // Saved while the NLP layer was unavailable — no mood means no judgement.
    final entry = JournalEntry()
      ..rawText = 'unscored'
      ..createdAt = yesterday;
    entry.id = await db.putEntry(entry);

    expect(await service.pendingQuestion(now: today), isNull);
  });
}
