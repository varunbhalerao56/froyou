import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:froyou/core/ui/backdrop_photo.dart';
import 'package:froyou/core/ui/noise_overlay.dart';
import 'package:progressive_blur/progressive_blur.dart';

/// A sharp image wrapped in soft color-glow bleed above and below it, sampled
/// from the image's own top and bottom edge colors.
///
/// The image blurs and fades near its own top and bottom edges so it dissolves
/// into the glow rather than handing off at a hard boundary — and because the
/// glow colors are the same colors the surrounding page is painted in, the
/// image reads as emerging from the background instead of sitting on it.
///
/// A widget rather than a function on purpose. A function-widget has no
/// [Element] of its own, so it rebuilds into its parent's element and takes the
/// whole subtree with it — which would defeat the [RepaintBoundary] caching
/// that keeps the shader off the critical path while the shell scrolls.
class EdgeGlowImage extends StatelessWidget {
  const EdgeGlowImage({
    required this.image,
    required this.topColor,
    required this.bottomColor,
    this.borderRadius = BorderRadius.zero,
    this.imageHeight = 420,
    this.topGlowExtent = 50,
    this.bottomGlowExtent = 250,
    this.topBlurFadeEnd = defaultTopBlurFadeEnd,
    this.bottomBlurFadeStart = defaultBottomBlurFadeStart,
    this.blurSigma = 40.0,
    this.fit = BoxFit.cover,
    this.zoom = 1,
    this.offset = Offset.zero,
    this.bleedSigma = 34,
    super.key,
  });

  /// Null renders the themed gradient placeholder instead. Onboarding requires
  /// an image, so this is the safety net for a stored path whose file has gone
  /// missing — not a normal state.
  final ImageProvider? image;

  final Color topColor;
  final Color bottomColor;
  final BorderRadius borderRadius;
  final double imageHeight;
  final double topGlowExtent;
  final double bottomGlowExtent;

  /// Roughly a fifth of the image at each end. Shorter than this and the
  /// dissolve reads as an edge you can point at rather than as the photo
  /// emerging from the page.
  static const double defaultTopBlurFadeEnd = 0.22;
  static const double defaultBottomBlurFadeStart = 0.74;

  /// What the two above come to: the share of the box at each end that this
  /// widget is going to dissolve, and therefore the share a picture must not
  /// be *fitted* into if all of it is meant to be visible.
  ///
  /// Public because the framing editor clamps a drag against the same
  /// placement the painter draws, and it has to ask for the same box.
  static const EdgeInsets defaultSharpInsets = EdgeInsets.fromLTRB(
    0,
    defaultTopBlurFadeEnd,
    0,
    1 - defaultBottomBlurFadeStart,
  );

  /// End of the image's blur/fade zone at the TOP, as a fraction of height.
  final double topBlurFadeEnd;

  /// Start of the image's blur/fade zone at the BOTTOM, as a fraction of height.
  final double bottomBlurFadeStart;

  /// Dropped mid-animation to cut the shader's per-frame cost, then restored
  /// at rest. The two-pass Gaussian runs a synchronous `toImageSync` at full
  /// device pixel ratio every frame, so fewer taps per pixel is real money.
  final double blurSigma;

  /// The photo's baseline placement. [BoxFit.cover] crops it to the box;
  /// [BoxFit.contain] shows all of it and lets [BackdropPhoto]'s extended blur
  /// carry it out to the edges.
  final BoxFit fit;

  /// A multiple of [fit], and a pan from centred in box widths and heights.
  /// Both come from the framing editor; see [BackdropPhoto].
  final double zoom;
  final Offset offset;

  /// How hard the extended surround is blurred, when there is one.
  final double bleedSigma;

  /// A smoothstep, sampled. Five stops rather than two because a straight
  /// alpha ramp has a corner at each end, and a corner is invisible over a
  /// gradient and a line you can point at over a bright sky.
  static const List<double> _fadeStops = [0, 0.25, 0.5, 0.75, 1];
  static const List<double> _fadeAlpha = [0, 0.156, 0.5, 0.844, 1];

  /// How far past the pane's own width the dissolve's ellipse reaches. Larger
  /// is flatter; at 1.5 the picture's sides stay solid through the middle of
  /// the pane and the arc across the top is about fifty points deep.
  static const double _dissolveSpread = 1.5;

  /// Where the picture stops dissolving, as a share of the ellipse. Chosen so
  /// the middle of the top edge lands on [topBlurFadeEnd] — the same place the
  /// straight version put the whole edge.
  static const double _dissolveHold = 0.55;

  /// The image's own alpha: solid in the middle, gone at the top and bottom.
  ///
  /// An **ellipse**, not a horizontal band. A straight ramp dissolves the
  /// picture along a line, and a line — however soft — is a horizon across the
  /// screen that the eye locks onto. Curved, the picture's top corners give way
  /// before its middle does and there is no straight edge anywhere to find.
  /// The ellipse is much wider than the pane, so this is a shallow arc rather
  /// than a vignette: the sides stay solid at mid-height.
  Shader _dissolve(Rect rect) {
    final centre = rect.center;
    final radiusX = rect.width * _dissolveSpread;
    final radiusY = rect.height / 2;

    return ui.Gradient.radial(
      centre,
      1,
      [
        for (final alpha in _fadeAlpha.reversed)
          Colors.white.withValues(alpha: alpha),
      ],
      [
        for (final stop in _fadeStops)
          _dissolveHold + stop * (1 - _dissolveHold),
      ],
      TileMode.clamp,
      // Gradient space to pane space: a unit circle becomes the ellipse.
      (Matrix4.identity()
            ..translateByDouble(centre.dx, centre.dy, 0, 1)
            ..scaleByDouble(radiusX, radiusY, 1, 1)
            ..translateByDouble(-centre.dx, -centre.dy, 0, 1))
          .storage,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: topGlowExtent + imageHeight + bottomGlowExtent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Top glow — solid where the image has faded to nothing, gone by the
          // time the image is fully opaque, so the two cross over smoothly.
          //
          // This used to run the other way, and it was right when it was
          // written: [topColor] was sampled from the image's own top edge, so
          // holding it solid *near the seam* extended the picture upward and
          // fading it out at the very top blended into the page. Once the glow
          // became the page's own background colour, that same gradient started
          // painting an opaque band of background over a fully opaque image and
          // then stopping dead at the strip's edge — a hard line across the top
          // of every photo.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topGlowExtent + (imageHeight * topBlurFadeEnd),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // Eased, like everything else that crosses this seam: the
                  // glow is what the picture is dissolving *into*, so a corner
                  // in its ramp shows up in exactly the band where the picture
                  // has gone and it is the only thing left.
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      topColor,
                      for (final alpha in _fadeAlpha.reversed)
                        topColor.withValues(alpha: alpha),
                    ],
                    stops: [
                      0.0,
                      for (final stop in _fadeStops) 0.25 + stop * 0.75,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom glow — holds steady, then fades at the very end
          Positioned(
            top: topGlowExtent + (imageHeight * bottomBlurFadeStart),
            left: 0,
            right: 0,
            height:
                (imageHeight * (1 - bottomBlurFadeStart)) + bottomGlowExtent,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      for (final alpha in _fadeAlpha)
                        bottomColor.withValues(alpha: alpha),
                      bottomColor,
                    ],
                    stops: [for (final stop in _fadeStops) stop * 0.75, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // Image — fades/blurs on BOTH top and bottom edges to dissolve into the glow
          Positioned(
            top: topGlowExtent,
            left: 0,
            right: 0,
            height: imageHeight,
            child: ClipRSuperellipse(
              borderRadius: borderRadius,
              child: ShaderMask(
                shaderCallback: _dissolve,
                blendMode: BlendMode.dstIn,
                child: ProgressiveBlurWidget(
                  sigma: blurSigma,
                  // Rebuilt inline each frame, which is fine: LinearGradientBlur
                  // implements == over its lists, and these values don't change
                  // while blurSigma animates — so the blur texture is not
                  // regenerated. Don't make these depend on animated values.
                  linearGradientBlur: LinearGradientBlur(
                    // Eased for the same reason the alpha ramp is, and ending
                    // exactly where the alpha ramp ends rather than a tenth of
                    // the pane later. That overshoot was the real thief: it
                    // meant the top eighty-five points of a picture fitted to
                    // the sharp band were still being progressively blurred,
                    // which is far more of a photograph than any taper takes.
                    values: const [
                      1,
                      0.844,
                      0.5,
                      0.156,
                      0,
                      0,
                      0.156,
                      0.5,
                      0.844,
                      1,
                    ],
                    stops: [
                      for (final stop in _fadeStops) stop * topBlurFadeEnd,
                      for (final stop in _fadeStops)
                        bottomBlurFadeStart + stop * (1 - bottomBlurFadeStart),
                    ],
                    start: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  child: image == null
                      ? _MissingBackdrop(
                          topColor: topColor,
                          bottomColor: bottomColor,
                        )
                      : BackdropPhoto(
                          image: image!,
                          fit: fit,
                          zoom: zoom,
                          offset: offset,
                          bleedSigma: bleedSigma,
                          sharpInsets: EdgeInsets.fromLTRB(
                            0,
                            topBlurFadeEnd,
                            0,
                            1 - bottomBlurFadeStart,
                          ),
                          fallback: _MissingBackdrop(
                            topColor: topColor,
                            bottomColor: bottomColor,
                          ),
                        ),
                ),
              ),
            ),
          ),

          // Noise overlay directly on top of the glow+image zone to prevent banding
          const Positioned.fill(
            child: NoiseOverlay(opacity: 0.035, density: 18),
          ),
        ],
      ),
    );
  }
}

/// Stands in when the stored image path no longer resolves — the file lives in
/// app storage and the path is persisted, so it can outlive what it points at.
/// A gradient in the theme's own colors degrades quietly; an exception here
/// would take the whole Home screen down.
class _MissingBackdrop extends StatelessWidget {
  const _MissingBackdrop({required this.topColor, required this.bottomColor});

  final Color topColor;
  final Color bottomColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, bottomColor],
        ),
      ),
    );
  }
}
