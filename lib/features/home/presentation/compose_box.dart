import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/home/presentation/compose_controller.dart';
import 'package:url_launcher/url_launcher.dart';

/// The text surface that slides up as the backdrop collapses.
///
/// Same field for both paths: while recording it is read-only and written to
/// by the transcript stream; once recording stops it becomes editable so the
/// user can fix what the recognizer heard before saving.
class ComposeBox extends StatelessWidget {
  const ComposeBox({required this.compose, super.key});

  final ComposeController compose;

  /// Caps the field's own height so a long transcript scrolls inside the box.
  /// Letting it grow would change the pane's height and break the invariant
  /// that compose only redistributes space, never adds it.
  static const double _maxFieldHeight = 168;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compose.error != null) _ErrorBanner(compose: compose),
          if (compose.downloadFraction != null)
            _DownloadBar(fraction: compose.downloadFraction!),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.textBox.withValues(alpha: 0.86),
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: colors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _maxFieldHeight),
                child: TextField(
                  controller: compose.text,
                  focusNode: compose.focusNode,
                  scrollController: compose.textScroll,
                  // Read-only during recording so the IME doesn't fight the
                  // programmatic writes coming off the transcript stream.
                  readOnly: compose.isRecording,
                  showCursor: !compose.isRecording,
                  maxLines: null,
                  minLines: 3,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTypography.body.copyWith(color: colors.textPrimary),
                  cursorColor: colors.primary,
                  decoration: InputDecoration.collapsed(
                    hintText: compose.isRecording
                        ? 'Listening…'
                        : "What's on your mind?",
                    hintStyle: AppTypography.body.copyWith(
                      color: colors.placeholder,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.compose});

  final ComposeController compose;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              compose.error!,
              style: AppTypography.footnote.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          if (compose.errorIsPermissions)
            TextButton(
              onPressed: () => launchUrl(Uri.parse('app-settings:')),
              child: const Text('Settings'),
            )
          else
            IconButton(
              onPressed: compose.dismissError,
              icon: Icon(
                CupertinoIcons.xmark,
                size: 14,
                color: colors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _DownloadBar extends StatelessWidget {
  const _DownloadBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Getting the on-device speech model ready…',
            style: AppTypography.caption.copyWith(color: colors.textSecondary),
          ),
          AppGap.xsV,
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: fraction, minHeight: 3),
          ),
        ],
      ),
    );
  }
}
