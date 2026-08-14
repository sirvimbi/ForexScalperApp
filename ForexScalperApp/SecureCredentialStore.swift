import Foundation
import Security
import Combine

struct SecureCredentialStore {
    nonisolated static let shared = SecureCredentialStore()
    private let service = "com.sirvimbi.ForexScalperApp.mt5"
    private func key(_ name: String) -> String { "mt5.\(name)" }

    nonisolated func read(_ name: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key(name),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    nonisolated func write(_ value: String, for name: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key(name)
        ]
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    @MainActor
    func migrateLegacyUserDefaults() {
        let defaults = UserDefaults.standard
        for name in ["mt5AuthToken", "mt5Login", "mt5Password", "mt5Server"] {
            if let legacy = defaults.string(forKey: name), !legacy.isEmpty {
                if read(name) == nil { _ = write(legacy, for: name) }
                defaults.removeObject(forKey: name)
            }
        }
    }
}
