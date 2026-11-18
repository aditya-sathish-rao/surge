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

    public init(
        id: String,
        projectPath: String,
        provider: String,
        modelName: String,
        maxContextWindow: Int,
        occurredAt: Date
    ) {
        self.id = id
        self.projectPath = projectPath
        self.provider = provider
        self.modelName = modelName
        self.maxContextWindow = maxContextWindow
        self.occurredAt = occurredAt
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

    public init(
        sessionID: String,
        modelName: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheHitTokens: Int,
        currentContextTokens: Int,
        occurredAt: Date
    ) {
        self.sessionID = sessionID
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheHitTokens = cacheHitTokens
        self.currentContextTokens = currentContextTokens
        self.occurredAt = occurredAt
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

    public init(
        id: String,
        provider: String,
        modelName: String,
        projectPath: String,
        parentSessionID: String?,
        occurredAt: Date
    ) {
        self.id = id
        self.provider = provider
        self.modelName = modelName
        self.projectPath = projectPath
        self.parentSessionID = parentSessionID
        self.occurredAt = occurredAt
    }
}

/// Token counts on usage events are per-request increments. `currentContextTokens` is the prompt size of that request.
public struct ProxyUsage: Codable, Sendable, Equatable {
    public let workerID: String
    public let provider: String
    public let modelName: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheHitTokens: Int
    public let currentContextTokens: Int
    public let occurredAt: Date

    public init(
        workerID: String,
        provider: String,
        modelName: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheHitTokens: Int,
        currentContextTokens: Int,
        occurredAt: Date
    ) {
        self.workerID = workerID
        self.provider = provider
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheHitTokens = cacheHitTokens
        self.currentContextTokens = currentContextTokens
        self.occurredAt = occurredAt
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
