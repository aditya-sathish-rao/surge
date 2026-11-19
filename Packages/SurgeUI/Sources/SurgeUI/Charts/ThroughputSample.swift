import Foundation
import SurgeCore

/// One sample of the 30-minute throughput series.
public struct ThroughputSample: Identifiable, Sendable, Equatable {
    public let date: Date
    public let tokensPerSecond: Double

    public var id: Date { date }

    public init(date: Date, tokensPerSecond: Double) {
        self.date = date
        self.tokensPerSecond = tokensPerSecond
    }
}

/// The headline and the one-line summary above the throughput chart.
public struct ThroughputSummary: Sendable, Equatable {
    public let currentTokensPerSecond: Double
    public let averageTokensPerSecond: Double

    public init(samples: [ThroughputSample]) {
        currentTokensPerSecond = max(samples.last?.tokensPerSecond ?? 0, 0)
        guard !samples.isEmpty else {
            averageTokensPerSecond = 0
            return
        }
        let total = samples.reduce(0) { $0 + max($1.tokensPerSecond, 0) }
        averageTokensPerSecond = total / Double(samples.count)
    }

    public var headline: String {
        SurgeFormatting.tokenRate(currentTokensPerSecond)
    }

    public var caption: String {
        guard averageTokensPerSecond > 0 else {
            return currentTokensPerSecond > 0 ? "Above your 30-minute average" : "No throughput yet"
        }
        let change = ((currentTokensPerSecond - averageTokensPerSecond) / averageTokensPerSecond) * 100
        let rounded = Int(change.rounded())
        if rounded == 0 {
            return "In line with your 30-minute average"
        }
        return "\(abs(rounded))% \(rounded > 0 ? "above" : "below") your 30-minute average"
    }
}
