import 'package:flutter/material.dart';

import 'theme.dart';

/// Radius and border-radius presets. Used together with [AppShapes] for
/// squircle-rounded surfaces.
class AppRadius {
  AppRadius._();

  static const Radius xs = Radius.circular(AppSpacing.xs);
  static const Radius sm = Radius.circular(AppSpacing.sm);
  static const Radius md = Radius.circular(AppSpacing.md);
  static const Radius lg = Radius.circular(AppSpacing.lg);
  static const Radius xl = Radius.circular(AppSpacing.xl);

  static const BorderRadius xsAll = BorderRadius.all(xs);
  static const BorderRadius smAll = BorderRadius.all(sm);
  static const BorderRadius mdAll = BorderRadius.all(md);
  static const BorderRadius lgAll = BorderRadius.all(lg);
  static const BorderRadius xlAll = BorderRadius.all(xl);

  static const BorderRadius topMd = BorderRadius.vertical(top: md);
  static const BorderRadius bottomMd = BorderRadius.vertical(bottom: md);
}

/// Squircle shape presets using Flutter's built-in [RoundedSuperellipseBorder]
/// (iOS-style continuous rounding). Apply these to [Card], [Container] with
/// [BoxDecoration.borderRadius], or any [ShapeBorder] slot.
class AppShapes {
  AppShapes._();

  static const RoundedSuperellipseBorder xs = RoundedSuperellipseBorder(
    borderRadius: AppRadius.xsAll,
  );
  static const RoundedSuperellipseBorder sm = RoundedSuperellipseBorder(
    borderRadius: AppRadius.smAll,
  );
  static const RoundedSuperellipseBorder md = RoundedSuperellipseBorder(
    borderRadius: AppRadius.mdAll,
  );
  static const RoundedSuperellipseBorder lg = RoundedSuperellipseBorder(
    borderRadius: AppRadius.lgAll,
  );
  static const RoundedSuperellipseBorder xl = RoundedSuperellipseBorder(
    borderRadius: AppRadius.xlAll,
  );
}
