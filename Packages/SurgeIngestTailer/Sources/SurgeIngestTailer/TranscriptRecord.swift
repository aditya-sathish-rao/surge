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
    /// The id of this record, used to de-duplicate repeated writes.
    let uuid: String?
    /// The record this one follows. A sidechain turn points at the turn that spawned it.
    let parentUuid: String?
    /// True for a turn written by a sub-agent rather than the top-level session.
    let isSidechain: Bool?
    let sessionId: String?
    let version: String?
    /// The harness's own running total for the session, written on a `cost-state` record.
    let totalCostUSD: Double?
    /// True when the harness could not price every turn it counted, so its total is not trusted.
    let hasUnknownModelCost: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case cwd
        case timestamp
        case message
        case uuid
        case parentUuid
        case isSidechain
        case sessionId
        case version
        case totalCostUSD
        case hasUnknownModelCost
    }

    struct Message: Decodable {
        let model: String?
        let usage: TranscriptUsage?
    }

    /// The metadata and numbers one line contributes, if any.
    struct ParsedEntry {
        let projectPath: String?
        let turn: ParsedTurn?
        /// The harness's running cost when this line carried one.
        let harnessCostUSD: Double?
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
        if type == "cost-state" {
            // The harness's own running total. It is computed at Anthropic list prices, so it is
            // only the bill when Anthropic is the account that pays.
            let reported = hasUnknownModelCost == true ? nil : totalCostUSD
            return ParsedEntry(projectPath: workingDirectory, turn: nil, harnessCostUSD: reported)
        }
        guard
            type == "assistant",
            let message,
            let usage = message.usage,
            usage.describesTurn,
            let model = message.model,
            !model.isEmpty,
            model != TranscriptRecord.syntheticModel
        else {
            return ParsedEntry(projectPath: workingDirectory, turn: nil, harnessCostUSD: nil)
        }
        return ParsedEntry(
            projectPath: workingDirectory,
            turn: ParsedTurn(
                model: model,
                inputTokens: usage.inputTokens ?? 0,
                outputTokens: usage.outputTokens ?? 0,
                cacheReadTokens: usage.cacheReadInputTokens ?? 0,
                cacheCreationTokens: usage.cacheCreationInputTokens ?? 0,
                occurredAt: timestamp.flatMap(TranscriptTimestamp.parse)
            ),
            harnessCostUSD: nil
        )
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
        inputTokens = TokenCount.int(in: container, forKey: .inputTokens)
        outputTokens = TokenCount.int(in: container, forKey: .outputTokens)
        cacheReadInputTokens = TokenCount.int(in: container, forKey: .cacheReadInputTokens)
        cacheCreationInputTokens = TokenCount.int(in: container, forKey: .cacheCreationInputTokens)
    }
}
