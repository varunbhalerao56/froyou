import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/backdrop_photo.dart';
import 'package:froyou/features/profile/data/user_profile.dart';
import 'package:froyou/features/profile/presentation/profile_controller.dart';
import 'package:froyou/features/profile/presentation/widgets/backdrop_framing_view.dart';
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
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => BackdropFramingView(
                            profile: widget.profile,
                            index: index,
                          ),
                        ),
                      ),
                      // The pane's shape rather than a square, and drawn the
                      // way Home draws it: the row is then a list of what each
                      // picture will actually look like, which is the thing
                      // being edited.
                      child: SizedBox(
                        // 40:86 is the pane's own 9:19.5, near enough. A
                        // square would be the wrong shape to judge a crop in.
                        width: 40,
                        height: 86,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRSuperellipse(
                              borderRadius: AppRadius.smAll,
                              child: BackdropPhoto(
                                image: widget.profile.providerFor(backdrop),
                                fit: backdrop.framing.baseFit,
                                zoom: backdrop.framing.zoom,
                                offset: backdrop.framing.offset,
                                bleedSigma: 6,
                                fallback: ColoredBox(
                                  color: colors.textBox,
                                  child: Icon(
                                    CupertinoIcons.photo,
                                    size: 16,
                                    color: colors.placeholder,
                                  ),
                                ),
                              ),
                            ),
                            // The one mark that says a photograph is a button.
                            // The subtitle above says so in words; a row of
                            // pictures needs it said on the picture too.
                            Positioned(
                              right: 3,
                              bottom: 3,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.background.withValues(
                                    alpha: 0.72,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(3),
                                  child: Icon(
                                    CupertinoIcons
                                        .arrow_up_left_arrow_down_right,
                                    size: 10,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ],
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
