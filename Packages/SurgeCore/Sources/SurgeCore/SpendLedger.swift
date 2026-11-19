import Foundation

/// Builds the daily spend history the Spend tab and the widget show.
///
/// The state store keeps live sessions, not history, so this type watches each agent's cumulative
/// cost and books only the increase into the day it arrives. A snapshot from the previous run seeds
/// both the history and each agent's last cost, so relaunching never counts the same dollars twice.
///
/// Spend is grouped by the provider family that bills it. An account whose provider reports no
/// per-turn cost is reconciled against the drop its balance reported: the balance is the only
/// figure that measures what left the account, so it replaces the per-turn amounts for that day and
/// the day carries the balance-derived label. A top-up is money added, never negative spend.
public struct DailySpendLedger: Equatable {
    public static let retentionDays = 14

    private struct AgentCost: Equatable {
        var costUSD: Double
        var lastSeenAt: Date
    }

    /// One balance-derived account's part of a day.
    private struct AccountSpend: Equatable {
        let family: Provider
        /// Spend the day already carried when this ledger took over, from the snapshot it seeded.
        var seededUSD = 0.0
        /// Spend the live agent rows booked for this account since the seed.
        var bookedUSD = 0.0
        var bookedSource: CostSource?
        /// The drop the account's balance reported since the seed. Nil until one is seen.
        var dropUSD: Double?
        /// The balance is the authority once it moved: per-turn amounts for such an account are the
        /// harness's own figures, and they are already inside the drop.
        var amountUSD: Double { seededUSD + (dropUSD ?? bookedUSD) }

        var source: CostSource {
            if dropUSD != nil { return .balanceDerived }
            let sources = [seededUSD > 0 ? .estimated : nil, bookedSource].compactMap { $0 }
            return CostSource.weakest(sources) ?? .estimated
        }
    }

    private struct DayRecord: Equatable {
        /// Spend no account claims, keyed by provider family.
        var byFamily: [String: Double] = [:]
        /// The weakest source behind `byFamily`, so the number can always be labelled.
        var familySource: CostSource?
        var accounts: [String: AccountSpend] = [:]
    }

    private var days: [Date: DayRecord]
    private var agentCosts: [String: AgentCost]
    /// The last amount each account reported, so a drop is measured from the balance this ledger
    /// last saw rather than from nothing.
    private var lastBalanceUSD: [String: Double]
    private let balanceDerivedAccounts: [String: BillingAccount]
    private let calendar: Calendar

    /// - Parameters:
    ///   - seed: The previous snapshot. Its daily history and each agent's cost are taken as
    ///     already booked, and its balances become the baseline the next drop is measured from.
    ///   - accounts: The billing accounts, so the ledger knows which ones report a balance instead
    ///     of a per-turn cost.
    public init(
        seed: SurgeSnapshot? = nil,
        accounts: [BillingAccount] = BillingAccount.standard,
        calendar: Calendar = .current
    ) {
        self.calendar = calendar
        balanceDerivedAccounts = Dictionary(
            accounts.filter { $0.authority == .balanceDerived }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var days: [Date: DayRecord] = [:]
        var agentCosts: [String: AgentCost] = [:]
        var lastBalanceUSD: [String: Double] = [:]
        if let seed {
            let families = Self.harnessFamilies(in: seed.workspaces)
            for point in seed.dailySpend {
                let day = calendar.startOfDay(for: point.date)
                var record = days[day] ?? DayRecord()
                for (key, amount) in point.spendByProvider where amount > 0 {
                    Self.addSeeded(
                        amount,
                        key: key,
                        families: families,
                        accounts: balanceDerivedAccounts,
                        into: &record
                    )
                }
                days[day] = record
            }
            for workspace in seed.workspaces {
                for agent in [workspace.orchestrator] + workspace.workers {
                    agentCosts[agent.id] = AgentCost(costUSD: agent.estimatedCostUSD, lastSeenAt: seed.generatedAt)
                }
            }
            for balance in seed.balances {
                lastBalanceUSD[balance.provider] = balance.amountUSD
            }
        }
        self.days = days
        self.agentCosts = agentCosts
        self.lastBalanceUSD = lastBalanceUSD
    }

    /// Books what the live rows have added since the last call, then measures any balance movement.
    public mutating func record(
        workspaces: [WorkspaceSession],
        balances: [AccountBalance] = [],
        at now: Date
    ) {
        let day = calendar.startOfDay(for: now)
        for workspace in workspaces {
            for agent in [workspace.orchestrator] + workspace.workers {
                let previous = agentCosts[agent.id]?.costUSD ?? 0
                let increase = max(agent.estimatedCostUSD - previous, 0)
                if increase > 0 {
                    book(increase, for: agent, on: day)
                }
                agentCosts[agent.id] = AgentCost(costUSD: agent.estimatedCostUSD, lastSeenAt: now)
            }
        }
        observe(balances, on: day)
        prune(before: calendar.date(byAdding: .day, value: -Self.retentionDays, to: day))
    }

    public func todayTotal(at now: Date) -> Double {
        guard let record = days[calendar.startOfDay(for: now)] else { return 0 }
        return familyAmounts(for: record).values.reduce(0, +)
    }

    /// How today's total was obtained. Unknown history reads as an estimate, never as reported.
    public func todaySource(at now: Date) -> CostSource {
        source(of: days[calendar.startOfDay(for: now)])
    }

    public func todayFigure(at now: Date) -> SpendFigure {
        SpendFigure(amountUSD: todayTotal(at: now), source: todaySource(at: now))
    }

    public func todayPoint(at now: Date) -> DailySpendPoint {
        let day = calendar.startOfDay(for: now)
        return DailySpendPoint(date: day, spendByProvider: familyAmounts(for: days[day]))
    }

    /// Contiguous days ending today, so the chart's axis always spans the whole range.
    public func lastDays(_ count: Int, at now: Date) -> [DailySpendPoint] {
        let today = calendar.startOfDay(for: now)
        return (0..<max(count, 1)).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailySpendPoint(date: day, spendByProvider: familyAmounts(for: days[day]))
        }
    }

    // MARK: - Booking

    private mutating func book(_ amount: Double, for agent: AgentNode, on day: Date) {
        var record = days[day] ?? DayRecord()
        if let account = agent.billingAccount.flatMap({ balanceDerivedAccounts[$0.id] }) {
            var spend = record.accounts[account.id] ?? AccountSpend(family: account.family)
            spend.bookedUSD += amount
            spend.bookedSource = CostSource.weakest([spend.bookedSource, agent.costSource].compactMap { $0 })
            record.accounts[account.id] = spend
        } else {
            record.byFamily[agent.providerKind.rawValue, default: 0] += amount
            record.familySource = CostSource.weakest(
                [record.familySource, agent.costSource].compactMap { $0 }
            )
        }
        days[day] = record
    }

    /// A drop in the balance is spend the provider actually charged. An increase is a top-up, and
    /// a poll with no amount says nothing, so neither books anything.
    private mutating func observe(_ balances: [AccountBalance], on day: Date) {
        for balance in balances {
            guard balance.quotaWindow == nil, let amount = balance.amountUSD else { continue }
            let previous = lastBalanceUSD[balance.provider]
            lastBalanceUSD[balance.provider] = amount
            guard let account = balanceDerivedAccounts[balance.provider],
                let movement = SpendAttribution.movement(
                    provider: account.family,
                    previousUSD: previous,
                    currentUSD: amount
                ),
                movement.hasSpend
            else { continue }
            var record = days[day] ?? DayRecord()
            var spend = record.accounts[account.id] ?? AccountSpend(family: account.family)
            spend.dropUSD = (spend.dropUSD ?? 0) + movement.dropUSD
            record.accounts[account.id] = spend
            days[day] = record
        }
    }

    // MARK: - Reading

    private func familyAmounts(for record: DayRecord?) -> [String: Double] {
        guard let record else { return [:] }
        var amounts = record.byFamily
        for spend in record.accounts.values {
            amounts[spend.family.rawValue, default: 0] += spend.amountUSD
        }
        return amounts
    }

    private func source(of record: DayRecord?) -> CostSource {
        guard let record else { return .estimated }
        var sources = record.accounts.values.map(\.source)
        if let familySource = record.familySource { sources.append(familySource) }
        return CostSource.weakest(sources) ?? .estimated
    }

    // MARK: - Seeding

    /// Puts one seeded amount on the account that owns it when the key names an account, and on its
    /// provider family otherwise. A snapshot from before the harness split keys spend by harness
    /// name, which is not a provider, so the agents in the snapshot are what name the family.
    private static func addSeeded(
        _ amount: Double,
        key: String,
        families: [String: Provider],
        accounts: [String: BillingAccount],
        into record: inout DayRecord
    ) {
        let account = accounts[key]
        if let account {
            var spend = record.accounts[account.id] ?? AccountSpend(family: account.family)
            spend.seededUSD += amount
            record.accounts[account.id] = spend
            return
        }
        let family = Provider(providerID: key) ?? families[key] ?? .other
        record.byFamily[family.rawValue, default: 0] += amount
        record.familySource = CostSource.weakest([record.familySource, .estimated].compactMap { $0 })
    }

    /// The provider family each harness name in a snapshot stands for, read from the accounts the
    /// agents were billed to. A harness name with no agent behind it has no family to claim.
    private static func harnessFamilies(in workspaces: [WorkspaceSession]) -> [String: Provider] {
        var families: [String: Provider] = [:]
        for workspace in workspaces {
            for agent in [workspace.orchestrator] + workspace.workers {
                guard Provider(providerID: agent.provider) == nil else { continue }
                if let family = agent.billingAccount?.family {
                    families[agent.provider] = family
                }
            }
        }
        return families
    }

    private mutating func prune(before cutoff: Date?) {
        guard let cutoff else { return }
        for day in days.keys where day < cutoff {
            days[day] = nil
        }
        for (id, cost) in agentCosts where cost.lastSeenAt < cutoff {
            agentCosts[id] = nil
        }
    }
}
