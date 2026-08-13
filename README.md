# Froyou (v1.0.0+1)

Talk or type a log. Froyou notices what you keep coming back to.

## Features

Froyou is a journal for getting out of thought loops, built on four ideas:

- Notice the loop — it groups entries by what they're *about*, even when the wording changes every time
- Check in the morning after a hard day, with a question about what you actually wrote
- Everything on-device — transcription, sentiment, embeddings and theme naming all use Apple frameworks
- A home screen worth opening — your own photos, your own words, no streaks or scores

## Getting Started

**Platform supported: iOS only.** Deployment target is iOS 26.0 — Android is out
of scope.

Themes are named by Apple's on-device language model, which needs an **A17 Pro or
newer** iPhone with Apple Intelligence enabled. On other devices, and in the
Simulator, the app still works — the naming falls back to a statistical method.

If you want to set up the project locally, follow the instructions below.

### Prerequisites

- **Xcode 26.0+** — the iOS 26 SDK. `SpeechTranscriber`, `NLContextualEmbedding`
  and `FoundationModels` don't exist in earlier SDKs and the Swift won't compile.
- **Flutter 3.44.8** stable (Dart 3.12.2)
- **CocoaPods 1.16.2+**
- An iPhone on iOS 26.0+, or a booted iOS 26 simulator

### Setup

```bash
git clone <repo-url> froyou
cd froyou

flutter pub get
cd ios && pod install && cd ..
```

That's it — the ObjectBox bindings are checked in, so no codegen is needed.

## Running/Building the App

```bash
# Run on an iOS device/simulator in DEBUG mode
flutter run

# Run with 12 sample logs seeded, so the clustering has something to show
flutter run --dart-define=SEED_DEMO=true

# Run in RELEASE mode
flutter run --release

# Build an IPA (set your Team in ios/Runner.xcworkspace first)
flutter build ipa --export-method development
# → build/ios/ipa/*.ipa

# Build unsigned, if you don't have an Apple Developer account
flutter build ios --release --no-codesign
```

To package the unsigned build as an IPA:

```bash
cd build/ios/iphoneos && mkdir -p Payload && cp -R Runner.app Payload/ \
  && zip -qr ../../../froyou-unsigned.ipa Payload && rm -rf Payload && cd ../../..
```

## Tests

```bash
flutter analyze
flutter test
```

Host tests load `libobjectbox.dylib` from a symlink at the repo root that points
into the ObjectBox pod, so run `pod install` first. If it goes missing:

```bash
ln -sfn ios/Pods/ObjectBox/ObjectBox.xcframework/macos-arm64_x86_64/ObjectBox.framework/Versions/A/ObjectBox \
  libobjectbox.dylib
```

## More

- Submission write-up: [`docs/devpost-submission.md`](docs/devpost-submission.md)
- Architecture and implementation notes: [`CLAUDE.md`](CLAUDE.md)

## License

MIT — see [`LICENSE`](LICENSE).
