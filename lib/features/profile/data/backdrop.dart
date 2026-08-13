import 'package:flutter/foundation.dart';

/// How a backdrop is framed inside the Home pane.
///
/// The pane is roughly 9:19.5 — far taller than any camera produces — so a
/// photo has to give something up to fill it. Which thing it gives up is a
/// judgement about that particular picture, not something the app can decide.
enum BackdropFit {
  /// Fill the pane, cropping whatever doesn't fit. What every backdrop did
  /// before this existed, and still the default.
  fill('Fill'),

  /// Show the whole picture, and fill the space it leaves with an
  /// over-scaled, heavily blurred copy of itself.
  ///
  /// For anything wide. A 4:3 landscape shot cropped to a phone-shaped hole
  /// is magnified about two and a half times, which is how a photo of a room
  /// turns into a photo of a curtain.
  whole('Whole picture');

  const BackdropFit(this.label);

  final String label;

  static BackdropFit fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fill;
  }
}

/// One image on the Home screen, with the words that go with it.
///
/// The caption is optional on purpose: some photos say the thing by
/// themselves, and forcing a sentence onto them makes setup feel like a form.
@immutable
class Backdrop {
  const Backdrop({
    required this.imagePath,
    this.caption,
    this.fit = BackdropFit.fill,
    this.focusY = 0,
  });

  /// The file's *name* in app-support storage, not a path and not the
  /// picker's temp location. Resolve it with `ProfileStore.absolutePathFor`.
  ///
  /// Deliberately not absolute: iOS moves an app's container between installs,
  /// so a path written on one run can be dangling on the next. May still point
  /// at a file that no longer exists — always guard.
  final String imagePath;

  final String? caption;

  final BackdropFit fit;

  /// Which part of the picture survives the crop, from −1 (top) to 1 (bottom).
  ///
  /// Adjusted rather than cropped, so nothing is re-encoded and nothing is
  /// thrown away — moving this back to 0 restores exactly what the picker
  /// handed over. Ignored by [BackdropFit.whole], which crops nothing.
  final double focusY;

  bool get hasCaption => caption != null && caption!.trim().isNotEmpty;

  Backdrop copyWith({
    String? imagePath,
    String? caption,
    BackdropFit? fit,
    double? focusY,
  }) => Backdrop(
    imagePath: imagePath ?? this.imagePath,
    caption: caption ?? this.caption,
    fit: fit ?? this.fit,
    focusY: focusY ?? this.focusY,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'imagePath': imagePath,
    'caption': caption,
    'fit': fit.name,
    'focusY': focusY,
  };

  /// Null for a malformed entry, so one bad record can't take the whole list
  /// down with it. Every field but the path is optional — backdrops saved
  /// before framing existed simply get the defaults, which is what they were
  /// already doing.
  static Backdrop? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final path = json['imagePath'];
    if (path is! String || path.isEmpty) return null;
    final caption = json['caption'];
    final focusY = json['focusY'];
    return Backdrop(
      imagePath: path,
      caption: caption is String ? caption : null,
      fit: BackdropFit.fromName(json['fit'] as String?),
      focusY: focusY is num ? focusY.toDouble().clamp(-1.0, 1.0) : 0,
    );
  }
}
