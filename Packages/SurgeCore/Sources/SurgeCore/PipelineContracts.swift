import Foundation

public protocol SessionTailing: Sendable {
    func events() -> AsyncStream<TailerEvent>
}

public protocol WorkerTraffic: Sendable {
    func events() -> AsyncStream<ProxyEvent>
}

public protocol WalletPolling: Sendable {
    func updates() -> AsyncStream<BalanceUpdate>
}

public struct SessionDescriptor: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let projectPath: String
    public let provider: String
    public let modelName: String
    public let maxContextWindow: Int
    public let occurredAt: Date
    /// Which harness wrote this session, and by which transport. Nil for a source that cannot say.
    public let harness: HarnessIdentity?
    /// The session that spawned this one, when the harness records the link. A sub-agent inherits
    /// its parent's billing account instead of resolving its own.
    public let parentSessionID: String?

    public init(
        id: String,
        projectPath: String,
        provider: String,
        modelName: String,
        maxContextWindow: Int,
        occurredAt: Date,
        harness: HarnessIdentity? = nil,
        parentSessionID: String? = nil
    ) {
        self.id = id
        self.projectPath = projectPath
        self.provider = provider
        self.modelName = modelName
        self.maxContextWindow = maxContextWindow
        self.occurredAt = occurredAt
        self.harness = harness
        self.parentSessionID = parentSessionID
    }
}

/// Token counts on a turn event are per-turn increments. `currentContextTokens` is a snapshot of the prompt size.
public struct TurnAppended: Codable, Sendable, Equatable {
    public let sessionID: String
    public let modelName: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheHitTokens: Int
    public let currentContextTokens: Int
    public let occurredAt: Date
    /// The record's own id within its harness. Repeats from branched, resumed or sub-agent writes
    /// must not be counted twice, so the store de-duplicates on it inside a session tree.
    public let eventID: String?
    /// The harness's cumulative cost for the session at this turn, at its own list prices. The
    /// store books only the increase. Claude Code's `totalCostUSD` is this figure, and it is not
    /// the bill when the session is routed to a different provider.
    public let harnessReportedCostUSD: Double?

    public init(
        sessionID: String,
        modelName: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheHitTokens: Int,
        currentContextTokens: Int,
        occurredAt: Date,
        eventID: String? = nil,
        harnessReportedCostUSD: Double? = nil
    ) {
        self.sessionID = sessionID
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheHitTokens = cacheHitTokens
        self.currentContextTokens = currentContextTokens
        self.occurredAt = occurredAt
        self.eventID = eventID
        self.harnessReportedCostUSD = harnessReportedCostUSD
    }
}

public enum TailerEvent: Codable, Sendable, Equatable {
    case sessionAppeared(SessionDescriptor)
    case turnAppended(TurnAppended)
    case sessionEnded(sessionID: String, occurredAt: Date)
}

public struct WorkerDescriptor: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let provider: String
    public let modelName: String
    public let projectPath: String
    public let parentSessionID: String?
    public let occurredAt: Date
    /// A proxy worker is not a harness: it is whatever program pointed its base URL at Surge.
    public let harness: HarnessIdentity?

    public init(
        id: String,
        provider: String,
        modelName: String,
        projectPath: String,
        parentSessionID: String?,
        occurredAt: Date,
        harness: HarnessIdentity? = nil
    ) {
        self.id = id
        self.provider = provider
        self.modelName = modelName
        self.projectPath = projectPath
        self.parentSessionID = parentSessionID
        self.occurredAt = occurredAt
        self.harness = harness
    }
}

/// Token counts on usage events are per-request increments. `currentContextTokens` is the prompt size of that request.
/// `reportedCostUSD` is the provider's own exact cost for the call when it reports one; it is
/// authoritative and needs no local price table.
public struct ProxyUsage: Codable, Sendable, Equatable {
    public let workerID: String
    public let provider: String
    public let modelName: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheHitTokens: Int
    public let currentContextTokens: Int
    public let occurredAt: Date
    public let reportedCostUSD: Double?

    public init(
        workerID: String,
        provider: String,
        modelName: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheHitTokens: Int,
        currentContextTokens: Int,
        occurredAt: Date,
        reportedCostUSD: Double? = nil
    ) {
        self.workerID = workerID
        self.provider = provider
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheHitTokens = cacheHitTokens
        self.currentContextTokens = currentContextTokens
        self.occurredAt = occurredAt
        self.reportedCostUSD = reportedCostUSD
    }
}

public enum ProxyEvent: Codable, Sendable, Equatable {
    case workerAppeared(WorkerDescriptor)
    case usage(ProxyUsage)
}

public enum BalanceUpdate: Codable, Sendable, Equatable {
    case loaded(AccountBalance)
    case unavailable(provider: String, lastPolledAt: Date)
}
