import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/noise_overlay.dart';
import 'package:froyou/features/profile/presentation/widgets/backdrop_picker.dart';

/// First launch. The user sets the image and quote everything else is built
/// around — the theme is derived from the image the moment it's picked, so the
/// screen recolors under them as they choose.
class OnboardingView extends HookWidget {
  const OnboardingView({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.profileOf(context);
    final colors = context.appColors;

    final quote = useTextEditingController(text: profile.profile.quote ?? '');
    useListenable(quote);

    final busy = useState(false);

    final canContinue =
        profile.profile.hasImage &&
        quote.text.trim().isNotEmpty &&
        !busy.value;

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

    Future<void> finish() async {
      busy.value = true;
      try {
        await profile.setQuote(quote.text);
        await profile.completeOnboarding();
      } finally {
        busy.value = false;
      }
    }

    return Scaffold(
      backgroundColor: profile.palette.bottomEdge,
      body: Stack(
        children: [
          const Positioned.fill(
            child: RepaintBoundary(
              child: NoiseOverlay(opacity: 0.03, density: 14),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Set an image and a quote that makes you feel good everytime you think of it!',
                    style: AppTypography.title2.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  AppGap.smV,
                  Text(
                    'Your photo colours the whole app.',
                    style: AppTypography.subheadline.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  AppGap.xlV,
                  BackdropPicker(
                    image: profile.backdrop,
                    onTap: chooseImage,
                    busy: busy.value,
                  ),
                  AppGap.lgV,
                  _QuoteField(controller: quote, colors: colors),
                  AppGap.xlV,
                  FilledButton(
                    onPressed: canContinue ? finish : null,
                    child: const Text('Continue'),
                  ),
                  AppGap.mdV,
                  Text(
                    'Froyou is a self-help companion, not a replacement for therapy.',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(
                      color: colors.placeholder,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteField extends StatelessWidget {
  const _QuoteField({required this.controller, required this.colors});

  final TextEditingController controller;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.textBox,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: AppInsets.md,
        child: TextField(
          controller: controller,
          maxLines: null,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
          style: AppTypography.body.copyWith(color: colors.textPrimary),
          cursorColor: colors.primary,
          decoration: InputDecoration.collapsed(
            hintText: 'Your quote',
            hintStyle: AppTypography.body.copyWith(color: colors.placeholder),
          ),
        ),
      ),
    );
  }
}
