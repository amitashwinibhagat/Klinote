//
// CaptureVaultStore.swift
//
// The production vault opener. Separate from CaptureVault.swift so the
// headless test bundle can compile the struct without the app's support
// directory or the Keychain: tests construct `CaptureVault(directory:key:)`
// directly. Only the app target compiles this file.
//
// The key is dedicated to the vault — never the store key. One key per
// purpose, so a future change to one does not silently change the blast
// radius of the other. Same Keychain pattern as `StoreKey`.
//

import CryptoKit
import Foundation
import Security

extension CaptureVault {
    /// Opens the sandboxed recovery directory with the Keychain-held vault
    /// key, creating both on first use. Retention is enforced by the model's
    /// `refreshRecoveries()`, not here, so a launch can say what it removed.
    static func open() -> CaptureVault {
        let directory = ModelDownloader.supportDirectory
            .appendingPathComponent("Recovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return CaptureVault(directory: directory, key: vaultKey())
    }

    private static func vaultKey() -> SymmetricKey {
        if let data = loadKeyData() {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        saveKeyData(data)
        return key
    }

    private static let keyService = "one.klinote.mac"
    private static let keyAccount = "capture-vault-key"

    private static func loadKeyData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return data
    }

    private static func saveKeyData(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess && status != errSecDuplicateItem {
            // The vault can still be used for this run, but nothing sealed with
            // this key will open after relaunch. Say so rather than fail closed
            // silently on every future recovery.
            NSLog("Klinote: could not store the capture-vault key (status %d)", status)
        }
    }
}
