import 'package:flutter/widgets.dart';

/// Spacing scale used throughout the app. Values match the legacy `UISpacing`
/// to keep visual rhythm consistent through the rebuild.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 28.0;
  static const double xxl = 40.0;

  static const double screenHorizontal = 24.0;
  static const double screenVertical = 16.0;
}

/// Pre-built [SizedBox] spacers for common gaps. Use these over inline
/// [SizedBox] for consistency.
class AppGap {
  AppGap._();

  static const Widget xsV = SizedBox(height: AppSpacing.xs);
  static const Widget smV = SizedBox(height: AppSpacing.sm);
  static const Widget mdV = SizedBox(height: AppSpacing.md);
  static const Widget lgV = SizedBox(height: AppSpacing.lg);
  static const Widget xlV = SizedBox(height: AppSpacing.xl);
  static const Widget xxlV = SizedBox(height: AppSpacing.xxl);

  static const Widget xsH = SizedBox(width: AppSpacing.xs);
  static const Widget smH = SizedBox(width: AppSpacing.sm);
  static const Widget mdH = SizedBox(width: AppSpacing.md);
  static const Widget lgH = SizedBox(width: AppSpacing.lg);
  static const Widget xlH = SizedBox(width: AppSpacing.xl);
}

/// Padding presets. Prefer these over inline [EdgeInsets] for layout
/// consistency.
class AppInsets {
  AppInsets._();

  static const EdgeInsets xs = EdgeInsets.all(AppSpacing.xs);
  static const EdgeInsets sm = EdgeInsets.all(AppSpacing.sm);
  static const EdgeInsets md = EdgeInsets.all(AppSpacing.md);
  static const EdgeInsets lg = EdgeInsets.all(AppSpacing.lg);
  static const EdgeInsets xl = EdgeInsets.all(AppSpacing.xl);

  static const EdgeInsets horizontalMd = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
  );
  static const EdgeInsets verticalMd = EdgeInsets.symmetric(
    vertical: AppSpacing.md,
  );
  static const EdgeInsets screen = EdgeInsets.symmetric(
    horizontal: AppSpacing.screenHorizontal,
    vertical: AppSpacing.screenVertical,
  );
}
