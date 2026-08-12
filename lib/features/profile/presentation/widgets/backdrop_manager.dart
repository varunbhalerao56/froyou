import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:froyou/core/theme/theme.dart';
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
                    ClipRSuperellipse(
                      borderRadius: AppRadius.smAll,
                      child: Image(
                        image: widget.profile.providerFor(backdrop),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
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
