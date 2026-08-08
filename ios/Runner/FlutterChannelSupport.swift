import Flutter
import Foundation

/// Shared plumbing for the app's platform channels.
///
/// The one non-negotiable rule when writing a Flutter channel on iOS is that
/// `FlutterResult` and `FlutterEventSink` must be invoked on the *platform
/// thread* — which on iOS is the main thread. Violating this is not reliably a
/// crash; it usually shows up as intermittent corruption inside the message
/// codec or an assertion deep in `FlutterBinaryMessengerRelay`, days later, on
/// someone else's device.
///
/// Rather than trusting every call site to remember, the two boxes below make
/// the hop structural: nothing in `SpeechChannel` or `NlpChannel` ever touches
/// a raw `result(...)` or `sink(...)`, so there is no code path that *can* get
/// it wrong.

/// Runs `body` on the main thread, without the needless async hop if we are
/// already there. Re-entering `DispatchQueue.main.async` from the main thread
/// would defer the reply by a runloop turn for no reason.
@inline(__always)
func onMainThread(_ body: @escaping @Sendable () -> Void) {
  if Thread.isMainThread {
    body()
  } else {
    DispatchQueue.main.async(execute: body)
  }
}

/// A single-use, main-thread-safe wrapper around `FlutterResult`.
///
/// Also enforces the *other* channel rule that is easy to get wrong: a
/// `FlutterResult` must be called exactly once. Our handlers are full of
/// `async` paths with multiple early exits, so the "did I already reply?"
/// bookkeeping lives here instead of being re-derived per method.
///
/// `@unchecked Sendable`: `FlutterResult` is an Objective-C block with no
/// `Sendable` annotation, and the mutable `hasReplied` flag is guarded by
/// `lock`. Both are safe; the compiler just can't see it.
final class ChannelReply: @unchecked Sendable {
  private let result: FlutterResult
  private let lock = NSLock()
  private var hasReplied = false

  init(_ result: @escaping FlutterResult) {
    self.result = result
  }

  /// Replies with a successful value (`nil` for void methods).
  func success(_ value: Any? = nil) {
    send(value)
  }

  /// Replies with an error Dart will surface as a `PlatformException`.
  /// `code` is the stable, matchable part — see the `speech_*` / `nlp_*`
  /// constants in the channel files.
  func failure(code: String, message: String, details: Any? = nil) {
    send(FlutterError(code: code, message: message, details: details))
  }

  /// Replies with `FlutterMethodNotImplemented`, which Dart turns into a
  /// `MissingPluginException`.
  func notImplemented() {
    send(FlutterMethodNotImplemented)
  }

  private func send(_ value: Any?) {
    lock.lock()
    let alreadyReplied = hasReplied
    hasReplied = true
    lock.unlock()

    // Dropping a duplicate reply is strictly better than letting the engine
    // trip its own assertion — a double-reply is a bug in our handler, and we
    // would rather it be a silently-ignored one than a crash in the field.
    guard !alreadyReplied else { return }

    let result = self.result
    onMainThread { result(value) }
  }
}

/// A main-thread-safe wrapper around `FlutterEventSink`.
///
/// Unlike `ChannelReply` this is *multi*-use: it stays alive for the whole
/// listen session and is written to from arbitrary executors (the speech
/// results drain runs on a cooperative-pool thread). `invalidate()` is called
/// from `onCancel` so that in-flight events produced after the Dart side
/// unsubscribed are dropped rather than delivered to a dead sink.
///
/// `@unchecked Sendable`: same reasoning as `ChannelReply` — ObjC block plus
/// lock-guarded state.
final class ChannelEventSink: @unchecked Sendable {
  private let lock = NSLock()
  private var sink: FlutterEventSink?

  init(_ sink: @escaping FlutterEventSink) {
    self.sink = sink
  }

  /// Emits an event to the Dart stream. No-op after `invalidate()`.
  func send(_ event: Any) {
    lock.lock()
    let sink = self.sink
    lock.unlock()

    guard let sink else { return }
    onMainThread { sink(event) }
  }

  /// Emits an error, which surfaces on the Dart stream as a `PlatformException`.
  func sendError(code: String, message: String, details: Any? = nil) {
    send(FlutterError(code: code, message: message, details: details))
  }

  /// Detaches the sink. Subsequent `send` calls are dropped.
  func invalidate() {
    lock.lock()
    sink = nil
    lock.unlock()
  }
}
