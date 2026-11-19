import Foundation
import Security
import SurgeCore

/// The boundary the poller reads API keys through, so tests never touch the real Keychain.
public protocol WalletKeyProviding: Sendable {
    /// The provider's API key, or nil when the user has not stored one.
    func apiKey(for provider: Provider) throws -> String?
}

public enum WalletKeyError: Error, Sendable, Equatable {
    case keychainUnavailable(status: Int32)
}

/// Reads provider keys from generic-password items in the user's login Keychain.
///
/// Surge never stores a key anywhere else, and the poller never logs one.
public struct KeychainWalletKeys: WalletKeyProviding {
    public static let defaultService = "com.surge.apikeys"

    private let service: String

    public init(service: String = KeychainWalletKeys.defaultService) {
        self.service = service
    }

    public static func account(for provider: Provider) -> String {
        provider.rawValue
    }

    public func apiKey(for provider: Provider) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: KeychainWalletKeys.account(for: provider),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecItemNotFound:
            return nil
        case errSecSuccess:
            guard let data = result as? Data,
                let stored = String(data: data, encoding: .utf8)
            else { return nil }
            let key = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : key
        default:
            throw WalletKeyError.keychainUnavailable(status: status)
        }
    }
}
