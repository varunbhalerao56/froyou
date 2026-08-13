import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Where a backdrop's framing starts from.
///
/// The pane is roughly 9:19.5 — far taller than any camera produces — so a
/// photo has to give something up to fill it. This picks which end of that
/// trade the adjustment starts at; [BackdropFraming.zoom] and the offsets take
/// it from there.
enum BackdropFit {
  /// Fill the pane, cropping whatever doesn't fit. Still the default.
  fill('Fill'),

  /// Show the whole picture, and let the extended blur fill the rest.
  ///
  /// For anything wide. A 4:3 landscape shot cropped to a phone-shaped hole is
  /// magnified about two and a half times, which is how a photo of a room
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

/// How one picture sits in the pane: a baseline, a zoom on top of it, and a
/// nudge in each direction.
///
/// Everything here is applied at paint time and nothing is ever re-encoded, so
/// [initial] is byte-for-byte what the picker handed over.
///
/// The units are the point. [zoom] is a *multiple of the baseline* and the
/// offsets are fractions of the *pane*, not of the picture — so a stored
/// framing means the same thing whatever the photo's dimensions turn out to be,
/// and nothing downstream has to resolve an image before it can lay one out.
@immutable
class BackdropFraming {
  const BackdropFraming({
    this.fit = BackdropFit.fill,
    this.zoom = 1,
    this.offsetX = 0,
    this.offsetY = 0,
  });

  /// What every backdrop gets before anyone touches it: fill the pane, centred.
  static const BackdropFraming initial = BackdropFraming();

  final BackdropFit fit;

  /// A multiple of whatever [fit] resolves to. 1 is the baseline exactly.
  final double zoom;

  /// Pan, in pane widths and pane heights, from centred.
  final double offsetX;
  final double offsetY;

  /// Deliberately not the ceiling the editor enforces — that one follows the
  /// picture, so it can only be worked out once the image has been decoded.
  /// This is the sanity bound a stored value has to clear.
  static const double maxZoom = 8;
  static const double maxOffset = 4;

  BoxFit get baseFit =>
      fit == BackdropFit.whole ? BoxFit.contain : BoxFit.cover;

  Offset get offset => Offset(offsetX, offsetY);

  bool get isInitial =>
      fit == BackdropFit.fill && zoom == 1 && offsetX == 0 && offsetY == 0;

  BackdropFraming copyWith({
    BackdropFit? fit,
    double? zoom,
    double? offsetX,
    double? offsetY,
  }) => BackdropFraming(
    fit: fit ?? this.fit,
    zoom: zoom ?? this.zoom,
    offsetX: offsetX ?? this.offsetX,
    offsetY: offsetY ?? this.offsetY,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'fit': fit.name,
    'zoom': zoom,
    'offsetX': offsetX,
    'offsetY': offsetY,
  };

  /// Reads whatever is there and clamps it, so a hand-edited or half-written
  /// record can't put a picture somewhere it can never be dragged back from.
  ///
  /// `focusY` — the single slider this replaced — is read and dropped on
  /// purpose. It was an [Alignment], so it only ever moved a photo that
  /// overflowed the pane *vertically*, and at 9:19.5 nothing short of a 1:2.2
  /// panorama does. Every stored value was therefore inert, and reinterpreting
  /// it in these units would move pictures that have never moved.
  static BackdropFraming fromJson(Map<Object?, Object?> json) {
    double read(String key, double fallback, double limit) {
      final value = json[key];
      if (value is! num) return fallback;
      final result = value.toDouble();
      if (!result.isFinite) return fallback;
      return result.clamp(-limit, limit);
    }

    return BackdropFraming(
      fit: BackdropFit.fromName(json['fit'] as String?),
      zoom: read('zoom', 1, maxZoom).clamp(1.0, maxZoom),
      offsetX: read('offsetX', 0, maxOffset),
      offsetY: read('offsetY', 0, maxOffset),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackdropFraming &&
      other.fit == fit &&
      other.zoom == zoom &&
      other.offsetX == offsetX &&
      other.offsetY == offsetY;

  @override
  int get hashCode => Object.hash(fit, zoom, offsetX, offsetY);
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
    this.framing = BackdropFraming.initial,
  });

  /// The file's *name* in app-support storage, not a path and not the
  /// picker's temp location. Resolve it with `ProfileStore.absolutePathFor`.
  ///
  /// Deliberately not absolute: iOS moves an app's container between installs,
  /// so a path written on one run can be dangling on the next. May still point
  /// at a file that no longer exists — always guard.
  final String imagePath;

  final String? caption;

  final BackdropFraming framing;

  bool get hasCaption => caption != null && caption!.trim().isNotEmpty;

  /// [caption] is nullable and clearing it is a real thing to want, so it takes
  /// a sentinel rather than reading `null` as "leave it alone".
  Backdrop copyWith({
    String? imagePath,
    Object? caption = _unset,
    BackdropFraming? framing,
  }) => Backdrop(
    imagePath: imagePath ?? this.imagePath,
    caption: identical(caption, _unset) ? this.caption : caption as String?,
    framing: framing ?? this.framing,
  );

  static const Object _unset = Object();

  Map<String, Object?> toJson() => <String, Object?>{
    'imagePath': imagePath,
    'caption': caption,
    ...framing.toJson(),
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
    return Backdrop(
      imagePath: path,
      caption: caption is String ? caption : null,
      framing: BackdropFraming.fromJson(json),
    );
  }
}
