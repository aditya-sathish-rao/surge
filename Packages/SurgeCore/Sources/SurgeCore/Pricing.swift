import Foundation

public struct ModelPricing: Codable, Sendable, Equatable {
    public let contextWindow: Int
    public let inputPerMillion: Double
    public let outputPerMillion: Double
    public let cacheReadPerMillion: Double
    public let stallThresholdSeconds: TimeInterval

    public init(
        contextWindow: Int,
        inputPerMillion: Double,
        outputPerMillion: Double,
        cacheReadPerMillion: Double,
        stallThresholdSeconds: TimeInterval = SurgeThresholds.defaultStallSeconds
    ) {
        self.contextWindow = contextWindow
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.cacheReadPerMillion = cacheReadPerMillion
        self.stallThresholdSeconds = stallThresholdSeconds
    }

    public func costUSD(inputTokens: Int, outputTokens: Int, cacheHitTokens: Int) -> Double {
        let input = Double(inputTokens) * inputPerMillion
        let output = Double(outputTokens) * outputPerMillion
        let cache = Double(cacheHitTokens) * cacheReadPerMillion
        return (input + output + cache) / 1_000_000
    }

    private enum CodingKeys: String, CodingKey {
        case contextWindow
        case inputPerMillion
        case outputPerMillion
        case cacheReadPerMillion
        case stallThresholdSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contextWindow = try container.decode(Int.self, forKey: .contextWindow)
        inputPerMillion = try container.decode(Double.self, forKey: .inputPerMillion)
        outputPerMillion = try container.decode(Double.self, forKey: .outputPerMillion)
        cacheReadPerMillion = try container.decode(Double.self, forKey: .cacheReadPerMillion)
        stallThresholdSeconds =
            try container.decodeIfPresent(TimeInterval.self, forKey: .stallThresholdSeconds)
            ?? SurgeThresholds.defaultStallSeconds
    }
}

public enum PricingError: Error, Sendable, Equatable {
    case resourceMissing
}

public struct PricingTable: Codable, Sendable, Equatable {
    public let models: [String: ModelPricing]

    public init(models: [String: ModelPricing]) {
        self.models = models
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        models = try container.decode([String: ModelPricing].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(models)
    }

    public func pricing(forModel modelName: String) -> ModelPricing? {
        models[modelName]
    }

    public func contextWindow(forModel modelName: String) -> Int? {
        models[modelName]?.contextWindow
    }

    public func stallThresholdSeconds(forModel modelName: String) -> TimeInterval {
        models[modelName]?.stallThresholdSeconds ?? SurgeThresholds.defaultStallSeconds
    }

    /// Returns nil for a model that is not in the table. New entries can be added to the JSON without a code change.
    public func estimatedCostUSD(
        forModel modelName: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheHitTokens: Int
    ) -> Double? {
        models[modelName]?.costUSD(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheHitTokens: cacheHitTokens
        )
    }

    public static func decode(from data: Data) throws -> PricingTable {
        try JSONDecoder().decode(PricingTable.self, from: data)
    }

    public static func bundled() throws -> PricingTable {
        guard let url = Bundle.module.url(forResource: "models-pricing", withExtension: "json") else {
            throw PricingError.resourceMissing
        }
        return try decode(from: Data(contentsOf: url))
    }
}
