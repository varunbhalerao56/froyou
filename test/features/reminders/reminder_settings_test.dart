import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/features/reminders/data/reminder_settings.dart';

void main() {
  test('defaults to off, in the evening', () {
    const settings = ReminderSettings.defaults;
    expect(settings.enabled, isFalse);
    expect(settings.timeOfDay, const TimeOfDay(hour: 21, minute: 0));
  });

  test('round-trips through JSON', () {
    const settings = ReminderSettings(enabled: true, minutesFromMidnight: 465);
    final restored = ReminderSettings.fromJson(settings.toJson());

    expect(restored, settings);
    expect(restored.timeOfDay, const TimeOfDay(hour: 7, minute: 45));
  });

  test('withTime converts a TimeOfDay to minutes', () {
    const settings = ReminderSettings();
    expect(
      settings.withTime(const TimeOfDay(hour: 6, minute: 30)).minutesFromMidnight,
      390,
    );
  });

  group('tolerance', () {
    test('a malformed field falls back on its own', () {
      // Each field independently, so one bad value doesn't lose the other.
      final settings = ReminderSettings.fromJson(const {
        'enabled': 'yes',
        'minutesFromMidnight': 480,
      });
      expect(settings.enabled, isFalse);
      expect(settings.minutesFromMidnight, 480);
    });

    test('missing keys give the defaults', () {
      expect(ReminderSettings.fromJson(const {}), ReminderSettings.defaults);
    });

    test('an out-of-range time wraps rather than clamping', () {
      // 25:00 is far more plausibly a corrupt write than a request for the
      // last minute of the day, so wrapping keeps it obviously wrong instead
      // of quietly becoming 23:59.
      expect(
        ReminderSettings.fromJson(const {'minutesFromMidnight': 25 * 60})
            .timeOfDay,
        const TimeOfDay(hour: 1, minute: 0),
      );
      expect(
        ReminderSettings.fromJson(const {'minutesFromMidnight': -60}).timeOfDay,
        const TimeOfDay(hour: 23, minute: 0),
      );
    });
  });
}
