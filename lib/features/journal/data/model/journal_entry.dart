import 'package:objectbox/objectbox.dart';

@Entity()
class JournalEntry {
  @Id()
  int id = 0;
  String? rawText; // full transcription, unedited
  String? keywords; // YAKE over the whole entry, for at-a-glance display
  double? moodScore; // -1.0 to 1.0, from NLTagger sentiment
  @Property(type: PropertyType.date)
  DateTime? createdAt;

  @Backlink('entry')
  final sentences = ToMany<JournalSentence>(); // now derived, read-only
}

@Entity()
class JournalSentence {
  @Id()
  int id = 0;
  String? text; // one sentence from embedSentences()
  String? keywords; // YAKE on just this sentence
  int? clusterId; // which ThemeCluster this belongs to

  @Property(type: PropertyType.date)
  DateTime? createdAt;

  final entry = ToOne<JournalEntry>();

  @HnswIndex(dimensions: 512, distanceType: VectorDistanceType.cosine)
  @Property(type: PropertyType.floatVector)
  List<double>? embedding;
}
