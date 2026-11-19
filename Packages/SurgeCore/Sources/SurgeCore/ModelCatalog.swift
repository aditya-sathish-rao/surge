import Foundation

/// What a provider's own model list says about one model.
///
/// The numbers come from the provider, not from a table frozen into the app, so a new model or a
/// larger context window is picked up without a release. A model list entry without a context
/// window is not usable and is dropped rather than cached as a small window.
public struct ModelMetadata: Codable, Sendable, Equatable {
    public let modelID: String
    public let provider: Provider
    public let contextWindow: Int
    public let maxOutputTokens: Int?
    public let inputPerMillion: Double?
    public let outputPerMillion: Double?
    public let cacheReadPerMillion: Double?
    public let fetchedAt: Date

    public init(
        modelID: String,
        provider: Provider,
        contextWindow: Int,
        maxOutputTokens: Int? = nil,
        inputPerMillion: Double? = nil,
        outputPerMillion: Double? = nil,
        cacheReadPerMillion: Double? = nil,
        fetchedAt: Date
    ) {
        self.modelID = modelID
        self.provider = provider
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.cacheReadPerMillion = cacheReadPerMillion
        self.fetchedAt = fetchedAt
    }

    public var isUsable: Bool {
        contextWindow > 0 && !modelID.isEmpty
    }

    /// True when the provider also reports what the model costs.
    public var hasPricing: Bool {
        inputPerMillion != nil && outputPerMillion != nil
    }
}

/// The model metadata fetched from providers, kept so an offline launch still uses real numbers.
///
/// Entries are keyed by provider and model id, so two providers may use the same id without one
/// overwriting the other.
public struct ModelCatalog: Codable, Sendable, Equatable {
    public let models: [String: ModelMetadata]
    public let fetchedAt: Date?

    public init(models: [String: ModelMetadata] = [:], fetchedAt: Date? = nil) {
        self.models = models
        self.fetchedAt = fetchedAt
    }

    public static let empty = ModelCatalog()

    public var isEmpty: Bool { models.isEmpty }

    public static func key(modelID: String, provider: Provider) -> String {
        "\(provider.rawValue):\(modelID)"
    }

    /// The metadata for a model id, preferring the named provider when several share the id.
    public func metadata(forModel modelID: String, provider: Provider? = nil) -> ModelMetadata? {
        if let provider {
            if let match = models[Self.key(modelID: modelID, provider: provider)] {
                return match
            }
        }
        let matches =
            models
            .filter { $0.value.modelID == modelID }
            .sorted { $0.key < $1.key }
        return matches.first?.value
    }

    /// The catalog for a set of entries fetched together.
    public init(entries: [ModelMetadata], fetchedAt: Date) {
        var models: [String: ModelMetadata] = [:]
        for entry in entries where entry.isUsable {
            models[Self.key(modelID: entry.modelID, provider: entry.provider)] = entry
        }
        self.init(models: models, fetchedAt: fetchedAt)
    }

    /// `other` wins on a shared key, because it came from a later fetch.
    public func merging(_ other: ModelCatalog) -> ModelCatalog {
        guard other.isEmpty == false else { return self }
        var merged = models
        for (key, value) in other.models {
            merged[key] = value
        }
        let newest = [fetchedAt, other.fetchedAt].compactMap { $0 }.max()
        return ModelCatalog(models: merged, fetchedAt: newest)
    }
}

/// The model numbers the app uses: live provider metadata first, then the bundled last-known
/// table, and nothing at all for a model neither knows.
public struct PriceBook: Sendable, Equatable {
    public let catalog: ModelCatalog
    public let fallback: PricingTable

    public init(catalog: ModelCatalog = .empty, fallback: PricingTable) {
        self.catalog = catalog
        self.fallback = fallback
    }

    /// The provider's context window, the bundled one, or the family the id belongs to. Nil only
    /// when nothing knows the model, in which case the UI says the context is unavailable rather
    /// than drawing a small window.
    public func contextWindow(forModel modelID: String) -> Int? {
        if let metadata = catalog.metadata(forModel: modelID), metadata.contextWindow > 0 {
            return metadata.contextWindow
        }
        if let exact = fallback.contextWindow(forModel: modelID) {
            return exact
        }
        return familyEntry(forModel: modelID)?.contextWindow
    }

    public func maxOutputTokens(forModel modelID: String) -> Int? {
        catalog.metadata(forModel: modelID)?.maxOutputTokens
    }

    public func stallThresholdSeconds(forModel modelID: String) -> TimeInterval {
        fallback.stallThresholdSeconds(forModel: modelID)
    }

    /// The local estimate for one turn, or nil when neither the provider nor the bundled table
    /// can price the model. A caller that gets nil must report the cost as unavailable, never zero.
    public func estimatedCostUSD(
        forModel modelID: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheHitTokens: Int
    ) -> Double? {
        guard let pricing = pricing(forModel: modelID) else { return nil }
        return pricing.costUSD(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheHitTokens: cacheHitTokens
        )
    }

    public func pricing(forModel modelID: String) -> ModelPricing? {
        let fromProvider = catalog.metadata(forModel: modelID).flatMap {
            Self.pricing(from: $0, fallback: fallback)
        }
        return fromProvider ?? fallback.pricing(forModel: modelID) ?? familyEntry(forModel: modelID)
    }

    /// A provider model list that carries rates is the best price there is; one without is not a
    /// price at all and leaves the bundled table in charge.
    private static func pricing(from metadata: ModelMetadata, fallback: PricingTable) -> ModelPricing? {
        guard metadata.hasPricing,
            let input = metadata.inputPerMillion,
            let output = metadata.outputPerMillion
        else { return nil }
        return ModelPricing(
            contextWindow: metadata.contextWindow,
            inputPerMillion: input,
            outputPerMillion: output,
            cacheReadPerMillion: metadata.cacheReadPerMillion ?? input,
            stallThresholdSeconds: fallback.stallThresholdSeconds(forModel: metadata.modelID)
        )
    }

    /// A dated id such as `claude-sonnet-4-5-20250929` is priced and measured from the
    /// `claude-sonnet` entry it starts with. Anything resolved this way is still an estimate.
    private func familyEntry(forModel modelID: String) -> ModelPricing? {
        let match = fallback.models.keys
            .filter { modelID.hasPrefix($0 + "-") }
            .max { $0.count < $1.count }
        return match.flatMap { fallback.pricing(forModel: $0) }
    }
}
