import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// A photo placed inside a box, with the space it doesn't reach filled by a
/// blurred continuation of the picture itself.
///
/// The fill is a **mirror tiling** of the same image, aligned to the same rect
/// the sharp copy is drawn into. That alignment is the whole trick: the pixel
/// immediately above the photo's top edge is the pixel immediately below it,
/// so the blurred surround leaves the picture in the colours the picture ends
/// in and carries them outward. An over-scaled centre-cropped copy — which is
/// what this replaced — is the same *photo* but not the same *place*, so a
/// yellow sign in the middle of the frame washes the sky above a blue wall.
///
/// The sharp copy's edges are then faded into the fill over a short taper.
/// Underneath that fade is the identical content, so there is nothing to
/// cross-fade *to* — the seam simply stops existing, and what's left reads as
/// one picture that goes soft toward the edges.
///
/// Painted rather than composed out of [Image] widgets because all of it —
/// placement, mirror, blur, taper — is one rect and three draws, and because
/// the surround has to be able to sample past the photo's edge, which no
/// arrangement of boxes can do.
class BackdropPhoto extends StatefulWidget {
  const BackdropPhoto({
    required this.image,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.zoom = 1,
    this.offset = Offset.zero,
    this.bleedSigma = 34,
    this.sharpInsets = EdgeInsets.zero,
    super.key,
  });

  final ImageProvider image;

  /// Shown until the first frame decodes, and permanently if it never does —
  /// the path is persisted and the file lives in app storage, so it can outlive
  /// what it points at.
  final Widget fallback;

  /// The baseline placement, before [zoom]. [BoxFit.cover] fills the box;
  /// [BoxFit.contain] fits the whole picture inside it.
  final BoxFit fit;

  /// A multiple of the baseline.
  final double zoom;

  /// Pan from centred, in box widths and box heights.
  final Offset offset;

  /// How hard the surround is blurred. Enough that no detail in it competes
  /// with the picture sitting on top. Worth dropping while a gesture is in
  /// flight: this one runs through an offscreen pass, so it is the expensive
  /// half of a frame that has any of it on screen at all.
  final double bleedSigma;

  /// The part of the box the caller is going to dissolve anyway, as fractions
  /// of the box, and therefore not part of the box a picture should be *fitted*
  /// to under [BoxFit.contain].
  ///
  /// "Whole picture" promises the whole picture. Fitting it to the full pane
  /// and then fading the top fifth and bottom quarter of that pane breaks the
  /// promise quietly: the picture is all there, and its ends are washed out.
  /// Fitting it to what will still be sharp keeps it — and the ends that were
  /// eating the photograph now hold the extended blur instead, which is what
  /// they are for.
  ///
  /// Deliberately ignored under [BoxFit.cover]: filling means filling, and a
  /// photo asked to fill the screen should reach the edges of it.
  final EdgeInsets sharpInsets;

  @override
  State<BackdropPhoto> createState() => _BackdropPhotoState();
}

class _BackdropPhotoState extends State<BackdropPhoto> {
  ImageStream? _stream;
  ui.Image? _frame;

  late final ImageStreamListener _listener = ImageStreamListener(
    _onFrame,
    // Required, not defensive: without a handler a dangling path escalates to
    // the uncaught-error handler, which fails the frame rather than falling
    // back to the placeholder.
    onError: _onError,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(BackdropPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) _resolve();
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _frame?.dispose();
    super.dispose();
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream;
    stream.addListener(_listener);
  }

  void _onFrame(ImageInfo info, bool synchronous) {
    // The listener owns what it is handed. Cloning first means the frame stays
    // alive after the info is released, and swapping only once the new one has
    // arrived is what keeps a backdrop change from flashing an empty box.
    final next = info.image.clone();
    info.dispose();
    setState(() {
      _frame?.dispose();
      _frame = next;
    });
  }

  void _onError(Object error, StackTrace? stack) {
    if (_frame == null) return;
    setState(() {
      _frame?.dispose();
      _frame = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (frame == null) return widget.fallback;

    return CustomPaint(
      size: Size.infinite,
      painter: _BackdropPainter(
        image: frame,
        fit: widget.fit,
        zoom: widget.zoom,
        offset: widget.offset,
        bleedSigma: widget.bleedSigma,
        sharpInsets: widget.sharpInsets,
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({
    required this.image,
    required this.fit,
    required this.zoom,
    required this.offset,
    required this.bleedSigma,
    required this.sharpInsets,
  });

  final ui.Image image;
  final BoxFit fit;
  final double zoom;
  final Offset offset;
  final double bleedSigma;
  final EdgeInsets sharpInsets;

  /// How far the sharp copy fades into the surround, per axis, as a fraction
  /// of the picture's own extent along it.
  ///
  /// The two ends of the tuning pull against each other and both were asked
  /// for: too short and the change in sharpness reads as a step rather than a
  /// fade, too long and "the whole picture" is a picture with soft ends. The
  /// floor is what it takes to hide the seam at all; the ceiling stops a large
  /// photo from giving up an inch of itself at each edge.
  static const double _taperFraction = 0.07;
  static const double _minTaper = 20;
  static const double _maxTaper = 56;

  /// The alpha ramp across a taper, sampled off a smoothstep and then held
  /// back a little at the start. A straight line has a corner at each end,
  /// and against a contrasting background a corner in an alpha ramp is a
  /// visible band — which is the whole reason this isn't two stops.
  static const List<double> _rampStops = [0, 0.25, 0.5, 0.75, 1];
  static const List<double> _rampAlpha = [0, 0.08, 0.32, 0.68, 1];

  /// Where the picture ends up, given a box. Public to the library so the
  /// editor can clamp a drag against the same arithmetic that draws it —
  /// two implementations of this would drift, and the one that drifted would
  /// be the one the user is dragging.
  static Rect placement({
    required Size image,
    required Size box,
    required BoxFit fit,
    required double zoom,
    required Offset offset,
    EdgeInsets sharpInsets = EdgeInsets.zero,
  }) {
    // Under contain the picture is fitted to what will still be sharp, and
    // centred in it — which sits a hair off the pane's own centre, because the
    // dissolve is longer at the bottom than at the top.
    final safe = fit == BoxFit.contain
        ? Rect.fromLTRB(
            box.width * sharpInsets.left,
            box.height * sharpInsets.top,
            box.width * (1 - sharpInsets.right),
            box.height * (1 - sharpInsets.bottom),
          )
        : Offset.zero & box;
    if (safe.isEmpty) return Offset.zero & box;

    final baseline = fit == BoxFit.contain
        ? math.min(safe.width / image.width, safe.height / image.height)
        : math.max(safe.width / image.width, safe.height / image.height);
    final scale = baseline * zoom;
    return Rect.fromCenter(
      center: Offset(
        safe.center.dx + offset.dx * box.width,
        safe.center.dy + offset.dy * box.height,
      ),
      width: image.width * scale,
      height: image.height * scale,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final source = Size(image.width.toDouble(), image.height.toDouble());
    if (size.isEmpty || source.isEmpty) return;

    final box = Offset.zero & size;
    final dst = placement(
      image: source,
      box: size,
      fit: fit,
      zoom: zoom,
      offset: offset,
      sharpInsets: sharpInsets,
    );

    // Half a pixel of slack: a photo that lands exactly on the edge is covered,
    // and paying for a full-screen offscreen pass to fill nothing is the one
    // outcome worth ruling out.
    const slack = 0.5;
    final gapTop = dst.top > box.top + slack;
    final gapBottom = dst.bottom < box.bottom - slack;
    final gapLeft = dst.left > box.left + slack;
    final gapRight = dst.right < box.right - slack;
    final hasGap = gapTop || gapBottom || gapLeft || gapRight;

    if (hasGap) _paintBleed(canvas, box, dst, source);

    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;

    if (!hasGap) {
      canvas.drawImageRect(image, Offset.zero & source, dst, paint);
      return;
    }

    final visible = dst.intersect(box);
    if (visible.isEmpty) return;

    canvas.saveLayer(visible, Paint());
    canvas.drawImageRect(image, Offset.zero & source, dst, paint);
    _taper(
      canvas,
      dst,
      verticalGap: math.max(dst.top - box.top, box.bottom - dst.bottom),
      horizontalGap: math.max(dst.left - box.left, box.right - dst.right),
    );
    canvas.restore();
  }

  /// The surround: the same picture, mirrored outward from the same rect, and
  /// blurred past the point of holding any detail.
  void _paintBleed(Canvas canvas, Rect box, Rect dst, Size source) {
    final matrix = Matrix4.identity()
      ..translateByDouble(dst.left, dst.top, 0, 1)
      ..scaleByDouble(
        dst.width / source.width,
        dst.height / source.height,
        1,
        1,
      );

    final shader = ui.ImageShader(
      image,
      TileMode.mirror,
      TileMode.mirror,
      matrix.storage,
      // The result is about to be blurred into mush, so sampling it well is
      // paying for detail that is thrown away in the next pass.
      filterQuality: FilterQuality.low,
    );

    // Drawn past the edges so the blur has real pixels to reach for there.
    // TileMode.clamp covers the rest; without both, the pane's own border
    // fades toward transparent and reads as a vignette.
    final bounds = box.inflate(bleedSigma);
    canvas.saveLayer(
      bounds,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: bleedSigma,
          sigmaY: bleedSigma,
          tileMode: TileMode.clamp,
        ),
    );
    canvas.drawRect(bounds, Paint()..shader = shader);
    canvas.restore();

    shader.dispose();
  }

  void _taper(
    Canvas canvas,
    Rect dst, {
    required double verticalGap,
    required double horizontalGap,
  }) {
    void fade(Offset from, Offset to, double extent) {
      final span = (to - from).distance;
      if (span <= 0) return;
      final width = (extent / span).clamp(0.0, 0.5);

      // The eased ramp, mirrored: in from one end, held solid across the
      // middle, out to the other.
      final colors = <Color>[
        for (final alpha in _rampAlpha) Color.fromRGBO(0, 0, 0, alpha),
        for (final alpha in _rampAlpha.reversed) Color.fromRGBO(0, 0, 0, alpha),
      ];
      final stops = <double>[
        for (final stop in _rampStops) stop * width,
        for (final stop in _rampStops.reversed) 1 - stop * width,
      ];

      canvas.drawRect(
        dst,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = ui.Gradient.linear(from, to, colors, stops),
      );
    }

    // The two axes are not the same problem, and one rule for both got each of
    // them wrong.
    //
    // Vertically the page's own dissolve is already working on the picture's
    // ends, so the taper only has to cover the change in sharpness and short
    // is right — long here means giving up an inch of photograph to a fade
    // that was happening anyway.
    //
    // Sideways nothing else is happening: it is sharp picture against blurred
    // picture and nothing else, so the cross-fade wants to be about as wide as
    // the band it is hiding. A tall photo leaves wide side margins, and twenty
    // points across seventy-five of blur reads as an edge.
    if (verticalGap > 0.5) {
      fade(
        dst.topCenter,
        dst.bottomCenter,
        (dst.height * _taperFraction).clamp(_minTaper, _maxTaper),
      );
    }
    if (horizontalGap > 0.5) {
      fade(
        dst.centerLeft,
        dst.centerRight,
        (horizontalGap * 0.6).clamp(_minTaper, dst.width * 0.18),
      );
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.image != image ||
      old.fit != fit ||
      old.zoom != zoom ||
      old.offset != offset ||
      old.bleedSigma != bleedSigma ||
      old.sharpInsets != sharpInsets;
}

/// Where a photo lands inside a box under a given framing.
///
/// The editor needs this to know how far a drag can go before it is dragging
/// nothing; the painter needs it to draw. Same function, so they cannot
/// disagree.
Rect backdropPlacement({
  required Size image,
  required Size box,
  required BoxFit fit,
  required double zoom,
  required Offset offset,
  EdgeInsets sharpInsets = EdgeInsets.zero,
}) => _BackdropPainter.placement(
  image: image,
  box: box,
  fit: fit,
  zoom: zoom,
  offset: offset,
  sharpInsets: sharpInsets,
);
