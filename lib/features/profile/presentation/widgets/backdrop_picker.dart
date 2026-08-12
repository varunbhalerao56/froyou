import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:froyou/core/logging/app_log.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:image_picker/image_picker.dart';

/// Opens the photo library and returns the picked file's path, or null if the
/// user backed out.
///
/// `requestFullMetadata: false` takes the PHPicker path, which hands back one
/// chosen image without the app ever asking for photo-library authorization.
///
/// The size caps matter beyond politeness: the picked file is copied into app
/// storage and then decoded for palette derivation, so capping it here is the
/// difference between a 1MB asset and an 8MB one.
Future<String?> pickBackdrop() async {
  try {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
      requestFullMetadata: false,
    );
    return picked?.path;
  } catch (e, stackTrace) {
    AppLog.error('Profile', 'image picker failed', e, stackTrace);
    return null;
  }
}

/// Tappable image well used by both onboarding and settings.
class BackdropPicker extends StatelessWidget {
  const BackdropPicker({
    required this.image,
    required this.onTap,
    this.busy = false,
    this.height = 260,
    super.key,
  });

  final ImageProvider? image;
  final VoidCallback onTap;
  final bool busy;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return GestureDetector(
      onTap: busy ? null : onTap,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ClipRSuperellipse(
          borderRadius: AppRadius.lgAll,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.textBox,
              border: Border.all(color: colors.border),
              borderRadius: AppRadius.lgAll,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (image != null)
                  Image(
                    image: image!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                if (image == null)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.photo,
                          size: 30,
                          color: colors.placeholder,
                        ),
                        AppGap.smV,
                        Text(
                          'Choose a photo',
                          style: AppTypography.callout.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: AppInsets.sm,
                      child: _ChangeChip(colors: colors),
                    ),
                  ),
                if (busy)
                  ColoredBox(
                    color: colors.background.withValues(alpha: 0.6),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChangeChip extends StatelessWidget {
  const _ChangeChip({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: 0.85),
        borderRadius: AppRadius.smAll,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          'Change',
          style: AppTypography.caption.copyWith(color: colors.textPrimary),
        ),
      ),
    );
  }
}
