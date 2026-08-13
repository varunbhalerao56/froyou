import Flutter
import Foundation
import FoundationModels

/// One MethodChannel (`app/genai`) over Apple's on-device language model.
///
/// This replaces keyword scoring for naming themes. A statistical extractor can
/// only ever return terms that literally appear in the text, so it cannot tell
/// that "my manager pushed the date again" and "the timeline slipped" are the
/// same worry. The model can.
///
/// Availability is a hardware-and-settings question, not an OS-version one: the
/// deployment target is already iOS 26, but the model is absent on devices
/// without the neural capacity for Apple Intelligence, when the user has it
/// switched off, and while assets are still downloading. Every method here
/// checks first and reports a stable reason, so Dart can fall back rather than
/// surface an error.
final class GenAiChannel: NSObject {

  static let channelName = "app/genai"

  /// Stable error codes — matched on by `GenAiException` in Dart.
  private enum ErrorCode {
    static let badArguments = "genai_bad_arguments"
    static let unavailable = "genai_unavailable"
    static let generationFailed = "genai_generation_failed"
    static let internalFailure = "genai_internal"
  }

  /// Availability reasons, mirrored as a Dart enum.
  private enum Reason {
    static let deviceNotEligible = "device_not_eligible"
    static let appleIntelligenceNotEnabled = "apple_intelligence_not_enabled"
    static let modelNotReady = "model_not_ready"
    static let unknown = "unknown"
  }

  // MARK: - Generable schemas

  /// The names for a batch of clusters, positionally.
  ///
  /// Deliberately a flat `[String]` rather than a list of `{id, label}` pairs.
  /// Making the model echo back an integer identifier is asking it to generate
  /// something it has no reason to get right, and a hallucinated id would
  /// silently name the wrong theme. The ids stay in Swift and are zipped back
  /// on by position.
  @Generable
  struct ThemeNames {
    @Guide(
      description:
        "One name per group, in the same order the groups were given. Each name is two to four lowercase words, no punctuation."
    )
    var names: [String]
  }

  /// The at-a-glance words shown under a single log.
  ///
  /// A flat `[String]` for the same reason as `ThemeNames`: nothing here needs
  /// the model to echo an identifier back, so nothing here can be joined to
  /// the wrong thing.
  @Generable
  struct EntryKeywords {
    @Guide(
      description:
        "Two or three lowercase words or very short phrases naming what this entry is about. No punctuation, no repetition, no advice."
    )
    var keywords: [String]
  }

  @Generable
  struct Question {
    @Guide(
      description:
        "One short, warm, open question of at most 18 words. No advice, no diagnosis, no emoji."
    )
    var question: String
  }

  @Generable
  struct ReminderLine {
    @Guide(
      description:
        "One gentle sentence of at most 12 words inviting the person to check in. No advice."
    )
    var line: String
  }

  // MARK: - Registration

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, reply: ChannelReply(result))
    }
  }

  private func handle(_ call: FlutterMethodCall, reply: ChannelReply) {
    switch call.method {
    case "availability":
      reply.success(availabilityPayload())

    case "labelThemes":
      guard
        let arguments = call.arguments as? [String: Any],
        let clusters = arguments["clusters"] as? [[String: Any]]
      else {
        reply.failure(code: ErrorCode.badArguments, message: "Expected a `clusters` list.")
        return
      }
      run(reply) { try await self.labelThemes(clusters) }

    case "entryKeywords":
      guard
        let arguments = call.arguments as? [String: Any],
        let text = arguments["text"] as? String
      else {
        reply.failure(code: ErrorCode.badArguments, message: "Expected a `text` string.")
        return
      }
      run(reply) { try await self.entryKeywords(text) }

    case "followUpQuestion":
      guard let arguments = call.arguments as? [String: Any] else {
        reply.failure(code: ErrorCode.badArguments, message: "Expected an argument map.")
        return
      }
      run(reply) { try await self.followUpQuestion(arguments) }

    case "reminderLine":
      let arguments = call.arguments as? [String: Any] ?? [:]
      run(reply) { try await self.reminderLine(arguments) }

    default:
      reply.notImplemented()
    }
  }

  // MARK: - Availability

  private func availabilityPayload() -> [String: Any] {
    switch SystemLanguageModel.default.availability {
    case .available:
      return ["status": "available"]
    case .unavailable(let reason):
      return ["status": "unavailable", "reason": Self.describe(reason)]
    @unknown default:
      // Apple has said more reasons are coming. An unrecognised one must read
      // as "can't use it", never as "available".
      return ["status": "unavailable", "reason": Reason.unknown]
    }
  }

  private static func describe(
    _ reason: SystemLanguageModel.Availability.UnavailableReason
  ) -> String {
    switch reason {
    case .deviceNotEligible: return Reason.deviceNotEligible
    case .appleIntelligenceNotEnabled: return Reason.appleIntelligenceNotEnabled
    case .modelNotReady: return Reason.modelNotReady
    @unknown default: return Reason.unknown
    }
  }

  private func requireAvailable() throws {
    guard case .available = SystemLanguageModel.default.availability else {
      throw GenAiError(
        code: ErrorCode.unavailable,
        message: "The on-device model is not available right now."
      )
    }
  }

  // MARK: - Methods

  /// Names every cluster in a single request.
  ///
  /// Deliberately not one call per cluster: the model seeing them together is
  /// what makes the names distinguish each other rather than all landing on
  /// whatever word the person uses most. It also keeps a save to one inference.
  private func labelThemes(_ clusters: [[String: Any]]) async throws -> [String: Any] {
    try requireAvailable()
    guard !clusters.isEmpty else { return ["labels": []] }

    // Ids kept here, never sent to the model; position is the join key.
    var ids: [Int] = []
    var described = ""
    for cluster in clusters {
      guard let id = cluster["id"] as? Int else { continue }
      let sentences = (cluster["sentences"] as? [String]) ?? []
      guard !sentences.isEmpty else { continue }
      ids.append(id)
      described += "\nGroup \(ids.count):\n"
      for sentence in sentences {
        described += "- \(sentence)\n"
      }
    }
    guard !ids.isEmpty else { return ["labels": []] }

    let session = LanguageModelSession(
      instructions: """
        You name recurring themes in someone's private journal.

        For each group of entries, give a short lowercase phrase naming what \
        those entries are actually about. Prefer the underlying concern over \
        the surface words, and make each name distinguish its group from the \
        others. Never invent a theme that is not there, never give advice, and \
        never diagnose.
        """
    )

    let response = try await session.respond(
      to: "Name each of these \(ids.count) groups.\n\(described)",
      generating: ThemeNames.self
    )

    // Zip by position, and only as far as both sides go: a short or long
    // response names fewer themes rather than mislabelling any.
    let names = response.content.names
    var labels: [[String: Any]] = []
    for (index, id) in ids.enumerated() where index < names.count {
      let name = names[index].trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { continue }
      labels.append(["id": id, "label": name])
    }
    return ["labels": labels]
  }

  /// The words shown under one log on its card.
  ///
  /// Per entry rather than batched, unlike `labelThemes`, and the difference is
  /// the point: theme names only mean anything relative to each other, whereas
  /// these describe one entry on its own terms. That is also exactly what the
  /// statistical fallback cannot do — with a single document there is nothing
  /// to be distinctive against, so it degenerates to counting words, and a
  /// short entry where everything appears once comes out as whichever content
  /// words sort first alphabetically.
  private func entryKeywords(_ text: String) async throws -> [String: Any] {
    try requireAvailable()

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return ["keywords": []] }

    let session = LanguageModelSession(
      instructions: """
        You label one entry from someone's private journal with the few words \
        that say what it is about.

        Name what the person is actually dealing with, not the words they \
        happened to use — an entry about carrying shame is about shame, whether \
        or not it says so. Skip filler and anything true of every entry. Never \
        give advice, never diagnose, and never address the person.
        """
    )

    let response = try await session.respond(
      to: "Entry:\n\(trimmed)",
      generating: EntryKeywords.self
    )

    let keywords =
      response.content.keywords
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
      .filter { !$0.isEmpty }
    return ["keywords": Array(keywords.prefix(3))]
  }

  /// The morning-after follow-up. Only ever asked for after a genuinely rough
  /// day, so the prompt is written to acknowledge rather than to cheer up.
  private func followUpQuestion(_ arguments: [String: Any]) async throws -> [String: Any] {
    try requireAvailable()

    let themes = (arguments["themes"] as? [String]) ?? []
    let excerpt = (arguments["excerpt"] as? String) ?? ""
    let tone = (arguments["tone"] as? String) ?? "hard"

    // The day's own character, in one line, because the question that follows a
    // good day and the one that follows a bad day are not the same question and
    // a single prompt cannot write both.
    let opening: String
    let guidance: String
    switch tone {
    case "good":
      opening = "Yesterday went well for them."
      guidance = """
        Ask about the good of it without inflating it or congratulating them. \
        What made it work, or what they want to carry into today. Do not treat \
        a good day as a result to be maintained.
        """
    case "steady":
      opening = "Yesterday was an ordinary day for them."
      guidance = """
        Ask an open question about where they are today. An unremarkable day \
        is still worth noticing, so do not manufacture significance in it.
        """
    default:
      opening = "Yesterday was a hard day for them."
      guidance = """
        Acknowledge what they said without repeating it back wholesale, and ask \
        how it sits today.
        """
    }

    var context = opening
    if !themes.isEmpty {
      context += " What came up: \(themes.joined(separator: ", "))."
    }
    if !excerpt.isEmpty {
      context += " In their words: \"\(excerpt)\""
    }

    let session = LanguageModelSession(
      instructions: """
        You write one short question for someone opening their journal the \
        morning after.

        \(guidance)

        Be warm and plain. Never give advice, never diagnose, never tell them \
        how to feel, and never use an exclamation mark.
        """
    )

    let response = try await session.respond(to: context, generating: Question.self)
    return ["question": response.content.question]
  }

  private func reminderLine(_ arguments: [String: Any]) async throws -> [String: Any] {
    try requireAvailable()
    let themes = (arguments["themes"] as? [String]) ?? []

    let context =
      themes.isEmpty
      ? "They have not written much recently."
      : "Lately they have kept coming back to: \(themes.joined(separator: ", "))."

    let session = LanguageModelSession(
      instructions: """
        You write the single line of a daily notification inviting someone to \
        write in their journal. Warm, quiet, never nagging, never advice. It is \
        read on a lock screen, so keep it very short.
        """
    )

    let response = try await session.respond(to: context, generating: ReminderLine.self)
    return ["line": response.content.line]
  }

  // MARK: - Plumbing

  /// Carries a code + message out of the async paths.
  ///
  /// Note this can't be `FlutterError`: despite the name it's an `NSObject`
  /// that does *not* conform to Swift's `Error`, so it can be returned to a
  /// `FlutterResult` but never thrown.
  private struct GenAiError: Error {
    let code: String
    let message: String
  }

  /// Runs an async body and replies exactly once, mapping every failure onto a
  /// stable code. Generation can fail for reasons that are entirely normal —
  /// a guardrail trip, a context overflow — and none of them should reach the
  /// user as a crash.
  private func run(
    _ reply: ChannelReply,
    _ body: @escaping @Sendable () async throws -> [String: Any]
  ) {
    Task {
      do {
        let value = try await body()
        onMainThread { reply.success(value) }
      } catch let error as GenAiError {
        onMainThread { reply.failure(code: error.code, message: error.message) }
      } catch let error as LanguageModelSession.GenerationError {
        onMainThread {
          reply.failure(
            code: ErrorCode.generationFailed,
            message: String(describing: error)
          )
        }
      } catch {
        onMainThread {
          reply.failure(
            code: ErrorCode.internalFailure,
            // `String(describing:)` rather than `localizedDescription`: the
            // framework's errors are Swift enums whose localized text is the
            // useless "The operation couldn't be completed. (… error -1.)",
            // while the description carries the actual case and its context.
            message: String(describing: error)
          )
        }
      }
    }
  }
}
