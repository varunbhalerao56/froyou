import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/debug/data/seed_data.dart';
import 'package:froyou/features/debug/presentation/channel_test_view.dart';
import 'package:froyou/features/profile/presentation/widgets/backdrop_picker.dart';
import 'package:url_launcher/url_launcher.dart';

/// Edit the image and quote set during onboarding.
///
/// Changing the photo here rethemes the whole app immediately, including the
/// screen underneath this one — the profile controller lives above
/// `MaterialApp`, so every route on the stack gets the new palette.
class SettingsView extends HookWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.profileOf(context);
    final colors = context.appColors;

    final quote = useTextEditingController(text: profile.profile.quote ?? '');
    final busy = useState(false);

    Future<void> chooseImage() async {
      final path = await pickBackdrop();
      if (path == null) return;
      busy.value = true;
      try {
        await profile.setBackdrop(path);
      } finally {
        busy.value = false;
      }
    }

    return Scaffold(
      backgroundColor: profile.palette.bottomEdge,
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
            _SectionLabel('Your image', colors: colors),
            AppGap.smV,
            BackdropPicker(
              image: profile.backdrop,
              onTap: chooseImage,
              busy: busy.value,
              height: 200,
            ),
            AppGap.xsV,
            Text(
              'The app takes its colours from this photo.',
              style: AppTypography.caption.copyWith(color: colors.placeholder),
            ),

            AppGap.xlV,
            _SectionLabel('Your quote', colors: colors),
            AppGap.smV,
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.textBox,
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: colors.border),
              ),
              child: Padding(
                padding: AppInsets.md,
                child: TextField(
                  controller: quote,
                  maxLines: null,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTypography.body.copyWith(color: colors.textPrimary),
                  cursorColor: colors.primary,
                  // Saved on blur rather than behind a button: there's one
                  // field here and nothing to confirm.
                  onTapOutside: (_) {
                    FocusScope.of(context).unfocus();
                    if (quote.text.trim().isNotEmpty) profile.setQuote(quote.text);
                  },
                  onSubmitted: profile.setQuote,
                  decoration: InputDecoration.collapsed(
                    hintText: 'Your quote',
                    hintStyle: AppTypography.body.copyWith(
                      color: colors.placeholder,
                    ),
                  ),
                ),
              ),
            ),

            AppGap.xxlV,
            _CrisisResources(colors: colors),

            if (kDebugMode) ...[
              AppGap.xlV,
              OutlinedButton(
                onPressed: () async {
                  final journal = AppScope.journalOf(context);
                  await DebugSeed.run(AppScope.dbOf(context).journalEntryDb);
                  journal.refresh();
                },
                child: const Text('Seed sample logs'),
              ),
            ],

            AppGap.xlV,
            Center(
              child: GestureDetector(
                // The channel test harness is the only way to diagnose the
                // native speech/NLP layer on a real device. Hidden, not gone.
                onLongPress: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => const ChannelTestView(),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.colors});

  final String text;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.headline.copyWith(color: colors.textPrimary),
    );
  }
}

/// Never more than one tap from where the user is journalling. Froyou is a
/// self-help companion, not a clinical tool, and the difference has to be
/// visible rather than assumed.
class _CrisisResources extends StatelessWidget {
  const _CrisisResources({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: AppInsets.md,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'If you need support now',
              style: AppTypography.headline.copyWith(color: colors.textPrimary),
            ),
            AppGap.xsV,
            Text(
              'Froyou is a self-help companion, not a replacement for therapy.',
              style: AppTypography.footnote.copyWith(
                color: colors.textSecondary,
              ),
            ),
            AppGap.mdV,
            _ResourceRow(
              label: '988 Suicide & Crisis Lifeline',
              action: 'Call 988',
              onTap: () => launchUrl(Uri.parse('tel:988')),
              colors: colors,
            ),
            AppGap.smV,
            _ResourceRow(
              label: 'Crisis Text Line',
              action: 'Text HOME to 741741',
              onTap: () => launchUrl(Uri.parse('sms:741741?body=HOME')),
              colors: colors,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    required this.label,
    required this.action,
    required this.onTap,
    required this.colors,
  });

  final String label;
  final String action;
  final VoidCallback onTap;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.subheadline.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  action,
                  style: AppTypography.footnote.copyWith(color: colors.primary),
                ),
              ],
            ),
          ),
          Icon(CupertinoIcons.chevron_right, size: 14, color: colors.placeholder),
        ],
      ),
    );
  }
}
