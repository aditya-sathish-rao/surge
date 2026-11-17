import Foundation
import SwiftUI

public struct WorkspaceSession: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let projectPath: String
    public var orchestrator: AgentNode
    public var workers: [AgentNode]

    public init(
        id: UUID = UUID(),
        projectPath: String,
        orchestrator: AgentNode,
        workers: [AgentNode] = []
    ) {
        self.id = id
        self.projectPath = projectPath
        self.orchestrator = orchestrator
        self.workers = workers
    }

    public var name: String {
        URL(fileURLWithPath: projectPath).lastPathComponent
    }

    public var totalTreeCostUSD: Double {
        orchestrator.estimatedCostUSD + workers.reduce(0) { $0 + $1.estimatedCostUSD }
    }

    public var needsYou: Bool {
        orchestrator.status.needsYou || workers.contains { $0.status.needsYou }
    }
}

public struct AgentNode: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let provider: String
    public let modelName: String
    public var status: AgentStatus
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheHitTokens: Int
    public var currentContextTokens: Int
    public var maxContextWindow: Int
    public var estimatedCostUSD: Double
    public var lastTokenAt: Date

    public init(
        id: String,
        provider: String,
        modelName: String,
        status: AgentStatus,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheHitTokens: Int = 0,
        currentContextTokens: Int = 0,
        maxContextWindow: Int = 0,
        estimatedCostUSD: Double = 0,
        lastTokenAt: Date
    ) {
        self.id = id
        self.provider = provider
        self.modelName = modelName
        self.status = status
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheHitTokens = cacheHitTokens
        self.currentContextTokens = currentContextTokens
        self.maxContextWindow = maxContextWindow
        self.estimatedCostUSD = estimatedCostUSD
        self.lastTokenAt = lastTokenAt
    }

    public var contextUsageRatio: Double {
        SurgeMath.contextUsageRatio(
            currentContextTokens: currentContextTokens,
            maxContextWindow: maxContextWindow
        )
    }

    public var contextLevel: ContextLevel {
        SurgeThresholds.contextLevel(forRatio: contextUsageRatio)
    }

    public var providerKind: Provider {
        Provider(providerID: provider) ?? .other
    }
}

public enum AgentStatus: Codable, Sendable, Equatable {
    case working
    case waitingForYou
    case stalled(since: Date)
    case compacting
    case idle(since: Date)
    case done
    case noSignal

    public var needsYou: Bool {
        switch self {
        case .stalled, .waitingForYou:
            true
        default:
            false
        }
    }

    public var symbol: String {
        switch self {
        case .working: "bolt.fill"
        case .waitingForYou: "hand.raised.fill"
        case .stalled: "exclamationmark.triangle.fill"
        case .compacting: "arrow.down.and.line.horizontal.and.arrow.up"
        case .idle: "pause.fill"
        case .done: "checkmark"
        case .noSignal: "bolt.slash"
        }
    }
}

public enum Provider: String, CaseIterable, Codable, Sendable {
    case anthropic
    case deepseek
    case openrouter
    case other

    public init?(providerID: String) {
        switch providerID.lowercased() {
        case "anthropic": self = .anthropic
        case "deepseek": self = .deepseek
        case "openrouter": self = .openrouter
        case "other": self = .other
        default: return nil
        }
    }

    public var name: String {
        switch self {
        case .anthropic: "Anthropic"
        case .deepseek: "DeepSeek"
        case .openrouter: "OpenRouter"
        case .other: "Other"
        }
    }
}
