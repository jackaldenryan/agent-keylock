import Foundation
import LocalAuthentication
import Security

let tag = "api-key-lock.se-probe".data(using: .utf8)!

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
    kSecClass as String: kSecClassKey,
    kSecAttrApplicationTag as String: tag,
    kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
    kSecReturnRef as String: true,
    kSecUseAuthenticationContext as String: context,
] as CFDictionary, &result)
fputs("other-binary-read: \(describe(status))\n", stderr)
if status == errSecSuccess {
    fputs("FOUND KEY REF\n", stderr)
    exit(3)
}
print("no-key")
