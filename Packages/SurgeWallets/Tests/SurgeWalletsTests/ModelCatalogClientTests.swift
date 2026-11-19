import Foundation
import SurgeCore
import Testing

@testable import SurgeWallets

@Suite("Model catalog")
struct ModelCatalogTests {
    private static let fetchDate = Date(timeIntervalSince1970: 1_763_000_100)

    private static let deepSeekModelsURL = "https://api.deepseek.com/models"
    private static let openRouterModelsURL = "https://openrouter.ai/api/v1/models"

    @Test func deepSeekModelsCarryTheRealContextWindow() throws {
        let entries = try DeepSeekModelListParser().metadata(
            from: Data(WalletFixtures.deepSeekModels.utf8),
            fetchedAt: Self.fetchDate
        )

        #expect(entries.count == 2)
        let chat = try #require(entries.first { $0.modelID == "deepseek-chat" })
        #expect(chat.provider == .deepseek)
        #expect(chat.contextWindow == 1_048_576)
        #expect(chat.maxOutputTokens == 8_192)
        #expect(chat.hasPricing == false)
    }

    @Test func openRouterModelsTurnPerTokenStringsIntoPerMillionRates() throws {
        let entries = try OpenRouterModelListParser().metadata(
            from: Data(WalletFixtures.openRouterModels.utf8),
            fetchedAt: Self.fetchDate
        )

        let sonnet = try #require(entries.first { $0.modelID == "anthropic/claude-3.5-sonnet" })
        #expect(sonnet.contextWindow == 200_000)
        #expect(sonnet.maxOutputTokens == 8_192)
        #expect(abs((sonnet.inputPerMillion ?? 0) - 3.00) < 0.000_001)
        #expect(abs((sonnet.outputPerMillion ?? 0) - 15.00) < 0.000_001)
        #expect(abs((sonnet.cacheReadPerMillion ?? 0) - 0.30) < 0.000_001)

        let chat = try #require(entries.first { $0.modelID == "deepseek/deepseek-chat" })
        #expect(chat.cacheReadPerMillion == nil)
    }

    @Test func aVariablePriceIsNotTreatedAsACost() throws {
        let entries = try OpenRouterModelListParser().metadata(
            from: Data(WalletFixtures.openRouterModelsVariablePricing.utf8),
            fetchedAt: Self.fetchDate
        )
        let model = try #require(entries.first)

        #expect(model.contextWindow == 2_000_000)
        #expect(model.inputPerMillion == nil)
        #expect(model.outputPerMillion == nil)
        #expect(model.hasPricing == false)
    }

    @Test func aModelWithoutAContextWindowIsDropped() throws {
        let entries = try OpenRouterModelListParser().metadata(
            from: Data(WalletFixtures.openRouterModelsMissingWindow.utf8),
            fetchedAt: Self.fetchDate
        )

        #expect(entries.isEmpty)
    }

    @Test func theClientMergesEveryProviderList() async {
        let transport = StubTransport(
            byURL: [
                Self.deepSeekModelsURL: [.response(statusCode: 200, body: WalletFixtures.deepSeekModels)],
                Self.openRouterModelsURL: [.response(statusCode: 200, body: WalletFixtures.openRouterModels)],
            ]
        )
        let catalog = await ModelCatalogClient(keys: StubKeys(), transport: transport)
            .fetch(now: Self.fetchDate)

        #expect(catalog.metadata(forModel: "deepseek-chat", provider: .deepseek)?.contextWindow == 1_048_576)
        #expect(
            catalog.metadata(forModel: "anthropic/claude-3.5-sonnet", provider: .openrouter)?.contextWindow
                == 200_000
        )
        let requests = await transport.sentRequests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.authorization?.isEmpty == false })
    }

    @Test func oneFailingProviderKeepsTheOthersNumbers() async {
        let transport = StubTransport(
            byURL: [
                Self.deepSeekModelsURL: [.response(statusCode: 401, body: WalletFixtures.unauthorized)],
                Self.openRouterModelsURL: [.response(statusCode: 200, body: WalletFixtures.openRouterModels)],
            ]
        )
        let catalog = await ModelCatalogClient(keys: StubKeys(), transport: transport)
            .fetch(now: Self.fetchDate)

        #expect(catalog.metadata(forModel: "deepseek-chat", provider: .deepseek) == nil)
        #expect(catalog.metadata(forModel: "deepseek/deepseek-chat", provider: .openrouter) != nil)
    }

    @Test func aFailedFetchLeavesTheCachedCatalogAlone() async {
        let transport = StubTransport([.response(statusCode: 500, body: "{}")])
        let fetched = await ModelCatalogClient(keys: StubKeys(), transport: transport)
            .fetch(now: Self.fetchDate)

        let cached = ModelCatalog(
            entries: [
                ModelMetadata(
                    modelID: "deepseek-chat",
                    provider: .deepseek,
                    contextWindow: 1_048_576,
                    fetchedAt: Self.fetchDate
                )
            ],
            fetchedAt: Self.fetchDate
        )

        #expect(fetched.isEmpty)
        #expect(cached.merging(fetched).metadata(forModel: "deepseek-chat")?.contextWindow == 1_048_576)
    }

    @Test func theCacheRoundTripsThroughDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "surge-catalog-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ModelCatalogStore(directory: directory)
        let catalog = ModelCatalog(
            entries: [
                ModelMetadata(
                    modelID: "deepseek-reasoner",
                    provider: .deepseek,
                    contextWindow: 1_048_576,
                    maxOutputTokens: 65_536,
                    fetchedAt: Self.fetchDate
                )
            ],
            fetchedAt: Self.fetchDate
        )

        #expect(store.load().isEmpty)
        store.save(catalog)
        #expect(store.load() == catalog)
    }

    @Test func keyStateDistinguishesMissingFromAFailure() {
        #expect(StubKeys().keyState(for: .deepseek) == .configured)
        #expect(StubKeys(deepSeek: nil).keyState(for: .deepseek) == .notConfigured)
        #expect(SilentKeys().keyState(for: .deepseek) == .notConfigured)
        #expect(FailingKeys().keyState(for: .deepseek) == .unavailable)
    }
}

private struct SilentKeys: WalletKeyProviding {
    func apiKey(for provider: Provider) throws -> String? { nil }
}

@Suite("Key containment")
struct ProviderKeyContainmentTests {
    private static let sentinel = "sk-sentinel-nothing-should-ever-see-this"

    @Test func aKeyIsUsedOnTheWireAndNowhereElse() async throws {
        let scheduler = ScriptedScheduler(date: Date(timeIntervalSince1970: 1_763_000_100), stopAfterSleeps: 1)
        let transport = StubTransport([.response(statusCode: 200, body: WalletFixtures.deepSeekBalance)])
        let updates = await collectUpdates(
            configuration: WalletConfiguration(accounts: [TestAccounts.deepSeek], pollInterval: 10),
            keys: StubKeys(deepSeek: Self.sentinel),
            transport: transport,
            scheduler: scheduler
        )

        let requests = await transport.sentRequests
        #expect(requests.first?.authorization == "Bearer \(Self.sentinel)")
        let published = try JSONEncoder().encode(updates)
        let text = try #require(String(data: published, encoding: .utf8))
        #expect(text.contains(Self.sentinel) == false)
    }

    @Test func aKeyNeverReachesTheCachedModelCatalog() async throws {
        let transport = StubTransport(
            byURL: [
                "https://api.deepseek.com/models": [
                    .response(statusCode: 200, body: WalletFixtures.deepSeekModels)
                ],
                "https://openrouter.ai/api/v1/models": [
                    .response(statusCode: 200, body: WalletFixtures.openRouterModels)
                ],
            ]
        )
        let catalog = await ModelCatalogClient(
            keys: StubKeys(deepSeek: Self.sentinel, openRouter: Self.sentinel),
            transport: transport
        ).fetch(now: Date(timeIntervalSince1970: 1_763_000_100))

        let entries = await transport.sentRequests
        #expect(entries.allSatisfy { $0.authorization == "Bearer \(Self.sentinel)" })
        let data = try JSONEncoder().encode(catalog)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains(Self.sentinel) == false)
    }
}
