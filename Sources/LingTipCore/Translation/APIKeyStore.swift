import Foundation
import Security

/// The Anthropic API key: `ANTHROPIC_API_KEY` in the environment wins (handy when
/// launching from a terminal during development), otherwise the login Keychain.
public enum APIKeyStore {
    static let account = "anthropic-api-key"

    public static var anthropicKey: String? {
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty {
            return env
        }
        return KeychainStore.read(account: account)
    }

    static var usingEnvironment: Bool {
        !(ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? "").isEmpty
    }

    static var hasKeychainKey: Bool { KeychainStore.read(account: account) != nil }

    static func save(_ key: String) throws {
        try KeychainStore.write(key.trimmingCharacters(in: .whitespacesAndNewlines), account: account)
    }

    static func clear() { KeychainStore.delete(account: account) }
}

enum KeychainStore {
    static let service = "com.lingtip.LingTip"

    struct Error: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        }
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) throws {
        delete(account: account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error(status: status) }
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
