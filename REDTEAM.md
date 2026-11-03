# Red team of the plan

Platform test, after this review: a second program did not get a silent read. It got an Allow dialog, not a fingerprint prompt. That result is written up in [PLATFORM.md](PLATFORM.md). The Allow dialog is an accepted limit of the login keychain. It is not Touch ID, and a program that can click Allow can pass it.

Reviewed against an agent that runs as you, can run any command, and can edit any file you can edit. It cannot complete Touch ID. It does not have kernel access or SIP turned off. Sudo is not assumed. Findings that need sudo are marked.

Two categories. A is "you touched the sensor, but the dialog lied." B is "no fingerprint, and the key is still copied or sent somewhere you did not approve."

Labels: **sure** means the platform behavior is reliable enough to design around. **test** means the plan must prove it before calling the control real.

## A. Fingerprint deception

This is the family that includes a host that looks like `api.openai.com` and is not. The shared mistake is treating text in a terminal as the approval. The agent controls the terminal. Only the system Touch ID dialog counts, and it has to be the same call that reads the Keychain. On macOS that dialog's reason string is a title, and titles clip. A long explanation will be cut off. Any binary, signed or not, can raise a real Touch ID dialog. That dialog does not by itself release a key. A fake front can show a convincing dialog, then start the real tool with different arguments.

The dialog title must be ASCII, must start with a fixed verb (`RUN`, `ALLOW-HOST`, `REVOKE-HOST`, `ADD`), and must contain the entire operation. If it would clip, refuse. Do not ask the human to read the terminal to understand what they are approving.

### Lookalike hosts

`аpi.openai.com` with a Cyrillic `а`, or `api.оpenai.com` with a Cyrillic `о`, renders as `api.openai.com`. Mixed-script labels and single-character confusables of a vendor host are the same bug. Punycode (`xn--…`) is the same bug if one layer shows Unicode and another connects to the ASCII form, or the reverse.

Do not prompt for these. Reject them.

Host grammar, exact bytes, nothing else:

- ASCII only, matching a single bare hostname: letters, digits, hyphens, dots.
- No uppercase, no trailing dot, no wildcard, no `xn--`, no URL syntax, no userinfo, no path, no port glued onto the host, no percent-encoding, no null, no backslash.
- Length at most 253. Must contain a dot.
- Reject `localhost`, loopback, link-local, private addresses, and `169.254.169.254`.
- Reject any host that Unicode confusables (UTS #39) fold onto a compiled-in vendor host or onto a host already on the list.
- Port is part of the identity. Default 443, and the dialog shows it. A later connect to another port is not a match.
- The bytes in the dialog are the bytes stored and the bytes connected to. No IDNA conversion. No "normalize then compare" that treats a lookalike as equal to an approved host. That second form is not deception. It is a no-fingerprint bypass, because a confusable would ride an approval you already gave.

### Characters that reorder the prompt

Right-to-left override, bidi isolates, zero-width spaces and joiners, BOM, newlines, tabs, and terminal control sequences can display `api.openai.com` while the logical string is a different host, or hide the real command past the clipped title.

Reject those code points in hosts, key ids, and the dialog. Show the command as quoted ASCII tokens. Do not render raw attacker-controlled strings in the dialog.

### The command you see is not the command that runs

The dialog says `python train.py`. Execution then searches `PATH`, follows a symlink, or reads `train.py` again. Between the dialog and exec, the agent replaces a Homebrew Python, a venv, or the script. `/usr/bin/python3` is protected by SIP. Interpreters under Homebrew, `~/.local`, or a project venv are not.

The dialog must show the absolute path, inode, and hash of the executable that will actually run, snapshotted before the prompt. Exec that snapshot, not a name lookup. If the inode or hash changes, abort. If the executable is an interpreter, the dialog must say that the script and its imports are not pinned and are writable by the agent. Disable interpreter startup files, and show those flags in the dialog. Do not invoke a shell.

A shell function or `PATH` entry named `keylock` can run first and then exec the real binary with different arguments. Enrollment and run must be invoked by absolute path. See B2.

### The named program is not the only client

The plan's own test allows a second shell to use the proxy during a run. macOS does not give a TCP listener the pid of the peer. A bearer token in the child's environment is readable by the same user. So approving `sleep 60` lets every local process spend the key until that process exits.

The dialog must say that. Any local process can send requests through this proxy until the direct child exits. The listener must die with that child, including no accept-after-exit window. Do not pretend a token in the environment binds the proxy to the child.

### Catalog text is attacker-controlled

The catalog is writable. A description of "throwaway test key" or an alias `openai` can point at `openai-admin`. A homoglyph id looks like `openai-personal`. Re-reading the catalog after the dialog is a swap.

The dialog shows the Keychain service name that will be read, and nothing from the catalog. No description, no alias, no `maps_to`. Key ids are `[a-z0-9-]`, short, snapshotted before the dialog, and not looked up again after. `maps_to` is not on the security path.

### Fatigue

The agent can raise many dialogs, mixing a `RUN` you expect with an `ALLOW-HOST` you do not. If both look like "keylock wants Touch ID," fatigue is the attack.

One operation per dialog. Verb first. No second host, no wildcard, no catalog prose. A short cooldown. No password button and no Allow button beside the sensor that can release the item or change the list.

### Overlay

A process with Accessibility might cover the system dialog with its own window. Uncertain whether LocalAuthentication windows sit above what an agent can create. Do not depend on overlay resistance. If a test shows the dialog can be covered, write that down as unclosed. It sits next to "you approved a prompt you did not mean to."

## Accepted risk: other programs can use the proxy during a run

This is a real limit, and it is not theft.

While a run you approved is still going, any other program on the machine can send requests through the proxy. It does not need a second fingerprint. A normal local HTTP address cannot be tied to one child when the agent is the same user.

That other program can spend the key at hosts already on the list, and it can send data to those hosts, until the approved run ends. It cannot read the key, print it, save it, or send it to a host that is not on the list. The proxy attaches the key only when forwarding to an approved host.

This is use for the length of that run, not possession of the key. It becomes theft only if an approved host has an endpoint that returns the key or mints a new long-lived credential. Those endpoints stay off the list. The dialog must say that any local process can use the proxy until the direct child exits, so the approval is not narrower than the mechanism.

## B. No fingerprint required

The leftover above is spending an approved key on an already approved host. It is not "the child learns the string" and not "the key goes to a new host." These findings are outside that leftover.

### B1. The two Keychain models were treated as one

Biometric access control belongs to the data-protection keychain. The old "only this signed app may read the item" ACL belongs to the file-based login keychain. They are not one switch. A free self-signed command-line tool is not a documented way to get both at once. Data-protection items use access groups and entitlements. A profile-less CLI may not get a private access group.

Two bad outcomes, both **test** before the design is called real:

- Another binary can ask for the item and, after you touch the sensor for that binary's dialog, receive the secret. The "only one program" claim is false.
- Another binary can read the item with no dialog. That is a direct bypass. Not asserted. Not ruled out.

The likely implementation failure is asserted. If `add` hits `errSecMissingEntitlement` and falls back to the login keychain or to `security add-generic-password`, the item is file-based. A modified caller then gets Allow / Always Allow, not a hard denial. That dialog does not require Touch ID. If Terminal already has Accessibility, a same-user process can press Allow. Always Allow persists. `security dump-keychain` against an unlocked login keychain can then reveal the item with no finger.

Required change: data-protection keychain only. `kSecUseDataProtectionKeychain` on every add, copy, update, and delete. Biometry-current-set, and a protection class of when-passcode-set-this-device-only. If the item does not read back with that exact policy, abort. Never retry with a weaker store. Prove a second binary, `security find-generic-password -w`, and Keychain Access get an error and no dialog. If isolation requires an access group the agent cannot enroll in, a self-signed CLI is not an acceptable trust anchor. Do not describe a designated requirement as the data-protection control.

Also test whether Keychain Access can show the password after Touch ID. If it can, the secret is not bound to `keylock`, and Screen Recording turns that into a copy.

### B2. Enrollment is stolen before the Keychain is involved

Replacing `keylock` breaks Keychain trust. It does not break `add`. You type or paste the secret into whatever program you invoked. That program may be a user-writable file, a `PATH` entry, or a function in `~/.zshrc`. A shell function intercepts the bare name `keylock` and does not intercept an absolute path. The agent can write both `~/.zshrc` and a user-owned install path. Untrusted is enough to record the paste. A trojan can also raise a real Touch ID dialog. The finger is not evidence that the process receiving the secret is the real tool.

If `add` runs in the agent's terminal, the pty master sees keystrokes even when echo is off. Secure event input does not hide keystrokes from the process that spawned the tool. The plan tells you to paste. A clipboard manager database under your home is an ordinary file the agent can read. If Screen Recording is already granted, a provider page that displays the key is enough. None of this needs a fingerprint.

Required change: install the binary root-owned, mode 755, in a directory you cannot write, with parents you cannot write. Enroll only by absolute path, after `/usr/bin/codesign` (SIP-protected, so the agent cannot replace that checker) matches a certificate hash you hold offline. Read the secret from `/dev/tty` only, after secure event input, never from argv, env, or a pipe. Refuse extra arguments so a secret in argv is not ignored while sitting in shell history and `ps`. Do not enroll while an agent is running, and do not enroll in the agent's terminal. Do not copy the secret to the clipboard. There is no software fix for a screen the agent is already recording.

### B3. The agent plants the Keychain item first

Any same-user process can call `SecItemAdd`. If `add` updates on duplicate, your secret is written into an item the agent already created with a weak or missing access control. The next read needs no finger. A query that does not force the data-protection keychain, and does not check the access-control attributes, can also return an agent-created allowlist. The proxy then treats attacker-chosen hosts as approved. No `allow-host` dialog.

Required change: insert only. Fail on duplicate. After every read, require exactly one data-protection item whose access control is the expected biometric policy. If it is weaker, do not use it and do not write a secret into it. The allowlist update is a pure append or remove of the single host from the dialog, not a merge from a file. The first-run seed is compiled in and shown, never merged with `~/.config`.

### B4. Sync, reuse, and a weaker biometric flag

The plan says it will not sync to iCloud and does not set `kSecAttrSynchronizable` to false. A copied sample that sets it true syncs the item off this Mac, outside this biometric rule. The protection class must be when-passcode-set-this-device-only, not a class that is backup-eligible.

Apple's own keychain sample sets a Touch ID reuse duration of about ten seconds so a recent device unlock satisfies a later keychain read. If `run` or `allow-host` copies that, the agent waits for a normal unlock and then loads a key or adds a host with no new finger. Any non-zero reuse duration is a bypass. Confirm the unset default is zero.

`kSecAccessControlUserPresence` allows passcode fallback. There must be no fallback button, no Apple Watch policy, and no "already unlocked is enough." If biometry is missing, `add` fails. One authentication context per operation, invalidated after use. A second copy in the same process, and one after a fresh unlock, must still prompt.

### B5. The allowlist check and the connection are different

These need a key already in the proxy, from a `run` you approved. They do not need another fingerprint.

The agent sets `HTTPS_PROXY` or `ALL_PROXY` before starting the tool. The check sees `api.openai.com`. curl, Python `requests`, and many other clients then connect to the agent's proxy and send `Authorization` there. `~/.curlrc` can do the same if the tool shells out. Changing the macOS system proxy or trusting a new root CA fairly likely needs an admin password, so that path is sudo-only unless a proxy or a MITM CA is already trusted.

`URLSession` follows redirects by default. An open redirect on approved host A to approved host B sends A's key to B. The plan's "refused, or forwarded with no key" is a second branch that can attach the key and then fail to strip it.

Required change: in-process HTTP client only. No subprocess, no curl, no shell. Before any network library initializes, clear `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY`, their lowercase forms, `CURL_HOME`, `SSLKEYLOGFILE`, and `CFNETWORK_DIAGNOSTICS`. Connect directly. Verify that an empty proxy dictionary means no proxy, and that `nil` does not mean "use the system proxy." Test both an env proxy and a configured system proxy.

One parser, then connect to those exact bytes. If the request-target and the `Host` header disagree, refuse. No userinfo, no null, no encoded dot, no IP literal, no client-supplied connect address. Set `Host` to the name you actually connect to. No `CONNECT`, no WebSocket, no pipelined second request. TLS must verify the certificate for that exact hostname, so DNS rebinding does not deliver the key to a listener the agent controls. Do not follow redirects. Never copy `Authorization` onto a new request. Match host and port by exact equality, not suffix or substring. Do not connect off-list at all.

The signed binary must not read routing, extra hosts, or key selection from `~/.config`, the catalog, the environment, or `maps_to`.

### B6. The key comes back to the agent after a normal run

Same-user processes can read another same-user process's arguments and environment through `sysctl` / `ps eww`. No extra permission. If the proxy, or a curl it spawns, has the key in argv or the environment, the agent has the key. Setting `OPENAI_API_KEY` so a library "just works" is that bug.

The agent that spawned the tool can read its stdout and stderr. A verbose flag, a printed error, or `NSLog` of the outgoing request is a copy. `CFNETWORK_DIAGNOSTICS`, if set at startup, makes the network stack write security-sensitive logs. The agent sets the variable.

The proxy adds `Authorization`. The upstream, or the proxy's own error string, echoes it. The child reads the body. `TRACE`, a blind tunnel, or a compressed body bypasses a redactor that only scans plaintext. Ignoring the child's `Authorization` header does not stop the proxy from returning the real one.

A temp file, a predictable shared-memory name, or a file descriptor without close-on-exec is same-user readable. Crash reports in `~/Library/Logs/DiagnosticReports` are user-readable. A key in a register or in an exception string can land there. The agent is the parent, so it can raise the core-dump limit before exec. The child must set that limit to zero itself.

Required change: the secret lives only in locked memory inside the proxy process. Never argv, env, stdout, stderr, logs, a URL query, a file, shared memory, or an exception string. Fixed error strings to the child: "denied" or "upstream failed," with no echo. Decode response bodies, redact the raw key and its URL-encoded and base64 forms, and fail closed if decoding fails. No debug flag. After a failed and a successful forward, `ps eww`, `lsof`, temp directories, `log show`, and DiagnosticReports must not contain the secret.

### B7. Injection into the trusted process

A hardened-runtime process without the debugger entitlement does not give a same-user caller a task port, and `DYLD_INSERT_LIBRARIES` is stripped. The plan requires that and then leaves the exceptions open. A debug build that ships `get-task-allow` lets the same user read the proxy's memory during a run, with no second finger. Disabling library validation, which is the usual way to link a Homebrew curl or OpenSSL, lets the agent replace a library on a user-writable path and read the key inside the trusted process.

Required change: the installed binary's entitlements must show the hardened runtime and must not show `get-task-allow`, disabled library validation, allow-dyld-environment-variables, allow-unsigned-executable-memory, allow-jit, or debugger. No Homebrew dylibs. No `dlopen` of a user-writable path. No unsigned helper. Test `lldb -p`, `sample`, `heap`, and `vmmap` as the same user. If any of them can read the secret, stop. Hardened runtime is not the control the plan thinks it is.

### B8. Signing key left on the machine

Trust is "anything signed by this certificate." If that private key is still in the login keychain, a `p12` in the project, or a keychain the agent can use because the login keychain is already open, the agent signs a trojan that passes the check. The next ordinary fingerprint releases the real secret to the trojan.

Required change: while agents run, `security find-identity -p codesigning` must not list this identity, and the login keychain must not contain the key. No `p12` or keychain file in the project or the home directory. The designated requirement must pin the leaf certificate, not merely the identifier `keylock`. A second binary with the same name and a different certificate must fail the B1 test.

### B9. Only if the agent has sudo

Replace a root-owned `keylock`, edit `/etc/hosts`, or install a trusted root so an approved name connects to a local listener. TLS verification stops the hosts-file case unless a CA is also trusted. Trust-settings changes fairly likely need an admin password. Reading swap or the sleep image is the same class. `mlock` is still worth doing. It is not the boundary against an agent without sudo.

## What has to change before this is buildable

In order of how completely each one closes a real bypass:

1. Pin one Keychain model and prove a second binary cannot read the item. No login-keychain fallback. No Allow dialog. This is the only change that closes a bypass in which the agent gets the secret with no valid trust anchor.
2. Move enrollment off any channel the agent can read. Root-owned absolute path, signature checked with `/usr/bin/codesign` against an offline hash, secret from `/dev/tty`, agent not running. A user-writable `keylock` cannot be repaired by checks inside the trojan.
3. Make the system dialog the entire approval, and give hosts a grammar that cannot lie. Fixed verb, full unclipped tuple, exact host and port, no Unicode, no catalog text, snapshot before the dialog. Reject confusables instead of prompting for them.
4. One in-process client, direct connect, one parser, no redirects, redact responses. This closes "the check said api.openai.com, the key went elsewhere" and "the child read the key back."
5. The secret must not appear in anything the same user can observe, and the hardened runtime must not be opted out of. If `sample` or `vmmap` can read it, stop and redesign.
6. Treat Keychain items as untrusted until their access control is checked. Insert-only add, no file merge, not synchronizable, reuse duration zero, no second use of an authentication context.
7. The dialog must say that any local process can use the proxy until the direct child exits, and the listener must match that sentence. This is an accepted risk of use, not theft. It does not need a further mechanism. The dialog must not describe a narrower set of clients than the proxy actually allows.
8. Keep the signing key off the machine as a checked condition, and pin the leaf certificate. If the key is present, the isolation test fails open for any binary the agent signs.
