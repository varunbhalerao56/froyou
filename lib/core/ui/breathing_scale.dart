import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A very slow scale, applied to a raster of the child rather than to the child.
///
/// The distinction is the entire widget. A [Transform] above a
/// [RepaintBoundary] *looks* free — a changing matrix should be the
/// compositor's problem — but nothing will hold a cached layer whose transform
/// moves every frame, so the subtree underneath is re-rendered at full device
/// pixel ratio on every frame instead. That is what made the old Ken Burns
/// drift the most expensive thing in the app: it re-ran a two-pass Gaussian and
/// resampled the photo sixty times a second while Home sat idle.
///
/// [SnapshotWidget] is the way out, and this is the case its own documentation
/// describes: the child is rasterized **once**, and the painter's
/// `notifyListeners` re-paints that same raster under a new matrix. A frame is
/// then one textured quad. Nothing below is asked to draw again.
///
/// Two consequences worth knowing:
///
/// * **It only ever scales up.** Growing keeps the raster covering the box;
///   shrinking would open a gap at the edges, and the raster has nothing to
///   put there. The cost is that the picture is very slightly magnified at the
///   far end of the breath, which at this amplitude is under a pixel.
/// * **A raster does not follow its child.** The snapshot is not invalidated
///   when the child repaints on its own — an image finishing its decode, say —
///   so [enabled] must stay false until the child is showing what it means to
///   show. Every rebuild re-takes it.
class BreathingScale extends StatefulWidget {
  const BreathingScale({
    required this.child,
    this.enabled = true,
    this.amplitude = 0.06,
    this.period = const Duration(seconds: 8),
    super.key,
  });

  final Widget child;

  /// Off paints the child directly, with no raster and no animation — which is
  /// also what a golden wants, and what anything still waiting on its content
  /// needs.
  final bool enabled;

  /// How far up the breath goes, as a fraction. Deliberately small: this is
  /// meant to be noticed the way a room's light is noticed, not watched.
  final double amplitude;

  final Duration period;

  @override
  State<BreathingScale> createState() => _BreathingScaleState();
}

class _BreathingScaleState extends State<BreathingScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );
  late final CurvedAnimation _breath = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );
  late final _BreathPainter _painter = _BreathPainter(
    animation: _breath,
    amplitude: widget.amplitude,
  );
  final SnapshotController _snapshot = SnapshotController();

  @override
  void initState() {
    super.initState();
    _sync(rearm: true);
  }

  @override
  void didUpdateWidget(BreathingScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.period != oldWidget.period) _controller.duration = widget.period;
    _painter.amplitude = widget.amplitude;
    // Any rebuild may have changed what the child paints, and the raster would
    // otherwise outlive it. Cheap, because the carousel rebuilds on a backdrop
    // or a theme changing and not otherwise.
    _sync(
      rearm:
          widget.child != oldWidget.child ||
          widget.enabled != oldWidget.enabled,
    );
  }

  void _sync({required bool rearm}) {
    if (widget.enabled) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
      // Off and on again in the same frame: dropping the flag is what discards
      // the stale raster, and paint takes a fresh one on the way back up.
      if (rearm) _snapshot.allowSnapshotting = false;
      _snapshot.allowSnapshotting = true;
    } else {
      _controller.stop();
      _controller.value = 0;
      _snapshot.allowSnapshotting = false;
    }
  }

  @override
  void dispose() {
    _snapshot.dispose();
    _painter.dispose();
    _breath.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return ClipRect(
      child: SnapshotWidget(
        controller: _snapshot,
        painter: _painter,
        // A size change means the raster is the wrong shape, not merely stale.
        autoresize: true,
        // Nothing here contains a platform view, but throwing on a backdrop is
        // a bad trade against quietly painting it the ordinary way.
        mode: SnapshotMode.permissive,
        child: widget.child,
      ),
    );
  }
}

class _BreathPainter extends SnapshotPainter {
  _BreathPainter({required this.animation, required double amplitude}) {
    _amplitude = amplitude;
    animation.addListener(notifyListeners);
  }

  final Animation<double> animation;

  /// Assigned rather than an initializing formal: it is settable, and the
  /// setter is what repaints.
  double get amplitude => _amplitude;
  late double _amplitude;
  set amplitude(double value) {
    if (value == _amplitude) return;
    _amplitude = value;
    notifyListeners();
  }

  double get _scale => 1 + _amplitude * animation.value;

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    Size size,
    PaintingContextCallback painter,
  ) {
    final scale = _scale;
    if (scale == 1 || size.isEmpty) {
      painter(context, offset);
      return;
    }
    final centre = size.center(Offset.zero);
    context.pushTransform(
      true,
      offset,
      Matrix4.identity()
        ..translateByDouble(centre.dx, centre.dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-centre.dx, -centre.dy, 0, 1),
      painter,
    );
  }

  @override
  void paintSnapshot(
    PaintingContext context,
    Offset offset,
    Size size,
    ui.Image image,
    Size sourceSize,
    double pixelRatio,
  ) {
    final scale = _scale;
    context.canvas.drawImageRect(
      image,
      Offset.zero & sourceSize,
      Rect.fromCenter(
        center: offset + size.center(Offset.zero),
        width: size.width * scale,
        height: size.height * scale,
      ),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _BreathPainter oldPainter) =>
      oldPainter.animation != animation || oldPainter.amplitude != _amplitude;

  @override
  void dispose() {
    animation.removeListener(notifyListeners);
    super.dispose();
  }
}
