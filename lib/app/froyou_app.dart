import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/home/data/follow_up_service.dart';
import 'package:froyou/features/home/presentation/home_shell.dart';
import 'package:froyou/features/journal/presentation/journal_controller.dart';
import 'package:froyou/features/onboarding/onboarding_view.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/features/profile/data/user_profile.dart';
import 'package:froyou/features/profile/presentation/profile_controller.dart';
import 'package:froyou/features/reminders/data/reminder_service.dart';
import 'package:froyou/services/services.dart';

/// Root of the running app. Owns the controllers for the process lifetime and
/// is the only place that disposes them.
class FroyouRoot extends StatefulWidget {
  const FroyouRoot({
    required this.db,
    required this.store,
    required this.initialProfile,
    required this.initialThemeSettings,
    required this.initialPlatformBrightness,
    super.key,
  });

  final AppDatabase db;
  final ProfileStore store;
  final UserProfile initialProfile;
  final ThemeSettings initialThemeSettings;
  final Brightness initialPlatformBrightness;

  @override
  State<FroyouRoot> createState() => _FroyouRootState();
}

class _FroyouRootState extends State<FroyouRoot> with WidgetsBindingObserver {
  late final ProfileController _profile;
  late final JournalController _journal;
  late final ReminderService _reminders;

  @override
  void initState() {
    super.initState();
    // Observed rather than read from MediaQuery: this widget sits above
    // MaterialApp, and the theme has to re-resolve when iOS switches
    // appearance while the user is in `system` mode.
    WidgetsBinding.instance.addObserver(this);
    _profile = ProfileController(
      store: widget.store,
      profile: widget.initialProfile,
      themeSettings: widget.initialThemeSettings,
      platformBrightness: widget.initialPlatformBrightness,
    );
    // Built before the journal controller, which takes its enrichment hook.
    // Construction is inert — no channel traffic until `init`.
    _reminders = ReminderService(
      store: widget.store,
      db: widget.db.journalEntryDb,
    );
    _journal = JournalController(
      widget.db.journalEntryDb,
      followUp: FollowUpService(
        store: widget.store,
        db: widget.db.journalEntryDb,
      ),
      // Recomputes the reminder's line from the theme labels a save just
      // produced. Baked in now because iOS background execution isn't
      // dependable enough to compose it when the notification fires.
      onEnriched: _reminders.onJournalEnriched,
    );
    // Deferred off the first frame: these reach the language model and load
    // the time-zone database, and nothing about the home screen should wait on
    // either.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _journal.refreshPrompt();
      _reminders.init();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Coming back to the app can cross midnight, which is exactly when a
    // follow-up becomes due — or stops being.
    _journal.refreshPrompt();
    // And it's how someone returns from turning notifications off in iOS
    // Settings, which the toggle has to notice.
    _reminders.syncPermission();
  }

  @override
  void didChangePlatformBrightness() {
    _profile.setPlatformBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _profile.dispose();
    _journal.dispose();
    _reminders.dispose();
    widget.db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      db: widget.db,
      profile: _profile,
      journal: _journal,
      reminders: _reminders,
      // Builder so this subtree — and therefore MaterialApp.theme — is what
      // depends on the profile notifier. Handing MaterialApp a new ThemeData
      // animates the change through the framework's own AnimatedTheme, because
      // AppColors implements lerp.
      child: Builder(
        builder: (context) {
          final profile = AppScope.profileOf(context);
          // Covers the routes with no app bar of their own — Home runs edge to
          // edge behind the status bar, so the clock and battery sit directly
          // on the theme and have to be told which way to read.
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: AppTheme.overlayStyleFor(profile.palette.brightness),
            child: MaterialApp(
              title: 'Froyou',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.fromPalette(profile.palette),
              home: profile.profile.onboarded
                  ? const HomeShell()
                  : const OnboardingView(),
            ),
          );
        },
      ),
    );
  }
}

/// Shown when startup itself fails — almost always ObjectBox refusing to open
/// after a schema change during development.
///
/// Exists so that failure is a readable screen with a way out, rather than a
/// grey void with a stack trace in the console.
class BootFailureApp extends StatelessWidget {
  const BootFailureApp({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Froyou could not start', style: AppTypography.title2),
                AppGap.smV,
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: AppTypography.footnote.copyWith(
                    color: AppColors.light.textSecondary,
                  ),
                ),
                AppGap.lgV,
                _ResetButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResetButton extends StatefulWidget {
  @override
  State<_ResetButton> createState() => _ResetButtonState();
}

class _ResetButtonState extends State<_ResetButton> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return Text(
        'Local data cleared. Reopen Froyou to continue.',
        textAlign: TextAlign.center,
        style: AppTypography.subheadline,
      );
    }
    return OutlinedButton(
      onPressed: () async {
        await AppDatabase.eraseLocalData();
        if (mounted) setState(() => _done = true);
      },
      child: const Text('Reset local data'),
    );
  }
}
