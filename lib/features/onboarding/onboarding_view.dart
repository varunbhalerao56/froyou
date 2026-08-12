import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/illustration.dart';
import 'package:froyou/core/ui/noise_overlay.dart';
import 'package:froyou/features/onboarding/widgets/onboarding_page.dart';
import 'package:froyou/features/profile/presentation/widgets/backdrop_manager.dart';

/// First launch: what this is · where your words stay · what it isn't · your
/// pictures · your first log.
///
/// No theme picker, on purpose. The app starts neutral and follows the
/// system's light/dark setting, so it already looks right — asking someone to
/// choose an accent colour before they've written a word is a decision in the
/// way of the one that matters. Theming lives in Settings, for whenever they
/// feel like looking.
///
/// A `PageView` rather than pushed routes: onboarding has no navigator of its
/// own, and finishing is a profile write that swaps the root — so there is no
/// stack to unwind, and paging back and forth costs nothing.
class OnboardingView extends HookWidget {
  const OnboardingView({super.key});

  /// The images step. The only one that gates progress.
  static const int _imagesPage = 3;
  static const int _pageCount = 5;

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.profileOf(context);
    final colors = context.appColors;

    final controller = usePageController();
    final index = useState(0);
    final busy = useState(false);

    Future<void> finish({required bool startRecording}) async {
      busy.value = true;
      try {
        await profile.completeOnboarding(startRecording: startRecording);
      } finally {
        // Success swaps the root — see the class comment — so by the time this
        // runs the view is gone and the hook's notifier has been disposed with
        // it. The flag only has somewhere to go back to when the write failed.
        if (context.mounted) busy.value = false;
      }
    }

    void next() => controller.nextPage(
      duration: AppDurations.normal,
      curve: Curves.easeOutCubic,
    );

    // One image is the single thing onboarding insists on. Blocking the swipe
    // as well as the button matters — otherwise the gate is trivially bypassed
    // and the last page offers to record over an unconfigured home screen.
    final blocked = index.value == _imagesPage && !profile.profile.isComplete;
    final isLast = index.value == _pageCount - 1;

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: RepaintBoundary(
              child: NoiseOverlay(opacity: 0.03, density: 14),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: controller,
                    physics: blocked
                        ? const NeverScrollableScrollPhysics()
                        : const BouncingScrollPhysics(),
                    onPageChanged: (page) => index.value = page,
                    children: [
                      const OnboardingPage(
                        illustration: Illustration.reflection,
                        title: 'Say what’s on your mind.',
                        body:
                            'Talk or type, whenever it helps. Froyou keeps '
                            'what you say and notices what you keep coming '
                            'back to — even when the words come out '
                            'differently every time.',
                      ),
                      const OnboardingPage(
                        illustration: Illustration.onDevice,
                        title: 'Everything stays on this device.',
                        body:
                            'Nothing you write is uploaded. Transcription, '
                            'sense-making, all of it runs on your iPhone, '
                            'offline — because a journal you have to trust '
                            'someone else with isn’t much of a journal.',
                      ),
                      const OnboardingPage(
                        illustration: Illustration.companion,
                        title: 'A companion, not a replacement.',
                        body:
                            'Froyou is a self-help tool. It isn’t therapy, and '
                            'it isn’t a crisis service. Crisis resources stay '
                            'one tap away in Settings, whenever you need them.',
                      ),
                      // No drawing here — the pictures the page is asking for
                      // are the ones that belong on it.
                      OnboardingPage(
                        title: 'Pick a few pictures that make you feel good.',
                        body:
                            'They’ll drift quietly on your home screen. Add a '
                            'caption if the picture needs one — most don’t.',
                        child: BackdropManager(profile: profile),
                      ),
                      const OnboardingPage(
                        illustration: Illustration.firstLog,
                        title: 'Try your first log.',
                        body:
                            'Tap below and just talk — a sentence is plenty. '
                            'iOS will ask for the microphone first: Froyou '
                            'needs it to turn what you say into text, here on '
                            'your phone.',
                      ),
                    ],
                  ),
                ),
                _Dots(index: index.value, count: _pageCount, colors: colors),
                AppGap.lgV,
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: isLast
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton(
                              onPressed: busy.value
                                  ? null
                                  : () => finish(startRecording: true),
                              child: const Text('Record my first log'),
                            ),
                            TextButton(
                              onPressed: busy.value
                                  ? null
                                  : () => finish(startRecording: false),
                              child: const Text('Maybe later'),
                            ),
                          ],
                        )
                      : SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: blocked || busy.value ? null : next,
                            child: const Text('Continue'),
                          ),
                        ),
                ),
                AppGap.lgV,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Position within the intro. The same soft-circle vocabulary as the theme
/// editor's swatches, so the app reads as one thing from the first screen.
class _Dots extends StatelessWidget {
  const _Dots({required this.index, required this.count, required this.colors});

  final int index;
  final int count;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: AppSpacing.sm,
      children: [
        for (var page = 0; page < count; page++)
          AnimatedContainer(
            duration: AppDurations.fast,
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: page == index ? colors.textPrimary : colors.border,
            ),
          ),
      ],
    );
  }
}
