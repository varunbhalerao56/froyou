import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/home/presentation/backdrop_carousel.dart';
import 'package:froyou/features/home/presentation/compose_box.dart';
import 'package:froyou/features/home/presentation/compose_controller.dart';
import 'package:froyou/features/home/presentation/home_layout.dart';
import 'package:froyou/features/profile/data/backdrop.dart';

/// The Home screen itself: caption, backdrop, prompt, and the controls that
/// open compose.
///
/// **Invariant: this pane is always exactly [height] tall.** Opening compose
/// only redistributes space *inside* it. Nothing outside the pane relayouts,
/// the scroll extent never changes mid-animation, and so the transition into
/// the logs list below has no seam and the list never jumps.
///
/// Reading order is caption → image → prompt: the words you chose sit above
/// the picture, and the question sits directly above the controls that answer
/// it.
class HomePane extends StatelessWidget {
  const HomePane({
    required this.height,
    required this.compose,
    required this.palette,
    required this.backdrops,
    required this.providerFor,
    required this.rotation,
    required this.prompt,
    required this.chromeOpacity,
    this.layout = HomeLayout.fullBleed,
    this.breathe = true,
    super.key,
  });

  final double height;
  final ComposeController compose;
  final AppPalette palette;
  final List<Backdrop> backdrops;
  final ImageProvider Function(Backdrop) providerFor;
  final BackdropRotation rotation;

  /// What sits under the image — the default "How are you feeling?", or a
  /// follow-up question when there's one pending.
  final String prompt;

  /// Fades the chrome as the shell scrolls toward the logs list. Scoped to the
  /// small widgets only — driving the whole pane off the scroll position would
  /// re-composite the blur shader every frame.
  final ValueListenable<double> chromeOpacity;

  /// How the chrome is arranged. Defaulted to what ships, so a call site that
  /// doesn't care gets the same thing the app does.
  final HomeLayout layout;

  /// The backdrop's slow scale. Off in goldens: it never reaches a resting
  /// frame, and a golden is a resting frame.
  final bool breathe;

  static const double _captionHeight = 76;

  /// How long a follow-up may run before it is cut short. A generated question
  /// is longer than "How are you feeling?" and a good one often carries a
  /// clause that a two-line ellipsis takes the point out of.
  static const int promptMaxLines = 3;

  /// Two lines of [AppTypography.prompt] with a little air — the floor rather
  /// than the figure. A question that needs a third line takes one (see
  /// [_reservedFor]); one that fits in two changes nothing, which is what
  /// keeps a short prompt from costing the photograph thirty points it was
  /// never going to use.
  static const double _promptHeight = 68;

  /// Room the controls row needs at the bottom of the pane.
  static const double _controlsHeight = 96;

  /// [HomeLayout.typeFirst] gives the prompt the top of the screen, so it is
  /// set larger and needs more room than it does under the image.
  static const double _leadPromptHeight = 92;

  /// What the prompt's slot has to be to hold [prompt] whole, never less than
  /// [floor].
  ///
  /// Measured rather than assumed: the slot is a fixed height that the pane's
  /// invariant is built on, so the only way to let a question run to three
  /// lines *sometimes* is to ask how many lines this particular question takes.
  /// Deliberately computed outside the compose animation — it depends on the
  /// text, the style and the width, and none of those move while the chrome
  /// collapses.
  double _reservedFor(BuildContext context, TextStyle style, double floor) {
    final width = MediaQuery.sizeOf(context).width - AppSpacing.lg * 2;
    if (width <= 0) return floor;

    final painter = TextPainter(
      text: TextSpan(text: prompt, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: promptMaxLines,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final height = painter.height;
    // Read before disposing, and read off the painter rather than multiplied
    // out of the style: this one already has the text scaler in it.
    final line = painter.preferredLineHeight;
    painter.dispose();

    // Whatever air the two-line figure was carrying, kept for a third line.
    return math.max(floor, height + floor - line * 2);
  }

  /// The strip of image [HomeLayout.typeFirst] keeps at the bottom.
  static const double _stripHeight = 140;

  @override
  Widget build(BuildContext context) {
    // The shell deliberately isn't inside a SafeArea — the surface has to run
    // edge to edge behind the status bar. So the pane insets its own content
    // instead; without this the caption and the compose field slide under the
    // clock and the dynamic island.
    final topInset = MediaQuery.paddingOf(context).top;

    // Once per build of the pane, not once per frame of the compose animation:
    // laying out a line of text sixty times a second to learn something that
    // cannot have changed is the sort of thing that only shows up on a device.
    final promptHeight = _reservedFor(
      context,
      AppTypography.prompt,
      _promptHeight,
    );
    final leadPromptHeight = _reservedFor(
      context,
      AppTypography.quote,
      _leadPromptHeight,
    );

    return SizedBox(
      height: height,
      child: AnimatedBuilder(
        animation: compose.expandCurve,
        builder: (context, _) {
          final t = compose.expandCurve.value;

          // Everything above the compose field gives up *all* of its height,
          // not just some: the ask was for the text to have room to breathe,
          // and a half-collapsed photo still competes with it.
          final available = math.max(0.0, height - _controlsHeight - topInset);

          // The one number every variant is held to. Whatever a layout puts
          // inside it, the chrome occupies exactly this much — so the pane
          // cannot change total height and the invariant holds by
          // construction rather than by each variant getting the sum right.
          final chromeHeight = lerpDouble(available, 0, t)!;

          // Chrome is gone well before the compose box arrives at 0.35, so the
          // two never overlap in the same space.
          final chromeOut = (1 - t * 1.6).clamp(0.0, 1.0);

          final column = Column(
            children: [
              SizedBox(height: topInset),
              ..._chrome(
                t: t,
                chromeHeight: chromeHeight,
                chromeOut: chromeOut,
                promptExtent: promptHeight,
                leadPromptExtent: leadPromptHeight,
              ),
              Expanded(
                child: t <= 0.01
                    ? const SizedBox.expand()
                    // The chrome above vacates over the same 320ms that this
                    // arrives, so for the first few frames there is less room
                    // here than the field needs. OverflowBox lets it lay out at
                    // its natural height regardless and ClipRect hides the
                    // excess — without them the transition spends its opening
                    // frames as a RenderFlex overflow.
                    : ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.center,
                          minHeight: 0,
                          // Finite rather than infinite: an unbounded height
                          // leaves the child's centre undefined, which parks it
                          // at the top instead of the middle. This is simply
                          // more than the field can ever need.
                          maxHeight: 640,
                          child: FadeTransition(
                            opacity: compose.boxReveal,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.12),
                                end: Offset.zero,
                              ).animate(compose.boxReveal),
                              child: ComposeBox(compose: compose),
                            ),
                          ),
                        ),
                      ),
              ),
              _Controls(compose: compose, chromeOpacity: chromeOpacity),
            ],
          );

          if (layout != HomeLayout.fullBleed) return column;

          // The only variant that needs a layer behind the whole pane. Note
          // the image is drawn at the *full* pane height here, so the two-pass
          // Gaussian is doing meaningfully more work than in the other
          // variants — which is exactly the sort of thing the live gallery
          // exists to let you feel on a device.
          //
          // The photo layer empties out; the [Stack] around it does not go
          // away, and the three children keep their count and their order
          // whatever happens. That is load-bearing. Returning the bare column
          // once the chrome has finished collapsing swaps the pane's root
          // widget mid-open, which re-parents everything beneath it — and
          // everything includes the compose field. Its [EditableText] gets
          // disposed and rebuilt, the platform input connection goes with it,
          // and the keyboard slides back down about 280ms in, just as it
          // finishes arriving. Holding the slots fixed keeps the column's
          // element, and the field's, alive across the whole animation.
          final hasChrome = chromeHeight > 1;

          return Stack(
            children: [
              Positioned.fill(
                child: hasChrome
                    ? Opacity(
                        opacity: chromeOut,
                        child: RepaintBoundary(
                          child: BackdropCarousel(
                            backdrops: backdrops,
                            providerFor: providerFor,
                            rotation: rotation,
                            glowColor: palette.glow,
                            imageHeight: height,
                            blurSigma: lerpDouble(40, 22, t)!,
                            breathe: breathe,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Positioned.fill(
                child: hasChrome
                    ? IgnorePointer(
                        child: Opacity(
                          opacity: chromeOut,
                          // Both ends: the caption sits at the very top of the
                          // photo here, and the bottom runs straight into the
                          // opaque logs bar with nothing between them.
                          child: _Scrim(
                            palette: palette,
                            topAlpha: 0.82,
                            bottomAlpha: 1,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              column,
            ],
          );
        },
      ),
    );
  }

  /// The chrome, as children spliced straight into the pane's column.
  ///
  /// A list rather than one widget so [HomeLayout.classic] can keep emitting
  /// the three separately-sized boxes it always has — the goldens pin that
  /// arrangement to the pixel, and nesting it a level deeper to be tidy would
  /// be paying for symmetry with the one thing that must not move.
  List<Widget> _chrome({
    required double t,
    required double chromeHeight,
    required double chromeOut,
    required double promptExtent,
    required double leadPromptExtent,
  }) {
    if (chromeOut <= 0.01) return [SizedBox(height: chromeHeight)];

    final captionHeight = lerpDouble(_captionHeight, 0, t)!;
    final promptHeight = lerpDouble(promptExtent, 0, t)!;

    Widget caption() => _Caption(
      backdrops: backdrops,
      rotation: rotation,
      palette: palette,
      chromeOpacity: chromeOpacity,
    );

    Widget promptLine([TextStyle? style]) => _Prompt(
      prompt: prompt,
      palette: palette,
      chromeOpacity: chromeOpacity,
      style: style,
    );

    Widget carousel(double imageHeight) => RepaintBoundary(
      child: BackdropCarousel(
        backdrops: backdrops,
        providerFor: providerFor,
        rotation: rotation,
        glowColor: palette.glow,
        imageHeight: imageHeight,
        // Cheaper mid-flight: the two-pass Gaussian is the one real cost
        // here, and fewer taps per pixel is the most direct lever on it.
        blurSigma: lerpDouble(40, 22, t)!,
        breathe: breathe,
      ),
    );

    switch (layout) {
      case HomeLayout.classic:
        final imageHeight = math.max(
          0.0,
          chromeHeight - captionHeight - promptHeight,
        );
        return [
          SizedBox(
            height: captionHeight,
            child: Opacity(opacity: chromeOut, child: caption()),
          ),
          if (imageHeight > 1)
            Opacity(opacity: chromeOut, child: carousel(imageHeight)),
          SizedBox(
            height: promptHeight,
            child: Opacity(opacity: chromeOut, child: promptLine()),
          ),
        ];

      case HomeLayout.captionOverImage:
        return [
          SizedBox(
            height: chromeHeight,
            child: Opacity(
              opacity: chromeOut,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  carousel(chromeHeight),
                  Positioned.fill(
                    child: IgnorePointer(child: _Scrim(palette: palette)),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: captionHeight, child: caption()),
                        SizedBox(height: promptHeight, child: promptLine()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ];

      case HomeLayout.fullBleed:
        // The image is a layer behind the whole pane, so the chrome box holds
        // only the words: the caption at the top and the question down by the
        // controls that answer it, each over its own end of the scrim.
        return [
          SizedBox(
            height: chromeHeight,
            child: Opacity(
              opacity: chromeOut,
              child: Column(
                children: [
                  SizedBox(height: captionHeight, child: caption()),
                  const Spacer(),
                  SizedBox(height: promptHeight, child: promptLine()),
                ],
              ),
            ),
          ),
        ];

      case HomeLayout.centred:
        return [
          SizedBox(
            height: chromeHeight,
            child: Opacity(
              opacity: chromeOut,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: captionHeight, child: caption()),
                  SizedBox(height: promptHeight, child: promptLine()),
                ],
              ),
            ),
          ),
        ];

      case HomeLayout.typeFirst:
        final leadHeight = lerpDouble(leadPromptExtent, 0, t)!;
        final stripHeight = math.min(
          lerpDouble(_stripHeight, 0, t)!,
          math.max(0.0, chromeHeight - leadHeight),
        );
        return [
          SizedBox(
            height: chromeHeight,
            child: Opacity(
              opacity: chromeOut,
              child: Column(
                children: [
                  SizedBox(
                    height: leadHeight,
                    // The hero style, because here the question *is* the top of
                    // the screen. Anything smaller would now be below the size
                    // the prompt already runs at in every other layout.
                    child: promptLine(AppTypography.quote),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: compose.openText,
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                          ),
                          child: Text(
                            "What's on your mind?",
                            textAlign: TextAlign.center,
                            style: AppTypography.composeInput.copyWith(
                              color: palette.colors.placeholder,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (stripHeight > 1) carousel(stripHeight),
                ],
              ),
            ),
          ),
        ];
    }
  }
}

/// Fades an image into the theme so words can sit on it.
///
/// Its own widget rather than an inline gradient because two variants overlay
/// text on the backdrop and they must dissolve into the same colour.
class _Scrim extends StatelessWidget {
  const _Scrim({
    required this.palette,
    this.topAlpha = 0,
    this.bottomAlpha = 0.88,
  });

  final AppPalette palette;

  /// Legibility for a caption sitting at the very top of the image.
  final double topAlpha;

  /// How completely the image is gone by the bottom edge. [HomeLayout.fullBleed]
  /// takes this to 1: the pane ends against the opaque logs bar, so anything
  /// short of the full background colour leaves a hard line across the seam.
  final double bottomAlpha;

  /// A smoothstep, sampled. This gradient used to be four stops — a straight
  /// line down to nothing and then a corner where it flattened — and over a
  /// bright sky that corner was a hard line straight across the screen at 30%.
  /// A ramp has to arrive at its ends with no slope or the eye finds where it
  /// stopped.
  static const List<double> _ease = [1, 0.844, 0.5, 0.156, 0];

  @override
  Widget build(BuildContext context) {
    final background = palette.colors.background;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            for (final t in _ease) background.withValues(alpha: topAlpha * t),
            for (final t in _ease.reversed)
              background.withValues(alpha: bottomAlpha * t),
          ],
          stops: [
            for (var i = 0; i < _ease.length; i++) 0.3 * i / 4,
            for (var i = 0; i < _ease.length; i++) 0.5 + 0.5 * i / 4,
          ],
        ),
      ),
    );
  }
}

/// The caption for the image currently showing, crossfading with it.
class _Caption extends StatelessWidget {
  const _Caption({
    required this.backdrops,
    required this.rotation,
    required this.palette,
    required this.chromeOpacity,
  });

  final List<Backdrop> backdrops;
  final BackdropRotation rotation;
  final AppPalette palette;
  final ValueListenable<double> chromeOpacity;

  @override
  Widget build(BuildContext context) {
    final caption = backdrops.isEmpty
        ? null
        : backdrops[rotation.index.clamp(0, backdrops.length - 1)].caption;

    return ValueListenableBuilder<double>(
      valueListenable: chromeOpacity,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Center(
          child: AnimatedSwitcher(
            // Matched to the image crossfade so the words and the picture
            // change as one thing.
            duration: const Duration(milliseconds: 1200),
            child: (caption == null || caption.trim().isEmpty)
                ? const SizedBox.shrink()
                : Text(
                    caption,
                    key: ValueKey(caption),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.quote.copyWith(
                      color: palette.colors.textPrimary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The line under the image. Not a button — the mic and keyboard below it are
/// how you answer.
class _Prompt extends StatelessWidget {
  const _Prompt({
    required this.prompt,
    required this.palette,
    required this.chromeOpacity,
    this.style,
  });

  final String prompt;
  final AppPalette palette;
  final ValueListenable<double> chromeOpacity;

  /// Overridden only by [HomeLayout.typeFirst], where the prompt leads the
  /// screen instead of sitting under the picture.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: chromeOpacity,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Center(
          child: AnimatedSwitcher(
            duration: AppDurations.slow,
            child: Text(
              prompt,
              key: ValueKey(prompt),
              textAlign: TextAlign.center,
              maxLines: HomePane.promptMaxLines,
              overflow: TextOverflow.ellipsis,
              style: (style ?? AppTypography.prompt).copyWith(
                color: palette.colors.textSecondary,
              ),
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
        padding: const EdgeInsets.only(
          bottom: AppSpacing.lg,
          top: AppSpacing.sm,
        ),
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
          FilledButton.icon(
            onPressed: compose.stopVoice,
            style: FilledButton.styleFrom(backgroundColor: colors.error),
            icon: const Icon(CupertinoIcons.stop_fill, size: 16),
            label: const Text('Stop'),
          )
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
