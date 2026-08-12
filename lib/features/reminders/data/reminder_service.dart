import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/features/journal/data/repository/journal_entry_db.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/features/reminders/data/reminder_settings.dart';
import 'package:froyou/services/services.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// One daily notification, with a line written from what the user keeps
/// coming back to.
///
/// **The body is composed at save time, never at fire time.** iOS background
/// execution isn't dependable enough to run a language model when a
/// notification is due, so the text is baked into the scheduled request and
/// re-baked whenever the themes it was built from change.
///
/// Owned by `AppScope`'s plain services layer rather than by
/// `ProfileController`: that one sits above `MaterialApp`, so notifying from
/// it would rebuild every route on the stack for a boolean only Settings
/// cares about.
class ReminderService extends ChangeNotifier {
  /// Callers pass `store:` and `db:` — the private names are initializing
  /// formals, which Dart maps to their public form, as elsewhere in the app.
  ReminderService({
    required this._store,
    required this._db,
    @visibleForTesting FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  @visibleForTesting
  static const String settingsKey = 'reminders.settings';

  @visibleForTesting
  static const String bodyKey = 'reminders.body';

  /// A single, always-replaced request. Rescheduling overwrites rather than
  /// stacking, so there is never more than one reminder pending.
  static const int notificationId = 1;

  /// Used whenever the model is unavailable, latched off, or returns nothing —
  /// which on the Simulator is always. The model is never required.
  static const String fallbackLine = 'A quiet minute, if you want one.';

  static const String title = 'Froyou';

  final ProfileStore _store;
  final JournalEntryDb _db;
  final FlutterLocalNotificationsPlugin _plugin;

  ReminderSettings _settings = ReminderSettings.defaults;
  bool _permissionDenied = false;
  bool _ready = false;
  List<String> _bodyThemes = const [];
  String _body = fallbackLine;

  ReminderSettings get settings => _settings;

  /// True when the user has turned reminders on but iOS is refusing them.
  /// Drives the "turn them on in Settings" line.
  bool get permissionDenied => _permissionDenied;

  /// False until [init] has resolved the device's time zone. Nothing is ever
  /// scheduled before this is true — see [_resolveTimeZone].
  bool get isReady => _ready;

  /// The line currently baked into the scheduled notification.
  String get body => _body;

  // ---------------------------------------------------------------------------
  // Boot
  // ---------------------------------------------------------------------------

  /// Safe to call once, off the first frame. Does channel work and loads the
  /// time-zone database, neither of which should sit in front of a frame.
  Future<void> init() async {
    final raw = _store.getString(settingsKey);
    if (raw == null) {
      // No stored config: either a fresh install or a schema wipe. Prefs are
      // cleared on a wipe but the iOS request survives it, and would go on
      // firing forever with a body from a journal that no longer exists.
      await _safely(_plugin.cancelAll);
    } else {
      _settings = _readSettings(raw);
    }
    _readBody();

    _ready = await _resolveTimeZone();
    if (!_ready) return;

    await _safely(
      () => _plugin.initialize(
        settings: const InitializationSettings(
          iOS: DarwinInitializationSettings(
            // Asked for from Settings, in context, rather than fired at
            // launch before anyone knows what it is for.
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      ),
    );

    if (_settings.enabled) {
      // Re-arm on every launch. A request can be lost to a restore or a long
      // period with the app uninstalled, and re-issuing an identical one is
      // free because the id is fixed.
      await _reschedule();
    }
    notifyListeners();
  }

  /// The time-zone database ships without knowing where the device is, and
  /// `tz.local` stays UTC until told. Scheduling against UTC would put a 21:00
  /// reminder hours off — plausible enough to ship and only detectable by
  /// waiting, so a failure here disables reminders rather than guessing.
  Future<bool> _resolveTimeZone() async {
    try {
      tz_data.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      return true;
    } catch (e, stackTrace) {
      AppLog.error(
        'Reminders',
        'could not resolve the time zone',
        e,
        stackTrace,
      );
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  /// Returns whether reminders ended up on. Turning them on can fail, and the
  /// toggle has to snap back when it does.
  Future<bool> setEnabled(bool enabled) async {
    if (!enabled) {
      _permissionDenied = false;
      await _write(_settings.copyWith(enabled: false));
      await _safely(() => _plugin.cancel(id: notificationId));
      notifyListeners();
      return false;
    }

    // iOS silently drops scheduled requests from an unauthorized app, so a
    // refused prompt must leave the toggle off rather than looking armed.
    final granted = await _requestPermission();
    _permissionDenied = !granted;
    await _write(_settings.copyWith(enabled: granted));
    if (granted) await _reschedule();
    notifyListeners();
    return granted;
  }

  Future<void> setTime(TimeOfDay time) async {
    final updated = _settings.withTime(time);
    if (updated == _settings) return;
    await _write(updated);
    if (_settings.enabled) await _reschedule();
    notifyListeners();
  }

  /// Re-checks authorization after a trip to iOS Settings. Called on resume,
  /// for the same reason the follow-up prompt is refreshed there.
  Future<void> syncPermission() async {
    if (!_settings.enabled) return;

    final options = await _safely(
      () => _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions(),
    );
    if (options == null) return;

    if (!options.isEnabled) {
      _permissionDenied = true;
      await _write(_settings.copyWith(enabled: false));
      notifyListeners();
    } else if (_permissionDenied) {
      _permissionDenied = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Body
  // ---------------------------------------------------------------------------

  /// Hook for the end of a save's enrichment phase.
  ///
  /// Never awaited by the caller and never throws: a reminder is not worth
  /// delaying, let alone failing, a log the user has already written.
  void onJournalEnriched() => unawaited(refreshBody());

  @visibleForTesting
  Future<void> refreshBody() async {
    if (!_settings.enabled) return;

    try {
      final themes = _topThemes();
      // Debounced on the themes the current line was built from. Clustering
      // has already paid one inference on this save; a second every time a log
      // lands is real model time for a line that would come out the same.
      if (listEquals(themes, _bodyThemes)) return;

      final line = await _composeLine(themes);
      _body = line;
      _bodyThemes = themes;
      await _store.setString(
        bodyKey,
        jsonEncode({'line': line, 'themes': themes}),
      );
      if (_settings.enabled) await _reschedule();
    } catch (e, stackTrace) {
      // The previously scheduled line stays armed, which is the right failure:
      // a slightly stale nudge beats none.
      AppLog.error('Reminders', 'body refresh failed', e, stackTrace);
    }
  }

  Future<String> _composeLine(List<String> themes) async {
    if (themes.isEmpty) return fallbackLine;
    final availability = await GenAiService.availability();
    if (!availability.isAvailable) return fallbackLine;

    try {
      final line = await GenAiService.reminderLine(themes: themes);
      return line.isEmpty ? fallbackLine : line;
    } on GenAiException {
      return fallbackLine;
    }
  }

  /// What the user keeps coming back to, biggest theme first.
  ///
  /// Deliberately not the follow-up service's "what did yesterday touch" —
  /// that answers a different question. A daily nudge is about the standing
  /// preoccupation, not the most recent one.
  List<String> _topThemes() {
    final clusters = _db.getAllThemeClusters().where((cluster) {
      final label = cluster.label;
      return label != null && label.trim().isNotEmpty;
    }).toList();

    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    clusters.sort((a, b) {
      final size = b.memberCount.compareTo(a.memberCount);
      if (size != 0) return size;
      // A cluster with no lastSeen sorts last rather than throwing.
      return (b.lastSeen ?? epoch).compareTo(a.lastSeen ?? epoch);
    });

    return [for (final cluster in clusters.take(3)) cluster.label!.trim()];
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  Future<void> _reschedule() async {
    if (!_ready) return;

    await _safely(
      () => _plugin.zonedSchedule(
        id: notificationId,
        title: title,
        body: _body,
        scheduledDate: nextOccurrence(_settings.timeOfDay),
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: false,
          ),
        ),
        // Required by the API but inert here; Android is out of scope.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // Repeats daily at this wall-clock time, following the device across
        // time-zone changes rather than drifting with them.
        matchDateTimeComponents: DateTimeComponents.time,
      ),
    );
  }

  @visibleForTesting
  static tz.TZDateTime nextOccurrence(TimeOfDay time, {tz.TZDateTime? from}) {
    final now = from ?? tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    // Today's slot has passed, so the first firing is tomorrow's.
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
  }

  Future<bool> _requestPermission() async {
    final granted = await _safely(
      () => _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true, badge: false),
    );
    return granted ?? false;
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Future<void> _write(ReminderSettings settings) async {
    _settings = settings;
    await _store.setString(settingsKey, jsonEncode(settings.toJson()));
  }

  ReminderSettings _readSettings(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return ReminderSettings.fromJson(decoded);
      }
    } catch (_) {
      // Corrupt entry: fall through to defaults rather than failing boot.
    }
    return ReminderSettings.defaults;
  }

  void _readBody() {
    final raw = _store.getString(bodyKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final line = decoded['line'];
      final themes = decoded['themes'];
      if (line is String && line.isNotEmpty) _body = line;
      if (themes is List) {
        _bodyThemes = [
          for (final theme in themes)
            if (theme is String) theme,
        ];
      }
    } catch (_) {
      // Same as above — a bad cache is not worth a failed launch.
    }
  }

  /// Swallows plugin failures. Every caller has a sensible degraded state, and
  /// nothing about a reminder is worth an error in front of the user.
  Future<T?> _safely<T>(Future<T?>? Function() action) async {
    try {
      return await action();
    } catch (e) {
      AppLog.warn('Reminders', 'notification plugin call failed: $e');
      return null;
    }
  }
}
