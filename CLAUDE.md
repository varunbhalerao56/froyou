# Froyou

A local-first, iOS-only CBT/rumination journaling app. You talk or type a log;
the app notices what you keep coming back to across entries — even when the
wording changes every time — and reflects that back.

**Everything runs on-device.** Transcription, sentiment, embeddings, clustering
and theme-naming all use Apple frameworks. Nothing is sent anywhere. That is a
product promise, not an implementation detail: don't add a network call without
raising it first.

**iOS 26 only.** Deployment target is 26.0. Android is explicitly out of scope.

---

## Running it

```bash
flutter run                                  # needs a booted iOS 26 simulator or device
flutter run --dart-define=SEED_DEMO=true     # + 12 believable clustered logs
flutter analyze                              # must be clean
flutter test                                 # ~210 tests, ~3.5min — scope it
flutter test test/features/journal/          # run only what you changed
flutter test --update-goldens                # after any deliberate visual change

./tool/render_icon.sh                        # app icon    ← assets/brand/app-icon.svg
./tool/render_splash.sh                      # launch screen ← splash-mark.svg
./tool/fetch_illustrations.sh --preview      # intro art   ← unDraw, then look at it
```

Settings has a **Developer** section — *Preview follow-up question*, which runs
the real prompt against your latest log without waiting for the day-after and
mood gates that normally trigger it, and *Seed sample logs*. Both ship rather
than being `kDebugMode`-gated, because both are how the thing gets demonstrated.

Long-pressing the version label opens `DebugMenuView` → `ChannelTestView`, the only way to
exercise the native speech/NLP/genai layer directly on a device, and the
**Home layouts** gallery, which switches the arrangement live.

At boot in debug you'll see `[boot] genai available=…`. Whether themes get
named by the language model or the statistical fallback is invisible from the
UI, so that line is usually the first thing to check when labels look wrong.

`kModelOnlyLabels` (`core/config/label_mode.dart`, currently **on**) switches
every statistical fallback off, so blank keywords and unnamed themes mean the
model declined rather than quietly filling in. `--dart-define=MODEL_ONLY_LABELS=false`
restores the shipping behaviour.

---

## Architecture

```
lib/
  main.dart                 bootstrap: prefs → schema wipe → DB → runApp
  app/
    froyou_app.dart         FroyouRoot; owns controllers; MaterialApp
    app_scope.dart          DI: InheritedNotifier ×2 + a plain InheritedWidget
                            (db + ReminderService — fixed for the process, so
                            reading them registers no dependency)
  core/
    theme/                  AppColors, AppPalette, ThemePresets, ThemeSettings,
                            AppTypography (SF Pro Rounded), spacing/radius
    ui/                     EdgeGlowImage, LivingBackdrop, NoiseOverlay,
                            Illustration + IllustrationView, color_utils
  features/
    home/                   HomeShell (Home + Logs as one scroll), HomePane,
                            HomeLayout ×5, compose, TranscriptWords +
                            TranscriptView, BackdropCarousel, FollowUpService
    journal/                ObjectBox entities, JournalEntryDb, save pipeline,
                            ClusterLabeler (fallback), ClusterNamer and
                            KeywordNamer (model-first)
    onboarding/             the paged first-run flow
    profile/                backdrops, theme settings, settings
    reminders/              ReminderSettings, ReminderService, Settings section
    analytics/              AnalyticsService + view
    debug/                  seed data, debug menu, channel test, layout gallery
  services/                 speech_service, nlp_service, genai_service, db_service
assets/brand/               app-icon.svg, splash-mark.svg — both in vector
assets/illustrations/       the intro's four drawings, tokenized (see README)
tool/                       render_icon.sh, render_splash.sh,
                            fetch_illustrations.sh, svg2png.swift
ios/Runner/                 SpeechChannel, NlpChannel, GenAiChannel (+ support)
```

**The app icon is generated, not drawn.** `assets/brand/app-icon.svg` is the
source; `./tool/render_icon.sh` rasterizes it and overwrites all fifteen PNGs in
`AppIcon.appiconset`. Don't edit those by hand — the next run will silently
undo it. Only the 1024 comes from vector and the rest are Lanczos downsamples
of it, because re-rendering the SVG at 40px puts the bezel highlight and the
turbulence field below a pixel each and simply drops them.

It is a porthole onto the app's own backdrop, and the field behind the glass
dissolves on `EdgeGlowImage`'s real stops rather than on something eyeballed to
look similar — if those numbers change, the icon is meant to change with them.
`xcrun actool --compile` is the cheap way to check the catalog still builds
without waiting on a full `flutter build ios`.

**The launch screen is the same mark with the room taken away.**
`assets/brand/splash-mark.svg` is app-icon.svg minus its ground and grain, at
identical coordinates, and `./tool/render_splash.sh` is the only supported way
to regenerate it — see the note under "Things that will bite you" about running
`flutter_native_splash:create` on its own. The background is the Paper preset's
surface at both brightnesses, which is what the app boots into, so the handover
from storyboard to first Flutter frame has nothing to give it away. `main.dart`
defers that first frame until `runApp`, in a `finally` so a failed boot still
gets its error screen.

**State:** `flutter_hooks` + `ChangeNotifier` behind `AppScope`.

`AppScope` sits **above** `MaterialApp` on purpose, so a theme change repaints
every route on the stack. Because `AppColors.lerp` is implemented, that's an
animated transition for free via the framework's own `AnimatedTheme`.

**Navigation:** plain `Navigator.push(CupertinoPageRoute(...))`. No go_router.

---

## The three native channels

| Channel | Shape | Notes |
|---|---|---|
| `app/speech` | EventChannel + MethodChannel | iOS 26 `SpeechTranscriber`. Streaming needs an event channel; the split is deliberate. |
| `app/nlp` | MethodChannel | `NLTokenizer`, `NLTagger`, `NLContextualEmbedding` (512-dim). |
| `app/genai` | MethodChannel | `SystemLanguageModel` via Foundation Models, `@Generable` guided generation. |

All three follow the same shape: `register(with:)`, `ChannelReply` from
`FlutterChannelSupport.swift` (single-use, main-thread-safe), a stable
error-code enum matched in Dart, and work off the platform thread.

**Adding a Swift file requires editing `project.pbxproj` in four places** — the
project uses explicit file references, not a synchronized folder group. See how
`GenAiChannel.swift` is registered.

---

## Things that will bite you

These are all real failures already hit once. They're cheap to re-introduce.

**`pumpAndSettle` is unusable on Home.** The `LivingBackdrop` wash and the
enrichment spinner on the newest log card never stop by design, so there is no
idle frame. Use bounded pumps (`_pumpHome` in `home_shell_test.dart`).
`LivingBackdrop` takes `animate: false` precisely so it can appear in a golden
at all.

**Don't animate a transform over the backdrop.** The Ken Burns drift that used
to live in `BackdropCarousel` looked free — a transform above a
`RepaintBoundary` should be compositor-only — and was the most expensive thing
in the app. A raster cache will not hold a layer whose transform changes every
frame, so the entire `EdgeGlowImage`, two-pass Gaussian included, was
re-rendered at full DPR on every frame Home was *idle*. It also resampled the
photo each frame, which read as shimmer on fine detail. The boundary only pays
off when what is above it holds still.

**Widget tests must mock `app/genai`.** Anything that saves a log or seeds data
reaches `ClusterNamer`, which asks the model if it's available. Unmocked, that
call never completes under the fake clock and the test hangs to its timeout.
Use `mockGenAi()` from `test/support/genai_mock.dart`. This once turned an 80s
suite into 20 minutes.

**Widget tests that record must mock `app/speech` too**, for the same reason and
with a nastier symptom. `SpeechSource.resolve` asks `isSupported` before it can
pick a source; unmocked, that never answers, so `ComposeController._speech`
stays null. Recording *looks* like it started — the transcript view is on
screen — but Stop silently does nothing, because `stopVoice` early-returns on
the source it never got. Use `mockSpeech()` from `test/support/speech_mock.dart`;
`supported: false` routes the debug build to `FakeSpeechSource`.

**`putAsync` doesn't complete in widget tests.** It finishes via a native
callback the fake clock can't advance. `putEntry` uses a synchronous `put` for
exactly this reason.

**`SystemLanguageModel` availability is necessary but not sufficient.** In the
Simulator it reports `.available` and generation still fails —
`SensitiveContentAnalysisML Code=15 → ModelManagerError 1026`, Apple's safety
classifier, which isn't provisioned there. **Real model output can only be
verified on a physical A17 Pro+ device.** `GenAiService` latches off after two
consecutive generation failures so a device in that state doesn't pay a doomed
inference on every save.

**`timezone` alone schedules in UTC.** The package ships the zone database but
cannot tell where the device is, so `tz.local` stays UTC until something sets
it — and a 21:00 reminder then fires at 21:00 UTC. That is plausible enough to
ship and only detectable by waiting. `flutter_timezone` supplies the IANA name;
if it fails, `ReminderService` reports itself unready and reminders switch off
rather than firing at the wrong hour.

**The notification plugin keys everything off `defaultTargetPlatform`,** which
is Android in host tests, and its registrant never runs there. Without
`useIosNotificationPlatform()` from `test/support/reminder_mock.dart`,
`initialize` rejects iOS-only settings and every
`resolvePlatformSpecificImplementation` returns null. It's opt-in rather than
part of `mockNotifications()` because the override also changes scroll physics
and page transitions.

**Host tests need `libobjectbox.dylib`.** There's a symlink at the repo root
pointing into `ios/Pods/ObjectBox/…/macos-arm64_x86_64/…` — that slice exports
the full C API, so no download is needed. `pod install` regenerating Pods
breaks the symlink; recreate it with the same `ln -sf`.

**`EdgeGlowImage`'s glow gradients must run *toward* the image.** They were
written when `topColor`/`bottomColor` were sampled from the photo's own edges,
where holding the colour solid near the seam extended the picture outward. The
glow is the page background now, so the same gradient painted an opaque band of
background over a fully opaque image and stopped dead at the strip's edge — a
hard line across the top of every photo. Solid where the image has faded to
nothing, transparent where it is fully there.

**`FileImage` caches on path alone**, never mtime. Backdrops are written with
timestamped filenames because reusing one would serve the previous photo's
decoded bitmap forever.

**The files in `assets/illustrations/` are not SVGs and no renderer will open
them.** Every fill is a role — `__INK__`, `__SURFACE__`, `__ACCENT__` — that
`IllustrationView` substitutes against the live palette, which is what lets one
asset serve seven presets × two brightnesses. The failure mode is silent in both
directions: flutter_svg discards `fill="__SOMETHING__"` without a word, so an
unmapped role is an invisible shape and nothing in the console, and a drawing
dropped in with unDraw's own colours looks completely fine until someone opens
it in dark mode. `illustration_test.dart` walks the assets on disk against the
ramp for exactly that reason. Refetch with `./tool/fetch_illustrations.sh`,
which fails rather than ships on an unmapped colour, and use `--preview` to see
them — that is the only way to look at one.

**Don't run `flutter_native_splash:create` on its own.** It treats its source as
@4x and downsamples with `Interpolation.average`, a box filter, on a ×0.75 ratio
for @3x — which lands on the bezel's 3px rim, the thing that reads as a window.
`./tool/render_splash.sh` runs it and then overwrites the three PNGs with
Lanczos resamples, the same argument as the app icon. It also undoes two things
the package does on every run: it re-indents the whole of `Info.plist` through
its own serializer, turning a one-key edit into a 134-line diff, and it writes
the *master's* pixel size into the storyboard's natural-size metadata, so the
launch mark claims to be 1200pt on a 390pt phone.

**Animate a cached subtree, don't repaint it.** `LivingBackdrop` paints each
blob behind a boundary and hands it to `AnimatedBuilder` as its `child`, so a
frame is three transform matrices rather than three full-screen gradient fills.
Note the limit of this — see the Ken Burns note above.

**The shell is deliberately not inside a `SafeArea`** — the surface runs edge to
edge behind the status bar. `HomePane` insets its own content instead. Anything
new at the top of the pane needs the same treatment.

---

## Clustering: what actually works, and why

Every number in `JournalEntryDb`'s grouping was arrived at by measuring on a
device. The wrong ones are recorded here too, because each was plausible.

**Raw cosine between sentence embeddings is meaningless here.** Mean-pooled
contextual embeddings are anisotropic: they share one large common direction,
so any two English sentences start around 0.9 before content is considered.
Measured on device, cooking, an audiobook and a girlfriend all scored 0.86–0.94
against a cluster named "anxiety" — a spread of 0.076 across topics with nothing
in common. Everything landed in one theme, and no threshold sits inside that
range. This is why `nearestNeighborsF32` is no longer used: the HNSW index can
only rank raw vectors.

**Centring is the fix.** Subtract the mean of every stored embedding, then
renormalize. What is left is the part that is actually about cooking or a
deadline. The same device data then reads: unrelated pairs at a median of
−0.036, related pairs out at p99 0.513. That is a usable signal.

**The threshold is measured, not chosen.** Three fixed values were tried and all
three failed differently:

| Value | Where it came from | How it failed |
|---|---|---|
| 0.55 | the synthetic seed, where same-topic vectors share an axis and score 0.88 | 26 sentences → 25 themes |
| 4/√512 ≈ 0.177 | the noise floor, four sigma past chance | sat below the user's p90; put an audiobook in with work |
| p90 | "the top tenth of pairs are related" | the seed's is a *fifth*; broke the seed |

`_thresholdFrom` samples the pairwise distribution and runs **Otsu's method** on
it. The scores are two overlapping piles — near-zero for sentences that merely
share a language, higher for ones that share a subject — and Otsu finds the
valley by maximising between-group variance. It assumes nothing about where the
cut sits or how many pairs fall either side. On the seed it picks 0.333 and
captures exactly the 13 same-topic pairs out of 66, rebuilding exactly the 4
seeded topics. `_noiseFloor` remains as a floor so a genuinely varied journal
cannot collapse into one theme.

**Incremental assignment cannot stand alone.** Two things compound: the mean is
only estimable once there is text, so the earliest sentences are placed with the
measure that does not work and nothing revisits them; and a centroid drifts as
it absorbs members, so what a cluster accepts depends on arrival order. A theme
that has swallowed everything becomes a magnet and never comes apart.
`reclusterAll` regroups every sentence from scratch, oldest first.

**But not on every save.** `maybeRecluster` rebuilds once per launch, then only
when the corpus has grown by half again or the mean has actually drifted
(`_meanStability`). The mean converges quickly, and a rebuild only earns its
cost when the thing every comparison is relative to has moved.

**The corpus mean comes from the clusters, not the sentences.** Each cluster
carries `sumVector`, so summing those over tens of clusters gives exactly the
mean of every clustered sentence — instead of loading thousands of sentences and
their 512-float embeddings on every save, which was the most expensive thing in
the pipeline.

Read `[Cluster]` in the console to see all of this: the per-sentence decision,
the pairwise distribution with the chosen threshold and which rule set it, and
whether a rebuild happened.

---

## Conventions

- **Never derive a colour by hand.** Everything goes through `contrastify` /
  `elevate` in `core/ui/color_utils.dart`. `AppPalette.fromSettings` is covered
  by a test that walks every preset × brightness × tint combination and
  asserts body text clears 4.5:1. Keep that true.
- **The model is never required.** `ClusterLabeler` (statistical) is the floor
  and must keep working; `ClusterNamer` (theme names) and `KeywordNamer` (the
  words under a log card) both prefer the model and fall back silently. The
  follow-up question simply doesn't appear when the model is unavailable.
  Nothing here has ever been YAKE, whatever a stray comment says.
- **Phase 1 of a save never depends on phase 2.** Raw text persists first and
  synchronously; sentiment, embeddings and clustering run unawaited afterwards.
  The user must never lose words to an NLP failure.
- **Cluster naming is always all clusters at once**, never just the ones that
  changed — both strategies score names against each other.
- **The follow-up asks about every day, not just bad ones.** The day's average
  mood picks the question's *tone* — `hard`, `good` or `steady`, chosen in
  `FollowUpService.toneFor` and branched on in Swift — rather than deciding
  whether there is a question at all. A journal that only speaks up when things
  are grim teaches you it is the bad-news app.
- **A notification's text is composed when it is scheduled, never when it
  fires.** Nothing of ours runs at fire time, so both `refreshBody` and
  `refreshFollowUp` run at the end of a save. The consequence for the follow-up
  is that the armed question describes the day the last log was written on, and
  a later log the same day rewrites it.
- Safety framing is load-bearing, and distortions are self-tagged, never
  auto-detected. The crisis hotline rows were removed from Settings on request;
  the "self-help companion, not a replacement for therapy" line stays, in
  Settings and in onboarding.
- **Backdrop framing is non-destructive.** `Backdrop.fit` and `Backdrop.focusY`
  are applied at paint time, never by re-encoding the file, so `fill` with a
  centred focus is byte-for-byte what the picker handed over. `whole` draws the
  photo twice — an over-scaled blurred copy behind, the whole picture in
  front — which costs one extra blur, and only for images set that way.

---

## Remaining work

Full plan, with rationale and decisions already made with the user:
**`docs/plan-phase-2.md`**.

**Phase 2 is complete.** Theme presets + customization · `app/genai` +
model-first naming · multiple backdrops with captions and a drifting carousel ·
caption-above-image layout with the prompt below · compose clearing the screen ·
follow-up question service · per-word speech fade with a speaking gradient ·
daily reminders · the paged first-time experience · five live-switchable Home
layouts.

Decisions taken during phase 2 that override what the plan document says — the
plan is the older record:

- **No theme picker in the FTUE.** The app starts neutral and follows the
  system; asking for a colour before the first word is a decision in the way of
  the one that matters. Theming lives in Settings only.
- **There is no accent picker at all.** It briefly lived behind a "Custom
  colour" sheet and was then removed outright: choosing a preset and then
  choosing a colour on top of it was two decisions to reach somewhere the
  presets already went. A preset now owns its accent **per brightness**, which
  is also what fixed dark mode looking washed out — correcting a single
  mid-tone accent up onto a near-black surface drains it to grey, and every
  theme arrived at the same pale lilac. `app_palette_test` guards that.
- **Settings is a stack of cards**, one per setting, rather than a single
  column separated by whitespace. Anything added there wants a `_Section`.
- **The backdrop ships full-bleed and blurred** (`HomeLayout.fullBleed`). A
  `window` variant framing it in an aeroplane window was tried and removed.
- **Tracking is negative above body size.** The scale had Apple's small-size
  tracking applied at display sizes too, sign and all, which is what made
  headings and the Home caption read loose and generic.
- **`flutter_timezone` was added**, beyond the plan's two packages. See the
  time-zone note under "Things that will bite you."

Verified on device only: real `SpeechTranscriber` output revising words that
have already faded in · real `SystemLanguageModel` reminder lines · a
notification actually firing at its scheduled time and its tap routing in ·
the `fullBleed` layout's frame cost with the Gaussian at full pane height.
