import Foundation
import Security
import LocalAuthentication

let service = "api-key-lock.probe"
let account = "isolation"
let secret = "probe-secret-not-a-real-key".data(using: .utf8)!

func describe(_ status: OSStatus) -> String {
    if let message = SecCopyErrorMessageString(status, nil) as String? {
        return "\(status) \(message)"
    }
    return "\(status)"
}

var accessError: Unmanaged<CFError>?
guard let access = SecAccessControlCreateWithFlags(
    nil,
    kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
    .biometryCurrentSet,
    &accessError
) else {
    fputs("access control failed: \(String(describing: accessError?.takeRetainedValue()))\n", stderr)
    exit(1)
}

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
    kSecValueData as String: secret,
    kSecAttrAccessControl as String: access,
    kSecUseDataProtectionKeychain as String: true,
    kSecAttrSynchronizable as String: false,
]

let deleted = SecItemDelete(query as CFDictionary)
fputs("delete-before: \(describe(deleted))\n", stderr)

let status = SecItemAdd(query as CFDictionary, nil)
fputs("add: \(describe(status))\n", stderr)
if status != errSecSuccess {
    exit(2)
}

var result: CFTypeRef?
let read = SecItemCopyMatching([
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
    kSecReturnData as String: true,
    kSecUseDataProtectionKeychain as String: true,
    kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
] as CFDictionary, &result)
fputs("self-read-without-ui: \(describe(read))\n", stderr)
print("wrote")
