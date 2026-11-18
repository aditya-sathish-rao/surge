import Foundation

/// The part of one transcript JSON line the tailer reads.
///
/// Only metadata and token counts are declared. Prompt and response content is not a
/// property of this type, so it can never be decoded, stored, logged or published.
struct TranscriptRecord: Decodable {
    static let provider = "anthropic"
    /// Claude Code writes bookkeeping messages under this model name. They are not model turns.
    static let syntheticModel = "<synthetic>"

    let type: String?
    let cwd: String?
    let timestamp: String?
    let message: Message?

    enum CodingKeys: String, CodingKey {
        case type
        case cwd
        case timestamp
        case message
    }

    struct Message: Decodable {
        let model: String?
        let usage: TranscriptUsage?
    }

    /// The metadata and numbers one line contributes, if any.
    struct ParsedEntry {
        let projectPath: String?
        let turn: ParsedTurn?
    }

    struct ParsedTurn {
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheCreationTokens: Int
        let occurredAt: Date?
    }

    func parse() -> ParsedEntry {
        guard
            type == "assistant",
            let message,
            let usage = message.usage,
            usage.describesTurn,
            let model = message.model,
            !model.isEmpty,
            model != TranscriptRecord.syntheticModel
        else {
            return ParsedEntry(projectPath: workingDirectory, turn: nil)
        }
        return ParsedEntry(
            projectPath: workingDirectory,
            turn: ParsedTurn(
                model: model,
                inputTokens: usage.inputTokens ?? 0,
                outputTokens: usage.outputTokens ?? 0,
                cacheReadTokens: usage.cacheReadInputTokens ?? 0,
                cacheCreationTokens: usage.cacheCreationInputTokens ?? 0,
                occurredAt: timestamp.flatMap(TranscriptRecord.parseTimestamp)
            )
        )
    }

    static func parseTimestamp(_ value: String) -> Date? {
        if let date = try? Date(value, strategy: .iso8601) {
            return date
        }
        return try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    private var workingDirectory: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return cwd
    }
}

/// The token counts of one model response, in Claude Code's field names.
struct TranscriptUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?

    /// True when the entry carries token counts, whatever their value.
    var describesTurn: Bool {
        inputTokens != nil || outputTokens != nil
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = Self.count(in: container, forKey: .inputTokens)
        outputTokens = Self.count(in: container, forKey: .outputTokens)
        cacheReadInputTokens = Self.count(in: container, forKey: .cacheReadInputTokens)
        cacheCreationInputTokens = Self.count(in: container, forKey: .cacheCreationInputTokens)
    }

    /// A token count that is not an integer is ignored instead of failing the whole line.
    private static func count(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}
