//
// StoreKey.swift
//
// 32-byte SQLCipher passphrase, hex-encoded, held in the Keychain.
// Never written next to the database.
//

import Foundation
import Security

enum StoreKey {
    private static let service = "one.klinote.mac"
    private static let account = "sqlite-key"

    static func hex() throws -> String {
        if let existing = load() { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KlinoteCoreError.engine("Could not create the store key.")
        }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        try save(hex)
        return hex
    }

    private static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ hex: String) throws {
        let data = Data(hex.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw KlinoteCoreError.engine("Could not store the database key.")
        }
    }
}
