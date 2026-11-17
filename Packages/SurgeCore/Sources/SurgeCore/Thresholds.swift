import Foundation

public enum ContextLevel: String, Codable, Sendable, CaseIterable {
    case normal
    case high
    case nearLimit
}

public enum BalanceLevel: String, Codable, Sendable, CaseIterable {
    case normal
    case low
    case empty
}

public enum SurgeThresholds {
    public static let contextHighRatio = 0.70
    public static let contextNearLimitRatio = 0.90
    public static let defaultStallSeconds: TimeInterval = 120
    public static let lowBalanceUSD = 5.0
    public static let emptyBalanceUSD = 0.50
    public static let doneDisplaySeconds: TimeInterval = 600
    public static let snapshotStaleSeconds: TimeInterval = 300

    public static func contextLevel(forRatio ratio: Double) -> ContextLevel {
        if ratio >= contextNearLimitRatio { return .nearLimit }
        if ratio >= contextHighRatio { return .high }
        return .normal
    }

    public static func balanceLevel(forUSD amount: Double) -> BalanceLevel {
        if amount < emptyBalanceUSD { return .empty }
        if amount < lowBalanceUSD { return .low }
        return .normal
    }
}

public enum SurgeMath {
    public static func contextUsageRatio(currentContextTokens: Int, maxContextWindow: Int) -> Double {
        guard maxContextWindow > 0 else { return 0 }
        let ratio = Double(currentContextTokens) / Double(maxContextWindow)
        return min(max(ratio, 0), 1)
    }
}
