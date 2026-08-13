import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/debug/data/seed_data.dart';
import 'package:froyou/features/home/data/follow_up_service.dart';
import 'package:froyou/features/debug/presentation/debug_menu_view.dart';
import 'package:froyou/features/reminders/presentation/reminder_section.dart';
import 'package:froyou/features/profile/presentation/widgets/backdrop_manager.dart';
import 'package:froyou/features/profile/presentation/widgets/theme_editor.dart';

/// Everything the user can change: theme, images and captions, reminders, and
/// clearing their logs.
///
/// Theme edits recolour the whole app as you make them — the profile controller
/// lives above `MaterialApp`, so every route on the stack gets the new palette.
class SettingsView extends HookWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.profileOf(context);
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          children: [
            _Section(
              title: 'Theme',
              colors: colors,
              // The preset row scrolls sideways, so it wants the card's full
              // width; the editor insets its own non-scrolling parts.
              bleed: true,
              child: ThemeEditor(profile: profile),
            ),
            _Section(
              title: 'Your images',
              // The framing editor is behind a tap on the picture and there is
              // nothing else to suggest it, so the subtitle has to say so.
              subtitle:
                  'They drift and fade on the home screen. Tap one to zoom and '
                  'move it. Captions are optional.',
              colors: colors,
              child: BackdropManager(profile: profile),
            ),
            _Section(
              title: 'Reminders',
              colors: colors,
              child: ReminderSection(reminders: AppScope.remindersOf(context)),
            ),
            _Section(
              title: 'Your logs',
              colors: colors,
              child: const _ClearLogsTile(),
            ),

            _CrisisResources(colors: colors),

            AppGap.lgV,
            _Section(
              title: 'Developer',
              colors: colors,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FollowUpPreviewTile(),
                  AppGap.smV,
                  OutlinedButton(
                    onPressed: () async {
                      final journal = AppScope.journalOf(context);
                      await DebugSeed.run(
                        AppScope.dbOf(context).journalEntryDb,
                      );
                      journal.refresh();
                    },
                    child: const Text('Seed sample logs'),
                  ),
                ],
              ),
            ),

            AppGap.xlV,
            Center(
              child: GestureDetector(
                // The channel test harness is the only way to diagnose the
                // native speech/NLP layer on a real device. Hidden, not gone.
                onLongPress: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => const DebugMenuView(),
                  ),
                ),
                child: Text(
                  'Froyou 1.0.0',
                  style: AppTypography.caption.copyWith(
                    color: colors.placeholder,
                  ),
                ),
              ),
            ),
            AppGap.xlV,
          ],
        ),
      ),
    );
  }
}

/// Deletes every log, sentence and theme.
///
/// Behind a confirmation that names the cost, because it is not recoverable
/// and the thing being deleted is everything the user has written.
class _ClearLogsTile extends HookWidget {
  const _ClearLogsTile();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final journal = AppScope.journalOf(context);
    final busy = useState(false);

    Future<void> confirmAndClear() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Clear all logs?'),
          content: Text(
            journal.count == 1
                ? 'Your 1 log and everything Froyou noticed in it will be deleted. This cannot be undone.'
                : 'All ${journal.count} of your logs, and every theme Froyou noticed across them, will be deleted. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep them'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'Clear everything',
                style: TextStyle(color: colors.error),
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      busy.value = true;
      try {
        await journal.clearAll();
      } finally {
        busy.value = false;
      }
    }

    final isEmpty = journal.count == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          onPressed: isEmpty || busy.value ? null : confirmAndClear,
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.error,
            side: BorderSide(color: colors.error.withValues(alpha: 0.4)),
          ),
          child: busy.value
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Clear all logs'),
        ),
        AppGap.xsV,
        Text(
          isEmpty
              ? 'Nothing to clear yet.'
              : 'Deletes every log and every theme. This cannot be undone.',
          style: AppTypography.caption.copyWith(color: colors.placeholder),
        ),
      ],
    );
  }
}

/// One setting, on its own surface.
///
/// Settings used to be a single column of labels and controls separated only by
/// whitespace, which left a horizontally scrolling swatch row, a list of images
/// and a destructive button all reading as one undifferentiated list. Giving
/// each its own card is what makes the page scannable — you can see where one
/// decision ends and the next begins without reading anything.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.colors,
    required this.child,
    this.subtitle,
    this.bleed = false,
  });

  static const EdgeInsets _inset = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
  );

  final String title;
  final String? subtitle;
  final AppColors colors;
  final Widget child;

  /// Lets a horizontally scrolling child run to the card's edges and inset
  /// itself instead. Without it the row is clipped mid-swatch by the card's
  /// padding, which reads as a layout mistake rather than as "there is more
  /// over there".
  final bool bleed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: AppRadius.mdAll,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: _inset,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: AppTypography.headline.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      AppGap.xsV,
                      Text(
                        subtitle!,
                        style: AppTypography.caption.copyWith(
                          color: colors.placeholder,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              AppGap.mdV,
              if (bleed) child else Padding(padding: _inset, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Never more than one tap from where the user is journalling. Froyou is a
/// self-help companion, not a clinical tool, and the difference has to be
/// visible rather than assumed.
/// What Froyou is not.
///
/// The hotline rows that used to sit here were removed on request. The one
/// sentence that remains is the claim the app has to keep making about itself,
/// and it costs nothing to keep making it.
class _CrisisResources extends StatelessWidget {
  const _CrisisResources({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: AppRadius.mdAll,
      ),
      child: Padding(
        padding: AppInsets.md,
        child: Text(
          'Froyou is a self-help companion, not a replacement for therapy.',
          style: AppTypography.footnote.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}

class _FollowUpPreviewTile extends HookWidget {
  const _FollowUpPreviewTile();

  @override
  Widget build(BuildContext context) {
    final busy = useState(false);

    Future<void> run() async {
      final service = AppScope.journalOf(context).followUp;
      if (service == null) return;
      busy.value = true;
      final preview = await service.preview();
      busy.value = false;
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.appColors.background,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _FollowUpPreviewSheet(preview: preview),
      );
    }

    return OutlinedButton(
      onPressed: busy.value ? null : run,
      child: Text(
        busy.value ? 'Asking the model…' : 'Preview follow-up question',
      ),
    );
  }
}

class _FollowUpPreviewSheet extends StatelessWidget {
  const _FollowUpPreviewSheet({required this.preview});

  final FollowUpPreview preview;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SafeArea(
      child: Padding(
        padding: AppInsets.lg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Follow-up question',
              style: AppTypography.headline.copyWith(color: colors.textPrimary),
            ),
            AppGap.smV,
            Text(
              'What the model is given, and what it writes back. Everything '
              'here stays on this device.',
              style: AppTypography.footnote.copyWith(
                color: colors.textSecondary,
              ),
            ),
            AppGap.lgV,

            _PreviewBlock(
              label: 'Themes it was told about',
              body: preview.themes.isEmpty
                  ? 'None — no themes are named yet.'
                  : preview.themes.join(' · '),
              colors: colors,
            ),
            if (preview.excerpt case final String excerpt) ...[
              AppGap.mdV,
              _PreviewBlock(
                label: 'Your words it was given',
                body: '“$excerpt”',
                colors: colors,
              ),
            ],
            AppGap.mdV,
            _PreviewBlock(
              label: preview.question == null ? 'Nothing came back' : 'It asks',
              body: preview.question ?? (preview.error ?? 'Unknown failure.'),
              colors: colors,
              emphasised: preview.question != null,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBlock extends StatelessWidget {
  const _PreviewBlock({
    required this.label,
    required this.body,
    required this.colors,
    this.emphasised = false,
  });

  final String label;
  final String body;
  final AppColors colors;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTypography.caption.copyWith(color: colors.placeholder),
        ),
        AppGap.xsV,
        Text(
          body,
          style: AppTypography.body.copyWith(
            color: emphasised ? colors.primary : colors.textPrimary,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}
