# API Key Lock

Mac-only plan. Implementation is in this folder. Read [README.md](README.md) and [PLATFORM.md](PLATFORM.md) before trusting it. Several sentences below describe the original plan, not the shipped tool. The shipped differences are: `run` follows `keylock auth` instead of asking every time, that setting lives in a signed helper process rather than a Keychain item, secrets live in the login keychain, and another program can still raise an Allow dialog.

Do not build from this document alone. A red team of the plan is in [REDTEAM.md](REDTEAM.md). Several findings are bypasses that do not need a fingerprint. The sentence below that says there is no second software bypass is the claim that review broke. A free self-signed command-line tool cannot make the Keychain item itself require a fingerprint. Another program can still raise an Allow dialog.

This project protects API keys from an agent that already has the run of the machine. OpenCode policies, Codex rules, file permissions, and instructions to the model are not the lock. Those can be ignored, edited, or bypassed by a process running as you. The lock is the Mac Keychain plus a signed program the agent cannot usefully modify.

## Outcomes

An agent may run any terminal command, write any program, edit any file, and replace any binary you own. In that setting:

- It cannot read an API key.
- It cannot print a key, write a key to a file, or send a key to a host you did not approve.
- It cannot get a key by editing the tool, renaming a modified copy, or calling the built-in `security` command.
- It cannot add a host that is allowed to receive a key.
- Changing the host list requires your fingerprint. Releasing a key through `run` asks unless you have set `keylock auth` to `never` or an open window. The default is every time. The dialog names the key and the host. It does not name the command.

Accepted risk, and it is not theft: while a run you approved is still going, any other program on the machine can send its own requests through the proxy. It does not need a second fingerprint. That program can spend the key at hosts already on the list, and it can send data to those hosts, until the approved run ends. It cannot read the key, print it, write it to a file, or send it anywhere else. The proxy attaches the key only when forwarding to an approved host. This is use of the key for the length of that run, not possession of the key. It becomes theft only if an approved host has an endpoint that returns the key or mints a new long-lived credential. Those endpoints stay off the list.

The accepted mistake is approving a fingerprint prompt you did not mean to approve. That is not the only hole. [REDTEAM.md](REDTEAM.md) lists ways an agent can still read a key, or send it to an unapproved host, without a fingerprint, if the implementation follows this plan as written.

Out of scope: someone who has your finger, kernel access, or a Mac with SIP turned off. This plan is for a same-user agent on a normal Mac.

## How it works

The agent never receives the key. A signed proxy holds it in memory and attaches it to outgoing requests.

1. You enroll a key yourself. The tool reads the secret from a prompt that does not echo and does not take the secret as an argument. It stores the secret in the Keychain and asks for Touch ID. The catalog records only a name, a description, and a reference such as `keylock://openai-personal`.
2. An agent may read the catalog and write env files full of those references. Nothing on the system resolves a reference into a key except the signed tool, and only when the auth setting allows that run.
3. When you want a program to call an API, you run `keylock run`. If auth is `always`, or the window has expired, the prompt names the key and the host. It does not name the command. The tool loads only that key into the proxy. The program is started with a local base URL and no key in its environment, arguments, or files.
4. The program sends normal API requests to that local address. The proxy adds the real key and forwards the request only to the host stored for that key. Any other destination is refused.
5. When the program exits, the proxy exits and the key is gone from memory. The next use asks again unless an auth window is still open.

The Keychain item does not trust a file name or a path. It trusts the code signature of one program. That signature covers a hash of the program. If the agent edits the program and leaves the name unchanged, the hash changes and the Keychain will not release the key. Re-signing the edited program only works with the original signing key. That key is not kept in the login keychain, and it is not left on this Mac while agents are running.

The host list is not inside the program and not in a file the agent can edit. It is a Keychain item with the same lock. Adding or removing a host runs a separate command. The prompt shows the exact host. Approving it does not modify the program, so the signature stays valid.

## What the agent can and cannot do

Allowed, and useless for stealing a key:

- Read and edit the catalog.
- Write `OPENAI_API_KEY=keylock://openai-personal` into a project env file.
- Start the signed tool. If a fingerprint is required, this shows you a prompt. It does not finish the prompt.
- Replace the tool's binary. The replacement is not trusted.
- Connect to a proxy it did not just get approved. No approved run means no proxy and no key in memory.
- Call the built-in `security` command. That command is not on the item's allow list, and Touch ID will not release the secret to it.

Not allowed, because the mechanism refuses it rather than because the agent was asked nicely:

- Print, copy, or exfiltrate the key string.
- Put the key in an environment variable the agent's program can read.
- Persist the key to disk.
- Change which program may read the key.
- Add `evil.com` to the host list without you approving that host on the sensor.

Still possible after you approve a run: the approved program, and anything that can ride that same run, can make requests to hosts already on the list. That spends the key. It does not reveal it.

## Pieces

One signed program, `keylock`, with a few commands. No separate unsigned helper. A script is not acceptable, because the agent can edit a script.

| Command | Touch ID | Sees secrets | Purpose |
| --- | --- | --- | --- |
| `list`, `show` | no | no | Print catalog descriptions and references. |
| `add` | yes | yes, once, from your typed input | Store a new key. Human runs this. An agent must not be given the secret to pass in. |
| `run` | follows `keylock auth`; default yes | yes, in the proxy only | Start the proxy, then the requested program, with no key in the program. |
| `allow-host`, `revoke-host` | yes | no | Change the host list. The prompt shows the host. |
| none | | | There is no `read`, `print`, `export`, or `env` command. |

The proxy is part of this same binary. It binds only to localhost, holds keys only in memory, loads only the keys named on the approved command, and exits with the child. It does not log headers. It does not follow a redirect onto a host that is not on the list. It ignores any `Authorization` header the child sends, so a child cannot smuggle or echo the real key. It does not listen in a way that survives the child and lets a later process reuse the approval.

Official client libraries are pointed at the local proxy with a base URL, for example `OPENAI_BASE_URL`. A program that ignores that and calls the vendor directly fails, because it does not have the key.

## Where things live

Source, in this repository:

```
PLAN.md          this document
Sources/         Swift package for the signed tool
Tests/           adversarial checks run as the normal user
```

Installed and runtime locations:

| What | Where | Agent may read or edit? |
| --- | --- | --- |
| Signed `keylock` binary | `~/.local/libexec/api-key-lock/keylock` | May replace the file. Replacement is not trusted. |
| Catalog | `~/.config/api-key-lock/catalog.json` | Yes. Descriptions and `keylock://` references only. |
| API key items | Login keychain, service `api-key-lock.secret.<id>` | Not a silent read. Another program can still raise an Allow dialog. |
| Host list | Login keychain, service `api-key-lock.allowlist` | Same limit. `run` sends the key only to the host stored with the secret. |
| Signing certificate private key | Not in the login keychain. Offline, or a locked keychain that is not mounted while agents run. | No. |
| Project env files | Inside the project, written by an agent or by you | Yes. They hold references, never values. |

The binary may live in a user-writable path. Trust is the signature, not the directory. `~/.local/libexec` is only so the installed copy is not sitting in a project an agent is already editing.

Catalog record, and nothing more:

```json
{
  "id": "openai-personal",
  "description": "Personal default key for OpenAI",
  "aliases": ["openai"],
  "mapsTo": "OPENAI_API_KEY",
  "reference": "keylock://openai-personal"
}
```

`mapsTo` tells a program which variable name it would have used. The run does not set that variable to the secret. It sets the base URL the library should use instead.

## Keychain lock

This section is the rejected plan. The shipped tool cannot use the Data Protection keychain. See [PLATFORM.md](PLATFORM.md).

Each secret is created with `SecItemAdd` in the login keychain, not with `security add-generic-password`. The trusted-app list names this binary. That stops a silent read. It does not stop an Allow dialog, and that dialog is not Touch ID.

The original plan asked for both of these. Neither is what shipped:

- Access control requires Touch ID for the current set of fingerprints (`kSecAccessControlBiometryCurrentSet`).
- The only trusted program is `keylock`, identified by the designated requirement of its signing certificate, with no Allow dialog for anyone else.

`/usr/bin/security`, Terminal, Python, and Keychain Access are not on the trusted-app list. `security find-generic-password -w` must not print the key. It can still raise an Allow dialog. Click Deny. Being logged in, with the login keychain already unlocked, is not sufficient for a silent read.

The signing certificate is a free self-signed code-signing identity. A paid Apple developer account is not required. An ad-hoc signature is not enough: macOS does not keep a stable biometric rule for a binary with no signing identity.

The binary is signed with the hardened runtime and without the debugger entitlement. That is what stops a same-user process from attaching and reading the key out of the proxy. This is a platform assumption the tests must check, not a hope.

When you rebuild the tool, you sign it with the same certificate, then put the signing key away again. Because trust is the certificate and not a hash of one build, an updated binary still works. Because the agent does not have that certificate's private key, it cannot produce an updated binary the Keychain will accept.

## Run, in order

1. You, or an agent, invokes `keylock run openai-personal -- python train.py`.
2. If auth requires it, the tool shows a prompt: the key id and the host. It does not show the command. You use Touch ID, or you cancel.
3. The tool reads that one key and the host list from the Keychain into the proxy.
4. The tool starts `python train.py` with `OPENAI_BASE_URL` set to the proxy. It does not set `OPENAI_API_KEY`. It does not pass the secret on the command line. Command lines are visible to other processes.
5. `train.py` calls the local base URL. The proxy checks the host, adds the key, and forwards.
6. The child exits. The proxy exits. The key is not written to swap, a temp file, or a log.

If step 2 is cancelled, nothing in steps 3 through 6 happens.

## Host list

Seed the first build with the hosts you already know you want, compiled in as the initial list and also stored in the Keychain on first run so later additions have somewhere to live. Expected first entries are the vendor API hosts you name before implementation, such as `api.openai.com`. Nothing is added because an agent asked for it.

`keylock allow-host api.example.com` requires Touch ID and shows `api.example.com`. That is the only update path. A JSON file of hosts, an env var, or a flag on `run` must not be able to widen the list.

Every host on the list is a place the key may be sent. An intermediary you run can be added the same way. A host that logs request headers will see the key. Do not add those. Redirects to a host that is not on the list are refused.

## Enrollment

You add keys. The agent does not.

1. Create the key at the provider.
2. Run `keylock add openai-personal` yourself.
3. Paste the secret into the tool's hidden prompt. Do not put it in chat, in an argument, or in a file for the agent to read.
4. Approve Touch ID.
5. Delete any older plaintext copy yourself, including project `.env` files and editor local history. The agent is not used for that step, because reading the old file would put the secret in the agent's context.

Older plaintext copies elsewhere are a migration task for you, outside this tool. This project does not read them.

## Implementation order

Do not start until this plan is accepted. Build in this order so each step has a failed attack to show.

1. Create the signing identity. Confirm the private key can be removed from the login keychain after signing.
2. Store one test secret with the two locks. Show that `security`, Python, and a copied binary cannot read it, and that the real binary can, only after Touch ID.
3. Add the catalog commands. They must have no code path that calls `SecItemCopyMatching` for a secret.
4. Add the proxy and `run`. Show that the child environment and the child's open files do not contain the key, and that a second process cannot keep using the proxy after the child exits.
5. Add `allow-host` and `revoke-host`. Show that editing any file under the project or under `~/.config/api-key-lock` does not change the list.
6. Point one real client library at the local base URL and complete one real call after a fingerprint.
7. Write the human enrollment notes in this folder. Still no agent-mediated paste.

Adversarial checks, all run as the normal user, with no OpenCode policy required:

- `security find-generic-password -w` on a stored key.
- Replace `keylock` with a modified copy at the same path and ask the Keychain for the key.
- Edit the catalog so a reference points at a different id, and confirm `run` still shows the id it will actually load.
- Run a child that prints its environment and writes a file. Confirm the key is absent.
- From a second shell, connect to the proxy port during a run and after the run. During a run, use of an already approved host may succeed. Reading the key must not. After the run, both must fail.
- Ask the proxy to follow a redirect off the allowlist.
- Rebuild without the signing key present and confirm the new binary is not trusted.

## What this project will not do

- It will not wrap or depend on the 1Password CLI. Uninstalling `op` remains a separate choice. This lock does not require it.
- It will not sync keys to iCloud or any other account.
- It will not try to stop an approved program from calling an approved host.
- It will not treat stdout masking as a control. The child never has the string, so there is nothing to mask.
- It will not store a recovery copy of the keys unless you later ask for an offline encrypted backup. Until then, the keys exist only in this Mac's Keychain. A wiped Mac or a fingerprint reset loses them. That is acceptable until an export command is designed with the same locks.
