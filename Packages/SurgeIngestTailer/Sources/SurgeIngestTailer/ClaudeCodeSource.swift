import Foundation
import SurgeCore

/// Tails Claude Code transcripts, one JSONL file per session.
struct ClaudeCodeAdapter: TranscriptSourceAdapter {
    static let provider = TranscriptRecord.provider

    static let capabilities = SourceCapabilities(
        transport: .appendOnlyJSONLFile,
        checkpoint: .byteOffset,
        providesUsage: true,
        // The transcript records tokens, not a billed amount. The turn cost is priced here instead.
        providesCost: false,
        providesCompactionMarkers: false,
        providesParentSessionLink: true
    )

    let root: URL
    let pricing: PricingTable
    let now: @Sendable () -> Date

    var info: TranscriptSourceInfo {
        TranscriptSourceInfo(
            kind: .claudeCode,
            provider: Self.provider,
            displayName: "Claude Code",
            root: root,
            capabilities: Self.capabilities
        )
    }

    func discover(now: Date) -> [SourceFile] {
        SourceScanner(root: root, now: self.now, identity: SourceLayout.claudeCode).discover()
    }

    func makeReader() -> any TranscriptFileReader {
        ClaudeCodeReader(pricing: pricing)
    }
}

/// One Claude Code line at a time. Claude repeats the model and the working directory on every
/// assistant line, so the reader's only carried state is the harness's running cost total.
struct ClaudeCodeReader: TranscriptFileReader {
    let pricing: PricingTable
    private var harnessCumulativeUSD: Double?

    init(pricing: PricingTable) {
        self.pricing = pricing
    }

    mutating func ingest(line: Data, at date: Date) -> SourceEntry {
        guard let record = try? JSONDecoder().decode(TranscriptRecord.self, from: line) else {
            return SourceEntry()
        }
        let entry = record.parse()
        if let harnessCost = entry.harnessCostUSD {
            harnessCumulativeUSD = harnessCost
        }
        let metadata = SourceEntry(
            projectPath: entry.projectPath,
            messageUUID: record.uuid,
            // Only a sidechain turn names the top-level turn that spawned it. Every other turn's
            // `parentUuid` is simply the previous message.
            parentUUID: record.isSidechain == true ? record.parentUuid : nil,
            harnessVersion: record.version
        )
        guard let turn = entry.turn else { return metadata }
        let cost =
            pricing.estimatedCostUSD(
                forModel: turn.model,
                inputTokens: turn.inputTokens,
                outputTokens: turn.outputTokens,
                cacheHitTokens: turn.cacheReadTokens
            ).map(TurnCost.locallyEstimated) ?? .unavailable
        return SourceEntry(
            projectPath: entry.projectPath,
            turn: SourceTurn(
                model: turn.model,
                inputTokens: turn.inputTokens,
                outputTokens: turn.outputTokens,
                cacheHitTokens: turn.cacheReadTokens,
                currentContextTokens: turn.inputTokens + turn.cacheReadTokens + turn.cacheCreationTokens,
                occurredAt: turn.occurredAt,
                cost: cost,
                eventID: record.uuid,
                harnessCumulativeCostUSD: harnessCumulativeUSD
            ),
            messageUUID: record.uuid,
            parentUUID: record.isSidechain == true ? record.parentUuid : nil,
            harnessVersion: record.version
        )
    }
}
