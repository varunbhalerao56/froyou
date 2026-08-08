import Flutter
import Foundation
import NaturalLanguage

/// One MethodChannel (`app/nlp`) covering all four NaturalLanguage features.
///
/// They live in the same Swift framework and are all simple request→response
/// calls, so a single handler switching on `call.method` beats four separate
/// channels: one registration, one error-mapping policy, one place to look.
/// Speech transcription is kept apart precisely because it *isn't* this shape.
///
/// Methods:
/// - `splitSentences` — `NLTokenizer(.sentence)`
/// - `sentimentScore` — `NLTagger(.sentimentScore)`
/// - `extractEntities` — `NLTagger(.nameType)`
/// - `embed` — `NLContextualEmbedding` + native mean-pooling
///
/// Of these, only `embed` needs a downloaded on-device asset; the first three
/// are built into the OS and always available.
final class NlpChannel: NSObject {

  static let channelName = "app/nlp"

  /// Stable error codes — matched on by `NlpException` in Dart.
  private enum ErrorCode {
    static let badArguments = "nlp_bad_arguments"
    static let unsupportedLanguage = "nlp_unsupported_language"
    static let assetsUnavailable = "nlp_assets_unavailable"
    static let internalFailure = "nlp_internal"
  }

  /// Carries a code + message out of the async embedding path.
  ///
  /// Note this can't be `FlutterError`: despite the name it's an `NSObject`
  /// that does *not* conform to Swift's `Error`, so it can be returned to a
  /// `FlutterResult` but never thrown.
  private struct EmbeddingError: Error {
    let code: String
    let message: String
  }

  /// `NLTokenizer` and `NLTagger` are synchronous and can take tens of
  /// milliseconds on a long document — well past the frame budget — so they run
  /// off the platform thread. `.userInitiated` because a human is waiting.
  private let queue = DispatchQueue(label: "app.nlp.channel", qos: .userInitiated)

  /// Loading an `NLContextualEmbedding` is expensive, so instances are cached
  /// per language. Reachable from both `queue` and the `Task` used by `embed`,
  /// hence the lock.
  private let embeddingsLock = NSLock()
  private var embeddings: [NLLanguage: NLContextualEmbedding] = [:]

  // MARK: - Registration

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, reply: ChannelReply(result))
    }
  }

  // MARK: - Method dispatch

  private func handle(_ call: FlutterMethodCall, reply: ChannelReply) {
    let args = call.arguments as? [String: Any] ?? [:]

    guard let text = args["text"] as? String else {
      reply.failure(code: ErrorCode.badArguments, message: "Missing 'text' argument.")
      return
    }

    switch call.method {
    case "splitSentences":
      queue.async { reply.success(Self.splitSentences(text)) }

    case "sentimentScore":
      queue.async { reply.success(Self.sentimentScore(text)) }

    case "extractEntities":
      queue.async { reply.success(Self.extractEntities(text)) }

    case "embed":
      let language = args["language"] as? String
      let normalize = args["normalize"] as? Bool ?? false
      embed(text: text, language: language, normalize: normalize, reply: reply)

    case "embedSentences":
      let language = args["language"] as? String
      let normalize = args["normalize"] as? Bool ?? false
      embedSentences(text: text, language: language, normalize: normalize, reply: reply)

    default:
      reply.notImplemented()
    }
  }

  // MARK: - Sentence splitting

  /// Splits `text` into sentences. Handles the cases a naive split on `.`
  /// cannot — abbreviations ("Dr. Smith"), decimals, ellipses.
  private static func splitSentences(_ text: String) -> [String] {
    sentenceRanges(in: text).map { String(text[$0]) }
  }

  /// The ranges `splitSentences` and `embedSentences` both work from, so the
  /// two can never disagree about where a sentence starts.
  ///
  /// Returns *ranges* rather than strings because `embedSentences` needs to
  /// report offsets back to Dart, and re-finding a trimmed substring in the
  /// original is both wasteful and wrong when the same sentence repeats.
  private static func sentenceRanges(in text: String) -> [Range<String.Index>] {
    guard !text.isEmpty else { return [] }

    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text

    return tokenizer.tokens(for: text.startIndex..<text.endIndex)
      .compactMap { trimming($0, in: text) }
  }

  /// Shrinks a range past leading and trailing whitespace.
  ///
  /// Note this trims the *range*, not the extracted string — trimming the
  /// string afterwards would leave the offsets pointing at the untrimmed span,
  /// so `text.substring(start, end)` would no longer equal the sentence we
  /// handed back. Returns `nil` for a range that is entirely whitespace.
  private static func trimming(
    _ range: Range<String.Index>,
    in text: String
  ) -> Range<String.Index>? {
    var lower = range.lowerBound
    var upper = range.upperBound

    while lower < upper, text[lower].isWhitespace {
      lower = text.index(after: lower)
    }
    while lower < upper {
      let previous = text.index(before: upper)
      guard text[previous].isWhitespace else { break }
      upper = previous
    }

    return lower < upper ? lower..<upper : nil
  }

  // MARK: - Sentiment

  /// Sentiment for the whole input, in `-1.0` (negative) … `1.0` (positive).
  ///
  /// Returns `0.0` when the tagger has no opinion, which is also what neutral
  /// text scores — the API doesn't distinguish the two, so neither do we.
  private static func sentimentScore(_ text: String) -> Double {
    guard !text.isEmpty else { return 0.0 }

    let tagger = NLTagger(tagSchemes: [.sentimentScore])
    tagger.string = text

    // `.paragraph` is the unit the sentiment scheme operates on; asking at
    // `.word` or `.sentence` yields nothing.
    let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
    guard let value = tag?.rawValue, let score = Double(value) else { return 0.0 }
    return score
  }

  // MARK: - Named entities

  /// Extracts people, places and organizations.
  ///
  /// `start` / `end` are UTF-16 code-unit offsets, which is exactly how Dart
  /// indexes `String` — so `dartString.substring(start, end)` returns `text`
  /// verbatim, including for input containing emoji or other non-BMP
  /// characters. Converting through `NSRange` is what makes that true; handing
  /// back Swift `String.Index` distances would not.
  private static func extractEntities(_ text: String) -> [[String: Any]] {
    guard !text.isEmpty else { return [] }

    let tagger = NLTagger(tagSchemes: [.nameType])
    tagger.string = text

    var entities: [[String: Any]] = []
    let interestingTags: Set<NLTag> = [.personalName, .placeName, .organizationName]

    tagger.enumerateTags(
      in: text.startIndex..<text.endIndex,
      unit: .word,
      scheme: .nameType,
      // `.joinNames` keeps "Tim Cook" as one entity instead of two tokens.
      options: [.omitPunctuation, .omitWhitespace, .joinNames]
    ) { tag, range in
      guard let tag, interestingTags.contains(tag) else { return true }

      let nsRange = NSRange(range, in: text)
      entities.append([
        "text": String(text[range]),
        "type": tag.rawValue,
        "start": nsRange.location,
        "end": nsRange.location + nsRange.length,
      ])
      return true
    }

    return entities
  }

  // MARK: - Contextual embeddings

  /// Produces a single fixed-length vector for `text` by mean-pooling the
  /// per-token vectors natively — pooling here rather than in Dart avoids
  /// shipping `tokenCount × dimension` doubles across the channel for a result
  /// that gets collapsed anyway.
  ///
  /// If the model's assets aren't on the device this requests them and waits.
  /// That download can be slow, but unlike speech there is nothing useful to
  /// show mid-call, so it's transparent rather than a separate `ensureModel`
  /// step.
  private func embed(text: String, language: String?, normalize: Bool, reply: ChannelReply) {
    guard !text.isEmpty else {
      reply.success([Double]())
      return
    }

    guard let resolved = Self.resolveLanguage(explicit: language, detectingIn: text, reply: reply)
    else { return }

    Task {
      do {
        let model = try await self.loadEmbedding(for: resolved)
        let result = try model.embeddingResult(for: text, language: resolved)
        let vector = Self.meanPooled(result, over: text, dimension: model.dimension)
        reply.success(normalize ? Self.l2Normalized(vector) : vector)
      } catch let error as EmbeddingError {
        reply.failure(code: error.code, message: error.message)
      } catch {
        reply.failure(code: ErrorCode.internalFailure, message: error.localizedDescription)
      }
    }
  }

  /// One vector per sentence, with the sentence split done here rather than in
  /// Dart.
  ///
  /// Each sentence is embedded **independently** — `embeddingResult` is called
  /// once per sentence, not once over the whole text. That is deliberate. The
  /// model is contextual, so tokens attend to everything in the string they are
  /// passed with; embedding the paragraph in one pass would make a sentence's
  /// vector depend on its neighbours, and the same sentence written on two
  /// different days would land in two different places. Isolating each sentence
  /// keeps sentence→vector a pure function, which is what makes these vectors
  /// safe to store and compare across entries.
  ///
  /// The language is detected once over the *whole* text and then passed
  /// explicitly to every sentence — detection on a single short sentence is
  /// unreliable, and this is a concrete win from doing the split natively.
  private func embedSentences(
    text: String,
    language: String?,
    normalize: Bool,
    reply: ChannelReply
  ) {
    let ranges = Self.sentenceRanges(in: text)
    guard !ranges.isEmpty else {
      reply.success([Any]())
      return
    }

    guard let resolved = Self.resolveLanguage(explicit: language, detectingIn: text, reply: reply)
    else { return }

    Task {
      do {
        let model = try await self.loadEmbedding(for: resolved)

        var output: [[String: Any]] = []
        output.reserveCapacity(ranges.count)

        for range in ranges {
          let sentence = String(text[range])
          let result = try model.embeddingResult(for: sentence, language: resolved)
          var vector = Self.meanPooled(result, over: sentence, dimension: model.dimension)
          if normalize { vector = Self.l2Normalized(vector) }

          // UTF-16 offsets, so these index into the Dart string directly.
          let nsRange = NSRange(range, in: text)
          output.append([
            "sentence": sentence,
            "vector": vector,
            "start": nsRange.location,
            "end": nsRange.location + nsRange.length,
          ])
        }

        reply.success(output)
      } catch let error as EmbeddingError {
        reply.failure(code: error.code, message: error.message)
      } catch {
        reply.failure(code: ErrorCode.internalFailure, message: error.localizedDescription)
      }
    }
  }

  /// An explicit language wins; otherwise detect it over the supplied text.
  ///
  /// Replies with a failure and returns `nil` when detection fails, which it
  /// legitimately can on very short or ambiguous input.
  private static func resolveLanguage(
    explicit: String?,
    detectingIn text: String,
    reply: ChannelReply
  ) -> NLLanguage? {
    if let explicit { return NLLanguage(rawValue: explicit) }
    if let detected = NLLanguageRecognizer.dominantLanguage(for: text) { return detected }

    reply.failure(
      code: ErrorCode.unsupportedLanguage,
      message: "Could not determine the language of the text; pass 'language' explicitly."
    )
    return nil
  }

  /// Returns a loaded model for `language`, downloading assets if needed.
  /// Cached, so only the first call per language pays the cost.
  private func loadEmbedding(for language: NLLanguage) async throws -> NLContextualEmbedding {
    embeddingsLock.lock()
    let cached = embeddings[language]
    embeddingsLock.unlock()
    if let cached { return cached }

    guard let model = NLContextualEmbedding(language: language) else {
      throw EmbeddingError(
        code: ErrorCode.unsupportedLanguage,
        message: "No contextual embedding model exists for language '\(language.rawValue)'."
      )
    }

    if !model.hasAvailableAssets {
      // Swift imports `requestEmbeddingAssetsWithCompletionHandler:` as
      // `requestAssets(completionHandler:)` — the "Embedding" is dropped as a
      // needless word given the receiver's type. Driving the completion-handler
      // form through a continuation rather than any synthesised `async` overload
      // keeps this independent of how a two-parameter `(result, NSError*)`
      // handler happens to import.
      let available: Bool = await withCheckedContinuation { continuation in
        model.requestAssets { result, _ in
          continuation.resume(returning: result == .available)
        }
      }
      guard available else {
        throw EmbeddingError(
          code: ErrorCode.assetsUnavailable,
          message: "Embedding assets for '\(language.rawValue)' could not be downloaded."
        )
      }
    }

    try model.load()

    embeddingsLock.lock()
    embeddings[language] = model
    embeddingsLock.unlock()

    return model
  }

  /// Averages the per-token vectors into one `dimension`-length vector.
  private static func meanPooled(
    _ result: NLContextualEmbeddingResult,
    over text: String,
    dimension: Int
  ) -> [Double] {
    var sum = [Double](repeating: 0, count: dimension)
    var count = 0

    result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
      // Guard rather than assume: a mismatched length would otherwise crash on
      // the index below.
      guard vector.count == dimension else { return true }
      for index in 0..<dimension {
        sum[index] += vector[index]
      }
      count += 1
      return true
    }

    guard count > 0 else { return sum }
    let divisor = Double(count)
    return sum.map { $0 / divisor }
  }

  /// Scales to unit length, so callers can use a plain dot product as cosine
  /// similarity. Leaves an all-zero vector alone rather than dividing by zero.
  private static func l2Normalized(_ vector: [Double]) -> [Double] {
    let magnitude = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
    guard magnitude > 0 else { return vector }
    return vector.map { $0 / magnitude }
  }
}
