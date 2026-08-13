import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;

/// When, and whether, to nudge.
///
/// Kept out of `UserProfile` and `ThemeSettings` for the same reason those are
/// separate from each other: a reminder write shouldn't rewrite the backdrops
/// blob, and a layout enum has no business in the input to the palette.
@immutable
class ReminderSettings {
  const ReminderSettings({
    this.enabled = false,
    this.minutesFromMidnight = _defaultMinutes,
    this.followUpEnabled = false,
    this.followUpMinutesFromMidnight = _defaultFollowUpMinutes,
  });

  /// Evening, when there's usually something to look back on.
  static const int _defaultMinutes = 21 * 60;

  /// Morning, because the follow-up is a question *about yesterday* and the
  /// point of it is to land before the day has written over it.
  static const int _defaultFollowUpMinutes = 9 * 60;

  static const ReminderSettings defaults = ReminderSettings();

  final bool enabled;

  /// Local wall-clock time, 0–1439. Stored as minutes rather than a
  /// [TimeOfDay] because that isn't serializable, and rather than a DateTime
  /// because the date would be meaningless and misleading.
  final int minutesFromMidnight;

  /// Whether to also send yesterday's follow-up question as its own
  /// notification, separate from the daily nudge.
  final bool followUpEnabled;

  final int followUpMinutesFromMidnight;

  TimeOfDay get timeOfDay => TimeOfDay(
    hour: minutesFromMidnight ~/ 60,
    minute: minutesFromMidnight % 60,
  );

  TimeOfDay get followUpTimeOfDay => TimeOfDay(
    hour: followUpMinutesFromMidnight ~/ 60,
    minute: followUpMinutesFromMidnight % 60,
  );

  ReminderSettings copyWith({
    bool? enabled,
    int? minutesFromMidnight,
    bool? followUpEnabled,
    int? followUpMinutesFromMidnight,
  }) => ReminderSettings(
    enabled: enabled ?? this.enabled,
    minutesFromMidnight: minutesFromMidnight ?? this.minutesFromMidnight,
    followUpEnabled: followUpEnabled ?? this.followUpEnabled,
    followUpMinutesFromMidnight:
        followUpMinutesFromMidnight ?? this.followUpMinutesFromMidnight,
  );

  ReminderSettings withTime(TimeOfDay time) =>
      copyWith(minutesFromMidnight: time.hour * 60 + time.minute);

  ReminderSettings withFollowUpTime(TimeOfDay time) =>
      copyWith(followUpMinutesFromMidnight: time.hour * 60 + time.minute);

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'minutesFromMidnight': minutesFromMidnight,
    'followUpEnabled': followUpEnabled,
    'followUpMinutesFromMidnight': followUpMinutesFromMidnight,
  };

  /// Tolerant by design — a malformed field falls back to its own default
  /// rather than losing the whole setting.
  factory ReminderSettings.fromJson(Map<String, Object?> json) {
    final enabled = json['enabled'];
    final minutes = json['minutesFromMidnight'];
    final followUpEnabled = json['followUpEnabled'];
    final followUpMinutes = json['followUpMinutesFromMidnight'];

    return ReminderSettings(
      followUpEnabled: followUpEnabled is bool ? followUpEnabled : false,
      followUpMinutesFromMidnight: followUpMinutes is num
          ? followUpMinutes.toInt() % (24 * 60)
          : _defaultFollowUpMinutes,
      enabled: enabled is bool ? enabled : false,
      // Wrapped rather than clamped: an out-of-range value is corrupt, and
      // 25:00 is more plausibly a bad write than a request for 23:59. Dart's
      // `%` is non-negative for a positive divisor, so this handles junk of
      // either sign.
      minutesFromMidnight: minutes is num
          ? minutes.toInt() % (24 * 60)
          : _defaultMinutes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      other.enabled == enabled &&
      other.minutesFromMidnight == minutesFromMidnight &&
      other.followUpEnabled == followUpEnabled &&
      other.followUpMinutesFromMidnight == followUpMinutesFromMidnight;

  @override
  int get hashCode => Object.hash(
    enabled,
    minutesFromMidnight,
    followUpEnabled,
    followUpMinutesFromMidnight,
  );
}
