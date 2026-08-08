import AVFoundation
import Foundation
import Speech

/// Owns one live voice-transcription session, built on iOS 26's `SpeechAnalyzer`
/// / `SpeechTranscriber` (the new Speech API — *not* the legacy
/// `SFSpeechRecognizer`).
///
/// The audio path is:
///
///     AVAudioEngine.inputNode
///       -> installTap (realtime render thread)
///       -> AVAudioConverter          (device format -> analyzer's preferred format)
///       -> AsyncStream<AnalyzerInput>
///       -> SpeechAnalyzer
///       -> SpeechTranscriber.results (AsyncSequence of partial + final results)
///
/// This type deliberately knows **nothing** about Flutter. It reports results
/// through a plain `@Sendable` closure, which keeps it unit-testable from
/// XCTest and keeps the main-thread-hopping concern entirely inside
/// `SpeechChannel`.
///
/// It is an `actor` because `start` / `stop` can be called concurrently from
/// Dart and both mutate the engine, the analyzer and the stream continuation.
@available(iOS 26.0, *)
actor SpeechTranscriptionSession {

  // MARK: - Types

  /// One transcription update. `isFinal == false` means this is a *volatile*
  /// result that the recognizer may still revise; `true` means it is settled.
  struct Transcript: Sendable {
    let text: String
    let isFinal: Bool
    /// Offsets into the audio stream, in seconds from the start of the session.
    let start: TimeInterval
    let end: TimeInterval
  }

  /// Errors are modelled as a closed enum so `SpeechChannel` can map each case
  /// to exactly one stable Dart-visible error code.
  enum SessionError: Error {
    /// This device has no `SpeechTranscriber` support at all.
    case unsupported
    /// The requested locale isn't one `SpeechTranscriber` knows about.
    case unsupportedLocale(String)
    /// The locale is supported but its on-device model isn't installed yet.
    /// Callers should run `ensureModel` first.
    case modelMissing(String)
    /// `start` was called while a session was already running.
    case alreadyRunning
    /// Microphone / audio-session / engine failure.
    case audio(String)
    /// Anything the Speech framework itself threw.
    case analyzer(String)
  }

  // MARK: - State

  private var analyzer: SpeechAnalyzer?
  private var transcriber: SpeechTranscriber?
  private var engine: AVAudioEngine?
  private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
  private var resultsTask: Task<Void, Never>?
  private var reservedLocale: Locale?
  private var interruptionObserver: (any NSObjectProtocol)?
  private var onInterruption: (@Sendable () -> Void)?

  /// `true` between a successful `start()` and the corresponding `stop()`.
  private(set) var isRunning = false

  // MARK: - Static capability queries
  //
  // These don't touch session state, so they're `static` and can be called
  // without holding the actor.

  /// Whether this device supports the new on-device transcriber at all.
  ///
  /// This exists because the answer is genuinely "not everywhere" — do not
  /// assume iOS 26 implies availability.
  static var isSupported: Bool {
    SpeechTranscriber.isAvailable
  }

  /// Every locale the transcriber can handle, as BCP-47 identifiers.
  /// Note this is *supported*, not *installed* — see `assetStatus`.
  static func supportedLocaleIdentifiers() async -> [String] {
    await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
  }

  /// Maps a loose identifier (`"en"`) onto a concrete supported one
  /// (`"en-US"`), or `nil` if there is no equivalent.
  static func resolveLocaleIdentifier(_ identifier: String) async -> String? {
    let requested = Locale(identifier: identifier)
    guard let match = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
      return nil
    }
    return match.identifier(.bcp47)
  }

  /// Asset state for a locale: `unsupported`, `supported` (downloadable but not
  /// present), `downloading`, or `installed`.
  ///
  /// iOS does not ship every locale's model on every device, which is exactly
  /// why `AssetInventory` and a separate `installedLocales` list exist.
  static func assetStatus(localeIdentifier: String) async -> String {
    guard isSupported else { return "unsupported" }
    guard let locale = await SpeechTranscriber.supportedLocale(
      equivalentTo: Locale(identifier: localeIdentifier)
    ) else {
      return "unsupported"
    }

    let probe = makeTranscriber(locale: locale)
    switch await AssetInventory.status(forModules: [probe]) {
    case .unsupported: return "unsupported"
    case .supported: return "supported"
    case .downloading: return "downloading"
    case .installed: return "installed"
    @unknown default: return "unsupported"
    }
  }

  /// Downloads and installs the on-device model for `localeIdentifier` if it
  /// isn't already present. Returns immediately when nothing is needed — which
  /// is the common case for the device's own language, since system dictation
  /// draws on the same asset pool.
  ///
  /// This can take a long time on a cold device and may be Wi-Fi-only, so
  /// `onProgress` reports `0.0`…`1.0` as the download advances. It is called
  /// from an arbitrary thread and always ends on `1.0`, including the
  /// nothing-to-do path — so a UI can drive a determinate bar off it without
  /// special-casing the instant return.
  static func ensureModel(
    localeIdentifier: String,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws {
    guard isSupported else { throw SessionError.unsupported }
    guard let locale = await SpeechTranscriber.supportedLocale(
      equivalentTo: Locale(identifier: localeIdentifier)
    ) else {
      throw SessionError.unsupportedLocale(localeIdentifier)
    }

    let probe = makeTranscriber(locale: locale)
    do {
      // A nil request means "nothing to install" — already satisfied.
      guard let request = try await AssetInventory.assetInstallationRequest(
        supporting: [probe]
      ) else {
        onProgress(1.0)
        return
      }

      // `AssetInstallationRequest` is `ProgressReporting`; `Progress` is
      // KVO-compliant on `fractionCompleted`. `.initial` fires once
      // immediately so a bar starts at the real value rather than at zero.
      let observation = request.progress.observe(
        \.fractionCompleted,
        options: [.initial, .new]
      ) { progress, _ in
        onProgress(progress.fractionCompleted)
      }
      // Must outlive the download; invalidating early silently stops updates.
      defer { observation.invalidate() }

      try await request.downloadAndInstall()
      onProgress(1.0)
    } catch {
      throw SessionError.analyzer(error.localizedDescription)
    }
  }

  /// Single place that decides which transcriber options we use, so the probe
  /// instances above and the real session below can never drift apart —
  /// `AssetInventory` keys off the module's configuration.
  ///
  /// - `.volatileResults` is what produces partial results *while the user is
  ///   still speaking*. Without it you only get finals at pause boundaries.
  /// - `.audioTimeRange` populates `Result.range` with real timings.
  private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
    SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [.volatileResults],
      attributeOptions: [.audioTimeRange]
    )
  }

  // MARK: - Session lifecycle

  /// Starts capturing and transcribing.
  ///
  /// - Parameters:
  ///   - localeIdentifier: BCP-47 locale; resolved against `supportedLocales`.
  ///   - onTranscript: called for every partial and final result, on an
  ///     arbitrary executor. Must be safe to call off the main thread.
  ///   - onFailure: called at most once if the results stream terminates with
  ///     an error mid-session.
  ///   - onInterruption: called after the session has been torn down because
  ///     the system took the audio route away (a phone call, Siri). See
  ///     `observeInterruptions`.
  ///
  /// Fails fast with `.modelMissing` rather than silently blocking for the
  /// duration of a model download — call `ensureModel` first if you want to
  /// show download progress.
  func start(
    localeIdentifier: String,
    onTranscript: @escaping @Sendable (Transcript) -> Void,
    onFailure: @escaping @Sendable (SessionError) -> Void,
    onInterruption: @escaping @Sendable () -> Void
  ) async throws {
    guard !isRunning else { throw SessionError.alreadyRunning }
    guard Self.isSupported else { throw SessionError.unsupported }

    guard let locale = await SpeechTranscriber.supportedLocale(
      equivalentTo: Locale(identifier: localeIdentifier)
    ) else {
      throw SessionError.unsupportedLocale(localeIdentifier)
    }

    let transcriber = Self.makeTranscriber(locale: locale)

    // Don't start an engine we can't feed. `AssetInventory` is the only
    // reliable way to know; `analyzer.start` would otherwise fail later and
    // less legibly.
    guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
      throw SessionError.modelMissing(locale.identifier(.bcp47))
    }

    // Best-effort: reserving tells the system we intend to keep this locale's
    // model resident. There is a finite budget (`maximumReservedLocales`), so
    // `teardown` releases symmetrically. Failure here is not fatal.
    if (try? await AssetInventory.reserve(locale: locale)) == true {
      reservedLocale = locale
    }

    let analyzer = SpeechAnalyzer(modules: [transcriber])

    // NOTE: this is `SpeechAnalyzer.bestAvailableAudioFormat`, *not* a method
    // on SpeechTranscriber — the transcriber only exposes the unranked
    // `availableCompatibleAudioFormats` list.
    guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
      compatibleWith: [transcriber]
    ) else {
      await releaseLocale()
      throw SessionError.analyzer("No compatible audio format for \(locale.identifier).")
    }

    // Drain results before the analyzer starts, so nothing is missed.
    resultsTask = Task {
      do {
        for try await result in transcriber.results {
          onTranscript(
            Transcript(
              text: String(result.text.characters),
              isFinal: result.isFinal,
              start: Self.seconds(result.range.start),
              end: Self.seconds(result.range.end)
            )
          )
        }
      } catch is CancellationError {
        // Expected on teardown.
      } catch {
        onFailure(.analyzer(error.localizedDescription))
      }
    }

    let stream = AsyncStream<AnalyzerInput>.makeStream()
    inputContinuation = stream.continuation

    do {
      // `prepareToAnalyze` warms the model up front. Skipping it is the usual
      // cause of the first word or two being dropped.
      try await analyzer.prepareToAnalyze(in: analyzerFormat)
      try await analyzer.start(inputSequence: stream.stream)
    } catch {
      await teardown()
      throw SessionError.analyzer(error.localizedDescription)
    }

    do {
      try startEngine(feeding: stream.continuation, analyzerFormat: analyzerFormat)
    } catch {
      await teardown()
      throw error
    }

    self.analyzer = analyzer
    self.transcriber = transcriber
    self.onInterruption = onInterruption
    isRunning = true

    observeInterruptions()
  }

  // MARK: - Interruptions

  /// Watches for the system taking the audio route away — an incoming call,
  /// Siri, another app claiming the mic.
  ///
  /// On `.began` the engine is already dead: iOS has deactivated our session
  /// and the tap has stopped firing, so there is no more audio arriving no
  /// matter what we do. Tearing down explicitly turns a wedged, silently-
  /// producing-nothing session into a clean stop the app can react to.
  ///
  /// We deliberately do *not* auto-resume on `.ended`. Restarting the mic
  /// without the user asking is the kind of thing that reads as a bug (or
  /// worse) — the app gets told, and decides.
  private func observeInterruptions() {
    interruptionObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(),
      // `nil` queue means the block runs on the posting thread, so it must
      // stay cheap — it only hops into the actor.
      queue: nil
    ) { [weak self] notification in
      guard
        let self,
        let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
        AVAudioSession.InterruptionType(rawValue: raw) == .began
      else { return }

      Task { await self.handleInterruption() }
    }
  }

  private func handleInterruption() async {
    guard isRunning else { return }

    // Captured before `stop()`, which clears it via `teardown`.
    let notify = onInterruption
    await stop()
    notify?()
  }

  /// Stops capture and flushes the recognizer.
  ///
  /// Awaiting `resultsTask` here is deliberate and load-bearing: it means the
  /// trailing final result reaches the caller's `onTranscript` *before* `stop()`
  /// returns. Both awaits suspend and release the actor, so the results task
  /// can still run; there's no deadlock because that task never re-enters this
  /// actor — it only calls the `@Sendable` closures.
  ///
  /// Safe to call when not running.
  func stop() async {
    guard isRunning else {
      await teardown()
      return
    }
    isRunning = false

    stopEngine()
    inputContinuation?.finish()

    if let analyzer {
      // Flush whatever audio is still buffered rather than discarding it.
      try? await analyzer.finalizeAndFinishThroughEndOfInput()
    }

    await resultsTask?.value
    await teardown()
  }

  // MARK: - Audio capture

  /// Wraps `AVAudioConverter` so it can be captured by the escaping tap block.
  ///
  /// `@unchecked Sendable` is honest here: the converter is created on the
  /// actor, then touched *only* by the audio render thread between
  /// `installTap` and `removeTap`, and never concurrently. There is no
  /// annotation that expresses "single-threaded, just not this thread".
  private final class ConverterBox: @unchecked Sendable {
    let converter: AVAudioConverter
    init(_ converter: AVAudioConverter) { self.converter = converter }
  }

  private func startEngine(
    feeding continuation: AsyncStream<AnalyzerInput>.Continuation,
    analyzerFormat: AVAudioFormat
  ) throws {
    let session = AVAudioSession.sharedInstance()
    do {
      // `.measurement` disables the system's own speech processing, which is
      // what we want given *we* are the recognizer. Trade-off: it also
      // disables automatic gain control, so far-field input can suffer — try
      // `mode: .default` if quality is poor at a distance.
      try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      throw SessionError.audio("Could not activate the audio session: \(error.localizedDescription)")
    }

    let engine = AVAudioEngine()
    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)

    // A zero sample rate means the mic isn't actually available — typically a
    // denied permission. Tapping it anyway throws something far less legible.
    guard inputFormat.sampleRate > 0 else {
      deactivateSession()
      throw SessionError.audio("Microphone unavailable — permission may be denied.")
    }

    guard let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
      deactivateSession()
      throw SessionError.audio("Cannot convert \(inputFormat) to the analyzer's format.")
    }
    // Correct for continuous streaming: no priming silence, no added latency.
    // If you ever hear clicks at buffer boundaries, drop this line.
    converter.primeMethod = .none
    let box = ConverterBox(converter)

    // Everything the tap needs is captured by value. The block runs on the
    // realtime audio render thread, so it must not `await`, must not enter the
    // actor, and must not touch Flutter.
    input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
      guard let converted = Self.convert(buffer, using: box.converter, to: analyzerFormat) else {
        return
      }
      continuation.yield(AnalyzerInput(buffer: converted))
    }

    engine.prepare()
    do {
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      deactivateSession()
      throw SessionError.audio("Could not start audio capture: \(error.localizedDescription)")
    }

    self.engine = engine
  }

  /// Resamples one captured buffer into the analyzer's format.
  ///
  /// `nonisolated static` so the audio thread can call it without touching
  /// actor state.
  nonisolated private static func convert(
    _ buffer: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    to format: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let ratio = format.sampleRate / buffer.format.sampleRate
    // +1 frame of slack: the converter can emit one extra frame on a
    // non-integer resampling ratio (e.g. 44100 -> 16000).
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
      return nil
    }

    // The input block is pulled repeatedly until it reports no more data. We
    // have exactly one buffer to give, so hand it over once and then say
    // `.noDataNow` — returning it twice would duplicate audio.
    var consumed = false
    var conversionError: NSError?
    let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
      if consumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return buffer
    }

    switch status {
    case .haveData, .inputRanDry:
      return output.frameLength > 0 ? output : nil
    case .endOfStream, .error:
      return nil
    @unknown default:
      return nil
    }
  }

  private func stopEngine() {
    guard let engine else { return }
    if engine.isRunning { engine.stop() }
    engine.inputNode.removeTap(onBus: 0)
    self.engine = nil
    deactivateSession()
  }

  nonisolated private func deactivateSession() {
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  // MARK: - Teardown

  /// Releases every resource. Idempotent, so `start`'s error paths and `stop`
  /// can both call it without coordination.
  private func teardown() async {
    isRunning = false

    if let interruptionObserver {
      NotificationCenter.default.removeObserver(interruptionObserver)
      self.interruptionObserver = nil
    }
    onInterruption = nil

    stopEngine()

    inputContinuation?.finish()
    inputContinuation = nil

    resultsTask?.cancel()
    resultsTask = nil

    if let analyzer {
      await analyzer.cancelAndFinishNow()
    }
    analyzer = nil
    transcriber = nil

    await releaseLocale()
  }

  private func releaseLocale() async {
    guard let reservedLocale else { return }
    _ = await AssetInventory.release(reservedLocale: reservedLocale)
    self.reservedLocale = nil
  }

  /// `CMTime` -> seconds, clamping the invalid/indefinite cases to 0.
  ///
  /// `CMTimeGetSeconds` happily returns NaN or infinity for `.invalid`, and a
  /// NaN crossing the Flutter codec into Dart is a nasty thing to debug.
  nonisolated private static func seconds(_ time: CMTime) -> TimeInterval {
    guard time.isValid, time.isNumeric else { return 0 }
    let value = CMTimeGetSeconds(time)
    return value.isFinite ? max(0, value) : 0
  }
}
