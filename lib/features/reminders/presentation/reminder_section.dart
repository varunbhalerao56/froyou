import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/reminders/data/reminder_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// The reminders section of Settings: on or off, and when.
///
/// Same rule as the theme editor — no stock Material switch, because one would
/// read as somebody else's UI dropped into this app. The on/off control is the
/// two-cell twin of the appearance pills, and the time picker is Cupertino's,
/// themed to the palette rather than left in its own colours.
///
/// Subscribes to [ReminderService] here rather than through the app scope's
/// notifier, so toggling a reminder repaints this section and nothing else.
class ReminderSection extends HookWidget {
  const ReminderSection({required this.reminders, super.key});

  final ReminderService reminders;

  @override
  Widget build(BuildContext context) {
    useListenable(reminders);
    final colors = context.appColors;
    final settings = reminders.settings;

    if (!reminders.isReady) {
      // Without the device's time zone a reminder would fire at the right
      // number in the wrong zone. Saying so beats scheduling a lie.
      return Text(
        'Reminders are unavailable — Froyou could not read this device’s time '
        'zone.',
        style: AppTypography.footnote.copyWith(color: colors.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Pills(
          enabled: settings.enabled,
          colors: colors,
          onChanged: reminders.setEnabled,
        ),
        if (reminders.permissionDenied) ...[
          AppGap.smV,
          Row(
            children: [
              Expanded(
                child: Text(
                  'Notifications are off for Froyou.',
                  style: AppTypography.footnote.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse('app-settings:')),
                child: const Text('Settings'),
              ),
            ],
          ),
        ],
        if (settings.enabled) ...[
          AppGap.lgV,
          _TimeRow(reminders: reminders, colors: colors),
          AppGap.smV,
          Text(
            'One a day. Froyou writes the line from what you’ve been coming '
            'back to, on this device.',
            style: AppTypography.caption.copyWith(color: colors.placeholder),
          ),

          AppGap.lgV,
          Divider(color: colors.textBox, height: 1),
          AppGap.lgV,

          Text(
            'Morning follow-up',
            style: AppTypography.subheadline.copyWith(
              color: colors.textPrimary,
            ),
          ),
          AppGap.smV,
          _Pills(
            enabled: settings.followUpEnabled,
            colors: colors,
            onChanged: reminders.setFollowUpEnabled,
            onLabel: 'On',
          ),
          if (settings.followUpEnabled) ...[
            AppGap.smV,
            _TimeRow(reminders: reminders, colors: colors, followUp: true),
          ],
          AppGap.smV,
          Text(
            'A question about the day before, written after your last log of '
            'it — so it can be there before the morning writes over it. It '
            'only arrives when there was actually a day to ask about.',
            style: AppTypography.caption.copyWith(color: colors.placeholder),
          ),
        ],
      ],
    );
  }
}

/// Off / On, shaped like the appearance selector so the two sections read as
/// one idea.
class _Pills extends StatelessWidget {
  const _Pills({
    required this.enabled,
    required this.colors,
    required this.onChanged,
    this.onLabel = 'Daily',
  });

  final bool enabled;
  final AppColors colors;

  /// Deliberately not typed to the return: `setEnabled` reports whether it
  /// stuck and `setFollowUpEnabled` has nothing to report, and neither answer
  /// is this widget's business — the service notifies and it repaints.
  final void Function(bool) onChanged;

  final String onLabel;

  @override
  Widget build(BuildContext context) {
    final options = {false: 'Off', true: onLabel};

    return Row(
      spacing: AppSpacing.sm,
      children: [
        for (final option in options.entries)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(option.key),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: AppDurations.fast,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  // textBox, not card: these pills sit *on* a card, so the
                  // selected one has to step further from the background
                  // rather than land on the surface it is already drawn on.
                  color: option.key == enabled
                      ? colors.textBox
                      : Colors.transparent,
                  borderRadius: AppRadius.smAll,
                ),
                child: Center(
                  child: Text(
                    option.value,
                    style: AppTypography.subheadline.copyWith(
                      color: option.key == enabled
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.reminders,
    required this.colors,
    this.followUp = false,
  });

  final ReminderService reminders;
  final AppColors colors;

  /// The same control for both times. They differ only in which setting they
  /// read and write, and a second near-identical widget would drift.
  final bool followUp;

  Future<void> _open(BuildContext context) async {
    var draft = followUp
        ? reminders.settings.followUpTimeOfDay
        : reminders.settings.timeOfDay;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.background,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: AppInsets.lg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                followUp ? 'Ask me at' : 'Remind me at',
                style: AppTypography.headline.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              AppGap.lgV,
              // Cupertino's own picker, but wearing the app's colours — left
              // stock it is the single loudest thing in Settings.
              CupertinoTheme(
                data: CupertinoThemeData(
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: AppTypography.body.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                child: SizedBox(
                  height: 200,
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    backgroundColor: const Color(0x00000000),
                    // The default overlay is Cupertino's own grey, which is
                    // the one part of this control that would still look
                    // borrowed. One rounded card spanning every column reads
                    // as the same soft shape used everywhere else.
                    //
                    // Translucent, and that is not a taste call: this is
                    // painted *over* the wheels, not behind them, so a solid
                    // fill hides the one row it exists to point at — the
                    // selected time came out as an empty bar. And the builder
                    // runs per column, so capping only the outer edges is what
                    // makes three boxes read as one card instead of three.
                    selectionOverlayBuilder:
                        (
                          context, {
                          required int selectedIndex,
                          required int columnCount,
                        }) => CupertinoPickerDefaultSelectionOverlay(
                          background: colors.card.withValues(alpha: 0.55),
                          capStartEdge: selectedIndex == 0,
                          capEndEdge: selectedIndex == columnCount - 1,
                        ),
                    initialDateTime: DateTime(
                      2026,
                      1,
                      1,
                      draft.hour,
                      draft.minute,
                    ),
                    onDateTimeChanged: (value) => draft = TimeOfDay(
                      hour: value.hour,
                      minute: value.minute,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Committed once the sheet closes, not per tick: onDateTimeChanged fires
    // continuously while the wheel spins, and each commit writes preferences
    // and re-arms the notification.
    await (followUp
        ? reminders.setFollowUpTime(draft)
        : reminders.setTime(draft));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Time',
              style: AppTypography.body.copyWith(color: colors.textPrimary),
            ),
            Row(
              spacing: AppSpacing.xs,
              children: [
                Text(
                  (followUp
                          ? reminders.settings.followUpTimeOfDay
                          : reminders.settings.timeOfDay)
                      .format(context),
                  style: AppTypography.body.copyWith(color: colors.primary),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: colors.placeholder,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
