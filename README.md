# Froyou

A local-first, iOS-only journal that notices what you keep coming back to.

You talk or type a log. Froyou transcribes it, reads its mood, embeds every
sentence, clusters those embeddings across all your entries, and names the
clusters — so it can tell you that six logs written in six different ways were
all the same worry. The next morning, if yesterday was rough, the home screen
asks about it in your own words.

**Everything runs on-device.** `SpeechTranscriber` for transcription, `NLTagger`
and `NLContextualEmbedding` for sentiment and 512-dimensional embeddings,
`SystemLanguageModel` (Foundation Models) for naming themes and writing the
follow-up question, and ObjectBox as the on-device vector store. There is no
server, no account, and no network call anywhere in the app. That is a product
promise, not an implementation detail.

None of those models is bundled — they're the ones iOS already ships. The
release build is **48.3 MB, of which 0 bytes are model weights** and 21 MB are
the four SF Pro Rounded weights. The largest asset in this AI app is the font.

Full submission write-up: **[`docs/devpost-submission.md`](docs/devpost-submission.md)**.
Architecture and the list of things that will bite you: **[`CLAUDE.md`](CLAUDE.md)**.

---

## What you need

| | Version | Why |
|---|---|---|
| macOS | Sonoma or later | Xcode 26 requires it |
| **Xcode** | **26.0+** | The iOS 26 SDK. `SpeechTranscriber`, `NLContextualEmbedding` and `FoundationModels` do not exist in earlier SDKs and the Swift will not compile. |
| **Flutter** | **3.44.8** stable (Dart 3.12.2) | Pinned in `pubspec.yaml` as `sdk: ^3.12.2` |
| CocoaPods | 1.16.2+ | ObjectBox pod |
| Target device | iPhone on **iOS 26.0+** | `IPHONEOS_DEPLOYMENT_TARGET = 26.0`. Android is explicitly out of scope. |

Verified against Xcode 26.1.1 / Flutter 3.44.8 / CocoaPods 1.16.2.

### Which device you use changes what you see

The app has three tiers of capability and degrades silently between them. This
matters when you evaluate it:

| Where you run it | Speech | Sentiment | Embeddings + clustering | Model-named themes, follow-up question |
|---|---|---|---|---|
| **A17 Pro / M-series device**, Apple Intelligence on | real, streaming | yes | yes | **yes** |
| Older iOS 26 device | real, streaming | yes | yes | falls back to c-TF-IDF |
| iOS 26 **Simulator** | fake source (debug builds) | yes | yes, after asset download | no — see below |

`SystemLanguageModel` reports `.available` in the Simulator and generation still
fails, because Apple's safety classifier (`SensitiveContentAnalysisML`) isn't
provisioned there. `GenAiService` latches off after two consecutive failures so
the Simulator doesn't pay for a doomed inference on every save. **Real model
output can only be verified on a physical A17 Pro or newer device.**

To confirm which tier you're on, watch the debug console at launch:

```
[boot] genai available=true
[boot] genai available=false reason=deviceNotEligible
```

---

## Setup

```bash
git clone <your-fork-url> froyou
cd froyou

flutter pub get      # also runs `pod install` on the next iOS build
```

That's it for a fresh clone. The ObjectBox bindings (`lib/generated/objectbox.g.dart`
and `objectbox-model.json`) are **checked in**, so you only need codegen if you
change an entity in `lib/features/journal/data/model/`:

```bash
dart run build_runner build --delete-conflicting-outputs
```

If pods don't resolve on the first build, force them:

```bash
cd ios && pod install --repo-update && cd ..
```

---

## Running it

```bash
flutter run                                  # a booted iOS 26 simulator or a connected device
flutter run --dart-define=SEED_DEMO=true     # + 12 believable clustered logs
flutter run --release                        # what the frame cost actually looks like
```

`SEED_DEMO` is `kDebugMode`-gated. It exists because clustering has nothing to
say until there are a couple of dozen sentences in the store, and typing those
by hand to demo the app is not a good use of anyone's time.

**Hidden entry points**, all reachable from Settings:

- **Seed sample logs** — a button, debug builds only.
- **Long-press the version label** → `DebugMenuView`, which ships in release. From there:
  - **Channel test** — the only way to drive `app/speech`, `app/nlp` and
    `app/genai` directly on a device. Start here when something looks wrong;
    it tells you whether the problem is the channel or the app.
  - **Home layouts** — switches between the five Home arrangements live.

---

## Tests and analysis

```bash
flutter analyze                  # must be clean
flutter test                     # 190 tests across 21 files, ~110s
flutter test --update-goldens    # after any deliberate visual change
```

Host tests need `libobjectbox.dylib` at the repo root. It's a symlink into the
macOS slice of the ObjectBox pod — that slice exports the full C API, so nothing
needs downloading:

```bash
ln -sfn ios/Pods/ObjectBox/ObjectBox.xcframework/macos-arm64_x86_64/ObjectBox.framework/Versions/A/ObjectBox \
  libobjectbox.dylib
```

The symlink is relative and checked in, so it resolves as soon as `pod install`
has run once. If `flutter test` dies with `Failed to load dynamic library`, the
pods aren't there yet.

---

## Building an IPA

Two routes. Pick by whether you have an Apple Developer account.

### Before either route: claim the bundle identifier

The repo ships with a placeholder identifier and the author's team, and both
will fail for you:

```
PRODUCT_BUNDLE_IDENTIFIER = com.example.froyou
DEVELOPMENT_TEAM          = CKJL48GV2C
```

Open `ios/Runner.xcworkspace` (**the workspace, not the project** — CocoaPods)
→ **Runner** target → **Signing & Capabilities**, then set your own Team and a
bundle identifier you own. Or edit `ios/Runner.xcodeproj/project.pbxproj`
directly — both keys appear once per configuration.

### Route A — signed IPA (needs a Developer account)

```bash
flutter build ipa --export-method development
```

`--export-method` takes `app-store` (the default), `ad-hoc`, `development`, or
`enterprise`. Use `development` for a build you'll install on your own registered
devices, `ad-hoc` for testers whose devices aren't registered, `app-store` for
TestFlight.

Output:

```
build/ios/archive/Runner.xcarchive     the archive
build/ios/ipa/*.ipa                    the signed IPA
```

For finer control over signing, hand it a plist instead:

```bash
flutter build ipa --export-options-plist=ios/ExportOptions.plist
```

If export fails but the archive succeeded, open
`build/ios/archive/Runner.xcarchive` in Xcode and use **Distribute App** from
the Organizer — the error messages there are considerably better than the
command line's.

### Route B — unsigned IPA (no account needed)

Useful for judging, for archiving, or for sideloading with a tool that does its
own signing.

```bash
flutter build ios --release --no-codesign

cd build/ios/iphoneos
mkdir -p Payload
cp -R Runner.app Payload/
zip -qr ../../../froyou-unsigned.ipa Payload
rm -rf Payload
cd ../../..
```

Leaves `froyou-unsigned.ipa` at the repo root. It will not install through
Finder or Apple Configurator as-is — sign it first, or use a sideloading tool
that signs for you.

### Installing a signed IPA on a device

Any of these:

```bash
xcrun devicectl device install app --device <UDID> path/to/froyou.ipa
```

- Xcode → **Window ▸ Devices and Simulators** → drag the `.ipa` onto the device.
- Apple Configurator → drag the `.ipa` onto the device.
- TestFlight, if you exported with `--export-method app-store`.

### Version numbers

`CFBundleShortVersionString` and `CFBundleVersion` come from `pubspec.yaml`'s
`version: 1.0.0+1`. Override per-build without editing the file:

```bash
flutter build ipa --build-name=1.0.1 --build-number=7
```

---

## The app icon is generated, not drawn

`assets/brand/app-icon.svg` is the source of truth. Editing the PNGs in
`AppIcon.appiconset` by hand is pointless — the next run of the renderer
silently undoes it.

```bash
./tool/render_icon.sh              # needs ImageMagick: brew install imagemagick
```

Only the 1024 comes from vector; the other fourteen are Lanczos downsamples of
it, because re-rendering the SVG at 40px puts the bezel highlight and the
turbulence field below a pixel each and simply drops them. To check the catalog
still compiles without waiting on a full iOS build:

```bash
xcrun actool --compile /tmp/actool-out \
  --platform iphoneos --minimum-deployment-target 26.0 \
  --app-icon AppIcon --output-partial-info-plist /tmp/actool.plist \
  ios/Runner/Assets.xcassets
```

---

## Adding a Swift file

The Xcode project uses **explicit file references, not a synchronized folder
group**, so dropping a `.swift` file into `ios/Runner/` is not enough — it needs
registering in `project.pbxproj` in four places (`PBXBuildFile`,
`PBXFileReference`, the group's `children`, and `PBXSourcesBuildPhase`). Adding
it through Xcode's UI does all four. `GenAiChannel.swift` is the worked example.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `cannot find type 'SpeechTranscriber'` / `no such module 'FoundationModels'` | Building against a pre-26 SDK | Xcode 26+, and check **Xcode ▸ Settings ▸ Locations ▸ Command Line Tools** points at it |
| `Failed to load dynamic library 'libobjectbox.dylib'` in `flutter test` | Pods not installed, or the symlink is broken | `cd ios && pod install`, then re-run the `ln -sfn` above |
| Themes are named oddly, like search results | The language model is unavailable; c-TF-IDF is naming them | Check `[boot] genai available=…`. On device: **Settings ▸ Apple Intelligence & Siri**. |
| Follow-up question never appears | Same — it has no fallback, by design | As above. It also only appears the day *after* a low-mood day. |
| Themes never form; logs stay unclustered | `NLContextualEmbedding` assets still downloading, or absent for the detected language | Give the first save 30s on Wi-Fi. `[Journal] embedding unavailable (…)` in the console confirms it. |
| Reminders fire at the wrong hour | `tz.local` fell back to UTC | `flutter_timezone` failed; `ReminderService` reports itself unready and switches reminders off rather than firing wrong. Check the console. |
| A golden test fails after a UI change | The golden is stale | `flutter test --update-goldens`, then **look at the diff** |
| Signing errors on `flutter build ipa` | Placeholder bundle id / someone else's team | See "claim the bundle identifier" above |
| A widget test hangs to its timeout | It saves a log or records without mocking `app/genai` / `app/speech` | `mockGenAi()` and `mockSpeech()` from `test/support/` |

---

## Layout

```
lib/
  main.dart                 bootstrap: prefs → schema wipe → DB → runApp
  app/                      FroyouRoot, AppScope (DI above MaterialApp)
  core/theme/               AppColors, AppPalette, ThemePresets, AppTypography
  core/ui/                  EdgeGlowImage, LivingBackdrop, NoiseOverlay, color_utils
  features/
    home/                   HomeShell, HomePane, 5 layouts, compose, transcript,
                            BackdropCarousel, FollowUpService
    journal/                ObjectBox entities, save pipeline, clustering,
                            ClusterLabeler / ClusterNamer / KeywordNamer
    onboarding/  profile/  reminders/  analytics/  debug/
  services/                 speech_service, nlp_service, genai_service, db_service
ios/Runner/                 SpeechChannel, NlpChannel, GenAiChannel (+ support)
assets/brand/               app-icon.svg — the app icon, in vector
tool/                       render_icon.sh, svg2png.swift
docs/                       plan-phase-2.md, devpost-submission.md
```

---

## License

MIT — see [`LICENSE`](LICENSE).
