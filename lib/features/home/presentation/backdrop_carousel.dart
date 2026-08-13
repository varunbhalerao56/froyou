import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:froyou/core/ui/breathing_scale.dart';
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
/// The slow breath on the picture is a [BreathingScale], not a transform. The
/// Ken Burns drift that used to sit here was a transform, and it re-rendered
/// the entire [EdgeGlowImage] — two-pass Gaussian included — at full device
/// pixel ratio on every frame the app was idle. Read that widget before
/// reaching for anything simpler-looking here.
class BackdropCarousel extends HookWidget {
  const BackdropCarousel({
    required this.backdrops,
    required this.providerFor,
    required this.rotation,
    required this.glowColor,
    required this.imageHeight,
    required this.blurSigma,
    this.breathe = true,
    super.key,
  });

  final List<Backdrop> backdrops;
  final ImageProvider Function(Backdrop) providerFor;
  final BackdropRotation rotation;
  final Color glowColor;
  final double imageHeight;
  final double blurSigma;

  /// Off for goldens and for anything that needs a settled frame — the breath
  /// never finishes, so there isn't one otherwise.
  final bool breathe;

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
              // at zero and cost nothing to composite — and, because a
              // zero-opacity subtree is never painted, are never rasterized by
              // the breath either.
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: i == rotation.index ? 1 : 0,
                  duration: _fade,
                  curve: Curves.easeInOut,
                  child: RepaintBoundary(
                    child: _Breathing(
                      // The raster the breath animates is taken once, so it
                      // must not be taken while the photo is still a
                      // placeholder waiting on its decode.
                      image: providerFor(backdrops[i]),
                      enabled: breathe,
                      child: EdgeGlowImage(
                        image: providerFor(backdrops[i]),
                        fit: backdrops[i].framing.baseFit,
                        zoom: backdrops[i].framing.zoom,
                        offset: backdrops[i].framing.offset,
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
              ),
          ],
        ),
      ),
    );
  }
}

/// [BreathingScale], held back until the picture it is about to rasterize is
/// the picture that will be there.
///
/// A snapshot is taken once and is not invalidated when the child repaints on
/// its own, and an image decode is exactly that kind of repaint: enable the
/// breath a frame too early and the backdrop is a placeholder gradient,
/// breathing, for as long as Home is up. Resolving the same provider a second
/// time costs nothing — the stream is the provider's own, already open.
class _Breathing extends StatefulWidget {
  const _Breathing({
    required this.image,
    required this.enabled,
    required this.child,
  });

  final ImageProvider image;
  final bool enabled;
  final Widget child;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing> {
  ImageStream? _stream;
  bool _ready = false;

  late final ImageStreamListener _listener = ImageStreamListener(
    _onFrame,
    // A path that no longer resolves simply never breathes.
    onError: (_, _) {},
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_Breathing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _ready = false;
      _resolve();
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
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
    // Handed over, so ours to release: every listener gets its own clone.
    info.dispose();
    if (_ready) return;
    // Both callers resolve from a lifecycle method that build follows, so a
    // cache hit — which answers inline — needs no rebuild scheduling.
    if (synchronous) {
      _ready = true;
    } else if (mounted) {
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) =>
      BreathingScale(enabled: widget.enabled && _ready, child: widget.child);
}
