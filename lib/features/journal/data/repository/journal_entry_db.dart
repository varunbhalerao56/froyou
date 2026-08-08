import 'dart:math';
import 'package:froyou/features/journal/journal.dart';
import 'package:froyou/generated/objectbox.g.dart';

class JournalEntryDb {
  final Store _store;
  late final Box<JournalEntry> _journalEntryBox;
  late final Box<JournalSentence> _journalSentenceBox;
  late final Box<ThemeCluster> _themeClusterBox;

  static const double _joinThreshold = 0.70; // cosine similarity

  /// Must match `@HnswIndex(dimensions: 512)` on both `JournalSentence.embedding`
  /// and `ThemeCluster.centroid`. ObjectBox throws on put if a vector of any
  /// other length reaches an indexed property, so it's checked here rather than
  /// trusted from the native side.
  static const int embeddingDimensions = 512;

  JournalEntryDb(this._store) {
    _journalEntryBox = _store.box<JournalEntry>();
    _journalSentenceBox = _store.box<JournalSentence>();
    _themeClusterBox = _store.box<ThemeCluster>(); // was missing
  }

  // ---------- JournalEntry ----------

  // Phase 1 — right after transcription, before any NLP has run
  Future<int> putEntry(JournalEntry entry) async {
    // getAllEntries() orders on createdAt, so an unset timestamp here means an
    // entry that sorts arbitrarily in the log list.
    entry.createdAt ??= DateTime.now();
    // Synchronous put rather than putAsync: this is one small row on a
    // user-initiated action, so the background write buys nothing measurable —
    // and it completes through a native callback that a widget test's fake
    // clock can never advance, which makes the whole save path untestable.
    // The rest of this class already writes synchronously inside transactions.
    return _journalEntryBox.put(entry);
  }

  JournalEntry? getEntry(int id) => _journalEntryBox.get(id);

  int countEntries() => _journalEntryBox.count();

  List<JournalEntry> getAllEntries() => _journalEntryBox
      .query()
      .order(JournalEntry_.createdAt, flags: Order.descending)
      .build()
      .find();

  // Remove an entry and all its sentences, undoing any contributions to clusters
  Future<void> deleteEntry(JournalEntry entry) async {
    await _store.runInTransaction(TxMode.write, () {
      for (final sentence in _sentencesForEntry(entry.id)) {
        _removeSentenceFromCluster(sentence);
        _journalSentenceBox.remove(sentence.id);
      }
      _journalEntryBox.remove(entry.id);
    });
  }

  // Edit an entry's text — undoes old sentences' cluster contributions.
  // Caller re-runs split -> YAKE -> embed -> putSentenceInEntry() on newText afterward.
  Future<void> updateEntryText(JournalEntry entry, String newText) async {
    await _store.runInTransaction(TxMode.write, () {
      for (final sentence in _sentencesForEntry(entry.id)) {
        _removeSentenceFromCluster(sentence);
        _journalSentenceBox.remove(sentence.id);
      }
      entry.rawText = newText;
      _journalEntryBox.put(entry);
    });
  }

  // ---------- JournalSentence ----------

  // Phase 2 — once YAKE + embedding finish for one sentence: link it to its
  // entry, decide which cluster it belongs to, and save both in one transaction.
  Future<int> putSentenceInEntry(
    JournalEntry entry,
    JournalSentence sentence,
  ) async {
    sentence.entry.target = entry;
    // Inherited from the entry rather than stamped with now(): re-enriching an
    // older entry must not make its sentences look like they were written
    // today, or every "past 7 days" query silently lies. Without this set at
    // all, getSentencesInClusterSince and sentencesSince return nothing —
    // successfully, and with no error anywhere.
    sentence.createdAt ??= entry.createdAt ?? DateTime.now();
    return _store.runInTransaction(TxMode.write, () {
      _assignSentenceToCluster(sentence); // sets sentence.clusterId
      return _journalSentenceBox.put(sentence);
    });
  }

  List<JournalSentence> _sentencesForEntry(int entryId) => _journalSentenceBox
      .query(JournalSentence_.entry.equals(entryId))
      .build()
      .find();

  List<JournalSentence> getSentencesInClusterSince(
    int clusterId,
    DateTime since,
  ) {
    return _journalSentenceBox
        .query(
          JournalSentence_.clusterId.equals(clusterId) &
              JournalSentence_.createdAt.greaterThan(
                since.millisecondsSinceEpoch,
              ),
        )
        .build()
        .find();
  }

  /// Every clustered sentence since [since], across all clusters.
  ///
  /// Analytics groups these by cluster in Dart rather than issuing one
  /// [getSentencesInClusterSince] per cluster — one query beats N.
  List<JournalSentence> sentencesSince(DateTime since) {
    return _journalSentenceBox
        .query(
          JournalSentence_.createdAt.greaterThan(
                since.millisecondsSinceEpoch,
              ) &
              JournalSentence_.clusterId.notNull(),
        )
        .build()
        .find();
  }

  // ---------- ThemeCluster ----------

  Future<int> putThemeCluster(ThemeCluster cluster) {
    return _themeClusterBox.putAsync(cluster);
  }

  ThemeCluster? getThemeCluster(int id) => _themeClusterBox.get(id);

  List<ThemeCluster> getAllThemeClusters() => _themeClusterBox.getAll();

  /// Recomputes labels for the given clusters from all of their members.
  ///
  /// Called once per save for the clusters that a new entry touched. Doing it
  /// here rather than at render time means analytics just reads
  /// `cluster.label` with no computation, and — unlike the original
  /// create-time-only seeding — a cluster's name improves as more sentences
  /// join it.
  void relabelClusters(Set<int> clusterIds) {
    if (clusterIds.isEmpty) return;
    _store.runInTransaction(TxMode.write, () {
      for (final clusterId in clusterIds) {
        final cluster = _themeClusterBox.get(clusterId);
        if (cluster == null) continue;

        final members = _journalSentenceBox
            .query(JournalSentence_.clusterId.equals(clusterId))
            .build()
            .find();
        final texts = members
            .map((sentence) => sentence.text)
            .whereType<String>()
            .where((text) => text.trim().isNotEmpty)
            .toList();
        if (texts.isEmpty) continue;

        cluster.label = ClusterLabeler.label(texts) ??
            ClusterLabeler.snippet(texts.first);
        _themeClusterBox.put(cluster);
      }
    });
  }

  // The core decision: does this sentence join an existing cluster,
  // or start a new one? Mutates sentence.clusterId as a side effect.
  void _assignSentenceToCluster(JournalSentence sentence) {
    final embedding = sentence.embedding;
    if (embedding == null) return;
    // A wrong-length vector would be rejected by the HNSW index at put time,
    // taking the whole enrichment transaction with it. Better to save the
    // sentence unclustered than to lose it.
    if (embedding.length != embeddingDimensions) {
      sentence.embedding = null;
      return;
    }

    final query = _themeClusterBox
        .query(ThemeCluster_.centroid.nearestNeighborsF32(embedding, 1))
        .build();
    final results = query.findWithScores();
    query.close();

    // ObjectBox returns cosine *distance* — similarity = 1 - distance
    if (results.isNotEmpty && (1 - results.first.score) >= _joinThreshold) {
      _joinCluster(results.first.object, sentence);
    } else {
      _createCluster(sentence);
    }
  }

  void _joinCluster(ThemeCluster cluster, JournalSentence sentence) {
    final sum = cluster.sumVector!;
    final emb = sentence.embedding!;
    for (var i = 0; i < sum.length; i++) {
      sum[i] += emb[i];
    }
    cluster.sumVector = sum;
    cluster.centroid = _normalize(sum);
    cluster.memberCount++;
    cluster.lastSeen = DateTime.now();

    _themeClusterBox.put(cluster);
    sentence.clusterId = cluster.id;
  }

  void _createCluster(JournalSentence sentence) {
    final emb = List<double>.from(sentence.embedding!);
    final cluster = ThemeCluster()
      ..sumVector = emb
      ..centroid = _normalize(emb)
      ..memberCount = 1
      ..lastSeen = DateTime.now()
      // Provisional: relabelClusters() replaces this with a label pooled from
      // every member once enrichment finishes.
      ..label = sentence.keywords;

    final id = _themeClusterBox.put(cluster);
    sentence.clusterId = id;
  }

  // Mirror of _joinCluster — subtracts instead of adds
  void _removeSentenceFromCluster(JournalSentence sentence) {
    if (sentence.clusterId == null) return;
    final cluster = _themeClusterBox.get(sentence.clusterId!);
    if (cluster == null) return;

    final sum = cluster.sumVector;
    final emb = sentence.embedding;
    // A sentence saved while NLP was unavailable has no embedding, so there is
    // nothing to subtract — and dereferencing it here would crash deleteEntry
    // and updateEntryText on every entry logged in the Simulator.
    if (sum == null || emb == null || sum.length != emb.length) {
      sentence.clusterId = null;
      return;
    }

    for (var i = 0; i < sum.length; i++) {
      sum[i] -= emb[i];
    }
    cluster.memberCount--;

    if (cluster.memberCount <= 0) {
      _themeClusterBox.remove(cluster.id);
    } else {
      cluster.sumVector = sum;
      cluster.centroid = _normalize(sum);
      _themeClusterBox.put(cluster);
    }
  }

  List<double> _normalize(List<double> v) {
    final mag = sqrt(v.fold(0.0, (a, b) => a + b * b));
    if (mag == 0) return v;
    return v.map((x) => x / mag).toList();
  }
}
