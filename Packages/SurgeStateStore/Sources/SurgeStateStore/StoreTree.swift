import Foundation
import SurgeCore

/// The low and empty thresholds an account balance is measured against.
///
/// `SurgeCore` supplies the defaults. Settings can pass its own values so the store, not the UI,
/// decides whether an account reads Low or Empty.
public struct BalanceThresholds: Sendable, Equatable {
    public var lowUSD: Double
    public var emptyUSD: Double

    public init(
        lowUSD: Double = SurgeThresholds.lowBalanceUSD,
        emptyUSD: Double = SurgeThresholds.emptyBalanceUSD
    ) {
        self.lowUSD = lowUSD
        self.emptyUSD = emptyUSD
    }

    public func level(forUSD amount: Double) -> BalanceLevel {
        if amount < emptyUSD { return .empty }
        if amount < lowUSD { return .low }
        return .normal
    }
}

/// The merged agent tree and balances every surface reads.
///
/// The tree is already in PRD 6.2 order and carries derived state: statuses include stall
/// detection as of `generatedAt`, and agents whose Done window elapsed are gone. `generatedAt`
/// only moves when the content changes, so an unchanged refresh does not re-publish.
public struct StoreTree: Sendable, Equatable {
    public let generatedAt: Date
    public let workspaces: [WorkspaceSession]
    public let balances: [AccountBalance]
    public let balanceThresholds: BalanceThresholds

    public init(
        generatedAt: Date,
        workspaces: [WorkspaceSession],
        balances: [AccountBalance],
        balanceThresholds: BalanceThresholds = BalanceThresholds()
    ) {
        self.generatedAt = generatedAt
        self.workspaces = workspaces
        self.balances = balances
        self.balanceThresholds = balanceThresholds
    }

    public static func empty(
        at generatedAt: Date,
        balanceThresholds: BalanceThresholds = BalanceThresholds()
    ) -> StoreTree {
        StoreTree(
            generatedAt: generatedAt,
            workspaces: [],
            balances: [],
            balanceThresholds: balanceThresholds
        )
    }

    /// Every agent in the tree that needs the user.
    public var attentionCount: Int {
        workspaces.reduce(0) { total, workspace in
            total + count(in: workspace)
        }
    }

    public var needsYou: Bool { attentionCount > 0 }

    /// One orchestrator per workspace.
    public var orchestratorCount: Int { workspaces.count }

    public var workerCount: Int {
        workspaces.reduce(0) { $0 + $1.workers.count }
    }

    public var totalSpendUSD: Double {
        workspaces.reduce(0) { $0 + $1.totalTreeCostUSD }
    }

    /// The tree total with the label its weakest part earns. Nil when any agent has no cost figure
    /// at all, because a partial total would silently understate spend.
    public var spendFigure: SpendFigure? {
        guard workspaces.isEmpty == false else {
            return SpendFigure(amountUSD: 0, source: .estimated)
        }
        let figures = workspaces.compactMap(\.spendFigure)
        guard figures.count == workspaces.count,
            let source = CostSource.weakest(figures.map(\.source))
        else { return nil }
        return SpendFigure(amountUSD: totalSpendUSD, source: source)
    }

    /// The count the workspace header shows when anything inside needs the user.
    public func attentionCount(forWorkspace id: UUID) -> Int {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return 0 }
        return count(in: workspace)
    }

    /// The Low or Empty modifier for an account, or nil when it is unavailable or unknown.
    public func balanceLevel(forProvider provider: String) -> BalanceLevel? {
        guard let balance = balances.first(where: { $0.provider == provider }) else { return nil }
        return balance.amountUSD.map(balanceThresholds.level(forUSD:))
    }

    private func count(in workspace: WorkspaceSession) -> Int {
        let orchestrator = workspace.orchestrator.status.needsYou ? 1 : 0
        return orchestrator + workspace.workers.filter { $0.status.needsYou }.count
    }
}
