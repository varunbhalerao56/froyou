import 'package:flutter/material.dart';
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
    // Roughly a fifth of the image at each end. Shorter than this and the
    // dissolve reads as an edge you can point at rather than as the photo
    // emerging from the page.
    this.topBlurFadeEnd = 0.22,
    this.bottomBlurFadeStart = 0.74,
    this.blurSigma = 40.0,
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

  /// End of the image's blur/fade zone at the TOP, as a fraction of height.
  final double topBlurFadeEnd;

  /// Start of the image's blur/fade zone at the BOTTOM, as a fraction of height.
  final double bottomBlurFadeStart;

  /// Dropped mid-animation to cut the shader's per-frame cost, then restored
  /// at rest. The two-pass Gaussian runs a synchronous `toImageSync` at full
  /// device pixel ratio every frame, so fewer taps per pixel is real money.
  final double blurSigma;

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
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [topColor, topColor, topColor.withValues(alpha: 0)],
                    stops: const [0.0, 0.35, 1.0],
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
                      bottomColor.withValues(alpha: 0),
                      bottomColor,
                      bottomColor,
                    ],
                    stops: const [0.0, 0.4, 1.0],
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
                shaderCallback: (rect) {
                  // The mid stop sits a little past halfway and holds back the
                  // opacity, so the image eases in rather than arriving at
                  // most of full strength in the first few pixels.
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: const [
                      Colors.transparent,
                      Colors.white38,
                      Colors.white,
                      Colors.white,
                      Colors.white38,
                      Colors.transparent,
                    ],
                    stops: [
                      0.0,
                      topBlurFadeEnd * 0.55,
                      topBlurFadeEnd,
                      bottomBlurFadeStart,
                      bottomBlurFadeStart + (1 - bottomBlurFadeStart) * 0.55,
                      1.0,
                    ],
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstIn,
                child: ProgressiveBlurWidget(
                  sigma: blurSigma,
                  // Rebuilt inline each frame, which is fine: LinearGradientBlur
                  // implements == over its lists, and these values don't change
                  // while blurSigma animates — so the blur texture is not
                  // regenerated. Don't make these depend on animated values.
                  linearGradientBlur: LinearGradientBlur(
                    values: const [1, 0, 0, 1],
                    stops: [
                      0.0,
                      topBlurFadeEnd + 0.1,
                      bottomBlurFadeStart - 0.15,
                      1.0,
                    ],
                    start: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  child: image == null
                      ? _MissingBackdrop(
                          topColor: topColor,
                          bottomColor: bottomColor,
                        )
                      : Image(
                          image: image!,
                          fit: BoxFit.cover,
                          // Without this, swapping the backdrop in Settings
                          // shows a blank frame while the new provider decodes.
                          gaplessPlayback: true,
                          errorBuilder: (context, error, stackTrace) =>
                              _MissingBackdrop(
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
