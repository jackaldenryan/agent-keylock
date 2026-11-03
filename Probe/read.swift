import Foundation
import Security

let service = "api-key-lock.probe"
let account = "isolation"

func describe(_ status: OSStatus) -> String {
    if let message = SecCopyErrorMessageString(status, nil) as String? {
        return "\(status) \(message)"
    }
    return "\(status)"
}

var result: CFTypeRef?
let status = SecItemCopyMatching([
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
    kSecReturnData as String: true,
    kSecUseDataProtectionKeychain as String: true,
    kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
] as CFDictionary, &result)

if status == errSecSuccess, let data = result as? Data, let text = String(data: data, encoding: .utf8) {
    fputs("LEAKED \(text)\n", stderr)
    exit(3)
}
fputs("read: \(describe(status))\n", stderr)
print("no-secret")
