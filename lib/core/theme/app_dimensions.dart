import 'package:flutter/material.dart';

/// Standard icon, button, and avatar sizes.
class AppSizes {
  AppSizes._();

  static const double iconXs = 16.0;
  static const double iconSm = 20.0;
  static const double iconMd = 24.0;
  static const double iconLg = 32.0;
  static const double iconXl = 40.0;

  static const double buttonSm = 32.0;
  static const double buttonMd = 40.0;
  static const double buttonLg = 48.0;

  /// Single uniform height for every tappable button in the app (filled,
  /// elevated, outlined, text, and FABs) so they read consistently.
  static const double buttonHeight = 52.0;

  static const double avatarXs = 24.0;
  static const double avatarSm = 32.0;
  static const double avatarMd = 40.0;
  static const double avatarLg = 56.0;
  static const double avatarXl = 80.0;

  // Bottom sticky bar / FAB sizing on phone home view.
  static const double bottomBarHeight = 64.0;
  static const double addButtonSize = 48.0;
}

/// Animation durations.
class AppDurations {
  AppDurations._();

  static const Duration instant = Duration.zero;
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration verySlow = Duration(milliseconds: 800);
}

/// Material elevation levels (matches Material 3 spec).
class AppElevation {
  AppElevation._();

  static const double level0 = 0.0;
  static const double level1 = 1.0;
  static const double level2 = 2.0;
  static const double level3 = 4.0;
  static const double level4 = 6.0;
  static const double level5 = 8.0;
}

/// Shadow presets. Pre-computed to avoid constructing lists at build time.
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> none = [];

  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
}

/// Layout breakpoints — phone / tablet / desktop. The adaptive shell in
/// `lib/core/router` switches between layouts at these widths.
class AppBreakpoints {
  AppBreakpoints._();

  static const double phone = 700.0;
  static const double tablet = 1024.0;

  static bool isPhone(double width) => width < phone;
  static bool isTablet(double width) => width >= phone && width < tablet;
  static bool isDesktop(double width) => width >= tablet;
}
