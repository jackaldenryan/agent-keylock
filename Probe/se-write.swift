import Foundation
import Security

let tag = "api-key-lock.se-probe".data(using: .utf8)!

func describe(_ status: OSStatus) -> String {
    if let message = SecCopyErrorMessageString(status, nil) as String? {
        return "\(status) \(message)"
    }
    return "\(status)"
}

var error: Unmanaged<CFError>?
guard let access = SecAccessControlCreateWithFlags(
    nil,
    kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
    [.privateKeyUsage, .biometryCurrentSet],
    &error
) else {
    fputs("access: \(String(describing: error?.takeRetainedValue()))\n", stderr)
    exit(1)
}

let attributes: [String: Any] = [
    kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
    kSecAttrKeySizeInBits as String: 256,
    kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
    kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: tag,
        kSecAttrAccessControl as String: access as Any,
    ] as [String: Any],
]

let deleted = SecItemDelete([
    kSecClass as String: kSecClassKey,
    kSecAttrApplicationTag as String: tag,
    kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
] as CFDictionary)
fputs("delete-before: \(describe(deleted))\n", stderr)

guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
    fputs("create: \(String(describing: error?.takeRetainedValue()))\n", stderr)
    exit(2)
}
fputs("created SE key\n", stderr)
_ = privateKey
print("wrote-se")
