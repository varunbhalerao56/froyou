import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/backdrop_photo.dart';
import 'package:froyou/core/ui/edge_glow_image.dart';
import 'package:froyou/features/profile/data/backdrop.dart';
import 'package:froyou/features/profile/presentation/profile_controller.dart';

/// Framing one picture, the way the wallpaper picker does it: the photo at the
/// size and shape it will actually appear, and you move it.
///
/// It replaced a sheet with a segmented control and a slider, and the slider
/// was inert — it set an [Alignment], which only moves an image that overflows
/// its box *vertically*, and at 9:19.5 nothing short of a 1:2.2 panorama does.
/// Every photograph overflows that pane sideways instead, so the one control
/// offered for "what to keep" could not move anything anyone would put in it.
///
/// Nothing here re-encodes the file. A zoom and two offsets are stored beside
/// the image and applied when it is drawn, so Reset is exact rather than
/// approximate.
class BackdropFramingView extends StatefulWidget {
  const BackdropFramingView({
    required this.profile,
    required this.index,
    super.key,
  });

  final ProfileController profile;
  final int index;

  @override
  State<BackdropFramingView> createState() => _BackdropFramingViewState();
}

class _BackdropFramingViewState extends State<BackdropFramingView> {
  static const double _maxZoom = 4;

  /// How far a picture that already fits may still be nudged, in pane
  /// fractions. It has nowhere it *needs* to go — but the blur extends it, so
  /// there is no hole to fall into, and letting a horizon sit high is worth
  /// more than the tidiness of pinning it dead centre.
  static const double _give = 0.12;

  late BackdropFraming _framing = _current?.framing ?? BackdropFraming.initial;

  ImageStream? _stream;
  Size? _imageSize;
  late final ImageStreamListener _listener = ImageStreamListener(
    _onFrame,
    onError: (_, _) {},
  );

  /// The box the gesture was measured in, so a drag in points can be turned
  /// into an offset in pane fractions.
  Size _pane = Size.zero;
  bool _gesturing = false;
  double _startZoom = 1;

  Backdrop? get _current {
    final backdrops = widget.profile.backdrops;
    if (widget.index < 0 || widget.index >= backdrops.length) return null;
    return backdrops[widget.index];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final backdrop = _current;
    if (backdrop == null) return;
    final stream = widget.profile
        .providerFor(backdrop)
        .resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream;
    stream.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  /// The picture's own proportions, which is all the clamp needs: how far a
  /// drag can go is a question about how much of the photo is off-screen.
  void _onFrame(ImageInfo info, bool synchronous) {
    final size = Size(
      info.image.width.toDouble(),
      info.image.height.toDouble(),
    );
    info.dispose();
    if (_imageSize == size) return;
    if (synchronous) {
      _imageSize = size;
    } else if (mounted) {
      setState(() => _imageSize = size);
    }
  }

  void _commit() {
    widget.profile.setFraming(widget.index, _framing);
  }

  void _apply(BackdropFraming framing) {
    setState(() => _framing = framing);
    _commit();
  }

  /// Clamped so a drag stops where the picture does. Once it is bigger than
  /// the pane the limit is exactly its overhang, which is what makes dragging
  /// to the edge of a wide photo feel like it hits the edge of the photo.
  Offset _clampOffset(Offset offset, double zoom) {
    final image = _imageSize;
    if (image == null || _pane.isEmpty) return offset;

    final drawn = backdropPlacement(
      image: image,
      box: _pane,
      fit: _framing.baseFit,
      zoom: zoom,
      offset: Offset.zero,
      // The same box the painter fits into, or the drag stops somewhere the
      // picture isn't.
      sharpInsets: EdgeGlowImage.defaultSharpInsets,
    );

    // Three cases, and the middle one matters: a picture hanging over the edge
    // may be dragged exactly as far as it hangs, one that falls short may be
    // nudged into the blur, and one that lands flush is already filling the
    // pane and has nowhere to go. Without that last case "Fill" would let a
    // drag open a band of blur along an edge it was chosen to reach.
    double limit(double drawnExtent, double paneExtent) {
      final overhang = (drawnExtent - paneExtent) / 2;
      if (overhang > 0) return overhang / paneExtent;
      return drawnExtent < paneExtent ? _give : 0;
    }

    final x = limit(drawn.width, _pane.width);
    final y = limit(drawn.height, _pane.height);
    return Offset(offset.dx.clamp(-x, x), offset.dy.clamp(-y, y));
  }

  void _onScaleStart(ScaleStartDetails details) {
    setState(() {
      _gesturing = true;
      _startZoom = _framing.zoom;
    });
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_pane.isEmpty) return;

    final zoom = (_startZoom * details.scale).clamp(1.0, _maxZoom);

    // Zooming holds whatever is under the fingers still. In pane fractions the
    // picture's centre moves as c' = f + k(c − f) about the focal point f,
    // with k the change in scale — which needs neither the image's size nor
    // where its edges are, only the ratio.
    final k = zoom / _framing.zoom;
    final focal = Offset(
      details.localFocalPoint.dx / _pane.width - 0.5,
      details.localFocalPoint.dy / _pane.height - 0.5,
    );
    var offset = focal + (_framing.offset - focal) * k;

    offset += Offset(
      details.focalPointDelta.dx / _pane.width,
      details.focalPointDelta.dy / _pane.height,
    );

    final clamped = _clampOffset(offset, zoom);
    setState(() {
      _framing = _framing.copyWith(
        zoom: zoom,
        offsetX: clamped.dx,
        offsetY: clamped.dy,
      );
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    setState(() => _gesturing = false);
    // Written once, at the end. Every save here rewrites the whole profile to
    // preferences, so committing per gesture frame would be a file write per
    // frame of a drag.
    _commit();
  }

  void _setFit(BackdropFit fit) {
    // A baseline is a starting point, so choosing one starts over. Keeping a
    // zoom across the switch lands somewhere neither button describes.
    _apply(BackdropFraming(fit: fit));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final backdrop = _current;
    if (backdrop == null) return const SizedBox.shrink();

    // The pane runs the whole height of the screen in the layout that ships,
    // so this is the shape a photo has to live in — measured rather than
    // written down, because it is different on every device.
    final screen = MediaQuery.sizeOf(context);
    final paneAspect = screen.width / screen.height;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'How this sits',
          style: AppTypography.headline.copyWith(color: colors.textPrimary),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(CupertinoIcons.chevron_left, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Done'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: AppInsets.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: paneAspect,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Read during build rather than in a callback: the
                        // gesture arithmetic is all in fractions of this, and
                        // it has to be right on the first touch.
                        _pane = constraints.biggest;
                        return _Preview(
                          image: widget.profile.providerFor(backdrop),
                          framing: _framing,
                          colors: colors,
                          gesturing: _gesturing,
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          onScaleEnd: _onScaleEnd,
                        );
                      },
                    ),
                  ),
                ),
              ),
              AppGap.mdV,

              // Directly under the picture, where a hand already is. Nothing
              // about a photograph says it can be dragged.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: AppSpacing.xs,
                children: [
                  Icon(
                    CupertinoIcons.arrow_up_left_arrow_down_right,
                    size: 13,
                    color: colors.placeholder,
                  ),
                  // Flexible, not fixed: it is one line at the shipping text
                  // size and two at the largest, and a hint that overflows is
                  // a red-and-yellow bar across the thing it is hinting at.
                  Flexible(
                    child: Text(
                      'Pinch to zoom · Drag to move',
                      style: AppTypography.caption.copyWith(
                        color: colors.placeholder,
                      ),
                    ),
                  ),
                ],
              ),
              AppGap.mdV,

              Row(
                spacing: AppSpacing.sm,
                children: [
                  for (final option in BackdropFit.values)
                    Expanded(
                      child: _FitButton(
                        option: option,
                        selected: option == _framing.fit,
                        colors: colors,
                        onTap: () => _setFit(option),
                      ),
                    ),
                ],
              ),
              AppGap.smV,

              Text(
                _framing.fit == BackdropFit.whole
                    ? 'All of it, sharp, with the blur carrying it out to the '
                          'edges. Good for anything wide.'
                    : 'Fills the screen, and the ends soften into the page.',
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: colors.placeholder,
                ),
              ),
              AppGap.smV,

              // Deliberately never disabled. Enabling it mid-drag asks the
              // framework to interpolate between the disabled and enabled
              // label styles, and Material's own text theme has `inherit:
              // false` on one side of that — which asserts, on the first
              // frame of the first drag.
              TextButton(
                onPressed: () => _apply(BackdropFraming.initial),
                child: const Text('Reset'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The picture at the shape and framing Home will give it, and the surface the
/// gesture is measured on.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.image,
    required this.framing,
    required this.colors,
    required this.gesturing,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onScaleEnd,
  });

  final ImageProvider image;
  final BackdropFraming framing;
  final AppColors colors;
  final bool gesturing;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;
  final GestureScaleEndCallback onScaleEnd;

  @override
  Widget build(BuildContext context) {
    final height = math.max(1.0, MediaQuery.sizeOf(context).height);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: onScaleStart,
      onScaleUpdate: onScaleUpdate,
      onScaleEnd: onScaleEnd,
      child: ClipRSuperellipse(
        borderRadius: AppRadius.lgAll,
        child: LayoutBuilder(
          builder: (context, constraints) => EdgeGlowImage(
            image: image,
            topColor: colors.background,
            bottomColor: colors.background,
            imageHeight: constraints.maxHeight,
            topGlowExtent: 0,
            bottomGlowExtent: 0,
            fit: framing.baseFit,
            zoom: framing.zoom,
            offset: framing.offset,
            // Both blurs are scaled to the box: the real pane runs 40 over a
            // full screen, and the same figure over a preview a third of the
            // height would swallow the picture whole. Both drop further while
            // a finger is down — each is an offscreen pass, and they are what
            // a dragging frame would otherwise be spent on.
            blurSigma: (gesturing ? 22 : 40) * constraints.maxHeight / height,
            bleedSigma: gesturing ? 16 : 30,
          ),
        ),
      ),
    );
  }
}

class _FitButton extends StatelessWidget {
  const _FitButton({
    required this.option,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final BackdropFit option;
  final bool selected;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? colors.textBox : Colors.transparent,
          borderRadius: AppRadius.smAll,
        ),
        child: Center(
          child: Text(
            option.label,
            style: AppTypography.subheadline.copyWith(
              color: selected ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
