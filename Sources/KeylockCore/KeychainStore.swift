import Foundation
import Security

public enum KeychainStoreError: Error, CustomStringConvertible {
    case status(OSStatus, String)
    case duplicate
    case missing
    case badRecord

    public var description: String {
        switch self {
        case .status(let code, let action):
            let message = SecCopyErrorMessageString(code, nil) as String? ?? "unknown"
            return "\(action) failed: \(code) \(message)"
        case .duplicate:
            return "an item with that id already exists; refusing to overwrite"
        case .missing:
            return "no keychain item for that id"
        case .badRecord:
            return "keychain item did not contain a host and a secret"
        }
    }
}

/// Login-keychain store. The item trusts this signed binary only.
/// Other programs do not get a silent read. They can still raise an Allow dialog.
/// This process requires Touch ID before it calls into here for a secret.
public enum KeychainStore {
    public static let secretPrefix = "api-key-lock.secret."
    public static let allowlistService = "api-key-lock.allowlist"
    public static let allowlistAccount = "hosts"
    public static let authService = "api-key-lock.auth"
    public static let authAccount = "run"

    public static func secretService(_ id: String) -> String {
        secretPrefix + id
    }

    public static func addSecret(id: String, host: String, secret: Data) throws {
        let service = secretService(id)
        if exists(service: service, account: id) {
            throw KeychainStoreError.duplicate
        }
        try add(service: service, account: id, label: host, secret: secret)
    }

    public static func loadHost(id: String) throws -> String {
        let service = secretService(id)
        guard let record = try copy(service: service, account: id, includeSecret: false) else {
            throw KeychainStoreError.missing
        }
        guard let host = record.label, !host.isEmpty else {
            throw KeychainStoreError.badRecord
        }
        return host
    }

    public static func loadSecret(id: String) throws -> (host: String, secret: Data) {
        let service = secretService(id)
        guard let record = try copy(service: service, account: id) else {
            throw KeychainStoreError.missing
        }
        guard let host = record.label, !host.isEmpty, !record.secret.isEmpty else {
            throw KeychainStoreError.badRecord
        }
        return (host, record.secret)
    }

    public static func loadAllowlist() throws -> [String] {
        guard let record = try copy(service: allowlistService, account: allowlistAccount) else {
            return []
        }
        return parseAllowlist(record.secret)
    }

    public static func saveAllowlist(_ hosts: [String]) throws {
        let data = (hosts.sorted().joined(separator: "\n") + (hosts.isEmpty ? "" : "\n")).data(using: .utf8) ?? Data()
        if exists(service: allowlistService, account: allowlistAccount) {
            let status = SecItemUpdate(
                baseQuery(service: allowlistService, account: allowlistAccount) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard status == errSecSuccess else {
                throw KeychainStoreError.status(status, "update allowlist")
            }
            return
        }
        try add(service: allowlistService, account: allowlistAccount, label: "allowlist", secret: data)
    }

    public static func loadAuth() throws -> AuthState {
        guard let record = try copy(service: authService, account: authAccount) else {
            return .default
        }
        return AuthPolicy.decode(record.secret)
    }

    public static func saveAuth(_ state: AuthState) throws {
        let data = AuthPolicy.encode(state)
        if exists(service: authService, account: authAccount) {
            let status = SecItemUpdate(
                baseQuery(service: authService, account: authAccount) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard status == errSecSuccess else {
                throw KeychainStoreError.status(status, "update auth")
            }
            return
        }
        try add(service: authService, account: authAccount, label: "auth", secret: data)
    }

    public static func parseAllowlist(_ data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }

    private struct Record {
        var label: String?
        var secret: Data
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private static func exists(service: String, account: String) -> Bool {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private static func add(service: String, account: String, label: String, secret: Data) throws {
        let access = try trustedAccess()
        var query = baseQuery(service: service, account: account)
        query[kSecValueData as String] = secret
        query[kSecAttrLabel as String] = label
        query[kSecAttrAccess as String] = access
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError.status(status, "add \(service)")
        }
    }

    private static func copy(service: String, account: String, includeSecret: Bool = true) throws -> Record? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = includeSecret
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainStoreError.status(status, "read \(service)")
        }
        guard let dict = result as? [String: Any] else {
            throw KeychainStoreError.badRecord
        }
        let secret = dict[kSecValueData as String] as? Data ?? Data()
        let label = dict[kSecAttrLabel as String] as? String
        return Record(label: label, secret: secret)
    }

    private static func trustedAccess() throws -> SecAccess {
        var trusted: SecTrustedApplication?
        let trustedStatus = SecTrustedApplicationCreateFromPath(nil, &trusted)
        guard trustedStatus == errSecSuccess, let trusted else {
            throw KeychainStoreError.status(trustedStatus, "identify this binary")
        }
        var access: SecAccess?
        let accessStatus = SecAccessCreate("keylock" as CFString, [trusted] as CFArray, &access)
        guard accessStatus == errSecSuccess, let access else {
            throw KeychainStoreError.status(accessStatus, "create keychain access")
        }
        return access
    }
}
