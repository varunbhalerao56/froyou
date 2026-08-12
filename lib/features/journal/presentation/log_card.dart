import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/journal/journal.dart';
import 'package:intl/intl.dart';

/// One past log in the list.
///
/// Shows the words first and everything derived second — the entry is the
/// user's, the keywords and mood are the app's guesses about it.
class LogCard extends StatelessWidget {
  const LogCard({
    required this.entry,
    required this.onDelete,
    this.isEnriching = false,
    super.key,
  });

  final JournalEntry entry;
  final Future<void> Function() onDelete;

  /// True while sentence embedding and clustering are still running for this
  /// entry — only ever the newest one.
  final bool isEnriching;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final text = entry.rawText ?? '';

    return Dismissible(
      key: ValueKey('entry-${entry.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete(),
      background: _DeleteBackground(color: colors.error),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        // No border. A soft wash plus a low, wide shadow is enough to separate
        // one entry from the next and to lift it off the moving background;
        // an outline turns a quiet list of your own thoughts into a form.
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.card.withValues(alpha: 0.72),
            borderRadius: AppRadius.mdAll,
            // Tight and close. A wide soft shadow reaches into the next card's
            // gap, and once every gap is filled the list reads as banded
            // rather than as a stack of separate things.
            boxShadow: [
              // BoxShadow(
              //   color: colors.cardShadow,
              //   blurRadius: 10,
              //   offset: const Offset(0, 3),
              // ),
            ],
          ),
          child: Padding(
            padding: AppInsets.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _formatDate(entry.createdAt),
                      style: AppTypography.footnote.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    if (isEnriching)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: colors.textSecondary,
                        ),
                      )
                    else if (entry.moodScore != null)
                      _MoodDot(score: entry.moodScore!, colors: colors),
                  ],
                ),
                AppGap.smV,
                Text(
                  text,
                  style: AppTypography.logBody.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                if (entry.keywords != null && entry.keywords!.isNotEmpty) ...[
                  AppGap.smV,
                  Text(
                    entry.keywords!,
                    style: AppTypography.footnote.copyWith(
                      color: colors.placeholder,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this log?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: context.appColors.error),
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final difference = today.difference(day).inDays;

    final time = DateFormat.jm().format(date);
    if (difference == 0) return 'Today, $time';
    if (difference == 1) return 'Yesterday, $time';
    if (difference < 7) return '${DateFormat.EEEE().format(date)}, $time';
    return DateFormat.MMMd().format(date);
  }
}

/// Sentiment as a single dot. Deliberately not a label — the app tags mood to
/// help the user notice patterns, not to tell them how they felt.
class _MoodDot extends StatelessWidget {
  const _MoodDot({required this.score, required this.colors});

  final double score;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (score > 0.15) {
      color = colors.success;
    } else if (score < -0.15) {
      color = colors.error;
    } else {
      color = colors.placeholder;
    }

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.7),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: AppRadius.mdAll,
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Icon(CupertinoIcons.delete, color: color),
          ),
        ),
      ),
    );
  }
}
