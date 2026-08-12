# Froyou — Phase 2: presets, on-device LLM, carousel, reminders, FTUE

> **Status: all nine sections are built and tested.** This document is the
> original plan, kept for its rationale; where it disagrees with `CLAUDE.md`,
> `CLAUDE.md` is the current record. Four things changed during
> implementation, deliberately:
>
> - Theming was removed from onboarding entirely — the app starts neutral and
>   follows the system's light/dark setting. **This supersedes §8 step 2,**
>   which still lists a theme picker.
> - The accent colour wheel moved behind a "Custom colour" sheet, because a
>   full-spectrum wheel and a stock segmented control read as somebody else's
>   UI in an app this quiet.
> - **`flutter_timezone` was added** beyond §7's two packages. `timezone` alone
>   leaves `tz.local` at UTC, so every reminder would have fired at the right
>   number in the wrong zone.
> - §9 ships **five** layouts, not 3–4: `classic` is one of them, because being
>   able to switch back on device is the point of a live gallery.

## Context

Phase 1 shipped a working app: onboarding, image-derived theming, mic/text compose, Home→Logs scroll, analytics, 77 passing tests. Using it surfaced the limits of three early decisions.

**Theme from photo doesn't survive contact with reality.** It was the demo moment, but it can't work with multiple photos, and it makes the palette hostage to whatever the user happened to pick. Presets with real customization give control back.

**c-TF-IDF labels lose the thread.** It scores terms, so it can only ever return terms — "deadline moved" is a handle, not a thought. It has no idea that "my manager pushed the date again" and "the timeline slipped" are the same worry. The device already carries a language model that does; on iOS 26 with an A17 Pro or better, `SystemLanguageModel` is right there.

**One photo, one quote is thin.** Several images with their own captions, drifting and crossfading, is what makes the screen feel personal.

Plus: reminders, a real first-run experience, a proactive follow-up the morning after a rough day, and a calmer compose transition.

**Verified before planning:** `FoundationModels.framework` is present in both the iOS 26.1 device and Simulator SDKs (Xcode 26.1.1). The API is `SystemLanguageModel.default.availability` → `.available` / `.unavailable(.deviceNotEligible | .appleIntelligenceNotEnabled | .modelNotReady)`, and `LanguageModelSession.respond(to:generating:)` with `@Generable` structs for guided generation. Your iPhone 16 Pro (A18 Pro) is eligible, and the M2 Pro host means the Simulator can run the model too.

**Decisions made:** silent fallback to the existing labeler when the model is unavailable · preset + accent + light/dark customization · photos no longer influence colour · one daily reminder with body text recomputed at save · auto-crossfade carousel with drift, swipeable · paged intro → setup → guided first log · up to 5 images, captions optional · follow-up question only the day after a negative day, cleared once you log · in-app debug gallery of Home variants.

**Existing data may be wiped** (user's call), which removes all migration work.

---

## 1. Native: `app/genai` channel

New `ios/Runner/GenAiChannel.swift`, registered in `AppDelegate.didInitializeImplicitFlutterEngine` beside the existing two, following `NlpChannel`'s exact shape: `register(with:)`, `ChannelReply` from `FlutterChannelSupport.swift`, stable error-code enum, work off the platform thread.

Deployment target is already 26.0, so no `@available` shims — but the availability *check* is still mandatory, because eligibility is about hardware and user settings, not OS version.

```
availability()  → {status, reason}   // never throws; the Dart side decides what to do
labelThemes(clusters:[{id, sentences:[…]}]) → [{id, label}]
followUpQuestion(mood, themes:[…], excerpt) → {question}
reminderLine(themes:[…]) → {line}
```

**One call labels every cluster**, not one call per cluster. The model seeing all clusters together is what makes the names mutually distinctive — the same property c-TF-IDF gets from its cross-class denominator — and it keeps a save to a single inference. Cap each cluster at its ~6 most central sentences (reuse the medoid logic in `AnalyticsService._representativeSentence`) so the prompt stays small.

Guided generation via `@Generable` structs rather than parsing free text — the framework constrains decoding to the schema, so there is no JSON-repair path to write.

Dart side: `lib/services/genai_service.dart`, static-only, mirroring `nlp_service.dart` — same `_invoke` error translation, a `GenAiException` with matching codes, and `GenAiAvailability` as a small enum. Export from `lib/services/services.dart`.

## 2. Labeling: LLM first, existing labeler as fallback

`JournalRepository._enrich` (`lib/features/journal/data/journal_repository.dart`) currently ends with `_db.relabelAllClusters()`. That becomes:

1. If `GenAiService` is available → gather clusters + their central sentences → one `labelThemes` call → write labels.
2. On unavailable, error, or timeout → `_db.relabelAllClusters()`, unchanged.

`ClusterLabeler` and its tests stay exactly as they are. It is the fallback, and it is the only thing that works on ineligible hardware.

`keywordsFor` (log-card summaries) stays on the labeler — it runs per entry and isn't worth an inference.

## 3. Theme presets + customization

**Delete:** `lib/features/profile/data/image_palette_service.dart`, its test, `sampleEdgeColor` in `lib/core/ui/color_utils.dart`, and the `palette_generator_master` dependency. **Keep** `contrastRatio`, `contrastify`, `elevate` — the preset builder leans on them for the same guarantees.

**New `lib/core/theme/theme_presets.dart`** — ~6 calming presets, each a `{id, name, background, accent, brightness}` seed. Working set: Sand, Sage, Dusk, Slate, Linen, Ink (three light, three dark).

**New `ThemeSettings`** (`lib/features/profile/data/theme_settings.dart`): `presetId`, `accentOverride: Color?`, `brightnessMode: light|dark|system`, `backgroundTint: double`. Persisted as JSON in prefs by `ProfileStore`.

`AppPalette.fromSettings(ThemeSettings, platformBrightness)` replaces `ImagePaletteService.derive`, building all 13 `AppColors` fields through `contrastify`/`elevate` exactly as the derivation does today — so **contrast is still guaranteed regardless of what the user picks**, which is the whole reason to derive rather than expose 13 colour pickers.

`EdgeGlowImage` gets `topColor` and `bottomColor` both set to the palette background, so any photo dissolves into the theme instead of fighting it.

Settings gains a theme section: preset swatches, an accent colour wheel, light/dark/system segmented control, and a tint slider — all live-previewing, which they already do for free via `MaterialApp`'s `AnimatedTheme`.

## 4. Multiple images + captions

**Model** `Backdrop {imagePath, caption}` (`lib/features/profile/data/backdrop.dart`); `UserProfile.backdrops: List<Backdrop>`, max 5, persisted as a JSON list. Files keep going to app-support `backdrops/` with timestamped names — `ProfileStore.adoptBackdrop` already does this and the `FileImage`-caches-on-path trap it guards against still applies.

**New `lib/features/home/presentation/backdrop_carousel.dart`** — crossfade every ~7s with a slow Ken Burns scale/translate drift, `PageView` for swipe, auto-advance paused on interaction and whenever `compose.isOpen`. Dots fade in only during a swipe. Each `ProfileController.backdropProviders` entry stays memoized, as today.

Caption sits **above** the image and crossfades in sync with it (item 7).

## 5. Home layout

Top-to-bottom: **caption → image → question**. In `home_pane.dart`:

- Caption moves above `EdgeGlowImage`, driven by the carousel's current index.
- Below the image, a `PromptLine`: default `"How are you feeling?"`; replaced by the generated follow-up when one is pending. Not a button — the mic and text controls below it are how you respond.
- **On compose open, caption, image and prompt all animate out together** and the compose field takes the whole pane (item 8). The one-viewport invariant from phase 1 still holds — the pane never changes total height, it only redistributes.

**Follow-up question logic** (`lib/features/home/data/follow_up_service.dart`):
- On first Home build of a calendar day, average `moodScore` across yesterday's entries.
- If below `-0.15` **and** nothing logged today → ask `GenAiService.followUpQuestion` with yesterday's dominant theme and a short excerpt; cache `{date, question}` in prefs so Home never waits on the model.
- Cleared as soon as today's first log saves. Never shown when the model is unavailable, or before the first log ever.

## 6. Speech: word-by-word fade + gradient

Today the joined transcript is written straight into the `TextEditingController`, so text appears in hard jumps.

**New `lib/features/home/presentation/transcript_view.dart`** — used *instead of* the `TextField` while `mode == voice`. It diffs each incoming transcript against what it is already showing and fades in only the new words (~220ms each, slightly staggered). On `stopVoice` the accumulated text hands off to the existing `TextEditingController` and the editable field takes over — which also removes the current `readOnly`/IME-fighting workaround in `compose_box.dart`.

Behind it while recording, an animated gradient in the theme's accent at low opacity, driven by a repeating controller and wrapped in a `RepaintBoundary`. It stops when recording stops — nothing animates at idle.

## 7. Reminders

Add `flutter_local_notifications` + `timezone` (let `flutter pub add` resolve versions). iOS setup: `DarwinInitializationSettings`, request permission from Settings rather than at launch.

**New `lib/features/reminders/`** — `ReminderService` (permission, schedule, cancel) and a Settings section with an on/off toggle and a time picker, persisted in prefs.

Body text is recomputed **every time a log saves**, from that moment's theme data (`GenAiService.reminderLine`, falling back to a fixed gentle line). This is deliberate: iOS background execution is not reliable enough to compose time-sensitive notification text at fire time, so the content is baked in at save.

## 8. First-time experience

`lib/features/onboarding/` (replacing the single `onboarding_view.dart`):
1. Three short value screens — what Froyou does · everything stays on this device · self-help companion, not a replacement for therapy.
2. Theme picker.
3. First image + caption (more can be added later in Settings).
4. Guided first log — explains what the mic will ask for **immediately before** the system prompt appears, so the permission is primed in context rather than fired cold.

Skippable from step 4 onward; steps 2–3 are required as today.

## 9. Home variant gallery (last priority)

3–4 alternative Home layouts behind the existing hidden Settings long-press, switchable live so the motion can be judged on-device. Variants: caption-over-image · full-bleed with bottom scrim · centred minimal (no image chrome) · type-first. Screenshots for each too.

## Wipe on upgrade

The prefs shape changes (single image+quote → backdrops list + theme settings). Store an `appSchemaVersion` in prefs; on mismatch, clear prefs, `AppDatabase.eraseLocalData()`, and route to onboarding. Simplest correct thing given migration is explicitly not wanted.

---

## Build order

1. **Theme presets** — presets, `ThemeSettings`, `AppPalette.fromSettings`, Settings theme section; delete the image-palette path. *Runs; whole app themeable.*
2. **`app/genai` channel + `GenAiService`** — availability + `labelThemes` first. Verify in the Simulator via the existing channel-test harness. *Model reachable from Dart.*
3. **LLM labeling with fallback** — wire into `_enrich`; confirm Analytics names improve, and still work with the model forced unavailable.
4. **Backdrops + carousel** — model, storage, carousel, caption above image.
5. **Home layout + prompt line + follow-up service.**
6. **Compose: transcript fade + gradient + full-pane focus.**
7. **Reminders.**
8. **FTUE.**
9. **Variant gallery.**

## Verification

- `flutter analyze` clean; `flutter test` green. Phase-1 tests that must keep passing: `cluster_labeler_test` (unchanged — it's the fallback), `journal_entry_db_test`, `home_shell_test`, `analytics_view_test`.
- **Delete** `image_palette_service_test.dart`; **regenerate** `test/features/journal/goldens/` after the type/theme changes.
- **New tests:** `AppPalette.fromSettings` holds ≥4.5:1 text contrast across every preset × accent × brightness combination (the guarantee that replaces image derivation); follow-up triggers only on a negative previous day and clears after today's first log; carousel advances, pauses while composing, and wraps; `GenAiService` availability states map correctly and labeling falls back cleanly when unavailable.
- **Simulator:** full FTUE on a wiped install → theme picking recolours live → multiple images crossfade with captions → compose clears the screen → follow-up appears after seeding a negative yesterday. Confirm the model is reachable; if the Simulator's Apple Intelligence isn't provisioned, expect `modelNotReady` and verify the fallback path instead.
- **Device (iPhone 16 Pro):** the parts the Simulator can't cover — live transcription with per-word fade, real `SystemLanguageModel` labels and follow-up questions, and a reminder actually firing at the scheduled time.
