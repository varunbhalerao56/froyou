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
  });

  /// Evening, when there's usually something to look back on.
  static const int _defaultMinutes = 21 * 60;

  static const ReminderSettings defaults = ReminderSettings();

  final bool enabled;

  /// Local wall-clock time, 0–1439. Stored as minutes rather than a
  /// [TimeOfDay] because that isn't serializable, and rather than a DateTime
  /// because the date would be meaningless and misleading.
  final int minutesFromMidnight;

  TimeOfDay get timeOfDay => TimeOfDay(
    hour: minutesFromMidnight ~/ 60,
    minute: minutesFromMidnight % 60,
  );

  ReminderSettings copyWith({bool? enabled, int? minutesFromMidnight}) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        minutesFromMidnight: minutesFromMidnight ?? this.minutesFromMidnight,
      );

  ReminderSettings withTime(TimeOfDay time) =>
      copyWith(minutesFromMidnight: time.hour * 60 + time.minute);

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'minutesFromMidnight': minutesFromMidnight,
  };

  /// Tolerant by design — a malformed field falls back to its own default
  /// rather than losing the whole setting.
  factory ReminderSettings.fromJson(Map<String, Object?> json) {
    final enabled = json['enabled'];
    final minutes = json['minutesFromMidnight'];

    return ReminderSettings(
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
      other.minutesFromMidnight == minutesFromMidnight;

  @override
  int get hashCode => Object.hash(enabled, minutesFromMidnight);
}
