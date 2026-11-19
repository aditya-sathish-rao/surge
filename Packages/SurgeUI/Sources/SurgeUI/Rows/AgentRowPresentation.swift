import Foundation
import SurgeCore

/// Whether a row is a top-level agent or a sub-agent under one.
public enum AgentRowKind: Sendable, Equatable {
    case agent
    case subAgent(parentName: String)
}

/// Everything an agent row shows and says, derived once from an agent.
public struct AgentRowPresentation: Sendable, Equatable {
    public let modelName: String
    public let provider: Provider
    public let status: AgentStatus
    public let kind: AgentRowKind
    public let stateSymbol: String
    /// Tokens per second while working, otherwise the state word with its timer.
    public let trailingText: String
    public let fuse: FusePresentation
    public let needsYou: Bool
    public let accessibilityLabel: String

    public init(
        agent: AgentNode,
        workspaceName: String,
        tokensPerSecond: Double? = nil,
        now: Date,
        kind: AgentRowKind = .agent
    ) {
        let modelName = Self.displayName(forModel: agent.modelName)
        self.modelName = modelName
        provider = agent.providerKind
        status = agent.status
        self.kind = kind
        stateSymbol = agent.status.symbol
        needsYou = agent.status.needsYou
        fuse = FusePresentation(agent: agent, now: now)
        trailingText = Self.trailingText(
            for: agent.status,
            tokensPerSecond: tokensPerSecond,
            now: now,
            lastActivityAt: agent.lastTokenAt
        )
        let role = Self.role(for: kind)
        let statusClause = Self.statusClause(
            for: agent.status,
            tokensPerSecond: tokensPerSecond,
            now: now,
            lastActivityAt: agent.lastTokenAt
        )
        let providerName = agent.providerKind.name
        let costClause = agent.costSource == nil ? " Cost unavailable for \(modelName)." : ""
        accessibilityLabel =
            "\(modelName), \(role), \(workspaceName), \(providerName). "
            + "\(statusClause) \(fuse.contextClause).\(costClause)"
    }

    public static func trailingText(
        for status: AgentStatus,
        tokensPerSecond: Double?,
        now: Date,
        lastActivityAt: Date
    ) -> String {
        switch status {
        case .working:
            guard let tokensPerSecond else { return "Working" }
            return SurgeFormatting.tokenRate(tokensPerSecond)
        default:
            return SurgeFormatting.statusLabel(status, now: now, lastActivityAt: lastActivityAt)
        }
    }

    /// "agent", or "sub-agent of Claude Sonnet" for a row under an agent.
    public static func role(for kind: AgentRowKind) -> String {
        switch kind {
        case .agent: "agent"
        case .subAgent(let parentName): "sub-agent of \(parentName)"
        }
    }

    /// The status half of the row's VoiceOver sentence.
    public static func statusClause(
        for status: AgentStatus,
        tokensPerSecond: Double?,
        now: Date,
        lastActivityAt: Date
    ) -> String {
        switch status {
        case .working:
            guard let tokensPerSecond else { return "Working." }
            return "Working, \(Int(tokensPerSecond.rounded())) tokens per second."
        default:
            return "\(SurgeFormatting.statusLabel(status, now: now, lastActivityAt: lastActivityAt))."
        }
    }

    /// Turns a model id into the words the design system shows: "claude-sonnet" reads as "Claude
    /// Sonnet", and the number segments of a version stay together as "claude-sonnet-5-5" reading
    /// "Claude Sonnet 5.5".
    public static func displayName(forModel modelName: String) -> String {
        let words =
            modelName
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { word -> String in
                let lowercased = word.lowercased()
                if let brand = brands[lowercased] { return brand }
                return word.prefix(1).uppercased() + word.dropFirst()
            }
        return words.isEmpty ? modelName : joinedVersions(words)
    }

    /// Consecutive number segments are one version, so `5-5` reads as `5.5` rather than `5 5`.
    private static func joinedVersions(_ words: [String]) -> String {
        var merged: [String] = []
        for word in words {
            let isNumber = word.allSatisfy(\.isNumber)
            if isNumber, let previous = merged.last, previous.allSatisfy(\.isNumber) {
                merged[merged.count - 1] = previous + "." + word
            } else {
                merged.append(word)
            }
        }
        return merged.joined(separator: " ")
    }

    private static let brands: [String: String] = [
        "deepseek": "DeepSeek",
        "openrouter": "OpenRouter",
        "gpt": "GPT",
        "claude": "Claude",
    ]
}
