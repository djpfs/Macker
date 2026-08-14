//===----------------------------------------------------------------------===//
// KeychainSecretStore — generic secret storage backed by macOS Keychain.
//===----------------------------------------------------------------------===//

import Foundation
#if canImport(Security)
import Security
#endif

/// Stores and resolves runtime secrets in Keychain (or a local fallback store
/// when Keychain is unavailable in the build environment).
public struct KeychainSecretStore: Sendable {
    public let serviceName: String

    public init(serviceName: String = "dev.macker.secrets") {
        self.serviceName = serviceName
    }

    /// Create or update a secret value.
    public func setSecret(name: String, value: String) throws {
        let account = try normalizedName(name)
#if canImport(Security)
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]

        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess {
            return
        }
        if status != errSecItemNotFound {
            throw BackendError.operationFailed(Self.keychainError(status, action: "update secret"))
        }

        var add = query
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw BackendError.operationFailed(Self.keychainError(addStatus, action: "create secret"))
        }
#else
        var secrets = try loadFallbackSecrets()
        secrets[account] = value
        try persistFallbackSecrets(secrets)
#endif
    }

    /// Return the secret value, if present.
    public func secret(named name: String) throws -> String? {
        let account = try normalizedName(name)
#if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw BackendError.operationFailed(Self.keychainError(status, action: "read secret"))
        }
        guard let data = out as? Data else {
            throw BackendError.invalidResponse("keychain item for '\(account)' did not contain data")
        }
        return String(data: data, encoding: .utf8)
#else
        return try loadFallbackSecrets()[account]
#endif
    }

    /// Delete a secret. Missing items are ignored.
    public func deleteSecret(named name: String) throws {
        let account = try normalizedName(name)
#if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BackendError.operationFailed(Self.keychainError(status, action: "delete secret"))
        }
#else
        var secrets = try loadFallbackSecrets()
        secrets.removeValue(forKey: account)
        try persistFallbackSecrets(secrets)
#endif
    }

    /// List all secret names in this service namespace.
    public func listSecretNames() throws -> [String] {
#if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw BackendError.operationFailed(Self.keychainError(status, action: "list secrets"))
        }

        let items = out as? [[String: Any]] ?? []
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
#else
        return try loadFallbackSecrets().keys.sorted()
#endif
    }

    /// Resolve `KEY=keychain://name` entries by fetching the referenced secret.
    public func resolveEnvironment(_ environment: [String]) throws -> [String] {
        try Self.resolveEnvironment(environment) { name in
            try secret(named: name)
        }
    }

    /// Resolve `KEY=keychain://name` entries using a custom lookup strategy.
    public static func resolveEnvironment(
        _ environment: [String],
        lookup: (String) throws -> String?
    ) throws -> [String] {
        try environment.map { entry in
            let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return entry }

            let key = String(parts[0])
            let value = String(parts[1])
            guard value.hasPrefix("keychain://") else { return entry }

            let name = String(value.dropFirst("keychain://".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw BackendError.operationFailed("invalid keychain secret reference for \(key)")
            }
            guard let secret = try lookup(name) else {
                throw BackendError.notFound("secret \(name)")
            }
            return "\(key)=\(secret)"
        }
    }

    private func normalizedName(_ name: String) throws -> String {
        let account = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if account.isEmpty {
            throw BackendError.operationFailed("secret name cannot be empty")
        }
        return account
    }

#if canImport(Security)
    private static func keychainError(_ status: OSStatus, action: String) -> String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "\(action) failed: \(message)"
    }
#else
    private var fallbackURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".macker", isDirectory: true)
            .appendingPathComponent("secrets-\(serviceName).json")
    }

    private func loadFallbackSecrets() throws -> [String: String] {
        let url = fallbackURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func persistFallbackSecrets(_ secrets: [String: String]) throws {
        let url = fallbackURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try JSONEncoder().encode(secrets)
        try data.write(to: url, options: .atomic)
    }
#endif
}
