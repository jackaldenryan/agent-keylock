# Platform result

Tested on this Mac before implementation. These are not theories.

## Fingerprint cannot be required on the item itself

A command-line tool can ask for Touch ID. That part works. `keylock` does it before it adds a key, changes a host, or changes how often `run` asks.

macOS will not let this kind of tool make the Keychain item itself demand a fingerprint, or refuse every other program with no dialog.

- The data-protection keychain, which is the one that supports `kSecAccessControlBiometryCurrentSet`, returned `-34018` (a required entitlement is not present) from an ad-hoc signed tool.
- Adding `keychain-access-groups` made the process get killed on launch (exit 137). Those entitlements need a provisioning profile. A free self-signed certificate does not have one.
- A Secure Enclave key failed the same way when the tool tried to store it.

So the item lives in the login keychain. The trusted-app list names only the signed `keylock` binary. That stops a silent read. It does not stop a dialog.

## What the second program actually did

A second program, not signed as `keylock`, asked for a test item whose value was the literal `login-probe-secret`. It did not receive the value immediately. macOS put up an Allow dialog. Approving that dialog lets the other program read the item. Denying it does not.

That dialog is not Touch ID. If an agent can click Allow, because Terminal or the agent app already has Accessibility permission, it can approve the dialog itself. If the button pressed is Always Allow, later reads by that program have no prompt at all.

This is an accepted platform limit. It is not fixed by the proxy. The proxy still stops a program that only has a base URL from seeing the key. It does not stop a program that gets through this Allow dialog.

## What we still require

`keylock` itself calls Touch ID, with no password button and no reuse of a recent unlock, before it adds a key, changes the host list, or changes the auth setting. `run` follows that setting. The default is every time. Canceling a required prompt means the tool does not touch the secret.

The signing key for `keylock` is kept in a separate keychain, not the login keychain. The password for that keychain is on disk so the tool can be rebuilt. An agent that can read that file can sign a trojan. Move that password off the machine before treating the signature as a boundary. See [README.md](README.md).
