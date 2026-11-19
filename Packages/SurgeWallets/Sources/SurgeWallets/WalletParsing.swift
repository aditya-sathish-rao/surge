import Foundation
import SurgeCore

/// What one provider response says about an account.
///
/// `amountUSD` is nil when the provider answered but quotes no remaining balance.
/// `usageUSD` is the provider's own cumulative usage total, when it reports one.
struct WalletBalance: Sendable, Equatable {
    let amountUSD: Double?
    let usageUSD: Double?
    let kind: BalanceKind

    init(amountUSD: Double?, usageUSD: Double? = nil, kind: BalanceKind = .wallet) {
        self.amountUSD = amountUSD
        self.usageUSD = usageUSD
        self.kind = kind
    }
}

enum WalletResponseError: Error, Sendable, Equatable {
    case malformedBody
}

protocol BalanceResponseParsing: Sendable {
    func balance(from data: Data) throws -> WalletBalance
}

/// Parses `GET https://api.deepseek.com/user/balance`.
struct DeepSeekBalanceParser: BalanceResponseParsing {
    func balance(from data: Data) throws -> WalletBalance {
        guard let response = try? JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data),
            response.isAvailable,
            let info = response.balanceInfos.first,
            let amount = Double(info.totalBalance)
        else {
            throw WalletResponseError.malformedBody
        }
        return WalletBalance(amountUSD: amount, usageUSD: nil, kind: .wallet)
    }
}

private struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [DeepSeekBalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

private struct DeepSeekBalanceInfo: Decodable {
    let totalBalance: String

    enum CodingKeys: String, CodingKey {
        case totalBalance = "total_balance"
    }
}

/// Parses `GET https://openrouter.ai/api/v1/auth/key`.
///
/// Remaining balance is the key's spend limit minus its usage. That is a per-key cap, not the
/// account wallet, so it is labelled as one. A key without a limit has no remaining amount to
/// report, but its cumulative usage is still shown.
struct OpenRouterBalanceParser: BalanceResponseParsing {
    func balance(from data: Data) throws -> WalletBalance {
        guard let response = try? JSONDecoder().decode(OpenRouterKeyResponse.self, from: data) else {
            throw WalletResponseError.malformedBody
        }
        let amount = response.data.limit.map { max($0 - response.data.usage, 0) }
        return WalletBalance(amountUSD: amount, usageUSD: response.data.usage, kind: .keyLimit)
    }
}

private struct OpenRouterKeyResponse: Decodable {
    let data: OpenRouterKeyPayload
}

private struct OpenRouterKeyPayload: Decodable {
    let usage: Double
    let limit: Double?
}
