import AVFoundation
import Flutter
import Foundation
import Speech

/// Bridges `SpeechTranscriptionSession` to Dart.
///
/// Two channels, because transcription has two shapes:
///
/// - `app/speech/methods` (MethodChannel) — request/response control:
///   availability, permissions, locales, model assets, start, stop.
/// - `app/speech` (EventChannel) — the continuous stream of partial and final
///   results. A method call can't push ongoing updates, which is the whole
///   reason this one feature needs two channels while all four
///   NaturalLanguage features share one.
///
/// Note they must be *distinct* channel names: both `setMethodCallHandler` and
/// `setStreamHandler` register on the messenger under the channel name, so
/// reusing one name would have the second registration silently replace the
/// first.
final class SpeechChannel: NSObject {

  static let methodChannelName = "app/speech/methods"
  static let eventChannelName = "app/speech"

  /// Stable error codes. These are the contract with Dart — `SpeechException`
  /// matches on them, so treat them as API and don't rename casually.
  private enum ErrorCode {
    static let unsupported = "speech_unsupported"
    static let permissionDenied = "speech_permission_denied"
    static let modelMissing = "speech_model_missing"
    static let alreadyRunning = "speech_already_running"
    static let audio = "speech_audio"
    static let badArguments = "speech_bad_arguments"
    static let internalFailure = "speech_internal"
  }

  private let session: Any?
  private var eventSink: ChannelEventSink?

  override init() {
    // Guarded because the whole Speech API surface we use is iOS 26+. The
    // deployment target is already 26.0, but keeping the guard means a
    // hypothetical lowered target degrades to "unsupported" instead of
    // refusing to build.
    if #available(iOS 26.0, *) {
      session = SpeechTranscriptionSession()
    } else {
      session = nil
    }
    super.init()
  }

  /// Typed accessor for the availability-erased `session` property.
  @available(iOS 26.0, *)
  private var typedSession: SpeechTranscriptionSession? {
    session as? SpeechTranscriptionSession
  }

  // MARK: - Registration

  func register(with messenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: Self.methodChannelName,
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, reply: ChannelReply(result))
    }

    let eventChannel = FlutterEventChannel(
      name: Self.eventChannelName,
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(self)
  }

  // MARK: - Method dispatch

  private func handle(_ call: FlutterMethodCall, reply: ChannelReply) {
    guard #available(iOS 26.0, *), let session = typedSession else {
      // Every method degrades to the same answer on an unsupported OS, except
      // `isSupported`, which should answer honestly rather than throw.
      if call.method == "isSupported" {
        reply.success(false)
      } else {
        reply.failure(
          code: ErrorCode.unsupported,
          message: "On-device speech transcription requires iOS 26 or later."
        )
      }
      return
    }

    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "isSupported":
      reply.success(SpeechTranscriptionSession.isSupported)

    case "permissions":
      reply.success(Self.currentPermissions())

    case "requestPermissions":
      Self.requestPermissions { reply.success($0) }

    case "supportedLocales":
      // `Task` inside this nonisolated handler block lands on the global
      // concurrent executor, so the await never blocks the platform thread.
      Task {
        reply.success(await SpeechTranscriptionSession.supportedLocaleIdentifiers())
      }

    case "resolveLocale":
      guard let identifier = args["localeIdentifier"] as? String else {
        reply.failure(code: ErrorCode.badArguments, message: "Missing 'localeIdentifier'.")
        return
      }
      Task {
        reply.success(await SpeechTranscriptionSession.resolveLocaleIdentifier(identifier))
      }

    case "modelStatus":
      guard let identifier = args["localeIdentifier"] as? String else {
        reply.failure(code: ErrorCode.badArguments, message: "Missing 'localeIdentifier'.")
        return
      }
      Task {
        reply.success(await SpeechTranscriptionSession.assetStatus(localeIdentifier: identifier))
      }

    case "ensureModel":
      guard let identifier = args["localeIdentifier"] as? String else {
        reply.failure(code: ErrorCode.badArguments, message: "Missing 'localeIdentifier'.")
        return
      }
      Task {
        do {
          try await SpeechTranscriptionSession.ensureModel(
            localeIdentifier: identifier,
            onProgress: { [weak self] fraction in
              self?.emit([
                "type": "download",
                "localeIdentifier": identifier,
                "progress": fraction,
              ])
            }
          )
          reply.success()
        } catch {
          Self.fail(reply, with: error)
        }
      }

    case "start":
      guard let identifier = args["localeIdentifier"] as? String else {
        reply.failure(code: ErrorCode.badArguments, message: "Missing 'localeIdentifier'.")
        return
      }
      start(session: session, localeIdentifier: identifier, reply: reply)

    case "stop":
      Task {
        await session.stop()
        self.emit(["type": "status", "state": "stopped"])
        reply.success()
      }

    default:
      reply.notImplemented()
    }
  }

  // MARK: - Start

  @available(iOS 26.0, *)
  private func start(
    session: SpeechTranscriptionSession,
    localeIdentifier: String,
    reply: ChannelReply
  ) {
    // Gate on the microphone before touching the engine, so a denied
    // permission produces a clear error instead of an opaque audio failure.
    guard AVAudioApplication.shared.recordPermission == .granted else {
      reply.failure(
        code: ErrorCode.permissionDenied,
        message: "Microphone permission has not been granted."
      )
      return
    }

    Task {
      do {
        try await session.start(
          localeIdentifier: localeIdentifier,
          onTranscript: { [weak self] transcript in
            // Called from a cooperative-pool thread. `emit` -> ChannelEventSink
            // does the hop to main.
            self?.emit([
              "type": "result",
              "text": transcript.text,
              "isFinal": transcript.isFinal,
              "start": transcript.start,
              "end": transcript.end,
            ])
          },
          onFailure: { [weak self] error in
            let (code, message) = Self.describe(error)
            self?.eventSink?.sendError(code: code, message: message)
          },
          onInterruption: { [weak self] in
            // The session has already torn itself down by this point, so this
            // is purely "tell Dart why listening stopped".
            self?.emit(["type": "status", "state": "interrupted"])
          }
        )
        self.emit(["type": "status", "state": "listening"])
        reply.success()
      } catch {
        Self.fail(reply, with: error)
      }
    }
  }

  private func emit(_ event: [String: Any]) {
    eventSink?.send(event)
  }

  // MARK: - Permissions

  /// Current status of both permissions, without prompting.
  ///
  /// Each value is one of `undetermined` / `granted` / `denied` / `restricted`.
  private static func currentPermissions() -> [String: String] {
    let microphone: String
    switch AVAudioApplication.shared.recordPermission {
    case .undetermined: microphone = "undetermined"
    case .granted: microphone = "granted"
    case .denied: microphone = "denied"
    @unknown default: microphone = "denied"
    }

    let speech: String
    switch SFSpeechRecognizer.authorizationStatus() {
    case .notDetermined: speech = "undetermined"
    case .authorized: speech = "granted"
    case .denied: speech = "denied"
    case .restricted: speech = "restricted"
    @unknown default: speech = "denied"
    }

    return ["microphone": microphone, "speechRecognition": speech]
  }

  /// Prompts for microphone, then speech recognition, then reports both.
  ///
  /// Whether `SpeechAnalyzer` actually enforces the speech-recognition TCC gate
  /// is unclear — Apple's own sample for the new API requests only the
  /// microphone, and the new error enum has no "not authorized" case. We
  /// request both so behaviour is correct either way; if you'd rather show a
  /// single dialog, delete the `SFSpeechRecognizer` call here and the
  /// `NSSpeechRecognitionUsageDescription` key from Info.plist.
  private static func requestPermissions(_ completion: @escaping ([String: String]) -> Void) {
    AVAudioApplication.requestRecordPermission { _ in
      SFSpeechRecognizer.requestAuthorization { _ in
        completion(currentPermissions())
      }
    }
  }

  // MARK: - Error mapping

  /// Maps a `SessionError` onto its stable Dart-visible code.
  private static func describe(_ error: Error) -> (code: String, message: String) {
    guard #available(iOS 26.0, *),
          let sessionError = error as? SpeechTranscriptionSession.SessionError
    else {
      return (ErrorCode.internalFailure, error.localizedDescription)
    }

    switch sessionError {
    case .unsupported:
      return (ErrorCode.unsupported, "This device does not support on-device transcription.")
    case .unsupportedLocale(let identifier):
      return (ErrorCode.unsupported, "Locale '\(identifier)' is not supported.")
    case .modelMissing(let identifier):
      return (
        ErrorCode.modelMissing,
        "The on-device model for '\(identifier)' is not installed. Call ensureModel first."
      )
    case .alreadyRunning:
      return (ErrorCode.alreadyRunning, "A transcription session is already running.")
    case .audio(let message):
      return (ErrorCode.audio, message)
    case .analyzer(let message):
      return (ErrorCode.internalFailure, message)
    }
  }

  private static func fail(_ reply: ChannelReply, with error: Error) {
    let (code, message) = describe(error)
    reply.failure(code: code, message: message)
  }
}

// MARK: - FlutterStreamHandler

/// `onListen` / `onCancel` are called on the platform thread. This type is
/// deliberately *not* `@MainActor`: annotating a class that conforms to an
/// `@objc` protocol with nonisolated requirements produces isolation warnings
/// today and hard errors under Swift 6. The explicit hop inside
/// `ChannelEventSink` is the portable form.
extension SpeechChannel: FlutterStreamHandler {
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = ChannelEventSink(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink?.invalidate()
    eventSink = nil

    // Dart went away — don't leave the microphone hot.
    if #available(iOS 26.0, *), let session = typedSession {
      Task { await session.stop() }
    }
    return nil
  }
}
