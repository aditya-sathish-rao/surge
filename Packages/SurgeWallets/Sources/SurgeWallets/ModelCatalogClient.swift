import Foundation
import SurgeCore

/// Parses one provider's model list into the numbers Surge uses for context and cost.
protocol ModelListParsing: Sendable {
    func metadata(from data: Data, fetchedAt: Date) throws -> [ModelMetadata]
}

/// Parses `GET https://api.deepseek.com/models`.
///
/// DeepSeek reports each model's context window and output limit but no prices, so the bundled
/// table supplies its rates until a balance movement replaces the estimate with a derived figure.
struct DeepSeekModelListParser: ModelListParsing {
    func metadata(from data: Data, fetchedAt: Date) throws -> [ModelMetadata] {
        guard let response = try? JSONDecoder().decode(DeepSeekModelList.self, from: data) else {
            throw WalletResponseError.malformedBody
        }
        return response.data.compactMap { entry in
            guard let contextWindow = entry.contextWindow, contextWindow > 0 else { return nil }
            return ModelMetadata(
                modelID: entry.id,
                provider: .deepseek,
                contextWindow: contextWindow,
                maxOutputTokens: entry.maxOutputTokens,
                fetchedAt: fetchedAt
            )
        }
    }
}

private struct DeepSeekModelList: Decodable {
    let data: [DeepSeekModelEntry]
}

private struct DeepSeekModelEntry: Decodable {
    let id: String
    let contextWindow: Int?
    let maxOutputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case contextWindow = "context_window"
        case maxOutputTokens = "max_output_tokens"
    }
}

/// Parses the public `GET https://openrouter.ai/api/v1/models`, which carries both the context
/// length and per-token pricing for every model it serves.
struct OpenRouterModelListParser: ModelListParsing {
    func metadata(from data: Data, fetchedAt: Date) throws -> [ModelMetadata] {
        guard let response = try? JSONDecoder().decode(OpenRouterModelList.self, from: data) else {
            throw WalletResponseError.malformedBody
        }
        return response.data.compactMap { entry in
            guard let contextLength = entry.contextLength, contextLength > 0 else { return nil }
            return ModelMetadata(
                modelID: entry.id,
                provider: .openrouter,
                contextWindow: contextLength,
                maxOutputTokens: entry.topProvider?.maxCompletionTokens,
                inputPerMillion: Self.perMillion(entry.pricing?.prompt),
                outputPerMillion: Self.perMillion(entry.pricing?.completion),
                cacheReadPerMillion: Self.perMillion(entry.pricing?.inputCacheRead),
                fetchedAt: fetchedAt
            )
        }
    }

    /// OpenRouter quotes dollars per token as a string. A variable or missing rate is not a price.
    private static func perMillion(_ perToken: String?) -> Double? {
        guard let perToken, let value = Double(perToken), value >= 0, value.isFinite else {
            return nil
        }
        return value * 1_000_000
    }
}

private struct OpenRouterModelList: Decodable {
    let data: [OpenRouterModelEntry]
}

private struct OpenRouterModelEntry: Decodable {
    let id: String
    let contextLength: Int?
    let pricing: OpenRouterPricing?
    let topProvider: OpenRouterTopProvider?

    enum CodingKeys: String, CodingKey {
        case id
        case contextLength = "context_length"
        case pricing
        case topProvider = "top_provider"
    }
}

private struct OpenRouterPricing: Decodable {
    let prompt: String?
    let completion: String?
    let inputCacheRead: String?

    enum CodingKeys: String, CodingKey {
        case prompt
        case completion
        case inputCacheRead = "input_cache_read"
    }
}

private struct OpenRouterTopProvider: Decodable {
    let maxCompletionTokens: Int?

    enum CodingKeys: String, CodingKey {
        case maxCompletionTokens = "max_completion_tokens"
    }
}

/// Fetches every provider's model list and merges the answers into one catalog.
///
/// Each provider is fetched independently, so one failing list never hides another's numbers. A
/// caller merges the result over the cached catalog, which is what keeps an offline launch on the
/// last known values.
public struct ModelCatalogClient: Sendable {
    private let keys: any WalletKeyProviding
    private let transport: any WalletTransport
    private let requestTimeout: TimeInterval

    public init(
        keys: any WalletKeyProviding,
        transport: any WalletTransport = URLSessionWalletTransport(),
        requestTimeout: TimeInterval = WalletConfiguration.defaultRequestTimeout
    ) {
        self.keys = keys
        self.transport = transport
        self.requestTimeout = requestTimeout
    }

    public func fetch(now: Date = Date()) async -> ModelCatalog {
        await withTaskGroup(of: ModelCatalog.self) { group in
            for target in Self.targets {
                group.addTask { await fetch(target, now: now) ?? .empty }
            }
            var merged = ModelCatalog.empty
            for await catalog in group {
                merged = merged.merging(catalog)
            }
            return merged
        }
    }

    private struct Target: Sendable {
        let provider: Provider
        let url: URL?
        let parser: any ModelListParsing
    }

    private static let targets: [Target] = [
        Target(
            provider: .deepseek,
            url: WalletEndpoints.deepSeekModels,
            parser: DeepSeekModelListParser()
        ),
        Target(
            provider: .openrouter,
            url: WalletEndpoints.openRouterModels,
            parser: OpenRouterModelListParser()
        ),
    ]

    private func fetch(_ target: Target, now: Date) async -> ModelCatalog? {
        guard let url = target.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = try? keys.apiKey(for: target.provider), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        do {
            let response = try await transport.get(request)
            guard response.isSuccess else { return nil }
            let entries = try target.parser.metadata(from: response.body, fetchedAt: now)
            guard entries.isEmpty == false else { return nil }
            return ModelCatalog(entries: entries, fetchedAt: now)
        } catch {
            return nil
        }
    }
}
