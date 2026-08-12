import 'dart:math';
import 'package:froyou/core/config/label_mode.dart';
import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/features/journal/journal.dart';
import 'package:froyou/generated/objectbox.g.dart';

class JournalEntryDb {
  final Store _store;
  late final Box<JournalEntry> _journalEntryBox;
  late final Box<JournalSentence> _journalSentenceBox;
  late final Box<ThemeCluster> _themeClusterBox;

  /// Cosine similarity, measured on *centred* vectors — see [_meanEmbedding].
  ///
  /// Raw cosine cannot carry this decision. Mean-pooled contextual embeddings
  /// are anisotropic: they share one large common direction, so two unrelated
  /// English sentences start around 0.9 before any content is considered.
  /// Measured on a real device, cooking, an audiobook and a relationship all
  /// scored 0.86–0.94 against the same cluster — a spread of 0.076 across
  /// topics with nothing whatsoever in common. No threshold sits inside that.
  /// The floor the join threshold can never go below.
  ///
  /// After centring, two unrelated sentences are near-orthogonal, and in
  /// [embeddingDimensions] dimensions random pairs scatter around zero with a
  /// standard deviation of 1/√d ≈ 0.044. Four sigma is comfortably beyond
  /// chance, and it is what stops everything collapsing into one theme on a
  /// journal whose entries genuinely have nothing in common.
  static double get _noiseFloor => 4 / sqrt(embeddingDimensions.toDouble());

  // The threshold is not a constant at all — see [_thresholdFrom]. Every
  // attempt to fix one failed on real text: 0.55 came from the synthetic seed
  // and split 26 sentences into 25 themes; the noise floor alone put an
  // audiobook in with work; a flat p90 assumed exactly a tenth of pairs are
  // related, which broke the seed, where it is a fifth.

  /// Raw-cosine threshold, used only until there is enough text to estimate the
  /// common direction. Deliberately generous: merging early is recoverable,
  /// and a handful of sentences cannot support a mean worth subtracting.
  static const double _rawJoinThreshold = 0.92;

  /// Sentences needed before centring is trusted.
  static const int _minSamplesForCentring = 8;

  /// How much the corpus can grow before the grouping is rebuilt.
  ///
  /// A rebuild only earns its cost when the *mean* has moved, because that is
  /// what every comparison is measured against. Adding one sentence to fifty
  /// barely moves it; adding fifty to fifty does.
  static const double _rebuildGrowth = 1.5;

  /// How closely the current mean must still track the one the last rebuild
  /// used. Below this the grouping was drawn against a direction that no longer
  /// describes the writing, and is redone.
  static const double _meanStability = 0.995;

  /// Bookkeeping for [maybeRecluster], deliberately per-process rather than
  /// persisted: a launch is a natural moment to pay for one rebuild, and it
  /// avoids a schema change for a number that is only an optimisation.
  List<double>? _meanAtLastRebuild;
  int _sentencesAtLastRebuild = 0;
  double _threshold = 0;

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
      // The id is passed rather than read back off `sentence.entry`: the
      // relation is not attached to the store until the sentence is put, and
      // touching `targetId` before that throws.
      _assignSentenceToCluster(sentence, entry.id); // sets sentence.clusterId
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
          JournalSentence_.createdAt.greaterThan(since.millisecondsSinceEpoch) &
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

  /// Recomputes every cluster's label.
  ///
  /// All of them, not just the ones a new entry touched: the labeler scores
  /// terms by how well they distinguish one cluster from the others, so adding
  /// a single sentence anywhere shifts what counts as distinctive everywhere.
  /// Relabelling in isolation would leave stale names that quietly contradict
  /// the fresh ones.
  ///
  /// Done at write time so analytics just reads `cluster.label` with nothing
  /// to compute at render time.
  void relabelAllClusters() {
    _store.runInTransaction(TxMode.write, () {
      final clusters = _themeClusterBox.getAll();
      if (clusters.isEmpty) return;

      final membersByCluster = <int, List<String>>{};
      for (final cluster in clusters) {
        membersByCluster[cluster.id] = _journalSentenceBox
            .query(JournalSentence_.clusterId.equals(cluster.id))
            .build()
            .find()
            .map((sentence) => sentence.text)
            .whereType<String>()
            .where((text) => text.trim().isNotEmpty)
            .toList();
      }

      final labels = ClusterLabeler.labelAll(membersByCluster);

      for (final cluster in clusters) {
        final texts = membersByCluster[cluster.id] ?? const <String>[];
        if (texts.isEmpty) continue;
        cluster.label =
            labels[cluster.id] ?? ClusterLabeler.snippet(texts.first);
        _themeClusterBox.put(cluster);
      }
    });
  }

  /// Each cluster's most central sentences, for the naming prompt.
  ///
  /// Ranked by cosine to the centroid rather than taken in insertion order, so
  /// a handful of sentences still describes what the cluster is *about* instead
  /// of just what landed in it first. Both the centroid and the stored
  /// embeddings are unit-normalized, so the dot product is the cosine.
  Map<int, List<String>> centralSentencesByCluster({int perCluster = 6}) {
    final result = <int, List<String>>{};

    for (final cluster in _themeClusterBox.getAll()) {
      final centroid = cluster.centroid;
      final members = sentencesInCluster(cluster.id);

      final scored = <(double, String)>[];
      for (final sentence in members) {
        final text = sentence.text?.trim();
        if (text == null || text.isEmpty) continue;

        final embedding = sentence.embedding;
        var similarity = 0.0;
        if (centroid != null &&
            embedding != null &&
            embedding.length == centroid.length) {
          for (var i = 0; i < centroid.length; i++) {
            similarity += centroid[i] * embedding[i];
          }
        }
        scored.add((similarity, text));
      }
      if (scored.isEmpty) continue;

      scored.sort((a, b) => b.$1.compareTo(a.$1));
      result[cluster.id] = [
        for (final entry in scored.take(perCluster)) entry.$2,
      ];
    }

    return result;
  }

  /// Writes labels produced elsewhere (the language model) onto their clusters.
  ///
  /// Ignores ids that no longer exist and blank labels, because a generated
  /// response is not a trusted input — a hallucinated cluster id must not
  /// create or clobber anything.
  void applyClusterLabels(Map<int, String> labels) {
    if (labels.isEmpty) return;
    _store.runInTransaction(TxMode.write, () {
      for (final entry in labels.entries) {
        final label = entry.value.trim();
        if (label.isEmpty) continue;
        final cluster = _themeClusterBox.get(entry.key);
        if (cluster == null) continue;
        cluster.label = label;
        _themeClusterBox.put(cluster);
      }
    });
  }

  /// Every sentence in a cluster, embeddings included — used to pick the one
  /// that best represents it.
  List<JournalSentence> sentencesInCluster(int clusterId) => _journalSentenceBox
      .query(JournalSentence_.clusterId.equals(clusterId))
      .build()
      .find();

  /// Deletes every entry, sentence and cluster. Not recoverable.
  void clearAll() {
    _store.runInTransaction(TxMode.write, () {
      _journalSentenceBox.removeAll();
      _journalEntryBox.removeAll();
      // Clusters are derived entirely from sentences, so with those gone there
      // is nothing left for a centroid to describe.
      _themeClusterBox.removeAll();
    });
  }

  // The core decision: does this sentence join an existing cluster,
  // or start a new one? Mutates sentence.clusterId as a side effect.
  /// Rebuilds the grouping, but only when it would come out different.
  ///
  /// The expensive part of clustering is not the arithmetic, it is that every
  /// comparison is relative to the corpus mean — so when the mean shifts, every
  /// past decision is suspect. That is why the naive version rebuilt on every
  /// save. It shifts meaningfully only while there is little text, though, and
  /// converges quickly after that: this rebuilds once per launch, then whenever
  /// the corpus has grown by half again or the mean has actually drifted, and
  /// otherwise leaves the existing themes alone.
  ///
  /// Returns the theme count, rebuilt or not.
  int maybeRecluster() {
    final mean = _meanEmbedding();
    final sentenceCount = _themeClusterBox.getAll().fold(
      0,
      (total, cluster) => total + cluster.memberCount,
    );

    final previous = _meanAtLastRebuild;
    final grown = sentenceCount >= _sentencesAtLastRebuild * _rebuildGrowth;
    final drifted =
        previous == null ||
        mean == null ||
        _dot(_normalize(mean), _normalize(previous)) < _meanStability;

    if (previous != null && !grown && !drifted) {
      AppLog.info(
        'Cluster',
        'grouping still current ($sentenceCount sentences, '
            'threshold ${_threshold.toStringAsFixed(3)}) — no rebuild',
      );
      return _themeClusterBox.count();
    }
    return reclusterAll();
  }

  /// Rebuilds every theme from scratch over all stored sentences.
  ///
  /// Incremental assignment cannot be trusted on its own here, for two reasons
  /// that compound. The common direction subtracted in [_centred] is only
  /// estimable once there is some text, so the earliest sentences are placed
  /// using a measure that does not work — and nothing ever revisits them. And
  /// a cluster's centroid drifts as it absorbs members, so what it will accept
  /// depends on the order things arrived in.
  ///
  /// Cheap enough to simply redo: a personal journal is hundreds of sentences
  /// against tens of themes, and the save it runs on already waits on an
  /// inference. Returns the number of themes.
  int reclusterAll() {
    return _store.runInTransaction(TxMode.write, () {
      final sentences = _journalSentenceBox.getAll()
        // Oldest first, so the result is at least deterministic.
        ..sort(
          (a, b) => (a.createdAt ?? DateTime(0)).compareTo(
            b.createdAt ?? DateTime(0),
          ),
        );

      final usable = [
        for (final sentence in sentences)
          if (sentence.embedding?.length == embeddingDimensions) sentence,
      ];
      for (final sentence in sentences) {
        sentence.clusterId = null;
      }
      if (usable.isEmpty) {
        _themeClusterBox.removeAll();
        _journalSentenceBox.putMany(sentences);
        return 0;
      }

      // Before the clusters go, since that is what the mean is derived from.
      final mean = _meanOf(usable);
      _themeClusterBox.removeAll();

      final threshold = mean == null
          ? _rawJoinThreshold
          : _thresholdFrom(usable, mean);
      _threshold = threshold;
      _meanAtLastRebuild = mean;
      _sentencesAtLastRebuild = usable.length;

      // Sums, and the members that produced them, held in memory until the
      // grouping settles — writing a cluster per decision would mean a put for
      // every sentence and an id churn for nothing.
      final sums = <List<double>>[];
      final members = <List<JournalSentence>>[];
      // Each group's comparison vectors, kept alongside its running sum and
      // refreshed only when it actually gains a member. Deriving them inside
      // the inner loop instead meant two 512-element allocations per
      // sentence-group pair, which is the one part of this that would have
      // stopped scaling.
      final centroids = <List<double>>[];
      final centredCentroids = <List<double>?>[];

      for (final sentence in usable) {
        final vector = sentence.embedding!;
        final centred = _centred(vector, mean);

        var best = -2.0;
        var bestIndex = -1;
        for (var i = 0; i < sums.length; i++) {
          final centredCentroid = centredCentroids[i];
          final score = (centred == null || centredCentroid == null)
              ? _dot(vector, centroids[i])
              : _dot(centred, centredCentroid);
          if (score > best) {
            best = score;
            bestIndex = i;
          }
        }

        if (bestIndex >= 0 && best >= threshold) {
          final sum = sums[bestIndex];
          for (var i = 0; i < sum.length; i++) {
            sum[i] += vector[i];
          }
          members[bestIndex].add(sentence);
          centroids[bestIndex] = _normalize(sum);
          centredCentroids[bestIndex] = _centred(centroids[bestIndex], mean);
        } else {
          final sum = List<double>.from(vector);
          sums.add(sum);
          members.add([sentence]);
          centroids.add(_normalize(sum));
          centredCentroids.add(_centred(centroids.last, mean));
        }
      }

      for (var i = 0; i < sums.length; i++) {
        final cluster = ThemeCluster()
          ..sumVector = sums[i]
          ..centroid = _normalize(sums[i])
          ..memberCount = members[i].length
          ..lastSeen = members[i]
              .map((s) => s.createdAt ?? DateTime(0))
              .reduce((a, b) => a.isAfter(b) ? a : b);
        final id = _themeClusterBox.put(cluster);
        for (final sentence in members[i]) {
          sentence.clusterId = id;
        }
      }

      _journalSentenceBox.putMany(sentences);
      AppLog.info(
        'Cluster',
        'rebuilt ${sums.length} themes from ${usable.length} sentences '
            '(${mean == null ? 'raw' : 'centred'}, threshold $threshold)',
      );
      return sums.length;
    });
  }

  /// The join threshold, read off how these particular sentences sit relative
  /// to each other rather than fixed in advance.
  ///
  /// Sampled rather than exhaustive: the pairwise count is quadratic, and a few
  /// dozen sentences describe the distribution as well as a few thousand.
  double _thresholdFrom(List<JournalSentence> sentences, List<double> mean) {
    const sampleLimit = 60;
    final stride = (sentences.length / sampleLimit).ceil();
    final vectors = [
      for (var i = 0; i < sentences.length; i += stride)
        if (_centred(sentences[i].embedding!, mean) case final List<double> v)
          v,
    ];
    if (vectors.length < 3) return _noiseFloor;

    final scores = <double>[];
    for (var i = 0; i < vectors.length; i++) {
      for (var j = i + 1; j < vectors.length; j++) {
        scores.add(_dot(vectors[i], vectors[j]));
      }
    }
    scores.sort();

    double at(double fraction) =>
        scores[(scores.length * fraction).clamp(0, scores.length - 1).toInt()];

    final split = _otsuSplit(scores);
    final threshold = max(_noiseFloor, split);
    final above = scores.where((s) => s >= threshold).length;

    AppLog.info(
      'Cluster',
      'pairwise centred similarity over ${vectors.length} sentences · '
          'median ${at(0.5).toStringAsFixed(3)} · p75 ${at(0.75).toStringAsFixed(3)} · '
          'p90 ${at(0.9).toStringAsFixed(3)} · p99 ${at(0.99).toStringAsFixed(3)} · '
          'max ${scores.last.toStringAsFixed(3)} → threshold '
          '${threshold.toStringAsFixed(3)} '
          '(${split > _noiseFloor ? 'valley' : 'noise floor'}) · '
          '$above/${scores.length} pairs clear it',
    );
    return threshold;
  }

  /// The valley between "unrelated" and "related", by Otsu's method.
  ///
  /// The pairwise scores are two overlapping piles: near-zero for sentences
  /// that merely share a language, and higher for ones that share a subject.
  /// Otsu picks the cut that best separates two groups by maximising the
  /// variance *between* them, which finds that valley wherever it happens to
  /// be — rather than assuming a fixed similarity or a fixed proportion, both
  /// of which vary with the model and with how repetitive the writing is.
  ///
  /// [scores] must be sorted ascending.
  double _otsuSplit(List<double> scores) {
    final total = scores.length;
    if (total < 4) return _noiseFloor;

    final sum = scores.fold(0.0, (a, b) => a + b);
    var below = 0.0;
    var bestVariance = -1.0;
    var best = _noiseFloor;

    for (var i = 0; i < total - 1; i++) {
      below += scores[i];
      final countBelow = i + 1;
      final countAbove = total - countBelow;
      final meanBelow = below / countBelow;
      final meanAbove = (sum - below) / countAbove;
      final difference = meanBelow - meanAbove;
      final variance = countBelow * countAbove * difference * difference;
      if (variance > bestVariance) {
        bestVariance = variance;
        best = (scores[i] + scores[i + 1]) / 2;
      }
    }
    return best;
  }

  void _assignSentenceToCluster(JournalSentence sentence, int entryId) {
    final embedding = sentence.embedding;
    if (embedding == null) return;
    // A wrong-length vector would be rejected by the HNSW index at put time,
    // taking the whole enrichment transaction with it. Better to save the
    // sentence unclustered than to lose it.
    if (embedding.length != embeddingDimensions) {
      sentence.embedding = null;
      return;
    }

    // Scored in Dart against every cluster rather than through the HNSW index.
    // There are tens of clusters at most in a personal journal, so the scan is
    // free — and the index can only rank raw vectors, which is exactly the
    // measure that does not work here.
    final clusters = _themeClusterBox.getAll();
    final mean = _meanEmbedding();
    final centredSentence = _centred(embedding, mean);

    ThemeCluster? nearest;
    var best = -2.0;
    var bestRaw = -2.0;
    for (final cluster in clusters) {
      final centroid = cluster.centroid;
      if (centroid == null || centroid.length != embeddingDimensions) continue;

      final raw = _dot(embedding, centroid);
      final centredCentroid = _centred(centroid, mean);
      // Falls back to the raw measure until there is enough text to centre.
      final score = (centredSentence == null || centredCentroid == null)
          ? raw
          : _dot(centredSentence, centredCentroid);

      if (score > best) {
        best = score;
        bestRaw = raw;
        nearest = cluster;
      }
    }

    // Provisional only: [reclusterAll] regroups everything moments later with a
    // threshold read off the data. The floor is enough to give the sentence a
    // home in the meantime.
    final centring = centredSentence != null;
    final threshold = centring ? _noiseFloor : _rawJoinThreshold;
    final joins = nearest != null && best >= threshold;

    // Both numbers, always. The raw one is what used to decide and is kept
    // visible so the two can be compared on real text rather than argued about.
    AppLog.info(
      'Cluster',
      'entry $entryId · '
          '${nearest == null ? 'first sentence' : '${centring ? 'centred' : 'raw'} '
                    '${best.toStringAsFixed(3)} (raw ${bestRaw.toStringAsFixed(3)}) '
                    'vs theme ${nearest.id}'} '
          '· threshold $threshold → '
          '${joins ? 'join theme ${nearest.id}' : 'NEW theme'} · '
          'sentence: "${_short(sentence.text)}"',
    );

    if (joins) {
      _joinCluster(nearest, sentence);
    } else {
      _createCluster(sentence);
    }
  }

  static String _short(String? text) {
    final trimmed = (text ?? '').trim();
    return trimmed.length <= 44
        ? trimmed
        : '${trimmed.substring(0, 44).trimRight()}…';
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
      ..label = kModelOnlyLabels ? null : sentence.keywords;

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

  /// The average direction of everything written so far.
  ///
  /// Subtracting it is what makes cosine mean something here: it is the shared
  /// component every sentence has purely by being English, and removing it
  /// leaves the part that is actually about cooking or a deadline. Recomputed
  /// on demand and cached against the sentence count, because it moves only
  /// when new text arrives.
  /// Every sentence with a usable embedding, for callers that need to score
  /// against the whole corpus — search, most obviously.
  List<JournalSentence> sentencesWithEmbeddings() => [
    for (final sentence in _journalSentenceBox.getAll())
      if (sentence.embedding?.length == embeddingDimensions) sentence,
  ];

  /// The corpus mean and a vector centred against it, exposed because search
  /// has to measure similarity the same way clustering does. Raw cosine is
  /// meaningless on these embeddings — see the clustering notes in CLAUDE.md.
  List<double>? corpusMean() => _meanEmbedding();

  List<double>? centred(List<double> vector, List<double>? mean) =>
      _centred(vector, mean);

  double similarity(List<double> a, List<double> b) => _dot(a, b);

  /// Read off the clusters, not the sentences.
  ///
  /// Every cluster already carries `sumVector`, the running sum of its members'
  /// embeddings, so summing those and dividing by the total member count gives
  /// exactly the mean of every clustered sentence — for the cost of loading
  /// tens of clusters instead of thousands of sentences. Loading every sentence
  /// here, on every save, was the single most expensive thing in the pipeline.
  List<double>? _meanEmbedding() {
    var count = 0;
    final sum = List<double>.filled(embeddingDimensions, 0);
    for (final cluster in _themeClusterBox.getAll()) {
      final vector = cluster.sumVector;
      if (vector == null || vector.length != embeddingDimensions) continue;
      for (var i = 0; i < embeddingDimensions; i++) {
        sum[i] += vector[i];
      }
      count += cluster.memberCount;
    }
    if (count < _minSamplesForCentring) return null;
    return [for (final value in sum) value / count];
  }

  /// The same mean, over an explicit set. Used by [reclusterAll], which has to
  /// compute it before it throws the old clusters away.
  List<double>? _meanOf(List<JournalSentence> sentences) {
    if (sentences.length < _minSamplesForCentring) return null;
    final sum = List<double>.filled(embeddingDimensions, 0);
    for (final sentence in sentences) {
      final vector = sentence.embedding!;
      for (var i = 0; i < embeddingDimensions; i++) {
        sum[i] += vector[i];
      }
    }
    return [for (final value in sum) value / sentences.length];
  }

  /// [v] with the common direction removed, renormalized. Null when there is
  /// not enough text yet, or when [v] *is* the common direction and nothing
  /// distinctive survives.
  List<double>? _centred(List<double> v, List<double>? mean) {
    if (mean == null) return null;
    final centred = [for (var i = 0; i < v.length; i++) v[i] - mean[i]];
    final magnitude = sqrt(centred.fold(0.0, (a, b) => a + b * b));
    if (magnitude < 1e-6) return null;
    return [for (final value in centred) value / magnitude];
  }

  double _dot(List<double> a, List<double> b) {
    var total = 0.0;
    for (var i = 0; i < a.length; i++) {
      total += a[i] * b[i];
    }
    return total;
  }

  List<double> _normalize(List<double> v) {
    final mag = sqrt(v.fold(0.0, (a, b) => a + b * b));
    if (mag == 0) return v;
    return v.map((x) => x / mag).toList();
  }
}
