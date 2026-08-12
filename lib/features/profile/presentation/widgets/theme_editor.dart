import 'package:flutter/material.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/features/profile/presentation/profile_controller.dart';

/// The theme section of Settings: a preset, and light or dark.
///
/// Deliberately quiet, and deliberately two decisions rather than three. A
/// separate accent picker on top of a preset meant choosing a colour and then
/// choosing a second colour over it — twice the work to arrive somewhere the
/// presets already went. The preset now owns its accent at both brightnesses,
/// so picking one is the whole choice.
///
/// Every control writes straight through to [ProfileController], which sits
/// above `MaterialApp` — so the whole app recolours as you go. There is no
/// preview swatch to keep in sync because the preview is the app itself.
class ThemeEditor extends StatelessWidget {
  const ThemeEditor({required this.profile, super.key});

  final ProfileController profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    // Only the swatch row runs to the card's edges; everything else insets
    // itself so it lines up with the section's title.
    const inset = EdgeInsets.symmetric(horizontal: AppSpacing.lg);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PresetRow(profile: profile, colors: colors),
        AppGap.lgV,
        Padding(
          padding: inset,
          child: _Label('Appearance', colors: colors),
        ),
        AppGap.smV,
        Padding(
          padding: inset,
          child: _AppearanceRow(profile: profile, colors: colors),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.colors});

  final String text;
  final AppColors colors;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTypography.footnote.copyWith(color: colors.textSecondary),
  );
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.profile, required this.colors});

  final ProfileController profile;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final selectedId = profile.themeSettings.presetId;
    final brightness = profile.palette.brightness;

    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: ThemePresets.all.length,
        separatorBuilder: (_, _) => AppGap.mdH,
        itemBuilder: (context, index) {
          final preset = ThemePresets.all[index];
          final selected = preset.id == selectedId;

          return GestureDetector(
            onTap: () => profile.setPreset(preset.id),
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Dot(
                  // The swatch shows the preset at the brightness currently in
                  // effect, so what you tap is what you get.
                  color: preset.surfaceFor(brightness),
                  inner: preset.accentFor(brightness),
                  selected: selected,
                  colors: colors,
                ),
                AppGap.xsV,
                Text(
                  preset.name,
                  style: AppTypography.caption.copyWith(
                    color: selected ? colors.textPrimary : colors.placeholder,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A preset swatch: the surface, with its accent as the pupil.
class _Dot extends StatelessWidget {
  const _Dot({
    required this.color,
    required this.selected,
    required this.colors,
    this.inner,
  });

  static const double size = 52;

  final Color color;
  final Color? inner;
  final bool selected;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDurations.fast,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          // A soft ring on the selected one only; the unselected swatches carry
          // no outline at all, which is what keeps the row calm.
          color: selected ? colors.textPrimary : colors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: Center(
        child: inner == null
            ? null
            : Container(
                width: size * 0.38,
                height: size * 0.38,
                decoration: BoxDecoration(color: inner, shape: BoxShape.circle),
              ),
      ),
    );
  }
}

class _AppearanceRow extends StatelessWidget {
  const _AppearanceRow({required this.profile, required this.colors});

  final ProfileController profile;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    const options = {
      ThemeBrightnessMode.system: 'Auto',
      ThemeBrightnessMode.light: 'Light',
      ThemeBrightnessMode.dark: 'Dark',
    };
    final selected = profile.themeSettings.brightnessMode;

    return Row(
      spacing: AppSpacing.sm,
      children: [
        for (final option in options.entries)
          Expanded(
            child: GestureDetector(
              onTap: () => profile.setBrightnessMode(option.key),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: AppDurations.fast,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  // textBox, not card: these pills now sit *on* a card, so
                  // selecting one has to step further from the background
                  // rather than land on the surface it is already drawn on.
                  color: option.key == selected
                      ? colors.textBox
                      : Colors.transparent,
                  borderRadius: AppRadius.smAll,
                ),
                child: Center(
                  child: Text(
                    option.value,
                    style: AppTypography.subheadline.copyWith(
                      color: option.key == selected
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
