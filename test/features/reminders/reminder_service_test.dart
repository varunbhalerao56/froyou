import 'dart:convert';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:froyou/core/config/label_mode.dart';
import 'package:froyou/features/debug/data/seed_data.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/features/reminders/data/reminder_service.dart';
import 'package:froyou/generated/objectbox.g.dart';
import 'package:froyou/services/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../support/genai_mock.dart';
import '../../support/reminder_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Store store;
  late AppDatabase db;
  late ProfileStore profileStore;
  late List<MethodCall> calls;
  int counter = 0;

  setUp(() async {
    // Both of these seed data and then assert on cluster labels, so they need
    // the statistical labeler that [kModelOnlyLabels] currently switches off
    // while the model path is being eyeballed on device.
    kModelOnlyLabels = false;
    calls = [];
    mockGenAi(available: false);
    mockNotifications(calls: calls, timeZone: 'Europe/London');
    useIosNotificationPlatform();
    SharedPreferences.setMockInitialValues({});
    store = Store(
      getObjectBoxModel(),
      directory: 'memory:reminder-test-${counter++}',
    );
    db = AppDatabase.forTesting(store);
    profileStore = ProfileStore(await SharedPreferences.getInstance());
  });

  tearDown(() {
    kModelOnlyLabels = true;
    unmockGenAi();
    unmockNotifications();
    store.close();
  });

  ReminderService service() =>
      ReminderService(store: profileStore, db: db.journalEntryDb);

  List<String> methods() => [for (final call in calls) call.method];

  group('init', () {
    test('clears stale requests when there is no stored config', () async {
      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();

      // Preferences are wiped on a schema change but the iOS request survives
      // it, and would keep firing forever with a body from a journal that no
      // longer exists.
      expect(methods(), contains('cancelAll'));
      expect(reminders.isReady, isTrue);
      expect(reminders.settings.enabled, isFalse);
    });

    test('restores stored settings and re-arms', () async {
      await profileStore.setString(
        ReminderService.settingsKey,
        jsonEncode(const {'enabled': true, 'minutesFromMidnight': 450}),
      );

      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();

      expect(reminders.settings.enabled, isTrue);
      expect(
        reminders.settings.timeOfDay,
        const TimeOfDay(hour: 7, minute: 30),
      );
      // Re-armed on every launch: a request can be lost to a restore, and
      // re-issuing an identical one is free because the id is fixed.
      expect(methods(), contains('zonedSchedule'));
      expect(methods(), isNot(contains('cancelAll')));
    });

    test('stays unready when the time zone cannot be read', () async {
      // Without a real IANA zone, scheduling would fire at the right number in
      // the wrong zone — so reminders switch off rather than lie.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(timezoneChannel),
            (call) async => throw PlatformException(code: 'unavailable'),
          );

      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();

      expect(reminders.isReady, isFalse);
      expect(methods(), isNot(contains('zonedSchedule')));
    });
  });

  group('enabling', () {
    test('asks for permission and schedules once granted', () async {
      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();
      calls.clear();

      expect(await reminders.setEnabled(true), isTrue);

      // The trailing cancel clears any follow-up left armed from a previous
      // run: turning reminders on does not turn the follow-up on with them.
      expect(methods(), ['requestPermissions', 'zonedSchedule', 'cancel']);
      expect(reminders.settings.enabled, isTrue);
      expect(reminders.permissionDenied, isFalse);
    });

    test('schedules a daily repeat carrying the body', () async {
      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();
      calls.clear();
      await reminders.setEnabled(true);

      final scheduled = calls.firstWhere(
        (call) => call.method == 'zonedSchedule',
      );
      final args = scheduled.arguments as Map<Object?, Object?>;
      expect(args['id'], ReminderService.notificationId);
      expect(args['body'], ReminderService.fallbackLine);
      // The body is baked in at schedule time because iOS background
      // execution can't be trusted to compose it when the alert fires.
      expect(args['matchDateTimeComponents'], isNotNull);
    });

    test('a refused prompt leaves the toggle off', () async {
      mockNotifications(calls: calls, granted: false);
      useIosNotificationPlatform();

      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();
      calls.clear();

      expect(await reminders.setEnabled(true), isFalse);

      // iOS silently drops scheduled requests from an unauthorized app, so
      // anything else here would look armed and never fire.
      expect(methods(), ['requestPermissions']);
      expect(reminders.settings.enabled, isFalse);
      expect(reminders.permissionDenied, isTrue);
    });

    test('disabling cancels the pending request', () async {
      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();
      await reminders.setEnabled(true);
      calls.clear();

      await reminders.setEnabled(false);

      expect(methods(), contains('cancel'));
      expect(reminders.settings.enabled, isFalse);
    });
  });

  group('time', () {
    test('persists and re-arms', () async {
      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();
      await reminders.setEnabled(true);
      calls.clear();

      await reminders.setTime(const TimeOfDay(hour: 8, minute: 15));

      expect(reminders.settings.minutesFromMidnight, 8 * 60 + 15);
      expect(methods(), contains('zonedSchedule'));

      final raw = profileStore.getString(ReminderService.settingsKey);
      expect(jsonDecode(raw!), {
        'enabled': true,
        'minutesFromMidnight': 8 * 60 + 15,
        // The follow-up is a separate opt-in with its own time — written
        // alongside so a settings blob is never half a record.
        'followUpEnabled': false,
        'followUpMinutesFromMidnight': 9 * 60,
      });
    });

    test('setting the same time again does nothing', () async {
      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();
      await reminders.setEnabled(true);
      calls.clear();

      await reminders.setTime(reminders.settings.timeOfDay);

      expect(calls, isEmpty);
    });
  });

  group('nextOccurrence', () {
    setUpAll(() {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('UTC'));
    });

    test('picks today when the time is still ahead', () {
      final now = tz.TZDateTime(tz.local, 2026, 8, 12, 9);
      final next = ReminderService.nextOccurrence(
        const TimeOfDay(hour: 21, minute: 0),
        from: now,
      );
      expect(next, tz.TZDateTime(tz.local, 2026, 8, 12, 21));
    });

    test('rolls to tomorrow once the time has passed', () {
      final now = tz.TZDateTime(tz.local, 2026, 8, 12, 22);
      final next = ReminderService.nextOccurrence(
        const TimeOfDay(hour: 21, minute: 0),
        from: now,
      );
      expect(next, tz.TZDateTime(tz.local, 2026, 8, 13, 21));
    });

    test('rolls forward when the time is exactly now', () {
      final now = tz.TZDateTime(tz.local, 2026, 8, 12, 21);
      final next = ReminderService.nextOccurrence(
        const TimeOfDay(hour: 21, minute: 0),
        from: now,
      );
      expect(next, tz.TZDateTime(tz.local, 2026, 8, 13, 21));
    });
  });

  group('follow-up notification', () {
    test('does nothing while it is switched off', () async {
      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();
      await reminders.setEnabled(true);
      calls.clear();

      await reminders.refreshFollowUp();

      // Cancelled, never scheduled: an armed request from a previous run must
      // not survive the switch going off.
      expect(methods(), ['cancel']);
    });

    test('without a FollowUpService there is nothing to arm', () async {
      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();
      await reminders.setEnabled(true);
      await reminders.setFollowUpEnabled(true);
      calls.clear();

      await reminders.refreshFollowUp();

      expect(
        methods().where((m) => m == 'zonedSchedule'),
        isEmpty,
        reason:
            'no question means no notification, rather than a generic one '
            'dressed as a question about a day that did not happen',
      );
    });

    test('the time and switch persist', () async {
      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();
      await reminders.setEnabled(true);

      await reminders.setFollowUpEnabled(true);
      await reminders.setFollowUpTime(const TimeOfDay(hour: 7, minute: 30));

      expect(reminders.settings.followUpEnabled, isTrue);
      expect(reminders.settings.followUpMinutesFromMidnight, 7 * 60 + 30);

      final raw = profileStore.getString(ReminderService.settingsKey);
      expect((jsonDecode(raw!) as Map)['followUpMinutesFromMidnight'], 450);
    });

    test('turning reminders off takes the follow-up with it', () async {
      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();
      await reminders.setEnabled(true);
      await reminders.setFollowUpEnabled(true);
      calls.clear();

      await reminders.setEnabled(false);

      // Both requests, because there is one permission and one thing the user
      // thinks of as "notifications".
      // The plugin sends `cancel` with the bare id, not a map.
      final cancelled = calls
          .where((call) => call.method == 'cancel')
          .map((call) => call.arguments)
          .toList();
      expect(
        cancelled,
        containsAll([
          ReminderService.notificationId,
          ReminderService.followUpNotificationId,
        ]),
      );
    });
  });

  group('body', () {
    test('is left alone while reminders are off', () async {
      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();
      await DebugSeed.run(db.journalEntryDb);
      calls.clear();

      await reminders.refreshBody();

      expect(calls, isEmpty);
      expect(reminders.body, ReminderService.fallbackLine);
    });

    test('falls back to a fixed line when the model is unavailable', () async {
      await DebugSeed.run(db.journalEntryDb);

      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();
      await reminders.setEnabled(true);
      calls.clear();

      await reminders.refreshBody();

      // The model is never required — this is the path the Simulator always
      // takes, so it is the one that has to be right.
      expect(reminders.body, ReminderService.fallbackLine);
      expect(methods(), contains('zonedSchedule'));
    });

    test('uses the model when it is available', () async {
      mockGenAi(available: true, reminder: 'Still carrying work around?');
      await DebugSeed.run(db.journalEntryDb);

      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();
      await reminders.setEnabled(true);

      await reminders.refreshBody();

      expect(reminders.body, 'Still carrying work around?');
    });

    test('does not ask the model twice for the same themes', () async {
      mockGenAi(available: true, reminder: 'Still carrying work around?');
      await DebugSeed.run(db.journalEntryDb);

      final reminders = service();
      addTearDown(reminders.dispose);
      await reminders.init();
      await reminders.setEnabled(true);
      await reminders.refreshBody();
      calls.clear();

      await reminders.refreshBody();

      // Clustering has already paid one inference on this save; a second every
      // time a log lands is real model time for a line that comes out the same.
      expect(calls, isEmpty);
    });
  });
}
