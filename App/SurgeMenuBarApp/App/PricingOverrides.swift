import Foundation
import SurgeCore

/// Applies the user's per-model stall thresholds to the bundled pricing table.
///
/// Only models already in the table are changed; an override for a model that is not there would
/// have nothing to measure its context window against.
enum PricingOverrides {
    static func applying(_ overrides: [String: TimeInterval], to base: PricingTable) -> PricingTable {
        guard !overrides.isEmpty else { return base }
        var models = base.models
        for (name, threshold) in overrides {
            guard let pricing = models[name] else { continue }
            models[name] = ModelPricing(
                contextWindow: pricing.contextWindow,
                inputPerMillion: pricing.inputPerMillion,
                outputPerMillion: pricing.outputPerMillion,
                cacheReadPerMillion: pricing.cacheReadPerMillion,
                stallThresholdSeconds: threshold
            )
        }
        return PricingTable(models: models)
    }
}
