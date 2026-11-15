import Foundation
import CryptoKit
import Security
import FeedDomain
import FeedStore

/// Standalone app container; no app group, game journal, cloud sync or network access.
actor PrivateVault {
    enum VaultFailure: Error, LocalizedError {
        case locked, keyUnavailable, corrupt, keychain(OSStatus)
        var errorDescription: String? {
            switch self {
            case .keychain(let status): return "Хранилище ключей недоступно (код \(status)). Данные не перезаписаны."
            case .locked: return "Разблокируйте устройство для доступа к архиву."
            case .keyUnavailable: return "Ключ локального архива недоступен. Данные не перезаписаны."
            case .corrupt: return "Защищённый архив не прошёл проверку. Данные не перезаписаны."
            }
        }
    }
    private let root: URL
    private let injectedKey: SymmetricKey?
    private let service: String
    init(root: URL? = nil, testKey: SymmetricKey? = nil, keychainTestID: UUID? = nil) {
        service = "org.worldexe.personalfeed.vault.v1" + (keychainTestID.map { ".test." + $0.uuidString } ?? "")
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrivateFeed", isDirectory: true)
        self.injectedKey = testKey
    }
    private var file: URL { root.appendingPathComponent("vault.aesgcm") }
    private func key(create: Bool) throws -> SymmetricKey {
        if let injectedKey { return injectedKey }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: "local-vault-key",
                                   kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let bytes = result as? Data, bytes.count == 32 { return SymmetricKey(data: bytes) }
        if status == errSecSuccess { throw VaultFailure.keyUnavailable }
        guard status == errSecItemNotFound else { throw VaultFailure.keychain(status) }
        guard create else { throw VaultFailure.keyUnavailable }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let insert: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: "local-vault-key",
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                    kSecValueData as String: data]
        let added = SecItemAdd(insert as CFDictionary, nil)
        guard added == errSecSuccess else { throw VaultFailure.keychain(added) }
        return key
    }
    func load() throws -> FeedVault {
        guard FileManager.default.fileExists(atPath: file.path) else { return FeedVault() }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        let data = try handle.read(upToCount: FeedVault.maximumBytes + 64) ?? Data()
        guard data.count <= FeedVault.maximumBytes + 28 else { throw VaultFailure.corrupt }
        do {
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key(create: false))
            return try FeedVault(data: plain)
        } catch { throw VaultFailure.corrupt }
    }
    func save(_ value: FeedVault) throws {
        let plain = try value.encoded()
        guard let sealed = try AES.GCM.seal(plain, using: key(create: true)).combined else { throw VaultFailure.corrupt }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        var directory = root; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try sealed.write(to: file, options: [.atomic, .completeFileProtection])
    }
    func erase() throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        if injectedKey == nil {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                       kSecAttrService as String: service, kSecAttrAccount as String: "local-vault-key"]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultFailure.keyUnavailable }
        }
    }
}
