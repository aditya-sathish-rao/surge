import Foundation
import SurgeCore

/// One transcript file found under a source's root.
struct SourceFile {
    let url: URL
    let path: String
    let sessionID: String
    let parentSessionID: String?
    let modificationDate: Date
    let size: UInt64
    let fileNumber: UInt64?
}

/// The only record of a turn's cost: billed by the provider, computed by the harness, or priced
/// from the local table.
///
/// A harness's own running total is not a per-turn cost, so it travels beside the turn as
/// `harnessCumulativeCostUSD` rather than as a case here.
enum TurnCost: Equatable {
    case providerReported(Double)
    case harnessReported(Double)
    case locallyEstimated(Double)
    case unavailable

    var providerReportedUSD: Double? {
        guard case .providerReported(let amount) = self else { return nil }
        return amount
    }

    var harnessReportedUSD: Double? {
        guard case .harnessReported(let amount) = self else { return nil }
        return amount
    }
}

/// The numbers and metadata of one turn, already named the way the event names them.
struct SourceTurn {
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheHitTokens: Int
    let currentContextTokens: Int
    let occurredAt: Date?
    let cost: TurnCost
    /// The record's own id, so a repeated write cannot be counted twice.
    let eventID: String?
    /// The harness's cumulative cost for the session at this turn, when it reports one.
    let harnessCumulativeCostUSD: Double?

    init(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheHitTokens: Int,
        currentContextTokens: Int,
        occurredAt: Date?,
        cost: TurnCost,
        eventID: String? = nil,
        harnessCumulativeCostUSD: Double? = nil
    ) {
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheHitTokens = cacheHitTokens
        self.currentContextTokens = currentContextTokens
        self.occurredAt = occurredAt
        self.cost = cost
        self.eventID = eventID
        self.harnessCumulativeCostUSD = harnessCumulativeCostUSD
    }
}

/// What one transcript line adds to the running state of its file.
struct SourceEntry {
    let projectPath: String?
    /// The provider family that bills this session, when the record names one. It is never the
    /// harness name: a harness can be billed by more than one account.
    let provider: String?
    let turn: SourceTurn?
    /// The record's id, indexed so a sidechain turn can find the session it belongs to.
    let messageUUID: String?
    /// The turn that spawned a sidechain record, when the source marks one.
    let parentUUID: String?
    /// The harness version the record names, when it names one.
    let harnessVersion: String?

    init(
        projectPath: String? = nil,
        provider: String? = nil,
        turn: SourceTurn? = nil,
        messageUUID: String? = nil,
        parentUUID: String? = nil,
        harnessVersion: String? = nil
    ) {
        self.projectPath = projectPath
        self.provider = provider
        self.turn = turn
        self.messageUUID = messageUUID
        self.parentUUID = parentUUID
        self.harnessVersion = harnessVersion
    }
}

/// Decoding state for one transcript file.
///
/// A source that carries a value across lines, such as pi's current model, keeps it here so the
/// tailer never has to re-read earlier bytes. A source with no such state leaves the method alone.
protocol TranscriptFileReader {
    mutating func ingest(line: Data, at date: Date) -> SourceEntry
}

/// One harness the tailer reads. Adding a harness means adding a conforming type and a kind.
protocol TranscriptSourceAdapter: Sendable {
    var info: TranscriptSourceInfo { get }
    func discover(now: Date) -> [SourceFile]
    func makeReader() -> any TranscriptFileReader
}

/// How a source turns a relative file path into a session identity.
struct SourceIdentity {
    let sessionID: String
    let parentSessionID: String?
}

/// Walks a source root and describes every transcript file it finds.
struct SourceScanner {
    let root: URL
    let now: @Sendable () -> Date
    let identity: @Sendable (_ url: URL, _ relativeComponents: [String]) -> SourceIdentity

    func discover() -> [SourceFile] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else { return [] }

        let rootComponents = root.standardizedFileURL.pathComponents
        var found: [SourceFile] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == TailerDefaults.transcriptExtension else { continue }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                let size = (attributes[.size] as? NSNumber)?.uint64Value
            else { continue }
            let components = url.standardizedFileURL.pathComponents
            guard components.count > rootComponents.count else { continue }
            let relative = Array(components.dropFirst(rootComponents.count))
            let identity = identity(url, relative)
            found.append(
                SourceFile(
                    url: url,
                    path: url.path,
                    sessionID: identity.sessionID,
                    parentSessionID: identity.parentSessionID,
                    modificationDate: (attributes[.modificationDate] as? Date) ?? now(),
                    size: size,
                    fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
                )
            )
        }
        return found.sorted { $0.path < $1.path }
    }
}

/// The directory layouts of the sources Surge reads.
enum SourceLayout {
    /// `~/.claude/projects/<project>/<session>.jsonl`, plus
    /// `~/.claude/projects/<project>/<session>/subagents/agent-x.jsonl`, which belongs to `<session>`.
    static func claudeCode(url: URL, relativeComponents: [String]) -> SourceIdentity {
        SourceIdentity(
            sessionID: url.deletingPathExtension().lastPathComponent,
            parentSessionID: claudeCodeParent(in: relativeComponents)
        )
    }

    /// `~/.pi/agent/sessions/--<path>--/<timestamp>_<session-id>.jsonl`.
    ///
    /// pi has no in-session sub-agents: a worker is its own session with its own file, and the
    /// only lineage a file records is a `/fork` or `/clone` parent session, which is not a worker
    /// parent. The tailer reports that as unavailable instead of inferring one.
    static func pi(url: URL, relativeComponents: [String]) -> SourceIdentity {
        SourceIdentity(
            sessionID: piSessionID(from: url),
            parentSessionID: nil
        )
    }

    private static func claudeCodeParent(in relativeComponents: [String]) -> String? {
        guard
            let index = relativeComponents.firstIndex(of: TailerDefaults.subagentsDirectory),
            index >= 2
        else { return nil }
        return relativeComponents[index - 1]
    }

    private static func piSessionID(from url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        guard let separator = stem.lastIndex(of: "_") else { return stem }
        let suffix = stem[stem.index(after: separator)...]
        return suffix.isEmpty ? stem : String(suffix)
    }
}

/// Parses an ISO 8601 timestamp, with or without fractional seconds.
enum TranscriptTimestamp {
    static func parse(_ value: String) -> Date? {
        if let date = try? Date(value, strategy: .iso8601) {
            return date
        }
        return try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}

/// Reads a token count written as either an integer or a floating point number.
enum TokenCount {
    static func int<Key: CodingKey>(
        in container: KeyedDecodingContainer<Key>,
        forKey key: Key
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
