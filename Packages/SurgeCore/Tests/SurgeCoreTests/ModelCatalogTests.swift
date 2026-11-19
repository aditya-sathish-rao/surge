import Foundation
import SurgeCore
import Testing

struct ModelCatalogTests {
    private static let deepSeekWindow = 1_048_576

    private static func fallback() -> PricingTable {
        PricingTable(models: [
            "deepseek-chat": ModelPricing(
                contextWindow: 128_000,
                inputPerMillion: 0.27,
                outputPerMillion: 1.10,
                cacheReadPerMillion: 0.07
            ),
            "claude-sonnet": ModelPricing(
                contextWindow: 200_000,
                inputPerMillion: 3.00,
                outputPerMillion: 15.00,
                cacheReadPerMillion: 0.30
            ),
        ])
    }

    @Test func theProvidersOwnWindowWinsOverTheBundledLastKnownValue() {
        let catalog = ModelCatalog(
            entries: [
                ModelMetadata(
                    modelID: "deepseek-chat",
                    provider: .deepseek,
                    contextWindow: Self.deepSeekWindow,
                    maxOutputTokens: Self.deepSeekWindow,
                    fetchedAt: SurgeFixtures.referenceDate
                )
            ],
            fetchedAt: SurgeFixtures.referenceDate
        )
        let book = PriceBook(catalog: catalog, fallback: Self.fallback())

        #expect(book.contextWindow(forModel: "deepseek-chat") == Self.deepSeekWindow)
        #expect(book.maxOutputTokens(forModel: "deepseek-chat") == Self.deepSeekWindow)
    }

    @Test func aProviderWithoutRatesUsesTheBundledRates() throws {
        let catalog = ModelCatalog(
            entries: [
                ModelMetadata(
                    modelID: "deepseek-chat",
                    provider: .deepseek,
                    contextWindow: Self.deepSeekWindow,
                    fetchedAt: SurgeFixtures.referenceDate
                )
            ],
            fetchedAt: SurgeFixtures.referenceDate
        )
        let book = PriceBook(catalog: catalog, fallback: Self.fallback())
        let cost = try #require(
            book.estimatedCostUSD(
                forModel: "deepseek-chat",
                inputTokens: 1_000_000,
                outputTokens: 0,
                cacheHitTokens: 0
            )
        )

        #expect(abs(cost - 0.27) < 0.000_001)
    }

    @Test func providerReportedRatesPriceAModelTheBundledTableDoesNotKnow() throws {
        let catalog = ModelCatalog(
            entries: [
                ModelMetadata(
                    modelID: "some/openrouter-model",
                    provider: .openrouter,
                    contextWindow: 262_144,
                    inputPerMillion: 0.15,
                    outputPerMillion: 0.60,
                    cacheReadPerMillion: 0.03,
                    fetchedAt: SurgeFixtures.referenceDate
                )
            ],
            fetchedAt: SurgeFixtures.referenceDate
        )
        let book = PriceBook(catalog: catalog, fallback: Self.fallback())

        #expect(book.contextWindow(forModel: "some/openrouter-model") == 262_144)
        let cost = try #require(
            book.estimatedCostUSD(
                forModel: "some/openrouter-model",
                inputTokens: 1_000_000,
                outputTokens: 1_000_000,
                cacheHitTokens: 2_000_000
            )
        )
        #expect(abs(cost - 0.81) < 0.000_001)
    }

    @Test func anUnknownModelHasNoWindowAndNoCost() {
        let book = PriceBook(catalog: .empty, fallback: Self.fallback())

        #expect(book.contextWindow(forModel: "mystery-model") == nil)
        #expect(book.pricing(forModel: "mystery-model") == nil)
        #expect(
            book.estimatedCostUSD(
                forModel: "mystery-model",
                inputTokens: 1_000,
                outputTokens: 1_000,
                cacheHitTokens: 0
            ) == nil
        )
        #expect(book.stallThresholdSeconds(forModel: "mystery-model") == SurgeThresholds.defaultStallSeconds)
    }

    @Test func aDatedModelIDResolvesToItsFamilyAsAnEstimate() throws {
        let book = PriceBook(catalog: .empty, fallback: Self.fallback())

        #expect(book.contextWindow(forModel: "claude-sonnet-4-5-20250929") == 200_000)
        let cost = try #require(
            book.estimatedCostUSD(
                forModel: "claude-sonnet-4-5-20250929",
                inputTokens: 1_000_000,
                outputTokens: 0,
                cacheHitTokens: 0
            )
        )
        #expect(abs(cost - 3.00) < 0.000_001)
    }

    @Test func aLaterFetchWinsOnASharedModel() {
        let first = ModelCatalog(
            entries: [
                ModelMetadata(
                    modelID: "deepseek-chat",
                    provider: .deepseek,
                    contextWindow: 128_000,
                    fetchedAt: SurgeFixtures.referenceDate
                )
            ],
            fetchedAt: SurgeFixtures.referenceDate
        )
        let second = ModelCatalog(
            entries: [
                ModelMetadata(
                    modelID: "deepseek-chat",
                    provider: .deepseek,
                    contextWindow: Self.deepSeekWindow,
                    fetchedAt: SurgeFixtures.referenceDate.addingTimeInterval(60)
                )
            ],
            fetchedAt: SurgeFixtures.referenceDate.addingTimeInterval(60)
        )
        let merged = first.merging(second)

        #expect(merged.metadata(forModel: "deepseek-chat")?.contextWindow == Self.deepSeekWindow)
    }

    @Test func theSameModelIDCanBelongToTwoProviders() {
        let catalog = ModelCatalog(
            entries: [
                ModelMetadata(
                    modelID: "shared-model",
                    provider: .deepseek,
                    contextWindow: 64_000,
                    fetchedAt: SurgeFixtures.referenceDate
                ),
                ModelMetadata(
                    modelID: "shared-model",
                    provider: .openrouter,
                    contextWindow: 128_000,
                    fetchedAt: SurgeFixtures.referenceDate
                ),
            ],
            fetchedAt: SurgeFixtures.referenceDate
        )

        #expect(catalog.metadata(forModel: "shared-model", provider: .deepseek)?.contextWindow == 64_000)
        #expect(catalog.metadata(forModel: "shared-model", provider: .openrouter)?.contextWindow == 128_000)
    }

    @Test func anEntryWithoutAContextWindowIsNotCached() {
        let catalog = ModelCatalog(
            entries: [
                ModelMetadata(
                    modelID: "broken",
                    provider: .openrouter,
                    contextWindow: 0,
                    fetchedAt: SurgeFixtures.referenceDate
                )
            ],
            fetchedAt: SurgeFixtures.referenceDate
        )

        #expect(catalog.isEmpty)
    }
}
