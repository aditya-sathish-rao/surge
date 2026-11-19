import Foundation
import SurgeCore

/// Tails pi session transcripts, one JSONL file per session.
struct PiSessionAdapter: TranscriptSourceAdapter {
    static let provider = "pi"

    static let capabilities = SourceCapabilities(
        transport: .appendOnlyJSONLFile,
        checkpoint: .byteOffset,
        providesUsage: true,
        // pi records a cost on every usage, flagged with `totalFromProvider` when it is billed.
        providesCost: true,
        providesCompactionMarkers: false,
        // A pi worker is its own session with no parent link. A `/fork` or `/clone` parent session
        // is not a worker parent, so the tailer reports the link as unavailable rather than guessing.
        providesParentSessionLink: false
    )

    let root: URL
    let pricing: PricingTable
    let now: @Sendable () -> Date

    var info: TranscriptSourceInfo {
        TranscriptSourceInfo(
            kind: .piAgent,
            provider: Self.provider,
            displayName: "pi",
            root: root,
            capabilities: Self.capabilities
        )
    }

    func discover(now: Date) -> [SourceFile] {
        SourceScanner(root: root, now: self.now, identity: SourceLayout.pi).discover()
    }

    func makeReader() -> any TranscriptFileReader {
        PiSessionReader(pricing: pricing)
    }
}

/// One pi session line at a time.
///
/// pi writes the model as a separate `model_change` record rather than on every message, so the
/// reader keeps the current model and re-reads it whenever the record changes.
struct PiSessionReader: TranscriptFileReader {
    let pricing: PricingTable
    private var model: String?
    private var projectPath: String?

    mutating func ingest(line: Data, at date: Date) -> SourceEntry {
        guard let record = try? JSONDecoder().decode(PiSessionRecord.self, from: line) else {
            return SourceEntry()
        }
        switch record.type {
        case "session":
            if let cwd = record.cwd, !cwd.isEmpty {
                projectPath = cwd
            }
            return SourceEntry(projectPath: projectPath)
        case "model_change":
            if let modelID = record.modelId, !modelID.isEmpty {
                model = modelID
            }
            return SourceEntry()
        case "message":
            return turn(from: record, at: date)
        default:
            // thinking_level_change, custom, custom_message, compaction, usage, label and the rest
            // are metadata. They are never turns.
            return SourceEntry()
        }
    }

    private mutating func turn(from record: PiSessionRecord, at date: Date) -> SourceEntry {
        guard
            let message = record.message,
            message.role == "assistant",
            let usage = message.usage,
            usage.describesTurn
        else { return SourceEntry() }

        // The message names the physical model that answered; a model_change sets the model for a
        // message that does not name one.
        let modelName = message.model.flatMap { $0.isEmpty ? nil : $0 } ?? model
        guard let modelName else { return SourceEntry() }

        let inputTokens = usage.input ?? 0
        let outputTokens = usage.output ?? 0
        // pi's input is the uncached prompt, so the context footprint adds both cache directions.
        let cacheReadTokens = usage.cacheRead ?? 0
        let cacheWriteTokens = usage.cacheWrite ?? 0
        return SourceEntry(
            projectPath: projectPath,
            turn: SourceTurn(
                model: modelName,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheHitTokens: cacheReadTokens,
                currentContextTokens: inputTokens + cacheReadTokens + cacheWriteTokens,
                occurredAt: record.occurredAt,
                cost: cost(
                    reported: usage.cost,
                    modelName: modelName,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cacheHitTokens: cacheReadTokens
                )
            )
        )
    }

    private func cost(
        reported: PiUsageCost?,
        modelName: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheHitTokens: Int
    ) -> TurnCost {
        if let reported, let total = reported.total {
            return reported.totalFromProvider == true
                ? .providerReported(total)
                : .locallyEstimated(total)
        }
        let estimate = pricing.estimatedCostUSD(
            forModel: modelName,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheHitTokens: cacheHitTokens
        )
        return estimate.map(TurnCost.locallyEstimated) ?? .unavailable
    }
}

/// The part of one pi session line the tailer reads.
///
/// Only metadata and numbers are declared. Message content is not a property of this type, so
/// prompt, response and tool-output text can never be decoded, stored, logged or published.
struct PiSessionRecord: Decodable {
    let type: String?
    let cwd: String?
    let timestamp: String?
    let modelId: String?
    let message: PiMessage?

    var occurredAt: Date? {
        if let timestamp, let date = TranscriptTimestamp.parse(timestamp) {
            return date
        }
        guard let milliseconds = message?.timestamp else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}

struct PiMessage: Decodable {
    let role: String?
    let model: String?
    let usage: PiUsage?
    /// A Unix timestamp in milliseconds.
    let timestamp: Double?
}

/// pi's usage in its own field names.
struct PiUsage: Decodable {
    let input: Int?
    let output: Int?
    let cacheRead: Int?
    let cacheWrite: Int?
    /// Recorded because the format carries it, but `TurnAppended` has no field for it.
    let reasoning: Int?
    let totalTokens: Int?
    let cost: PiUsageCost?

    var describesTurn: Bool {
        // pi writes all four counts. A record missing one is incomplete, and `TurnAppended` has no
        // way to say a count is unavailable, so the turn is left out rather than published as zero.
        input != nil && output != nil && cacheRead != nil && cacheWrite != nil
    }

    enum CodingKeys: String, CodingKey {
        case input
        case output
        case cacheRead
        case cacheWrite
        case reasoning
        case totalTokens
        case cost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = TokenCount.int(in: container, forKey: .input)
        output = TokenCount.int(in: container, forKey: .output)
        cacheRead = TokenCount.int(in: container, forKey: .cacheRead)
        cacheWrite = TokenCount.int(in: container, forKey: .cacheWrite)
        reasoning = TokenCount.int(in: container, forKey: .reasoning)
        totalTokens = TokenCount.int(in: container, forKey: .totalTokens)
        cost = try? container.decodeIfPresent(PiUsageCost.self, forKey: .cost)
    }
}

struct PiUsageCost: Decodable {
    let total: Double?
    /// True when `total` is what the provider billed, absent or false when it is pi's estimate.
    let totalFromProvider: Bool?
}
