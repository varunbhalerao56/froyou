import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:froyou/features/home/data/transcript_words.dart';

/// The live transcript while recording, in place of the text field.
///
/// Words fade in as they arrive rather than appearing in hard jumps. The
/// controller driving that stops by the only mechanism that can't be
/// forgotten: this widget is built only while `compose.isRecording`, so ending
/// a session unmounts it and the ticker with it.
///
/// Takes plain data rather than the controller so it can be pumped standalone.
class TranscriptView extends HookWidget {
  const TranscriptView({
    required this.words,
    required this.style,
    required this.accent,
    required this.hintColor,
    required this.minHeight,
    this.hint = 'Listening…',
    super.key,
  });

  final TranscriptWords words;

  /// Must carry a colour — its alpha is what the fade animates.
  final TextStyle style;

  /// The contrast-corrected accent (`colors.primary`), not the raw swatch.
  final Color accent;

  final Color hintColor;
  final String hint;

  /// Floor for the box, matching what the editable field comes out at with
  /// `minLines: 3` — so ending a recording swaps the widget without resizing
  /// anything around it.
  final double minHeight;

  /// The clock the word fade is measured against. Nothing sweeps on it any
  /// more; [_FadingWords] only wants `lastElapsedDuration`, which keeps
  /// growing across repeats and so is monotonic for the whole session.
  static const Duration pulsePeriod = Duration(milliseconds: 2600);

  /// How long a single word takes to reach full opacity.
  static const int fadeMs = 220;

  /// Offset between words that arrive in the same batch, so a settled sentence
  /// reveals left to right instead of flashing in as a block.
  static const int staggerMs = 40;

  @override
  Widget build(BuildContext context) {
    final pulse = useAnimationController(duration: pulsePeriod);

    useEffect(() {
      pulse.repeat(reverse: true);
      return pulse.stop;
    }, [pulse]);

    // Birth times, keyed on word id. Lives exactly as long as the recording
    // session — the view is unmounted at handoff — so it never needs pruning.
    final birth = useRef(<int, Duration>{});

    final scroll = useScrollController();
    final wordCount = words.words.length;
    useEffect(() {
      // Post-frame, because the new line hasn't been laid out yet and
      // maxScrollExtent is still the previous value.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scroll.hasClients) return;
        scroll.jumpTo(scroll.position.maxScrollExtent);
      });
      return null;
    }, [wordCount, scroll]);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: SingleChildScrollView(
        controller: scroll,
        // The transcript follows itself; letting it be dragged would only
        // fight the auto-scroll and the shell's own scroll view.
        physics: const NeverScrollableScrollPhysics(),
        child: wordCount == 0
            ? Text(
                hint,
                textAlign: TextAlign.center,
                style: style.copyWith(color: hintColor),
              )
            : _FadingWords(
                pulse: pulse,
                words: words,
                birth: birth.value,
                style: style,
              ),
      ),
    );
  }
}

/// The paragraph itself, rebuilt every frame off the shared controller.
///
/// One [Text.rich] whose spans differ only in colour. That is deliberate:
/// `TextStyle.compareTo` reports a colour-only change as `RenderComparison
/// .paint`, so `RenderParagraph` marks itself needing paint rather than
/// needing layout — the per-frame fade costs a repaint, and the text re-lays-out
/// only when a word actually arrives. A column of per-word widgets would lose
/// text-metrics parity with the field it hands off to, and reflow at the seam.
class _FadingWords extends AnimatedWidget {
  const _FadingWords({
    required this.pulse,
    required this.words,
    required this.birth,
    required this.style,
  }) : super(listenable: pulse);

  final AnimationController pulse;
  final TranscriptWords words;
  final Map<int, Duration> birth;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // The controller's own elapsed time, which keeps growing across repeat
    // cycles — so it is a monotonic clock for the whole session, unlike value.
    final now = pulse.lastElapsedDuration ?? Duration.zero;
    final list = words.words;
    final color = style.color ?? const Color(0xFF000000);

    var fresh = 0;
    final spans = <InlineSpan>[];
    for (var index = 0; index < list.length; index++) {
      final word = list[index];
      // Assigned once, on the first frame that sees this word. The increment
      // runs only for genuinely new words, so a batch staggers and the words
      // already on screen are untouched.
      final born = birth[word.id] ??=
          now + Duration(milliseconds: TranscriptView.staggerMs * fresh++);

      // A staggered word's birth is in the future, so this clamps to 0 and it
      // simply waits its turn.
      final progress = ((now - born).inMilliseconds / TranscriptView.fadeMs)
          .clamp(0.0, 1.0);

      spans.add(
        TextSpan(
          text: index == list.length - 1 ? word.text : '${word.text} ',
          style: style.copyWith(color: color.withValues(alpha: progress)),
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.center,
      style: style,
    );
  }
}

/// A soft accent blob travelling across the transcript.
///
/// Radial rather than linear because it is soft at every edge — no ShaderMask
/// and no saveLayer to keep it from reading as a filled panel, which matters
/// because the compose field deliberately has no surface of its own.
