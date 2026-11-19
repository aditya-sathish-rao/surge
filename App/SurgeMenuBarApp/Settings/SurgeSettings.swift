import Foundation
import Observation
import SurgeCore
import SurgeStateStore

/// The user's settings, stored in `UserDefaults` and read by the app at launch.
///
/// Thresholds and notification opt-ins are read on every notification decision, so toggling one
/// takes effect at once. The stall threshold reaches the state store through its pricing table,
/// which is built once at launch, so a changed stall threshold applies when Surge next starts.
@MainActor
@Observable
final class SurgeSettings {
    static let defaultLowBalanceUSD = SurgeThresholds.lowBalanceUSD
    static let defaultEmptyBalanceUSD = SurgeThresholds.emptyBalanceUSD
    static let minimumStallSeconds: TimeInterval = 30
    static let maximumStallSeconds: TimeInterval = 3600

    private enum Key {
        static let stallOverrides = "stallThresholdOverrides"
        static let stallTimeSensitive = "notifyStallTimeSensitive"
        static let completionPassive = "notifyCompletionPassive"
        static let lowBalance = "lowBalanceThreshold"
        static let emptyBalance = "emptyBalanceThreshold"
        static let shortcut = "globalShortcut"
        static let mutedAgents = "mutedAgentIDs"
        static let quotaWindows = "billingQuotaWindows"
        static let bindings = "billingBindings"
    }

    private let defaults: UserDefaults
    private var hasLoaded = false

    var stallOverrides: [String: TimeInterval] {
        didSet { persist(stallOverrides, forKey: Key.stallOverrides) }
    }
    var notifyStallTimeSensitive: Bool {
        didSet { defaults.set(notifyStallTimeSensitive, forKey: Key.stallTimeSensitive) }
    }
    var notifyCompletionPassive: Bool {
        didSet { defaults.set(notifyCompletionPassive, forKey: Key.completionPassive) }
    }
    var lowBalanceThreshold: Double {
        didSet { defaults.set(lowBalanceThreshold, forKey: Key.lowBalance) }
    }
    var emptyBalanceThreshold: Double {
        didSet { defaults.set(emptyBalanceThreshold, forKey: Key.emptyBalance) }
    }
    var shortcut: GlobalShortcut? {
        didSet {
            persist(shortcut, forKey: Key.shortcut)
            onShortcutChanged?()
        }
    }
    var mutedAgentIDs: Set<String> {
        didSet { defaults.set(Array(mutedAgentIDs).sorted(), forKey: Key.mutedAgents) }
    }
    /// A subscription account and the window it reports instead of a balance, keyed by account id.
    var quotaWindows: [String: QuotaWindow] {
        didSet {
            persist(quotaWindows.isEmpty ? nil : quotaWindows, forKey: Key.quotaWindows)
            onBillingChanged?()
        }
    }
    /// The user's explicit statement that a harness and model belong to one account.
    var bindings: [BillingBinding] {
        didSet {
            persist(bindings.isEmpty ? nil : bindings, forKey: Key.bindings)
            onBillingChanged?()
        }
    }

    /// Set by the app model so recording a shortcut re-registers it immediately.
    var onShortcutChanged: (() -> Void)?
    /// Set by the app model so a billing change re-resolves the sessions already on screen.
    var onBillingChanged: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stallOverrides = Self.decode([String: TimeInterval].self, from: defaults, key: Key.stallOverrides) ?? [:]
        notifyStallTimeSensitive = defaults.bool(forKey: Key.stallTimeSensitive)
        notifyCompletionPassive = defaults.bool(forKey: Key.completionPassive)
        lowBalanceThreshold = defaults.object(forKey: Key.lowBalance) as? Double ?? Self.defaultLowBalanceUSD
        emptyBalanceThreshold = defaults.object(forKey: Key.emptyBalance) as? Double ?? Self.defaultEmptyBalanceUSD
        shortcut = Self.decode(GlobalShortcut.self, from: defaults, key: Key.shortcut)
        mutedAgentIDs = Set(defaults.stringArray(forKey: Key.mutedAgents) ?? [])
        quotaWindows = Self.decode([String: QuotaWindow].self, from: defaults, key: Key.quotaWindows) ?? [:]
        bindings = Self.decode([BillingBinding].self, from: defaults, key: Key.bindings) ?? []
        hasLoaded = true
    }

    var balanceThresholds: BalanceThresholds {
        BalanceThresholds(
            lowUSD: max(lowBalanceThreshold, 0),
            emptyUSD: max(emptyBalanceThreshold, 0)
        )
    }

    var notificationOptions: NotificationOptions {
        NotificationOptions(
            mutedAgentIDs: mutedAgentIDs,
            stallTimeSensitive: notifyStallTimeSensitive,
            completionPassive: notifyCompletionPassive
        )
    }

    /// The accounts whose row comes from a window instead of a polled balance.
    var quotaAccountIDs: Set<String> { Set(quotaWindows.keys) }

    func quotaWindow(forAccount id: String) -> QuotaWindow? { quotaWindows[id] }

    func setQuotaWindow(_ window: QuotaWindow?, forAccount id: String) {
        if let window {
            quotaWindows[id] = window
        } else {
            quotaWindows[id] = nil
        }
    }

    func addBinding(harness: HarnessIdentity.Kind, modelPrefix: String, accountID: String) {
        let trimmed = modelPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let binding = BillingBinding(harness: harness, modelPrefix: trimmed, accountID: accountID)
        bindings.removeAll { $0.id == binding.id }
        bindings.append(binding)
    }

    func removeBinding(id: String) {
        bindings.removeAll { $0.id == id }
    }

    /// The accounts, bindings and windows the state store resolves against.
    ///
    /// When a Claude subscription is configured it takes over the `anthropic` account, and the API
    /// account stays available as `anthropic-api`. Both match `claude-*`, which is exactly the
    /// case the user has to settle with a binding rather than have Surge guess.
    func billingConfiguration() -> BillingConfiguration {
        var accounts = BillingAccount.standard
        var windows: [String: QuotaWindow] = [:]
        if let window = quotaWindows["anthropic"] {
            accounts.removeAll { $0.id == "anthropic" }
            accounts.append(
                BillingAccount(
                    id: "anthropic",
                    family: .anthropic,
                    credentialRef: "anthropic",
                    authority: .quotaWindow,
                    modelPrefixes: ["claude"]
                )
            )
            accounts.append(
                BillingAccount(
                    id: "anthropic-api",
                    family: .anthropic,
                    credentialRef: "anthropic",
                    authority: .harnessReported,
                    modelPrefixes: ["claude"]
                )
            )
            windows["anthropic"] = window
        }
        let knownIDs = Set(accounts.map(\.id))
        return BillingConfiguration(
            accounts: accounts,
            bindings: bindings.filter { knownIDs.contains($0.accountID) },
            quotaWindows: windows
        )
    }

    func stallThreshold(for modelName: String) -> TimeInterval {
        if let override = stallOverrides[modelName] {
            return override
        }
        return SurgeStateStore.defaultPricing.stallThresholdSeconds(forModel: modelName)
    }

    func setStallThreshold(_ seconds: TimeInterval?, for modelName: String) {
        guard let seconds else {
            stallOverrides[modelName] = nil
            return
        }
        let clamped = min(max(seconds, Self.minimumStallSeconds), Self.maximumStallSeconds)
        stallOverrides[modelName] = clamped
    }

    func toggleMuted(_ agentID: String) {
        if mutedAgentIDs.contains(agentID) {
            mutedAgentIDs.remove(agentID)
        } else {
            mutedAgentIDs.insert(agentID)
        }
    }

    private func persist<T: Encodable>(_ value: T?, forKey key: String) {
        guard hasLoaded else { return }
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
