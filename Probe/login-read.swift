import Foundation
import LocalAuthentication
import Security

let service = "api-key-lock.login-probe"
let account = "isolation"

func describe(_ status: OSStatus) -> String {
    if let message = SecCopyErrorMessageString(status, nil) as String? {
        return "\(status) \(message)"
    }
    return "\(status)"
}

let context = LAContext()
context.interactionNotAllowed = true
var result: CFTypeRef?
let status = SecItemCopyMatching([
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
    kSecReturnData as String: true,
    kSecUseAuthenticationContext as String: context,
] as CFDictionary, &result)
if status == errSecSuccess, let data = result as? Data {
    fputs("LEAKED \(data.count) bytes\n", stderr)
    exit(3)
}
fputs("other-binary: \(describe(status))\n", stderr)
print("no-secret")
