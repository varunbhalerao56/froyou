import 'package:objectbox/objectbox.dart';

@Entity()
class ThemeCluster {
  @Id()
  int id = 0;
  String? label; // e.g. "work stress" — built from member keywords
  int memberCount = 0;
  @Property(type: PropertyType.date)
  DateTime? lastSeen;

  List<double>?
  sumVector; // running Σ of member embeddings — for exact incremental mean
  @HnswIndex(dimensions: 512, distanceType: VectorDistanceType.cosine)
  @Property(type: PropertyType.floatVector)
  List<double>? centroid; // normalize(sumVector / memberCount) — what you compare against
}
