import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:froyou/core/ui/edge_glow_image.dart';
import 'package:froyou/features/profile/data/backdrop.dart';

/// Which backdrop is showing, and how it got there.
///
/// The index is lifted out of the carousel because the caption above the image
/// has to change with it. One source of truth beats a callback that the caption
/// then has to mirror.
class BackdropRotation {
  const BackdropRotation({
    required this.index,
    required this.count,
    required this.next,
    required this.previous,
  });

  final int index;
  final int count;
  final VoidCallback next;
  final VoidCallback previous;

  bool get hasMultiple => count > 1;
}

/// Advances through the backdrops on a timer, pausing while [paused].
///
/// Interacting resets the clock rather than merely deferring it — otherwise a
/// deliberate swipe can be overridden a moment later by an auto-advance that
/// was already most of the way through its interval.
BackdropRotation useBackdropRotation({
  required int count,
  required bool paused,
  Duration interval = const Duration(seconds: 7),
}) {
  final index = useState(0);
  final restartToken = useState(0);

  // Clamp when images are removed, so the index can't dangle past the end.
  if (count > 0 && index.value >= count) index.value = 0;

  useEffect(() {
    if (paused || count < 2) return null;
    final timer = Timer.periodic(interval, (_) {
      index.value = (index.value + 1) % count;
    });
    return timer.cancel;
  }, [paused, count, interval, restartToken.value]);

  void step(int delta) {
    if (count == 0) return;
    index.value = (index.value + delta) % count;
    if (index.value < 0) index.value += count;
    restartToken.value++;
  }

  return BackdropRotation(
    index: count == 0 ? 0 : index.value.clamp(0, count - 1),
    count: count,
    next: () => step(1),
    previous: () => step(-1),
  );
}

/// The Home backdrop: images crossfading into each other.
///
/// A cross-faded [Stack] rather than a [PageView]. A page view slides, and a
/// slide reads as "next item in a list" — wrong for something meant to sit
/// quietly behind a journal. Swiping still works; it just resolves as a fade.
///
/// Nothing moves between crossfades, and that is a fix rather than an
/// omission. A slow Ken Burns transform used to sit here, and because its
/// scale changed every frame the raster cache could never hold the layer
/// steady long enough to reuse it — so the whole [EdgeGlowImage], two-pass
/// Gaussian and all, was re-rendered at full device pixel ratio on every
/// frame the app was idle. It also resampled the photo each frame, which is
/// what made fine detail shimmer.
class BackdropCarousel extends HookWidget {
  const BackdropCarousel({
    required this.backdrops,
    required this.providerFor,
    required this.rotation,
    required this.glowColor,
    required this.imageHeight,
    required this.blurSigma,
    super.key,
  });

  final List<Backdrop> backdrops;
  final ImageProvider Function(Backdrop) providerFor;
  final BackdropRotation rotation;
  final Color glowColor;
  final double imageHeight;
  final double blurSigma;

  static const Duration _fade = Duration(milliseconds: 1200);

  @override
  Widget build(BuildContext context) {
    if (backdrops.isEmpty) {
      return EdgeGlowImage(
        image: null,
        topColor: glowColor,
        bottomColor: glowColor,
        imageHeight: imageHeight,
        topGlowExtent: 0,
        bottomGlowExtent: 0,
        blurSigma: blurSigma,
      );
    }

    return GestureDetector(
      // Velocity rather than distance: the images don't track the finger, so a
      // flick is the honest gesture to read.
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 120 || !rotation.hasMultiple) return;
        velocity < 0 ? rotation.next() : rotation.previous();
      },
      child: SizedBox(
        height: imageHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < backdrops.length; i++)
              // Only the active image is painted at full opacity; the rest sit
              // at zero and cost nothing to composite.
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: i == rotation.index ? 1 : 0,
                  duration: _fade,
                  curve: Curves.easeInOut,
                  child: RepaintBoundary(
                    child: EdgeGlowImage(
                      image: providerFor(backdrops[i]),
                      fit: backdrops[i].fit == BackdropFit.whole
                          ? BoxFit.contain
                          : BoxFit.cover,
                      focusY: backdrops[i].focusY,
                      topColor: glowColor,
                      bottomColor: glowColor,
                      imageHeight: imageHeight,
                      topGlowExtent: 0,
                      bottomGlowExtent: 0,
                      blurSigma: blurSigma,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
