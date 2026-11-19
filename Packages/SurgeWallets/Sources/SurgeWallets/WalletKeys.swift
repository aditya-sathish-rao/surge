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

/// What the Settings screen needs to show for one provider.
public enum ProviderKeyState: Sendable, Equatable {
    case configured
    case notConfigured
    /// The Keychain refused the read, so the provider has to be treated as unavailable.
    case unavailable
}

extension WalletKeyProviding {
    /// Reads one provider's key and turns any Keychain failure into a plain state, so a caller
    /// never has to stop on it. `errSecItemNotFound` is simply "not configured".
    public func keyState(for provider: Provider) -> ProviderKeyState {
        do {
            return try apiKey(for: provider) == nil ? .notConfigured : .configured
        } catch {
            return .unavailable
        }
    }
}

/// A key store the Settings screen can write to and remove from.
public protocol WalletKeyStoring: WalletKeyProviding {
    func saveKey(_ key: String, for provider: Provider) throws
    func removeKey(for provider: Provider) throws
}

/// Reads provider keys from generic-password items in the user's login Keychain.
///
/// Surge never stores a key anywhere else, and the poller never logs one.
public struct KeychainWalletKeys: WalletKeyStoring {
    public static let defaultService = "com.surge.apikeys"

    private let service: String

    public init(service: String = KeychainWalletKeys.defaultService) {
        self.service = service
    }

    public static func account(for provider: Provider) -> String {
        provider.rawValue
    }

    public func apiKey(for provider: Provider) throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(Self.query(for: provider, service: service) as CFDictionary, &result)
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

    /// Writes the key as a generic-password item in the login Keychain. An empty key removes it.
    public func saveKey(_ key: String, for provider: Provider) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try removeKey(for: provider)
            return
        }
        guard let data = trimmed.data(using: .utf8) else { return }
        let query = Self.baseQuery(for: provider, service: service)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw WalletKeyError.keychainUnavailable(status: addStatus)
            }
        default:
            throw WalletKeyError.keychainUnavailable(status: status)
        }
    }

    public func removeKey(for provider: Provider) throws {
        let status = SecItemDelete(Self.baseQuery(for: provider, service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WalletKeyError.keychainUnavailable(status: status)
        }
    }

    private static func baseQuery(for provider: Provider, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
        ]
    }

    private static func query(for provider: Provider, service: String) -> [String: Any] {
        var query = baseQuery(for: provider, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }
}
