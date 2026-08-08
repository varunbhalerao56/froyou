import 'package:flutter/material.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/home/presentation/home_shell.dart';
import 'package:froyou/features/journal/presentation/journal_controller.dart';
import 'package:froyou/features/profile/data/profile_store.dart';
import 'package:froyou/features/profile/data/user_profile.dart';
import 'package:froyou/features/profile/presentation/onboarding_view.dart';
import 'package:froyou/features/profile/presentation/profile_controller.dart';
import 'package:froyou/services/services.dart';

/// Root of the running app. Owns the controllers for the process lifetime and
/// is the only place that disposes them.
class FroyouRoot extends StatefulWidget {
  const FroyouRoot({
    required this.db,
    required this.store,
    required this.initialProfile,
    required this.initialPalette,
    super.key,
  });

  final AppDatabase db;
  final ProfileStore store;
  final UserProfile initialProfile;
  final AppPalette initialPalette;

  @override
  State<FroyouRoot> createState() => _FroyouRootState();
}

class _FroyouRootState extends State<FroyouRoot> {
  late final ProfileController _profile;
  late final JournalController _journal;

  @override
  void initState() {
    super.initState();
    _profile = ProfileController(
      store: widget.store,
      profile: widget.initialProfile,
      palette: widget.initialPalette,
    );
    _journal = JournalController(widget.db.journalEntryDb);
  }

  @override
  void dispose() {
    _profile.dispose();
    _journal.dispose();
    widget.db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      db: widget.db,
      profile: _profile,
      journal: _journal,
      // Builder so this subtree — and therefore MaterialApp.theme — is what
      // depends on the profile notifier. Handing MaterialApp a new ThemeData
      // animates the change through the framework's own AnimatedTheme, because
      // AppColors implements lerp.
      child: Builder(
        builder: (context) {
          final profile = AppScope.profileOf(context);
          return MaterialApp(
            title: 'Froyou',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.fromPalette(profile.palette),
            home: profile.profile.onboarded
                ? const HomeShell()
                : const OnboardingView(),
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
