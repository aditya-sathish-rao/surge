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

    /// The workspace total with the label its weakest part earns. Nil when any agent in the tree
    /// has no cost figure at all, because a partial total would silently understate spend.
    public var spendFigure: SpendFigure? {
        let agents = [orchestrator] + workers
        guard agents.contains(where: { $0.costSource == nil }) == false else { return nil }
        guard let source = CostSource.weakest(agents.compactMap(\.costSource)) else { return nil }
        return SpendFigure(amountUSD: totalTreeCostUSD, source: source)
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
    /// The accumulated cost amount. `costSource` says where it came from and whether it exists.
    public var estimatedCostUSD: Double
    /// Provider reported, harness reported, balance derived, quota window or estimated. Nil when
    /// nothing could price the work, in which case the amount is meaningless and must be shown as
    /// unavailable rather than as zero. `costAuthority` names that case explicitly.
    public var costSource: CostSource?
    public var lastTokenAt: Date
    /// The harness that produced this agent's records, when the source can name one.
    public var harness: HarnessIdentity?
    /// The account that pays for this agent's work, once one is resolved. Nil when the match was
    /// ambiguous or nothing matched, which is why the figure is not attributed to an account.
    public var billingAccount: BillingAccount?

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
        costSource: CostSource? = .estimated,
        lastTokenAt: Date,
        harness: HarnessIdentity? = nil,
        billingAccount: BillingAccount? = nil
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
        self.costSource = costSource
        self.lastTokenAt = lastTokenAt
        self.harness = harness
        self.billingAccount = billingAccount
    }

    /// The same vocabulary with the unavailable case spelled out.
    public var costAuthority: CostSource { costSource ?? .unavailable }

    /// The number and its label together, or nil when the cost is unavailable.
    public var spendFigure: SpendFigure? {
        costSource.map { SpendFigure(amountUSD: estimatedCostUSD, source: $0) }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case provider
        case modelName
        case status
        case inputTokens
        case outputTokens
        case cacheHitTokens
        case currentContextTokens
        case maxContextWindow
        case estimatedCostUSD
        case costSource
        case lastTokenAt
        case harness
        case billingAccount
    }

    /// A snapshot written before the cost source existed still reads as a local estimate.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        provider = try container.decode(String.self, forKey: .provider)
        modelName = try container.decode(String.self, forKey: .modelName)
        status = try container.decode(AgentStatus.self, forKey: .status)
        inputTokens = try container.decode(Int.self, forKey: .inputTokens)
        outputTokens = try container.decode(Int.self, forKey: .outputTokens)
        cacheHitTokens = try container.decode(Int.self, forKey: .cacheHitTokens)
        currentContextTokens = try container.decode(Int.self, forKey: .currentContextTokens)
        maxContextWindow = try container.decode(Int.self, forKey: .maxContextWindow)
        estimatedCostUSD = try container.decode(Double.self, forKey: .estimatedCostUSD)
        costSource = try container.decodeIfPresent(CostSource.self, forKey: .costSource) ?? .estimated
        lastTokenAt = try container.decode(Date.self, forKey: .lastTokenAt)
        harness = try container.decodeIfPresent(HarnessIdentity.self, forKey: .harness)
        billingAccount = try container.decodeIfPresent(BillingAccount.self, forKey: .billingAccount)
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
