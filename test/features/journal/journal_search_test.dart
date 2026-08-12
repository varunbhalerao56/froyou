import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/features/journal/journal.dart';
import 'package:froyou/generated/objectbox.g.dart';
import 'package:froyou/services/services.dart';

/// The keyword half only. The semantic half needs `app/nlp`, which is absent
/// here exactly as it is in the Simulator — and `JournalSearch` is written to
/// degrade to literal matching when that happens, which is what these pin.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Store store;
  late AppDatabase db;
  late JournalSearch search;
  int counter = 0;

  setUp(() {
    store = Store(
      getObjectBoxModel(),
      directory: 'memory:search-test-${counter++}',
    );
    db = AppDatabase.forTesting(store);
    search = JournalSearch(db.journalEntryDb);
  });

  tearDown(() => store.close());

  Future<void> add(String text, {String? keywords}) async {
    final entry = JournalEntry()
      ..rawText = text
      ..keywords = keywords
      ..createdAt = DateTime.now();
    await db.journalEntryDb.putEntry(entry);
  }

  test('finds a log by a word in its text', () async {
    await add('The deadline moved again and I felt it in my chest.');
    await add('Dinner with my sister was lovely.');

    final hits = await search.search('deadline');

    expect(hits, hasLength(1));
    expect(hits.single.entry.rawText, contains('deadline'));
    expect(hits.single.byMeaning, isFalse);
  });

  test('matching a keyword outranks matching the body', () async {
    await add('A long note that mentions sleep only in passing.');
    await add('I could not switch off last night.', keywords: 'sleep, worry');

    final hits = await search.search('sleep');

    expect(hits, hasLength(2));
    expect(
      hits.first.entry.keywords,
      contains('sleep'),
      reason:
          'the words the model chose describe the entry better than the '
          'same letters buried in it',
    );
  });

  test('is case-insensitive', () async {
    await add('Work has been heavy.');
    expect(await search.search('WORK'), hasLength(1));
  });

  test('an empty query matches nothing rather than everything', () async {
    await add('Something.');
    expect(await search.search('   '), isEmpty);
  });

  test('no literal match and no NLP means no results, not a crash', () async {
    await add('The deadline moved again.');
    expect(await search.search('unrelated phrase'), isEmpty);
  });
}
