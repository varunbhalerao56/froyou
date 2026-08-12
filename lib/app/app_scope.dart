import 'package:flutter/material.dart';
import 'package:froyou/features/journal/presentation/journal_controller.dart';
import 'package:froyou/features/profile/presentation/profile_controller.dart';
import 'package:froyou/features/reminders/data/reminder_service.dart';
import 'package:froyou/services/services.dart';

/// Dependency scope for the whole app.
///
/// Deliberately mounted *above* `MaterialApp` so that pushed routes can read
/// it and so a theme change reaches every route already on the stack — not
/// just the one on top.
///
/// Two notifiers rather than one, so saving a log doesn't rebuild the themed
/// shell and changing the backdrop doesn't rebuild the log list.
class AppScope extends StatelessWidget {
  const AppScope({
    required this.db,
    required this.profile,
    required this.journal,
    required this.reminders,
    required this.child,
    super.key,
  });

  final AppDatabase db;
  final ProfileController profile;
  final JournalController journal;
  final ReminderService reminders;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _Services(
      db: db,
      reminders: reminders,
      child: _ProfileScope(
        notifier: profile,
        child: _JournalScope(notifier: journal, child: child),
      ),
    );
  }

  /// The database handle. Does not register a dependency — it never changes.
  static AppDatabase dbOf(BuildContext context) {
    final services = context.dependOnInheritedWidgetOfExactType<_Services>();
    assert(services != null, 'AppScope.dbOf called outside an AppScope');
    return services!.db;
  }

  /// The reminder service. Like [dbOf], the *handle* is fixed for the process,
  /// so reading it registers no dependency — a widget that cares about the
  /// reminder's state subscribes to it directly with `useListenable`. Putting
  /// it on a scope instead would rebuild every route for a setting only one
  /// section of Settings shows.
  static ReminderService remindersOf(BuildContext context) {
    final services = context.dependOnInheritedWidgetOfExactType<_Services>();
    assert(services != null, 'AppScope.remindersOf called outside an AppScope');
    return services!.reminders;
  }

  /// Subscribes the calling widget to profile and theme changes.
  static ProfileController profileOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ProfileScope>();
    assert(scope != null, 'AppScope.profileOf called outside an AppScope');
    return scope!.notifier!;
  }

  /// Subscribes the calling widget to log-list changes.
  static JournalController journalOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_JournalScope>();
    assert(scope != null, 'AppScope.journalOf called outside an AppScope');
    return scope!.notifier!;
  }
}

/// Named subclasses rather than bare `InheritedNotifier<T>`: the base class is
/// abstract, and distinct types are what let `dependOnInheritedWidgetOfExactType`
/// tell the two notifiers apart.
class _ProfileScope extends InheritedNotifier<ProfileController> {
  const _ProfileScope({required super.notifier, required super.child});
}

class _JournalScope extends InheritedNotifier<JournalController> {
  const _JournalScope({required super.notifier, required super.child});
}

/// Holds handles that are fixed for the process lifetime, so nothing should
/// ever rebuild on their account.
class _Services extends InheritedWidget {
  const _Services({
    required this.db,
    required this.reminders,
    required super.child,
  });

  final AppDatabase db;
  final ReminderService reminders;

  @override
  bool updateShouldNotify(_Services oldWidget) => false;
}
