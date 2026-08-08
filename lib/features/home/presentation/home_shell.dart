import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:froyou/app/app_scope.dart';
import 'package:froyou/core/theme/theme.dart';
import 'package:froyou/core/ui/noise_overlay.dart';
import 'package:froyou/features/home/presentation/compose_controller.dart';
import 'package:froyou/features/home/presentation/home_pane.dart';
import 'package:froyou/features/journal/presentation/log_card.dart';
import 'package:froyou/features/journal/presentation/logs_bar_delegate.dart';

/// Home and the logs list as one continuous surface.
///
/// A single [CustomScrollView] rather than two screens: the background
/// gradient and grain span the whole shell behind everything, so scrolling
/// down doesn't cross a boundary — the backdrop just slides up out of a
/// surface that keeps going.
///
/// The Home pane is a [SliverToBoxAdapter], not a [SliverPersistentHeader].
/// A persistent header re-lays-out and rebuilds its child on every scroll
/// frame, which would mean rebuilding the blur shader and the text field 60
/// times a second. A box adapter rebuilds zero times while scrolling — the
/// pane rasterizes once and the compositor just translates the layer.
class HomeShell extends HookWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.profileOf(context);
    final journal = AppScope.journalOf(context);
    final palette = profile.palette;

    final ticker = useSingleTickerProvider();
    final scroll = useScrollController();
    final chromeOpacity = useMemoized(() => ValueNotifier<double>(1));
    useEffect(() => chromeOpacity.dispose, [chromeOpacity]);

    final compose = useMemoized(
      () => ComposeController(vsync: ticker, onSave: journal.save),
      [ticker, journal],
    );
    useEffect(() => compose.dispose, [compose]);
    useListenable(compose);

    // Opening compose must start from the top: the pane's height changes with
    // the keyboard, and being mid-scroll while that happens is what would
    // otherwise produce a jump.
    compose.beforeOpen = () async {
      if (!scroll.hasClients || scroll.offset == 0) return;
      await scroll.animateTo(
        0,
        duration: AppDurations.normal,
        curve: Curves.easeOutCubic,
      );
    };

    // Read inside the scroll listener rather than captured, so the listener is
    // attached exactly once and still sees the current pane height.
    final paneHeightRef = useRef<double>(0);

    // Fades the quote and controls out over the first third of the scroll.
    // Driven through a ValueNotifier that only two small widgets listen to,
    // rather than by rebuilding the pane: the backdrop has to stay a static
    // cached layer or the progressive-blur shader re-composites every frame.
    useEffect(() {
      void update() {
        if (!scroll.hasClients) return;
        final fadeDistance = paneHeightRef.value * 0.35;
        if (fadeDistance <= 0) return;
        chromeOpacity.value = (1 - scroll.offset / fadeDistance).clamp(
          0.0,
          1.0,
        );
      }

      scroll.addListener(update);
      return () => scroll.removeListener(update);
    }, [scroll, chromeOpacity]);

    return LayoutBuilder(
      builder: (context, constraints) {
        final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
        // The pane shrinks with the keyboard, so the backdrop rises with it for
        // free — the framework already animates viewInsets over ~250ms.
        final paneHeight = math.max(
          240.0,
          constraints.maxHeight - keyboardInset,
        );
        paneHeightRef.value = paneHeight;

        return Scaffold(
          // Mandatory. Scaffold would otherwise shrink the body for the
          // keyboard *as well*, and the double shrink reads as a bug.
          resizeToAvoidBottomInset: false,
          backgroundColor: palette.bottomEdge,
          body: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        palette.bottomEdge,
                        palette.bottomEdge,
                        palette.bottomEdge,
                      ],
                      stops: const [0.0, 0.1, 1.0],
                    ),
                  ),
                ),
              ),
              // Spans the whole shell, not just the image: the background is a
              // huge, low-contrast gradient and is where banding actually shows.
              const Positioned.fill(
                child: RepaintBoundary(
                  child: NoiseOverlay(opacity: 0.03, density: 14),
                ),
              ),
              CustomScrollView(
                controller: scroll,
                physics: compose.isOpen
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                slivers: [
                  SliverToBoxAdapter(
                    child: HomePane(
                      height: paneHeight,
                      compose: compose,
                      palette: palette,
                      quote: profile.profile.quote ?? '',
                      backdrop: profile.backdrop,
                      chromeOpacity: chromeOpacity,
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: LogsBarDelegate(
                      background: palette.bottomEdge,
                      foreground: palette.colors.textPrimary,
                      border: palette.colors.border,
                      count: journal.count,
                      topPadding: MediaQuery.paddingOf(context).top,
                      onCompose: compose.openText,
                    ),
                  ),
                  if (journal.isEmpty)
                    const SliverToBoxAdapter(child: _EmptyLogs())
                  else
                    SliverList.builder(
                      itemCount: journal.count,
                      itemBuilder: (context, index) {
                        final entry = journal.entries[index];
                        return LogCard(
                          entry: entry,
                          isEnriching: index == 0 && journal.isEnriching,
                          onDelete: () => journal.delete(entry),
                        );
                      },
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyLogs extends StatelessWidget {
  const _EmptyLogs();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        children: [
          Icon(CupertinoIcons.mic, size: 32, color: colors.placeholder),
          AppGap.mdV,
          Text(
            'Nothing here yet.',
            style: AppTypography.callout.copyWith(color: colors.textSecondary),
          ),
          AppGap.xsV,
          Text(
            'Scroll back up and tap the mic to start.',
            textAlign: TextAlign.center,
            style: AppTypography.footnote.copyWith(color: colors.placeholder),
          ),
        ],
      ),
    );
  }
}
