# Agent Keylock

You describe each API key once. The agent reads those descriptions, selects the key you name, and calls the API. You do not create an environment file. The agent cannot read the secret.

A local proxy attaches the secret to an HTTP request for the one host you allowed. A printed environment, a saved file, or a request to another host such as evil.com contains no key, because the agent never receives the secret.

`keylock` is a Mac command and an agent skill. It runs on macOS.

## What it does

| | |
| --- | :---: |
| You describe each key once. The agent sees those descriptions, picks the one you name, and never sees the secret | ✅ |
| You do not create or maintain an environment file | ✅ |
| The installed skill tells the agent how to run, so the agent does not ask you to paste a key into chat | ✅ |
| The secret is stored in the encrypted macOS Keychain | ✅ |
| Malware that searches the disk for environment files and pasted API keys does not find the secret | ✅ |
| A prompt-injected agent that reads files, the environment, or the catalog does not find the secret | ✅ |
| A prompt-injected agent cannot print the key, save it, or attach it to a request | ✅ |
| A prompt-injected agent cannot send the key to a host you did not allow, including one it was told to use | ✅ |
| The only use of a key is an HTTP request to the one host you already allowed | ✅ |
| Touch ID can be required for every use of a key. That is the default | ✅ |
| Adding a key or allowing a host always requires Touch ID | ✅ |
| The release is signed with a Developer ID certificate and notarized by Apple | ✅ |

## Agent access

A coding agent with full permission can read your files, run your commands, and write programs. The key is absent from those files, from that command, and from a program the agent writes.

The agent can cause an approved key to be sent to one approved host. The agent has no copy it can print, export, write to a file, place in an environment variable, or send to any other host.

## Key storage

The secret is stored in the macOS login Keychain. macOS encrypts Keychain items. `keylock run` leaves the secret out of the command and does not write it to disk.

The agent can read `~/.config/api-key-lock/catalog.json`. That file has names, descriptions, and hosts.

Adding a key, allowing a host, and changing how often `run` asks all require Touch ID.

## Command wrapper

The skill tells the agent to wrap every command that needs a key:

```bash
/opt/homebrew/bin/keylock run openai-personal -- <command>
```

The wrapper removes `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, and `XAI_API_KEY` if they were set. It starts a proxy on `127.0.0.1` and points the command at that proxy. The proxy adds the key to the outbound HTTP request for the host stored with that key. The proxy exits when the command exits.

A request straight to `https://api.openai.com` has no key. An empty `OPENAI_API_KEY` is the expected result. The program receives a localhost address.

A Keychain Allow dialog and a signing key left on the Mac are separate limits. Those limits are described below.

## Quickstart

Homebrew installs `keylock` and the agent skill in one command. The binary is signed with a Developer ID certificate and notarized by Apple. Notarization means Apple checked the signature and scanned the file. Apple did not review or endorse the program.

```bash
brew install --cask jackaldenryan/tap/agent-keylock
```

Add a key once, in your own Terminal. Touch ID is the approval. Cancel if the host in the dialog differs from the host you typed.

```bash
keylock allow-host api.openai.com
keylock add openai-personal \
  --host api.openai.com \
  --description "Personal default key for OpenAI" \
  --maps-to OPENAI_API_KEY
```

Type the secret when asked. The terminal does not echo it. Keep the secret out of chat.

Ask your agent:

```text
List my keys. Use my personal OpenAI key to list the available models. Do not print the key, and do not create an environment file.
```

The reply is a model list. The key is absent from that reply, and the agent has no reason to ask you to paste one.

## Program calls

`keylock run` leaves the secret out of the environment. It removes `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, and `XAI_API_KEY` if they were set. The program calls a localhost base URL. The proxy adds the key.

| Host | Variable the program reads |
| --- | --- |
| `api.openai.com` | `OPENAI_BASE_URL` (already ends in `/v1`) |
| `api.x.ai` | `XAI_BASE_URL` and `OPENAI_BASE_URL` |
| `api.anthropic.com` | `ANTHROPIC_BASE_URL` (the proxy sends `x-api-key`) |
| any other allowed host | `KEYLOCK_BASE_URL` |

```python
import os, urllib.request
base = os.environ["OPENAI_BASE_URL"].rstrip("/")
urllib.request.urlopen(base + "/models", timeout=30)
```

A request straight to `https://api.openai.com` has no key and fails.

## Command behavior

- `list` and `show` print ids, descriptions, and hosts. They skip Touch ID and omit secrets.
- `allow-host` and `add` ask for Touch ID on every call.
- `run` follows the auth setting. The default is every time.
- A lookalike host, a URL, or punycode is rejected before any dialog.
- If macOS shows a Keychain Allow dialog for a program other than `keylock`, click Deny. Clicking Always Allow lets that program read the item later with no prompt.

## Auth setting

```bash
keylock auth
keylock auth always
keylock auth never
keylock auth 3h
keylock auth 1d
```

`30m` and `1h` work the same way. Changing this setting requires Touch ID. The value is held in memory by a helper that `run` accepts only when that helper is this signed binary. A file or a Keychain item can be rewritten by another program, so the setting is stored in neither place. If the helper is missing, `run` asks every time.

The setting lasts until you log out, restart, or the helper exits. It ends at reboot. After a reboot, the keys and allowed hosts remain. Run `keylock auth` once, in your own Terminal, and approve Touch ID. A signing key is unnecessary for that step. With the default left unchanged, a reboot leaves `run` asking every time.

`never` and a long window let an agent spend the key at an approved host while you are away. A spending cap at the provider limits that spend. The proxy withholds the key from the agent and from any host outside the allowlist.

## Request path

1. You approve a hostname. The proxy sends the key only to names on that list.
2. You add a secret. The secret goes into the login Keychain, trusted to the signed `keylock` binary.
3. An agent reads the catalog at `~/.config/api-key-lock/catalog.json`. That file has names and descriptions.
4. `keylock run` starts a proxy on `127.0.0.1` and points the program at it.
5. The proxy adds the key and forwards to the host stored for that key. The proxy skips redirects and ignores `HTTPS_PROXY`. If a response contains the key, the proxy withholds that body.

While a run is in progress, another local program can send requests through that proxy. The other program can spend the key. The other program cannot read the key. The proxy exits when the command exits.

## Limits

A Keychain Allow dialog can still appear for another program.

A self-signed command-line tool cannot make the Keychain item itself require Touch ID, and it cannot make every other program fail with no dialog. The Allow dialog is a password prompt, separate from Touch ID. A program that can click Allow can pass that dialog. Details are in [PLATFORM.md](PLATFORM.md).

Touch ID inside `keylock` remains in force for adding a key, allowing a host, and changing the auth setting. A cancelled prompt stops the tool before it touches the secret.

The design notes and the red team are in [PLAN.md](PLAN.md) and [REDTEAM.md](REDTEAM.md).

## Development

```bash
swift test
```

A Homebrew install copies the agent skill. A source build leaves that step to you: run `keylock install-skill` after `./scripts/sign-and-install.sh`.

`./scripts/sign-and-install.sh` builds a local copy and signs it with a certificate created on this Mac. The public release uses a different certificate. After a local rebuild, move the signing key off the Mac. The local signing files are under `~/Library/Application Support/APIKeyLock/signing` and `~/Library/Keychains/api-key-lock-signing-db`. An agent that can read those files can sign a fake `keylock`.

The public release is signed with a Developer ID certificate and published by `./scripts/release-macos.sh`. Run that script in a Terminal you control.

The code-signing identifier is `com.apikeylock.keylock`.

## License

[MIT](LICENSE)
