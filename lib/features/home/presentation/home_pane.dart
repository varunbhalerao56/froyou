import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/color_utils.dart';
import 'package:froyou/core/ui/edge_glow_image.dart';
import 'package:froyou/features/home/presentation/compose_box.dart';
import 'package:froyou/features/home/presentation/compose_controller.dart';

/// The Home screen itself: backdrop, quote, and the controls that open compose.
///
/// **Invariant: this pane is always exactly [height] tall.** Opening compose
/// only redistributes space *inside* it — the backdrop gives up exactly the
/// height the compose box takes. Nothing outside the pane relayouts, the
/// scroll extent never changes mid-animation, and so the transition into the
/// logs list below has no seam and the list never jumps.
class HomePane extends StatelessWidget {
  const HomePane({
    required this.height,
    required this.compose,
    required this.palette,
    required this.quote,
    required this.chromeOpacity,
    this.backdrop,
    super.key,
  });

  final double height;
  final ComposeController compose;
  final AppPalette palette;
  final String quote;
  final ImageProvider? backdrop;

  /// Fades the quote and controls as the shell scrolls toward the logs list.
  /// Scoped to just those two small widgets — driving the whole pane off the
  /// scroll position would re-composite the blur shader every frame.
  final ValueListenable<double> chromeOpacity;

  /// Glow above the image, matching the background gradient's start color.
  static const double _topGlow = 50;

  /// Space the compose box and controls need once open.
  static const double _composeReserve = 300;

  @override
  Widget build(BuildContext context) {
    final available = math.max(0.0, height - _topGlow);
    final expandedImage = available * 0.62;
    final collapsedImage = math
        .max(140.0, available - _composeReserve)
        .clamp(0.0, expandedImage);

    return SizedBox(
      height: height,
      child: AnimatedBuilder(
        animation: compose.expandCurve,
        builder: (context, _) {
          final t = compose.expandCurve.value;
          final imageHeight = lerpDouble(expandedImage, collapsedImage, t)!;
          // Fully gone by the halfway point, so the quote is never competing
          // with the compose box for the same space.
          final quoteOpacity =
              1 - Curves.easeOut.transform((t * 2).clamp(0.0, 1.0));

          return Column(
            children: [
              RepaintBoundary(
                child: EdgeGlowImage(
                  image: backdrop,
                  topColor: palette.topEdge,
                  bottomColor: palette.bottomEdge,
                  imageHeight: imageHeight,
                  topGlowExtent: _topGlow,
                  bottomGlowExtent: 0,
                  // Cheaper mid-flight: the two-pass Gaussian is the one real
                  // cost in this animation, and fewer taps per pixel is the
                  // most direct lever on it.
                  blurSigma: lerpDouble(40, 22, t)!,
                ),
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (quoteOpacity > 0.01)
                      _Quote(
                        quote: quote,
                        palette: palette,
                        opacity: quoteOpacity,
                        chromeOpacity: chromeOpacity,
                      ),
                    if (t > 0.01)
                      FadeTransition(
                        opacity: compose.boxReveal,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.15),
                            end: Offset.zero,
                          ).animate(compose.boxReveal),
                          child: Center(child: ComposeBox(compose: compose)),
                        ),
                      ),
                  ],
                ),
              ),
              _Controls(compose: compose, chromeOpacity: chromeOpacity),
            ],
          );
        },
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({
    required this.quote,
    required this.palette,
    required this.opacity,
    required this.chromeOpacity,
  });

  final String quote;
  final AppPalette palette;
  final double opacity;
  final ValueListenable<double> chromeOpacity;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: chromeOpacity,
      builder: (context, scrollOpacity, child) =>
          Opacity(opacity: opacity * scrollOpacity, child: child),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Text(
            quote,
            textAlign: TextAlign.center,
            style: AppTypography.quote.copyWith(
              // Derived from the background it sits on rather than taken from
              // the palette, so it stays legible over the image's own colors.
              color: ensureContrast(palette.bottomEdge),
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.compose, required this.chromeOpacity});

  final ComposeController compose;
  final ValueListenable<double> chromeOpacity;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ValueListenableBuilder<double>(
      valueListenable: chromeOpacity,
      builder: (context, opacity, child) => Opacity(
        opacity: opacity,
        child: IgnorePointer(ignoring: opacity < 0.05, child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg, top: AppSpacing.sm),
        child: AnimatedSwitcher(
          duration: AppDurations.fast,
          child: compose.isOpen
              ? _OpenControls(compose: compose, colors: colors)
              : _IdleControls(compose: compose, colors: colors),
        ),
      ),
    );
  }
}

class _IdleControls extends StatelessWidget {
  const _IdleControls({required this.compose, required this.colors});

  final ComposeController compose;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('idle'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: AppSpacing.md,
      children: [
        IconButton(
          onPressed: compose.openVoice,
          tooltip: 'Record a log',
          icon: Icon(CupertinoIcons.mic, color: colors.textPrimary, size: 28),
        ),
        IconButton(
          onPressed: compose.openText,
          tooltip: 'Write a log',
          icon: Icon(
            CupertinoIcons.textformat,
            color: colors.textPrimary,
            size: 28,
          ),
        ),
      ],
    );
  }
}

class _OpenControls extends StatelessWidget {
  const _OpenControls({required this.compose, required this.colors});

  final ComposeController compose;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('open'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: AppSpacing.md,
      children: [
        TextButton(
          onPressed: compose.isSaving ? null : compose.close,
          child: const Text('Cancel'),
        ),
        if (compose.isRecording)
          _StopRecordingButton(compose: compose, colors: colors)
        else
          FilledButton(
            onPressed: compose.canSave ? compose.save : null,
            child: compose.isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
      ],
    );
  }
}

class _StopRecordingButton extends StatelessWidget {
  const _StopRecordingButton({required this.compose, required this.colors});

  final ComposeController compose;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: compose.stopVoice,
      style: FilledButton.styleFrom(backgroundColor: colors.error),
      icon: const Icon(CupertinoIcons.stop_fill, size: 16),
      label: const Text('Stop'),
    );
  }
}
