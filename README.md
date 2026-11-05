# Agent Keylock

You describe each API key once. The agent reads those descriptions, selects the key you name, and calls the API. You do not create an environment file. The agent cannot read the secret.

A local proxy attaches the secret only to an HTTP request for the host you allowed. A request to another host, such as evil.com, goes out without the key.

`keylock` is a Mac command and an agent skill.

## What keylock does

Each row is something the tool does.

| Capability | Included |
| --- | :---: |
| You describe each key once. The agent sees those descriptions, picks the one you name, and never sees the secret | ✅ |
| You do not create or maintain an environment file | ✅ |
| The installed skill tells the agent which command to run | ✅ |
| The secret is stored in the encrypted macOS Keychain | ✅ |
| Malware that searches the disk for environment files and pasted API keys does not find the secret | ✅ |
| A prompt-injected agent that reads files, the environment, or the catalog does not find the secret | ✅ |
| A prompt-injected agent cannot print the key, save it, or attach it to a request | ✅ |
| A prompt-injected agent cannot send the key to a host you did not allow, including one it was told to use | ✅ |
| The only use of a key is an HTTP request to the one host you already allowed | ✅ |
| Touch ID can be required for every use of a key. That is the default | ✅ |
| You approve Touch ID every time you add a key or allow a host | ✅ |
| The release is signed with a Developer ID certificate and notarized by Apple | ✅ |

## Quickstart

The install has three steps: install the command, add one key, and ask your agent to use it.

1. Install `keylock` and the agent skill.

```bash
brew install --cask jackaldenryan/tap/agent-keylock
```

2. Add a key in your own Terminal. Touch ID is the approval. Cancel if the host in the dialog differs from the host you typed.

```bash
keylock allow-host api.openai.com
keylock add openai-personal \
  --host api.openai.com \
  --description "Personal default key for OpenAI" \
  --maps-to OPENAI_API_KEY
```

Type the secret when asked. The terminal does not echo it. Keep the secret out of chat.

3. Ask your agent:

```text
List the available OpenAI models using my OpenAI API key.
```

The reply is a model list. The key is absent from that reply.

## How often Touch ID asks

`keylock run` is the command that uses a stored key. It asks for Touch ID every time unless you change that setting. `keylock add` and `keylock allow-host` always ask.

```bash
keylock auth
keylock auth always
keylock auth never
keylock auth 3h
keylock auth 1d
```

`30m` means 30 minutes. `1h` means one hour. `3h` means three hours. `1d` means one day. The same pattern works for other lengths, up to 30 days. You approve Touch ID before this setting changes. After that approval, `keylock run` skips Touch ID until the window ends. The next run asks again, and a successful approval starts another window of the same length.

The setting ends when you log out, restart, or the helper process exits. The helper is a small process that remembers the setting in memory. Your keys and allowed hosts remain after a reboot. Run `keylock auth` once in your own Terminal and approve Touch ID.

If you set `keylock auth` to `never`, or to a window such as `3h`, an agent can spend the key at an approved host while you are away. A spending cap at the provider limits that spend.

## API calls from a program

`keylock run` leaves the secret out of the environment. The program calls the localhost base URL that this command sets. A request straight to `https://api.openai.com` has no key and fails.

| Host | Base URL variable |
| --- | --- |
| `api.openai.com` | `OPENAI_BASE_URL` (already ends in `/v1`) |
| `api.x.ai` | `XAI_BASE_URL` and `OPENAI_BASE_URL` |
| `api.anthropic.com` | `ANTHROPIC_BASE_URL` (`keylock` sends `x-api-key`) |
| any other allowed host | `KEYLOCK_BASE_URL` |

```bash
/opt/homebrew/bin/keylock run openai-personal -- <command>
```

```python
import os, urllib.request
base = os.environ["OPENAI_BASE_URL"].rstrip("/")
urllib.request.urlopen(base + "/models", timeout=30)
```

`keylock list` and `keylock show` print ids, descriptions, and hosts. They omit secrets. `keylock` rejects a lookalike host, a URL, or punycode before it shows a dialog. Punycode is an international domain written with ASCII, such as `xn--`. `stream: true` is not supported. A streaming client can time out.

## Signature and limits

The public binary is signed with a Developer ID certificate and notarized by Apple. Notarization means Apple checked the signature and scanned the file. Apple did not review or endorse the program.

The secret is stored in the macOS login Keychain. macOS encrypts Keychain items. The catalog at `~/.config/api-key-lock/catalog.json` has names, descriptions, and hosts. `keylock run`, the command that uses a stored key, does not write the secret to disk.

The setting for how often `keylock run` asks for Touch ID stays in the memory of a helper process. `keylock run` accepts that helper only when the helper is this signed binary. Another program can rewrite a file or a Keychain item. If the helper is missing, `keylock run` asks every time.

A Keychain Allow dialog can still appear for another program. That dialog is separate from Touch ID. If macOS shows it for a program other than `keylock`, click Deny. Always Allow lets that program read the item later with no prompt. A cancelled Touch ID prompt stops `keylock` before it touches the secret.

While `keylock run` is in progress, another local program can send requests through the localhost proxy that the command started. That program can spend the key at the approved host. It cannot read the key. The proxy exits when the command exits. The proxy skips redirects and ignores `HTTPS_PROXY`. If a response contains the key, the proxy withholds that body.

A copy you build and sign yourself cannot make the Keychain item require Touch ID. Details are in [PLATFORM.md](PLATFORM.md). The design notes and the red team are in [PLAN.md](PLAN.md) and [REDTEAM.md](REDTEAM.md).

## Development

```bash
swift test
```

`brew install` copies the agent skill. A build from this repository does not. After `./scripts/sign-and-install.sh`, run `keylock install-skill`.

`./scripts/sign-and-install.sh` signs that local copy with a certificate created on this Mac. The public release uses a Developer ID certificate and is published by `./scripts/release-macos.sh`. Run the release script in a Terminal you control. After a local rebuild, move the signing files off the Mac. They are under `~/Library/Application Support/APIKeyLock/signing` and `~/Library/Keychains/api-key-lock-signing-db`. An agent that can read those files can sign a fake `keylock`.

The code-signing identifier is `com.apikeylock.keylock`.

## License

[MIT](LICENSE)
