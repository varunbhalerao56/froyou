import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/home/presentation/compose_controller.dart';
import 'package:froyou/features/home/presentation/transcript_view.dart';
import 'package:url_launcher/url_launcher.dart';

/// The text surface that slides up as the backdrop collapses.
///
/// Two surfaces, one box: while recording, [TranscriptView] renders the live
/// words and fades in each new one; once recording stops it is replaced by the
/// editable field so the user can fix what the recognizer heard before saving.
/// Nothing is handed across at that seam — the controller has been writing the
/// field's value all along — so the swap is purely which widget is mounted.
class ComposeBox extends StatelessWidget {
  const ComposeBox({required this.compose, super.key});

  final ComposeController compose;

  /// Caps the field's own height so a long transcript scrolls inside the box.
  /// Letting it grow would change the pane's height and break the invariant
  /// that compose only redistributes space, never adds it.
  static const double _maxFieldHeight = 168;

  /// What `TextField(minLines: 3)` comes out at. Applied to the transcript
  /// only, never to the field: the field already sizes itself this way, and
  /// imposing the same number as an outer constraint lands its vertically
  /// centred text on a different subpixel.
  static final double _minTranscriptHeight =
      AppTypography.composeInput.fontSize! *
      AppTypography.composeInput.height! *
      3;

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
          // No fill and no border: the field sits directly on the themed
          // background so writing feels like writing onto the page, not into a
          // widget. The caret and the text carry the affordance instead.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _maxFieldHeight),
            child: compose.isRecording
                ? TranscriptView(
                    words: compose.words,
                    accent: colors.primary,
                    hintColor: colors.placeholder,
                    minHeight: _minTranscriptHeight,
                    style: AppTypography.composeInput.copyWith(
                      color: colors.textPrimary,
                    ),
                  )
                : TextField(
                    controller: compose.text,
                    focusNode: compose.focusNode,
                    scrollController: compose.textScroll,
                    // Unconditional: after recording stops the field is not yet
                    // focused, and the static caret is what says it can now be
                    // edited. The default — caret only while focused — would
                    // leave the transcript looking inert.
                    showCursor: true,
                    maxLines: null,
                    minLines: 3,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    textAlign: TextAlign.center,
                    style: AppTypography.composeInput.copyWith(
                      color: colors.textPrimary,
                    ),
                    cursorColor: colors.primary,
                    decoration: InputDecoration.collapsed(
                      hintText: "What's on your mind?",
                      hintStyle: AppTypography.composeInput.copyWith(
                        color: colors.placeholder,
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
