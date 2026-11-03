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
/// Adding a secret requires Touch ID before this process calls into here.
public enum KeychainStore {
    public static let secretPrefix = "api-key-lock.secret."
    public static let allowlistService = "api-key-lock.allowlist"
    public static let allowlistAccount = "hosts"

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
        guard trustsOnlyThisBinary(service: allowlistService, account: allowlistAccount) else {
            return []
        }
        guard let record = try copy(service: allowlistService, account: allowlistAccount) else {
            return []
        }
        return parseAllowlist(record.secret)
    }

    public static func saveAllowlist(_ hosts: [String]) throws {
        let data = (hosts.sorted().joined(separator: "\n") + (hosts.isEmpty ? "" : "\n")).data(using: .utf8) ?? Data()
        try replace(service: allowlistService, account: allowlistAccount, label: "allowlist", secret: data)
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

    private static func replace(service: String, account: String, label: String, secret: Data) throws {
        var query = baseQuery(service: service, account: account)
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainStoreError.status(status, "replace \(service). Delete that item in Keychain Access if this binary did not create it. Do not click Allow.")
        }
        try add(service: service, account: account, label: label, secret: secret)
    }

    /// True only when a silent-access ACL names exactly this binary.
    /// An item created with `security add-generic-password -A` fails this check.
    /// A program can still create an item that names this binary. Do not use that
    /// check to decide whether `run` may skip Touch ID.
    private static func trustsOnlyThisBinary(service: String, account: String) -> Bool {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnRef as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let result else {
            return false
        }
        var access: SecAccess?
        guard SecKeychainItemCopyAccess(result as! SecKeychainItem, &access) == errSecSuccess, let access else {
            return false
        }
        var aclList: CFArray?
        guard SecAccessCopyACLList(access, &aclList) == errSecSuccess, let acls = aclList as? [SecACL] else {
            return false
        }
        guard let expected = trustedApplicationData() else { return false }
        for acl in acls {
            var apps: CFArray?
            var description: CFString?
            var prompt = SecKeychainPromptSelector(rawValue: 0)
            guard SecACLCopyContents(acl, &apps, &description, &prompt) == errSecSuccess else { return false }
            guard let list = apps as? [SecTrustedApplication], list.count == 1 else { continue }
            var data: CFData?
            guard SecTrustedApplicationCopyData(list[0], &data) == errSecSuccess, let data else { return false }
            if (data as Data) == expected { return true }
        }
        return false
    }

    private static func trustedApplicationData() -> Data? {
        var trusted: SecTrustedApplication?
        guard SecTrustedApplicationCreateFromPath(nil, &trusted) == errSecSuccess, let trusted else { return nil }
        var data: CFData?
        guard SecTrustedApplicationCopyData(trusted, &data) == errSecSuccess, let data else { return nil }
        return data as Data
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
