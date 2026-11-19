import Foundation

/// Which harness ran an agent, and how its records reached Surge.
///
/// The harness is the program that runs the agent: Claude Code, pi, Codex, opencode, or anything
/// that reaches Surge through the proxy. It is deliberately separate from the account that pays:
/// Claude Code can be billed by Anthropic, by OpenRouter, or by a subscription.
public struct HarnessIdentity: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable, Equatable, CaseIterable {
        case claudeCode = "claude-code"
        case piAgent = "pi"
        case codex
        case opencode
        case generic

        public var name: String {
            switch self {
            case .claudeCode: "Claude Code"
            case .piAgent: "pi"
            case .codex: "Codex"
            case .opencode: "opencode"
            case .generic: "Unidentified harness"
            }
        }
    }

    public enum Transport: String, Codable, Sendable, Equatable {
        /// Appended JSON lines read from disk.
        case jsonl
        /// A SQLite database read from disk.
        case sqlite
        /// OpenTelemetry records.
        case otlp
        /// Requests forwarded through Surge's local proxy.
        case proxy
    }

    public let kind: Kind
    public let version: String?
    public let sessionID: String
    public let transport: Transport

    public init(kind: Kind, version: String? = nil, sessionID: String, transport: Transport) {
        self.kind = kind
        self.version = version
        self.sessionID = sessionID
        self.transport = transport
    }
}

/// An account that can pay for a harness's work.
///
/// `credentialRef` names where the credential lives, usually the Keychain account, and is never
/// the credential itself. `authority` is the figure this account can supply, so the cost label and
/// the account stay the same concept everywhere.
///
/// `modelPrefixes` is what an unattributed model is matched against. It is a table, not a guess:
/// when more than one account matches, Surge stops and reports the harness's own figure instead of
/// picking one.
public struct BillingAccount: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let family: Provider
    public let credentialRef: String
    public let authority: CostSource
    public let modelPrefixes: [String]

    public init(
        id: String,
        family: Provider,
        credentialRef: String,
        authority: CostSource,
        modelPrefixes: [String] = []
    ) {
        self.id = id
        self.family = family
        self.credentialRef = credentialRef
        self.authority = authority
        self.modelPrefixes = modelPrefixes
    }

    public var name: String { family.name }

    /// True when this account could pay for the model. Case-insensitive, prefix only.
    public func matches(modelName: String) -> Bool {
        let model = modelName.lowercased()
        return modelPrefixes.contains { prefix in
            let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed.isEmpty == false && model.hasPrefix(trimmed)
        }
    }

    /// The three provider accounts Surge knows without any user configuration.
    ///
    /// OpenRouter claims a model only when the id names it or names a vendor it serves. Those
    /// vendor ids are exactly where an account cannot be guessed: `deepseek/deepseek-chat` could be
    /// billed by DeepSeek or by OpenRouter, so it stays ambiguous until the user binds it.
    public static let standard: [BillingAccount] = [
        BillingAccount(
            id: "anthropic",
            family: .anthropic,
            credentialRef: "anthropic",
            authority: .harnessReported,
            modelPrefixes: ["claude"]
        ),
        BillingAccount(
            id: "deepseek",
            family: .deepseek,
            credentialRef: "deepseek",
            authority: .balanceDerived,
            modelPrefixes: ["deepseek"]
        ),
        BillingAccount(
            id: "openrouter",
            family: .openrouter,
            credentialRef: "openrouter",
            authority: .providerReported,
            modelPrefixes: [
                "openrouter/",
                "anthropic/",
                "deepseek/",
                "google/",
                "meta-llama/",
                "mistralai/",
                "openai/",
                "qwen/",
                "x-ai/",
            ]
        ),
    ]
}

/// A user's explicit statement that one harness and model belong to one account.
public struct BillingBinding: Identifiable, Codable, Sendable, Equatable {
    public let harness: HarnessIdentity.Kind
    public let modelPrefix: String
    public let accountID: String

    public init(harness: HarnessIdentity.Kind, modelPrefix: String, accountID: String) {
        self.harness = harness
        self.modelPrefix = modelPrefix
        self.accountID = accountID
    }

    public var id: String { "\(harness.rawValue):\(modelPrefix)" }

    public func matches(harness kind: HarnessIdentity.Kind, modelName: String) -> Bool {
        guard harness == kind else { return false }
        let prefix = modelPrefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard prefix.isEmpty == false else { return false }
        return modelName.lowercased().hasPrefix(prefix)
    }
}

/// Which account, if any, pays for a session tree, and why.
public enum BillingAttribution: Sendable, Equatable {
    public enum Basis: String, Sendable, Equatable {
        /// The user bound this harness and model to the account.
        case binding
        /// Exactly one account matched the model.
        case modelPrefix
    }

    case account(BillingAccount, basis: Basis)
    /// Several accounts could pay for this model. None of them is guessed.
    case ambiguous(accountIDs: [String])
    /// No account matched.
    case none

    public var account: BillingAccount? {
        guard case .account(let account, _) = self else { return nil }
        return account
    }

    public var isAmbiguous: Bool {
        if case .ambiguous = self { return true }
        return false
    }
}

/// A subscription's window, which is what a plan reports instead of a wallet balance.
///
/// A window carries no provider dollar figure, so the budget is a notional ceiling the user sets
/// for one window. `resetsAt` and the burn inside it are real; the ceiling is the user's own.
public struct QuotaWindow: Codable, Sendable, Equatable, Hashable {
    public enum Preset: String, Codable, Sendable, Equatable, CaseIterable {
        case claudePro = "claude-pro"
        case claudeMax5x = "claude-max-5x"
        case claudeMax20x = "claude-max-20x"
        case custom

        public var name: String {
            switch self {
            case .claudePro: "Claude Pro"
            case .claudeMax5x: "Claude Max 5x"
            case .claudeMax20x: "Claude Max 20x"
            case .custom: "Custom window"
            }
        }

        /// The interval the plan enforces, and the notional budget a preset starts from. Every
        /// plan window is five hours, and the budget is the plan price until the user edits it.
        public var defaults: (interval: TimeInterval, budgetUSD: Double) {
            switch self {
            case .claudePro: (5 * 3600, 20)
            case .claudeMax5x: (5 * 3600, 100)
            case .claudeMax20x: (5 * 3600, 200)
            case .custom: (5 * 3600, 20)
            }
        }
    }

    /// A fixed schedule that resets on the grid, or a window that starts at the first spend and
    /// resets one interval later. Claude's five-hour window is the second kind.
    public enum Style: String, Codable, Sendable, Equatable, CaseIterable {
        case reset
        case rolling
    }

    public let preset: Preset
    public let style: Style
    public let interval: TimeInterval
    public let limitUSD: Double

    public init(preset: Preset, style: Style = .rolling, interval: TimeInterval? = nil, limitUSD: Double? = nil) {
        self.preset = preset
        self.style = style
        self.interval = max(interval ?? preset.defaults.interval, 60)
        self.limitUSD = max(limitUSD ?? preset.defaults.budgetUSD, 0)
    }

    public var title: String {
        switch preset {
        case .custom: "Custom window"
        default: preset.name
        }
    }

}

/// One window's running total: what has been booked inside it, and how much room is left.
public struct QuotaWindowState: Codable, Sendable, Equatable {
    public let window: QuotaWindow
    public private(set) var spentUSD: Double
    public private(set) var startedAt: Date

    public init(window: QuotaWindow, startedAt: Date, spentUSD: Double = 0) {
        self.window = window
        self.startedAt = startedAt
        self.spentUSD = max(spentUSD, 0)
    }

    public var usedUSD: Double { spentUSD }

    public var headroomUSD: Double { max(window.limitUSD - spentUSD, 0) }

    /// Clamped, so a window that went past its ceiling reads as full rather than over 100 percent.
    public var fractionUsed: Double {
        guard window.limitUSD > 0 else { return 0 }
        return min(max(spentUSD / window.limitUSD, 0), 1)
    }

    public var percentUsed: Int { Int((fractionUsed * 100).rounded()) }

    public var isOverWindow: Bool { spentUSD >= window.limitUSD }

    public var resetsAt: Date { startedAt.addingTimeInterval(window.interval) }

    public func remainingSeconds(at now: Date) -> TimeInterval {
        max(resetsAt.timeIntervalSince(now), 0)
    }

    public func isExpired(at now: Date) -> Bool { now >= resetsAt }

    /// Moves the window to the one that contains `now`, clearing the spend when it rolled over.
    ///
    /// A fixed window advances on its own grid so the reset does not drift with polling. A rolling
    /// window re-anchors when it expires, which is how a five-hour plan window behaves.
    public mutating func advance(to now: Date) {
        guard now >= resetsAt else { return }
        switch window.style {
        case .rolling:
            startedAt = now
        case .reset:
            let elapsed = now.timeIntervalSince(startedAt)
            let windows = floor(elapsed / window.interval)
            startedAt = startedAt.addingTimeInterval(windows * window.interval)
        }
        spentUSD = 0
    }

    public mutating func book(_ amount: Double) {
        guard amount > 0 else { return }
        spentUSD += amount
    }
}

/// Where accounts, bindings and quota windows come from. The app builds it from Settings; the
/// state store only resolves against it.
public struct BillingConfiguration: Sendable, Equatable {
    public let accounts: [BillingAccount]
    public let bindings: [BillingBinding]
    /// Account id to the window it reports instead of a balance.
    public let quotaWindows: [String: QuotaWindow]

    public init(
        accounts: [BillingAccount] = BillingAccount.standard,
        bindings: [BillingBinding] = [],
        quotaWindows: [String: QuotaWindow] = [:]
    ) {
        self.accounts = accounts
        self.bindings = bindings
        self.quotaWindows = quotaWindows
    }

    public static let standard = BillingConfiguration()

    public func account(withID id: String) -> BillingAccount? {
        accounts.first { $0.id == id }
    }

    /// The window an account reports, or nil when none is configured. A missing window is never
    /// filled in with a default, because a budget Surge invented would look like a real one.
    public func quotaWindow(forAccount id: String) -> QuotaWindow? {
        guard let account = account(withID: id), account.authority == .quotaWindow else { return nil }
        return quotaWindows[id]
    }

    /// Every account that reports a window instead of a balance.
    public var quotaAccounts: [BillingAccount] {
        accounts.filter { $0.authority == .quotaWindow }
    }
}

/// Decides which account pays, and which figure is booked, in one place.
public enum BillingResolver {
    /// The user's binding first, then exactly one account matching the model, then nothing.
    ///
    /// Two matching accounts is never resolved by picking one of them. The caller books the
    /// harness's own figure instead, or a local estimate, and says so on screen.
    public static func attribution(
        harness: HarnessIdentity.Kind,
        modelName: String,
        configuration: BillingConfiguration
    ) -> BillingAttribution {
        let bindings = configuration.bindings
            .filter { $0.matches(harness: harness, modelName: modelName) }
            .sorted { $0.modelPrefix.count > $1.modelPrefix.count }
        for binding in bindings {
            if let account = configuration.account(withID: binding.accountID) {
                return .account(account, basis: .binding)
            }
        }

        let matches = configuration.accounts.filter { $0.matches(modelName: modelName) }
        switch matches.count {
        case 0: return .none
        case 1: return .account(matches[0], basis: .modelPrefix)
        default: return .ambiguous(accountIDs: matches.map(\.id).sorted())
        }
    }

    /// The strongest figure a turn can be booked from.
    ///
    /// A provider's own bill outranks everything, including the harness figure. That matters on a
    /// router binding: Claude Code's `totalCostUSD` is computed at Anthropic list prices, so when
    /// the session is explicitly bound to OpenRouter the provider-reported cost is the real one.
    ///
    /// A subscription account has no per-token bill, so its figures are window bookkeeping and are
    /// labelled with the window rather than as a provider charge.
    public static func book(_ figures: TurnFigures, attribution: BillingAttribution) -> SpendFigure? {
        if let provider = figures.providerReportedUSD {
            return SpendFigure(amountUSD: provider, source: .providerReported)
        }
        if let account = attribution.account, account.authority == .quotaWindow {
            if let harness = figures.harnessReportedUSD {
                return SpendFigure(amountUSD: harness, source: .quotaWindow)
            }
            if let estimate = figures.estimateUSD {
                return SpendFigure(amountUSD: estimate, source: .quotaWindow)
            }
            return nil
        }
        if let harness = figures.harnessReportedUSD {
            return SpendFigure(amountUSD: harness, source: .harnessReported)
        }
        if let estimate = figures.estimateUSD {
            return SpendFigure(amountUSD: estimate, source: .estimated)
        }
        return nil
    }
}
