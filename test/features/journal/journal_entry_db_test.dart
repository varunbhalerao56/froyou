import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/features/journal/journal.dart';
import 'package:froyou/generated/objectbox.g.dart';

/// Exercises the clustering write path with synthetic vectors, so it needs no
/// device, no iOS 26, and no contextual-embedding assets — the parts of this
/// pipeline that are otherwise impossible to test off a physical phone.
void main() {
  late Store store;
  late JournalEntryDb db;
  int storeCounter = 0;

  setUp(() {
    store = Store(
      getObjectBoxModel(),
      directory: 'memory:journal-test-${storeCounter++}',
    );
    db = JournalEntryDb(store);
  });

  tearDown(() => store.close());

  /// A unit vector pointing along [axis], optionally jittered. Two vectors on
  /// the same axis have cosine similarity near 1 (they cluster together); two
  /// on different axes are near 0 (they do not).
  List<double> vector(int axis, {double jitter = 0, int seed = 0}) {
    final random = Random(seed);
    final values = List<double>.filled(JournalEntryDb.embeddingDimensions, 0);
    values[axis] = 1;
    if (jitter > 0) {
      for (var i = 0; i < values.length; i++) {
        values[i] += (random.nextDouble() - 0.5) * jitter;
      }
    }
    final magnitude = sqrt(values.fold(0.0, (a, b) => a + b * b));
    return values.map((v) => v / magnitude).toList();
  }

  Future<JournalEntry> addEntry(
    String text, {
    List<double>? embedding,
    DateTime? createdAt,
  }) async {
    final entry = JournalEntry()
      ..rawText = text
      ..createdAt = createdAt;
    entry.id = await db.putEntry(entry);

    await db.putSentenceInEntry(
      entry,
      JournalSentence()
        ..text = text
        ..embedding = embedding,
    );
    return entry;
  }

  group('putEntry', () {
    test('stamps createdAt so the log list can order on it', () async {
      final entry = JournalEntry()..rawText = 'no timestamp set';
      entry.id = await db.putEntry(entry);

      expect(db.getEntry(entry.id)!.createdAt, isNotNull);
    });
  });

  group('clustering', () {
    test('similar sentences join one cluster, dissimilar ones start another',
        () async {
      await addEntry('work was hard', embedding: vector(0));
      await addEntry('work again today', embedding: vector(0, jitter: 0.02, seed: 1));
      await addEntry('the soup was good', embedding: vector(1));

      final clusters = db.getAllThemeClusters();
      expect(clusters, hasLength(2));

      final sizes = clusters.map((c) => c.memberCount).toList()..sort();
      expect(sizes, [1, 2]);
    });

    test('a sentence with no embedding is stored but left unclustered', () async {
      final entry = await addEntry('nlp was unavailable');

      expect(db.getAllThemeClusters(), isEmpty);
      // Re-read: the backlink is only populated on an instance attached to the
      // store, not on the one we constructed.
      final sentence = db.getEntry(entry.id)!.sentences.single;
      expect(sentence.clusterId, isNull);
      expect(sentence.text, 'nlp was unavailable');
    });

    test('a wrong-length vector is dropped rather than crashing the put',
        () async {
      final entry = await addEntry('bad dims', embedding: List.filled(768, 0.1));

      expect(db.getAllThemeClusters(), isEmpty);
      final sentence = db.getEntry(entry.id)!.sentences.single;
      expect(sentence.clusterId, isNull);
      expect(sentence.embedding, isNull);
    });
  });

  group('relabelClusters', () {
    test('names a cluster from words shared across its members', () async {
      await addEntry('Work has been heavy again.', embedding: vector(0));
      await addEntry(
        'Work followed me home tonight.',
        embedding: vector(0, jitter: 0.02, seed: 2),
      );

      final cluster = db.getAllThemeClusters().single;
      db.relabelClusters({cluster.id});

      final label = db.getThemeCluster(cluster.id)!.label;
      expect(label, isNotNull);
      expect(label, isNotEmpty);
      expect(label, contains('work'));
    });
  });

  group('sentencesSince', () {
    test('returns only clustered sentences inside the window', () async {
      final now = DateTime.now();

      await addEntry('recent work', embedding: vector(0), createdAt: now);
      await addEntry(
        'old work',
        embedding: vector(0, jitter: 0.02, seed: 3),
        createdAt: now.subtract(const Duration(days: 30)),
      );
      // Unclustered — has no embedding, so it must not count toward trends.
      await addEntry('recent but unclustered', createdAt: now);

      final recent = db.sentencesSince(now.subtract(const Duration(days: 7)));

      expect(recent, hasLength(1));
      expect(recent.single.text, 'recent work');
    });

    test('sentences inherit their entry timestamp, not the write time',
        () async {
      final backdated = DateTime.now().subtract(const Duration(days: 30));
      await addEntry('backdated', embedding: vector(0), createdAt: backdated);

      final recent = db.sentencesSince(
        DateTime.now().subtract(const Duration(days: 7)),
      );
      expect(recent, isEmpty);
    });
  });

  group('deleteEntry', () {
    test('removes the entry and undoes its cluster contribution', () async {
      await addEntry('work one', embedding: vector(0));
      final second = await addEntry(
        'work two',
        embedding: vector(0, jitter: 0.02, seed: 4),
      );

      expect(db.getAllThemeClusters().single.memberCount, 2);

      await db.deleteEntry(second);

      expect(db.countEntries(), 1);
      expect(db.getAllThemeClusters().single.memberCount, 1);
    });

    test('drops the cluster entirely when its last member goes', () async {
      final entry = await addEntry('only member', embedding: vector(0));

      await db.deleteEntry(entry);

      expect(db.getAllThemeClusters(), isEmpty);
    });

    test('does not crash on an entry saved without embeddings', () async {
      // The normal case for anything logged in the Simulator, where the
      // contextual-embedding assets are unavailable.
      final entry = await addEntry('no embedding here');

      await expectLater(db.deleteEntry(entry), completes);
      expect(db.countEntries(), 0);
    });
  });
}
