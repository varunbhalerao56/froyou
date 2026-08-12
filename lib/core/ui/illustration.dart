import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../logging/app_log.dart';
import '../theme/theme.dart';

/// The onboarding artwork, by role rather than by filename.
///
/// Four drawings from unDraw, refetched by `tool/fetch_illustrations.sh`. The
/// files in `assets/illustrations/` are not standalone SVGs — every fill has
/// been rewritten to a token, and [IllustrationView] resolves those against the
/// live palette. See the tool for why.
enum Illustration {
  /// A figure at a lit window with a flower field behind the glass. It is the
  /// app icon as a scene, which is why it opens the intro.
  reflection('reflection'),

  /// A figure walking with their own data kept beside them, under a lock.
  onDevice('on-device'),

  /// A figure alone on a bench, looking out. Self-directed, not clinical —
  /// which is the distinction that page is drawing.
  companion('companion'),

  /// A phone showing a waveform mid-recording.
  firstLog('first-log');

  const Illustration(this.name);

  final String name;

  String get asset => 'assets/illustrations/$name.svg';
}

/// Where each token sits between the page and its text, as a lerp factor.
///
/// The whole reason the art survives a theme change is that this ramp is
/// anchored at [AppColors.background] and [AppColors.textPrimary] rather than
/// at black and white. Those two have already swapped by the time dark mode is
/// resolved, so the drawing inverts with the page for free — the near-white
/// paper of the original becomes the darkest tone, and the near-black figure
/// becomes the lightest, with no second set of assets.
///
/// The values keep unDraw's own luminance order so the drawing still reads as
/// the drawing; they are compressed toward the page because a full-strength
/// version of a flat illustration shouts on a surface this quiet.
///
/// `tool/fetch_illustrations.sh --preview` hard-codes these numbers to rasterize
/// a preview. Change them here and change them there.
const Map<String, double> _ramp = {
  '__SURFACE_HI__': 0.035,
  '__SURFACE__': 0.08,
  '__SURFACE_DIM__': 0.13,
  '__MUTED__': 0.22,
  '__SKIN__': 0.34,
  '__SKIN_DEEP__': 0.52,
  '__INK_SOFT__': 0.74,
  '__INK__': 1.0,
};

/// One of the [Illustration]s, coloured by the current theme.
///
/// Sizes to the width it is given and keeps the drawing's own aspect ratio, so
/// the caller controls the height by constraining the box — see how the intro
/// hands it a fraction of the viewport.
class IllustrationView extends HookWidget {
  const IllustrationView({
    required this.illustration,
    this.semanticLabel,
    super.key,
  });

  final Illustration illustration;

  /// Left null for decoration, which is what these are: every page states its
  /// point in the headline directly underneath. A label here would only make a
  /// screen reader announce the same thing twice.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    // Keyed on the asset alone. `loadString` caches, so this is a real future
    // exactly once per asset per process and a resolved one afterwards — which
    // is what stops a theme change from blanking the art for a frame.
    final source = useMemoized(() => _load(illustration.asset), [illustration]);
    final snapshot = useFuture(source, initialData: null);
    final raw = snapshot.data;

    // Cheap enough to redo whenever the palette moves: a dozen replaces over
    // ~20KB. flutter_svg caches the parsed picture against the resulting
    // string, so an unchanged theme re-renders without re-parsing.
    final resolved = useMemoized(
      () => raw == null ? null : resolve(raw, colors),
      [raw, colors],
    );

    return AnimatedSwitcher(
      duration: AppDurations.normal,
      child: resolved == null
          // Holds the slot rather than collapsing it, so the headline below
          // doesn't jump when the first frame after load arrives. Needs bounded
          // constraints from the caller — the intro gives it a fixed height.
          ? const SizedBox.expand(key: ValueKey('illustration-pending'))
          : SvgPicture.string(
              resolved,
              key: ValueKey(illustration),
              fit: BoxFit.contain,
              semanticsLabel: semanticLabel,
              excludeFromSemantics: semanticLabel == null,
            ),
    );
  }

  /// Swallows a missing or unreadable asset rather than throwing.
  ///
  /// These are decoration on a page that states its point in words directly
  /// underneath, so the page is still the page without them — and losing the
  /// intro to a bad bundle would be an absurd way to lose someone on their
  /// first launch.
  static Future<String?> _load(String asset) async {
    try {
      return await rootBundle.loadString(asset);
    } catch (error, stackTrace) {
      AppLog.error('illustration', 'could not load $asset', error, stackTrace);
      return null;
    }
  }

  /// Every role the resolver can substitute.
  ///
  /// The contract between `assets/illustrations/` and this file: a refetched
  /// drawing that introduced a role not listed here would keep its token
  /// through [resolve] and land in the SVG as `fill="__SOMETHING__"`, which
  /// flutter_svg discards without complaint — an invisible shape in the output
  /// and nothing at all in the console. The test walks the assets against this.
  @visibleForTesting
  static Set<String> get roles => {
    ..._ramp.keys,
    '__ACCENT__',
    '__ACCENT_SOFT__',
  };

  @visibleForTesting
  static String resolve(String svg, AppColors colors) {
    var out = svg;
    for (final MapEntry(key: token, value: t) in _ramp.entries) {
      out = out.replaceAll(
        token,
        _hex(Color.lerp(colors.background, colors.textPrimary, t)!),
      );
    }
    // The accent stays the accent — it is the one part of the drawing allowed
    // to carry colour, and it is already contrast-corrected for this surface.
    // Its softer partner is the same hue held back toward the page, rather than
    // unDraw's pink, which belongs to no preset here.
    return out
        .replaceAll(
          '__ACCENT_SOFT__',
          _hex(Color.lerp(colors.background, colors.primary, 0.55)!),
        )
        .replaceAll('__ACCENT__', _hex(colors.primary));
  }

  /// Every fill in these files is opaque and `fill` takes no alpha, so only the
  /// RGB triplet is written.
  static String _hex(Color color) {
    String channel(double v) =>
        (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${channel(color.r)}${channel(color.g)}${channel(color.b)}';
  }
}
