import 'package:flutter/material.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/illustration.dart';

/// One page of the intro: a drawing, a headline, a short body, and optionally
/// a control.
///
/// Scrolls rather than assuming it fits, but stretches to fill the viewport so
/// the pure-text pages centre themselves. The alternative — a fixed Column —
/// starts overflowing at the largest accessibility text sizes, on the screens
/// that are nothing but text.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    required this.title,
    required this.body,
    this.illustration,
    this.child,
    super.key,
  });

  final String title;
  final String body;

  /// The drawing above the headline. Decorative — the headline underneath
  /// always says the thing outright.
  final Illustration? illustration;

  /// A control belonging to this step, e.g. the image manager.
  final Widget? child;

  /// Share of the page the drawing may take at the default text size.
  static const double _artFraction = 0.34;

  /// Below this the drawing is a smudge rather than a picture, and the words
  /// are what matter. Dropping it entirely beats shrinking it to nothing.
  static const double _artFloor = 120;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    // Yields the page to the type as soon as anyone has asked for larger text:
    // at 200% the drawing is already down to a sixth of the screen, and past
    // roughly 250% it gives up its slot altogether.
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight - AppSpacing.xl * 2;
        final artHeight = available * _artFraction / textScale;
        final showArt = illustration != null && artHeight >= _artFloor;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xl,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: available),
            child: Column(
              // Text-only steps sit in the middle of the screen; a step with a
              // control starts at the top so the control has room below it.
              mainAxisAlignment: child == null
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showArt) ...[
                  SizedBox(
                    height: artHeight,
                    child: IllustrationView(illustration: illustration!),
                  ),
                  AppGap.xlV,
                ],
                Text(
                  title,
                  style: AppTypography.title2.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                AppGap.smV,
                Text(
                  body,
                  style: AppTypography.subheadline.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                if (child != null) ...[AppGap.xlV, child!],
              ],
            ),
          ),
        );
      },
    );
  }
}
