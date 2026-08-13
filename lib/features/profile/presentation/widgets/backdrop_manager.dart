import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/edge_glow_image.dart';
import 'package:froyou/features/profile/data/backdrop.dart';
import 'package:froyou/features/profile/data/user_profile.dart';
import 'package:froyou/features/profile/presentation/profile_controller.dart';
import 'package:froyou/features/profile/presentation/widgets/backdrop_picker.dart';

/// Add, caption, reorder and remove the Home images.
///
/// Used by both Settings and onboarding, so the setup flow and the edit flow
/// are literally the same control rather than two that drift apart.
class BackdropManager extends StatefulWidget {
  const BackdropManager({required this.profile, super.key});

  final ProfileController profile;

  @override
  State<BackdropManager> createState() => _BackdropManagerState();
}

class _BackdropManagerState extends State<BackdropManager> {
  /// Keyed by image path rather than index: reordering and removal shuffle
  /// indices, and a controller following the wrong row would move the caption
  /// with it.
  final Map<String, TextEditingController> _captions = {};
  bool _busy = false;

  @override
  void dispose() {
    for (final controller in _captions.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String path, String? caption) {
    return _captions.putIfAbsent(
      path,
      () => TextEditingController(text: caption ?? ''),
    );
  }

  Future<void> _add() async {
    final path = await pickBackdrop();
    if (path == null) return;
    setState(() => _busy = true);
    try {
      await widget.profile.addBackdrop(path);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final backdrops = widget.profile.backdrops;

    // Drop controllers for images that are gone, so captions don't resurrect
    // if a path is ever reused.
    final live = {for (final backdrop in backdrops) backdrop.imagePath};
    _captions.removeWhere((path, controller) {
      if (live.contains(path)) return false;
      controller.dispose();
      return true;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (backdrops.isEmpty)
          BackdropPicker(image: null, onTap: _add, busy: _busy, height: 200)
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: backdrops.length,
            onReorderItem: widget.profile.reorderBackdrops,
            itemBuilder: (context, index) {
              final backdrop = backdrops[index];
              return Padding(
                key: ValueKey(backdrop.imagePath),
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        backgroundColor: colors.background,
                        showDragHandle: true,
                        isScrollControlled: true,
                        builder: (_) => BackdropFramingSheet(
                          profile: widget.profile,
                          index: index,
                        ),
                      ),
                      child: ClipRSuperellipse(
                        borderRadius: AppRadius.smAll,
                        child: Image(
                          image: widget.profile.providerFor(backdrop),
                          width: 64,
                          height: 64,
                          fit: backdrop.fit == BackdropFit.whole
                              ? BoxFit.contain
                              : BoxFit.cover,
                          alignment: Alignment(0, backdrop.focusY),
                          gaplessPlayback: true,
                          errorBuilder: (context, error, stack) => Container(
                            width: 64,
                            height: 64,
                            color: colors.textBox,
                            child: Icon(
                              CupertinoIcons.photo,
                              size: 18,
                              color: colors.placeholder,
                            ),
                          ),
                        ),
                      ),
                    ),
                    AppGap.smH,
                    Expanded(
                      child: TextField(
                        controller: _controllerFor(
                          backdrop.imagePath,
                          backdrop.caption,
                        ),
                        style: AppTypography.subheadline.copyWith(
                          color: colors.textPrimary,
                        ),
                        cursorColor: colors.primary,
                        textCapitalization: TextCapitalization.sentences,
                        // Committed on blur rather than per keystroke: each
                        // save writes the whole profile to preferences.
                        onTapOutside: (_) {
                          FocusScope.of(context).unfocus();
                          widget.profile.setCaption(
                            index,
                            _captions[backdrop.imagePath]?.text,
                          );
                        },
                        onSubmitted: (value) =>
                            widget.profile.setCaption(index, value),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Caption (optional)',
                          hintStyle: AppTypography.subheadline.copyWith(
                            color: colors.placeholder,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => widget.profile.removeBackdrop(index),
                      icon: Icon(
                        CupertinoIcons.minus_circle,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        if (backdrops.isNotEmpty && !widget.profile.profile.isFull) ...[
          AppGap.smV,
          OutlinedButton.icon(
            onPressed: _busy ? null : _add,
            icon: const Icon(CupertinoIcons.add, size: 16),
            label: const Text('Add another image'),
          ),
        ],
        if (widget.profile.profile.isFull) ...[
          AppGap.xsV,
          Text(
            'That\'s the maximum of ${UserProfile.maxBackdrops}.',
            style: AppTypography.caption.copyWith(color: colors.placeholder),
          ),
        ],
      ],
    );
  }
}

/// Choosing how one picture sits in the Home pane.
///
/// The pane is about 9:19.5 — taller than any camera produces — so every photo
/// has to give something up. Which thing is a judgement about that picture, and
/// this is where it gets made. Nothing here re-encodes the file: both controls
/// are stored alongside the image and applied at paint time, so "Fill" with the
/// slider centred is byte-for-byte what the picker handed over.
class BackdropFramingSheet extends HookWidget {
  const BackdropFramingSheet({
    required this.profile,
    required this.index,
    super.key,
  });

  final ProfileController profile;
  final int index;

  /// The preview's shape. Not the real pane's — that would be nearly a full
  /// screen — but the same proportions, so what is cropped here is what is
  /// cropped there.
  static const double _previewAspect = 9 / 19.5;

  @override
  Widget build(BuildContext context) {
    useListenable(profile);
    final colors = context.appColors;

    if (index < 0 || index >= profile.backdrops.length) {
      return const SizedBox.shrink();
    }
    final backdrop = profile.backdrops[index];
    final cropping = backdrop.fit == BackdropFit.fill;

    return SafeArea(
      child: Padding(
        padding: AppInsets.lg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'How this sits',
              textAlign: TextAlign.center,
              style: AppTypography.headline.copyWith(color: colors.textPrimary),
            ),
            AppGap.lgV,

            Center(
              child: SizedBox(
                height: 260,
                child: AspectRatio(
                  aspectRatio: _previewAspect,
                  child: ClipRSuperellipse(
                    borderRadius: AppRadius.mdAll,
                    child: EdgeGlowImage(
                      image: profile.providerFor(backdrop),
                      topColor: colors.background,
                      bottomColor: colors.background,
                      imageHeight: 260,
                      topGlowExtent: 0,
                      bottomGlowExtent: 0,
                      // The real pane blurs at 40 over a full screen. This box
                      // is a fraction of that height, so the same sigma would
                      // swallow the whole preview.
                      blurSigma: 12,
                      fit: cropping ? BoxFit.cover : BoxFit.contain,
                      focusY: backdrop.focusY,
                    ),
                  ),
                ),
              ),
            ),
            AppGap.lgV,

            Row(
              spacing: AppSpacing.sm,
              children: [
                for (final option in BackdropFit.values)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => profile.setFraming(index, fit: option),
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedContainer(
                        duration: AppDurations.fast,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: option == backdrop.fit
                              ? colors.textBox
                              : Colors.transparent,
                          borderRadius: AppRadius.smAll,
                        ),
                        child: Center(
                          child: Text(
                            option.label,
                            style: AppTypography.subheadline.copyWith(
                              color: option == backdrop.fit
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            AppGap.mdV,

            // Only means anything when something is actually being cut off.
            if (cropping) ...[
              Text(
                'What to keep',
                style: AppTypography.caption.copyWith(
                  color: colors.placeholder,
                ),
              ),
              Slider(
                value: backdrop.focusY,
                min: -1,
                max: 1,
                onChanged: (value) => profile.setFraming(index, focusY: value),
              ),
              Text(
                'Drag to choose which part of a tall crop survives.',
                style: AppTypography.caption.copyWith(
                  color: colors.placeholder,
                ),
              ),
            ] else
              Text(
                'The whole picture, with a blurred copy of itself filling the '
                'rest. Good for anything wide.',
                style: AppTypography.caption.copyWith(
                  color: colors.placeholder,
                ),
              ),

            AppGap.lgV,
            TextButton(
              onPressed: () =>
                  profile.setFraming(index, fit: BackdropFit.fill, focusY: 0),
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}
