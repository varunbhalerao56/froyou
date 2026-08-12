import 'package:flutter/foundation.dart';

/// One image on the Home screen, with the words that go with it.
///
/// The caption is optional on purpose: some photos say the thing by
/// themselves, and forcing a sentence onto them makes setup feel like a form.
@immutable
class Backdrop {
  const Backdrop({required this.imagePath, this.caption});

  /// The file's *name* in app-support storage, not a path and not the
  /// picker's temp location. Resolve it with `ProfileStore.absolutePathFor`.
  ///
  /// Deliberately not absolute: iOS moves an app's container between installs,
  /// so a path written on one run can be dangling on the next. May still point
  /// at a file that no longer exists — always guard.
  final String imagePath;

  final String? caption;

  bool get hasCaption => caption != null && caption!.trim().isNotEmpty;

  Backdrop copyWith({String? imagePath, String? caption}) => Backdrop(
    imagePath: imagePath ?? this.imagePath,
    caption: caption ?? this.caption,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'imagePath': imagePath,
    'caption': caption,
  };

  /// Null for a malformed entry, so one bad record can't take the whole list
  /// down with it.
  static Backdrop? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final path = json['imagePath'];
    if (path is! String || path.isEmpty) return null;
    final caption = json['caption'];
    return Backdrop(
      imagePath: path,
      caption: caption is String ? caption : null,
    );
  }
}
