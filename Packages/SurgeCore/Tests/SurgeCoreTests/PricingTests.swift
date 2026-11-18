import Foundation
import SurgeCore
import Testing

struct PricingTests {
    @Test func bundledTableDecodesTheKnownModels() throws {
        let table = try SurgeFixtures.pricingTable()

        #expect(table.models.count == 4)
        #expect(table.contextWindow(forModel: "claude-sonnet") == 200_000)
        #expect(table.contextWindow(forModel: "claude-sonnet-5-5") == 200_000)
        #expect(table.contextWindow(forModel: "deepseek-chat") == 128_000)
        #expect(table.stallThresholdSeconds(forModel: "deepseek-reasoner") == 300)
        #expect(table.stallThresholdSeconds(forModel: "deepseek-chat") == 120)
        #expect(table.stallThresholdSeconds(forModel: "claude-sonnet-5-5") == 120)
    }

    @Test func claudeSonnet55UsesTheCaptainSuppliedRates() throws {
        let table = try SurgeFixtures.pricingTable()
        let cost = try #require(
            table.estimatedCostUSD(
                forModel: "claude-sonnet-5-5",
                inputTokens: 1_000_000,
                outputTokens: 1_000_000,
                cacheHitTokens: 1_000_000
            )
        )

        #expect(abs(cost - 12.10) < 0.000_001)
    }

    @Test func costUsesInputOutputAndCacheReadRates() throws {
        let table = try SurgeFixtures.pricingTable()
        let cost = try #require(
            table.estimatedCostUSD(
                forModel: "deepseek-chat",
                inputTokens: 1_000_000,
                outputTokens: 1_000_000,
                cacheHitTokens: 1_000_000
            )
        )

        #expect(abs(cost - 1.44) < 0.000_001)
    }

    @Test func cacheHitTokensArePricedBelowInputTokens() throws {
        let table = try SurgeFixtures.pricingTable()
        let withCache = try #require(
            table.estimatedCostUSD(
                forModel: "claude-sonnet", inputTokens: 0, outputTokens: 0, cacheHitTokens: 1_000_000)
        )
        let withoutCache = try #require(
            table.estimatedCostUSD(
                forModel: "claude-sonnet", inputTokens: 1_000_000, outputTokens: 0, cacheHitTokens: 0)
        )

        #expect(abs(withCache - 0.30) < 0.000_001)
        #expect(abs(withoutCache - 3.00) < 0.000_001)
        #expect(withCache < withoutCache)
    }

    @Test func unknownModelHasDefinedFallbackBehaviour() throws {
        let table = try SurgeFixtures.pricingTable()

        #expect(table.pricing(forModel: "openrouter-auto") == nil)
        #expect(table.contextWindow(forModel: "openrouter-auto") == nil)
        #expect(table.stallThresholdSeconds(forModel: "openrouter-auto") == 120)
        #expect(
            table.estimatedCostUSD(forModel: "openrouter-auto", inputTokens: 100, outputTokens: 100, cacheHitTokens: 0)
                == nil
        )
    }

    @Test func newModelCanBeAddedThroughJSON() throws {
        let json = """
            {
              "custom-model": {
                "contextWindow": 8000,
                "inputPerMillion": 1.0,
                "outputPerMillion": 2.0,
                "cacheReadPerMillion": 0.5
              }
            }
            """
        let table = try PricingTable.decode(from: Data(json.utf8))

        #expect(table.contextWindow(forModel: "custom-model") == 8000)
        #expect(table.stallThresholdSeconds(forModel: "custom-model") == 120)
        let cost = try #require(
            table.estimatedCostUSD(
                forModel: "custom-model",
                inputTokens: 1_000_000,
                outputTokens: 1_000_000,
                cacheHitTokens: 2_000_000
            )
        )
        #expect(abs(cost - 4.0) < 0.000_001)
    }

    @Test func pricingTableRoundTripsThroughJSON() throws {
        let table = try SurgeFixtures.pricingTable()
        let data = try JSONEncoder().encode(table)
        let decoded = try PricingTable.decode(from: data)

        #expect(decoded == table)
    }
}
