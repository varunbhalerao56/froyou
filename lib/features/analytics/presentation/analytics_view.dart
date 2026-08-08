import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/analytics/data/analytics_service.dart';

/// What you keep coming back to, over the last week.
class AnalyticsView extends StatelessWidget {
  const AnalyticsView({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppScope.profileOf(context).palette;
    final snapshot = AnalyticsService(
      AppScope.dbOf(context).journalEntryDb,
    ).compute();

    return Scaffold(
      backgroundColor: palette.bottomEdge,
      appBar: AppBar(
        title: const Text('Patterns'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: snapshot.hasEnoughLogs
              ? _Patterns(snapshot: snapshot)
              : _NotEnoughLogs(snapshot: snapshot),
        ),
      ),
    );
  }
}

class _Patterns extends StatelessWidget {
  const _Patterns({required this.snapshot});

  final AnalyticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ListView(
      children: [
        _LogCountTile(count: snapshot.logCount, colors: colors),
        AppGap.xlV,
        if (snapshot.trends.isEmpty)
          _NoThemesYet(count: snapshot.logCount, colors: colors)
        else ...[
          Text(
            'Over the last ${snapshot.windowDays} days',
            style: AppTypography.headline.copyWith(color: colors.textPrimary),
          ),
          AppGap.mdV,
          for (final trend in snapshot.trends)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _TrendRow(trend: trend, colors: colors),
            ),
        ],
      ],
    );
  }
}

class _LogCountTile extends StatelessWidget {
  const _LogCountTile({required this.count, required this.colors});

  final int count;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: AppInsets.lg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count',
              style: AppTypography.largeTitle.copyWith(color: colors.primary),
            ),
            Text(
              count == 1 ? 'log so far' : 'logs so far',
              style: AppTypography.subheadline.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.trend, required this.colors});

  final ThemeTrend trend;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card.withValues(alpha: 0.7),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: AppInsets.md,
        child: Row(
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: AppTypography.body.copyWith(color: colors.textPrimary),
                  children: [
                    const TextSpan(text: 'You talked about '),
                    TextSpan(
                      text: '"${trend.label}"',
                      style: AppTypography.bodyBold.copyWith(
                        color: colors.primary,
                      ),
                    ),
                    TextSpan(text: ' ${_times(trend.occurrences)}'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _times(int count) => switch (count) {
    2 => 'twice',
    _ => '$count times',
  };
}

/// The guaranteed state on the Simulator, where contextual embeddings are
/// unavailable so nothing ever clusters — and the normal state on device for
/// the first day or two. Treated as a real screen, not an edge case.
class _NoThemesYet extends StatelessWidget {
  const _NoThemesYet({required this.count, required this.colors});

  final int count;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No repeating themes yet',
          style: AppTypography.headline.copyWith(color: colors.textPrimary),
        ),
        AppGap.smV,
        Text(
          "You've logged $count times. Themes show up when you come back to "
          'the same thing more than once.',
          style: AppTypography.body.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _NotEnoughLogs extends StatelessWidget {
  const _NotEnoughLogs({required this.snapshot});

  final AnalyticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.chart_bar_alt_fill,
            size: 34,
            color: colors.placeholder,
          ),
          AppGap.mdV,
          Text(
            'No data yet. Please enter more logs',
            textAlign: TextAlign.center,
            style: AppTypography.title3.copyWith(color: colors.textPrimary),
          ),
          AppGap.smV,
          Text(
            snapshot.logsRemaining == 1
                ? '1 more to go.'
                : '${snapshot.logsRemaining} more to go.',
            style: AppTypography.subheadline.copyWith(
              color: colors.textSecondary,
            ),
          ),
          AppGap.lgV,
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Write one now'),
          ),
        ],
      ),
    );
  }
}
