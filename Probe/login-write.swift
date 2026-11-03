import Foundation
import Security

let service = "api-key-lock.login-probe"
let account = "isolation"
let secret = "login-probe-secret".data(using: .utf8)!

func describe(_ status: OSStatus) -> String {
    if let message = SecCopyErrorMessageString(status, nil) as String? {
        return "\(status) \(message)"
    }
    return "\(status)"
}

var trusted: SecTrustedApplication?
guard SecTrustedApplicationCreateFromPath(nil, &trusted) == errSecSuccess, let trusted else {
    fputs("trusted app failed\n", stderr)
    exit(1)
}

var access: SecAccess?
guard SecAccessCreate("api-key-lock probe" as CFString, [trusted] as CFArray, &access) == errSecSuccess, let access else {
    fputs("access create failed\n", stderr)
    exit(1)
}

var aclList: CFArray?
let copied = SecAccessCopyACLList(access, &aclList)
fputs("acl-copy: \(describe(copied)) count=\((aclList as? [SecACL])?.count ?? -1)\n", stderr)

if let acls = aclList as? [SecACL] {
    for acl in acls {
        var apps: CFArray?
        var desc: CFString?
        var prompt = SecKeychainPromptSelector()
        let got = SecACLCopyContents(acl, &apps, &desc, &prompt)
        let appCount = (apps as? [Any])?.count ?? -1
        fputs("acl status=\(describe(got)) apps=\(appCount) desc=\(desc as String? ?? "-") prompt=\(prompt.rawValue)\n", stderr)
        if appCount == 0 {
            let removed = SecACLRemove(acl)
            fputs("removed-prompt-acl: \(describe(removed))\n", stderr)
        }
    }
}

_ = SecItemDelete([
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
] as CFDictionary)

let status = SecItemAdd([
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
    kSecAttrAccount as String: account,
    kSecValueData as String: secret,
    kSecAttrAccess as String: access,
    kSecAttrSynchronizable as String: false,
] as CFDictionary, nil)
fputs("add: \(describe(status))\n", stderr)
if status != errSecSuccess { exit(2) }
print("wrote-login")
