import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/analytics/presentation/analytics_view.dart';
import 'package:froyou/features/journal/presentation/search_view.dart';
import 'package:froyou/features/profile/presentation/settings_view.dart';

/// The bar that divides Home from the logs list.
///
/// Pinned rather than floating, so it scrolls up behind the Home pane and then
/// stays put once the list starts — which is what tells you you've crossed from
/// "now" into "before". Also the entry point for Analytics and Settings.
class LogsBarDelegate extends SliverPersistentHeaderDelegate {
  const LogsBarDelegate({
    required this.background,
    required this.foreground,
    required this.count,
    required this.topPadding,
    required this.onCompose,
  });

  final Color background;
  final Color foreground;
  final int count;

  /// Status-bar inset. Folded into the extent so that, once pinned, the bar's
  /// content sits below the status bar rather than under it.
  final double topPadding;

  final VoidCallback onCompose;

  static const double _barHeight = 56;

  @override
  double get minExtent => _barHeight + topPadding;

  @override
  double get maxExtent => _barHeight + topPadding;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Deliberately one flat blur and one flat wash, both edge to edge.
    //
    // A soft top edge was tried twice, to dissolve the line this cuts across
    // the photo behind it, and it can't be had: a `BackdropFilter` is clipped
    // to a rectangle, so feathering it means several of them, and several of
    // them is a render-pass break each on a header that is pinned throughout
    // a scroll. Ramping only the wash is cheap but reaches the same dead end
    // from the other side — this delegate cannot tell whether it is halfway
    // down the photo or pinned over the status bar, because `overlapsContent`
    // is `constraints.overlap > 0` (an earlier sliver obstructing it, which
    // nothing here does) and `shrinkOffset` is clamped to
    // `maxExtent - minExtent`, which is zero. So a top edge soft enough to
    // dissolve into the photo is also soft enough to let a log card show
    // through beside the clock.
    //
    // The line it was chasing came from the backdrop's Ken Burns zoom
    // dragging live photo past the point the dissolve had finished — fixed at
    // the source, in `EdgeGlowImage`'s drift margins.
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        // No dividing rule: the whole point of the shell is that Home and the
        // logs are one continuous surface, and a hairline across it reads as
        // a seam.
        child: DecoratedBox(
          decoration: BoxDecoration(color: background.withValues(alpha: 0.82)),
          child: Padding(
            padding: EdgeInsets.only(
              top: topPadding,
              left: AppSpacing.md,
              right: AppSpacing.xs,
            ),
            child: SizedBox(
              height: _barHeight,
              child: Row(
                children: [
                  Text(
                    count == 0 ? 'Your logs' : 'Your logs · $count',
                    style: AppTypography.headline.copyWith(color: foreground),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'New log',
                    onPressed: onCompose,
                    icon: Icon(CupertinoIcons.add, color: foreground, size: 22),
                  ),
                  IconButton(
                    tooltip: 'Search',
                    onPressed: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => const SearchView(),
                      ),
                    ),
                    icon: Icon(
                      CupertinoIcons.search,
                      color: foreground,
                      size: 22,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Analytics',
                    onPressed: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => const AnalyticsView(),
                      ),
                    ),
                    icon: Icon(
                      CupertinoIcons.chart_bar_alt_fill,
                      color: foreground,
                      size: 22,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => const SettingsView(),
                      ),
                    ),
                    icon: Icon(
                      CupertinoIcons.settings,
                      color: foreground,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Compares every field that affects what this paints. Returning a blanket
  /// `false` here is the classic delegate bug — the bar would keep the old
  /// theme's colors and a stale count forever.
  @override
  bool shouldRebuild(LogsBarDelegate oldDelegate) {
    return oldDelegate.background != background ||
        oldDelegate.foreground != foreground ||
        oldDelegate.count != count ||
        oldDelegate.topPadding != topPadding ||
        oldDelegate.onCompose != onCompose;
  }
}
