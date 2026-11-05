# Agent Keylock

Describe each API key once. Your agent sees those descriptions, picks the one you name, and uses it. You never create an environment file. The agent cannot read the secret.

That is the point of Agent Keylock. You stop keeping keys in files and pasting them into chat. The agent chooses from the descriptions you wrote. A local proxy attaches the secret, and only to an HTTP request for the one host you allowed. The key cannot be printed. It cannot be saved. It cannot be sent anywhere else, including a host an agent was told to use, such as evil.com. The agent never receives the secret, so it has nothing to copy.

Agent Keylock is a Mac command-line tool and an agent skill, shipped together. The command is `keylock`. It is macOS only.

## What it does

| | |
| --- | :---: |
| You describe each key once. The agent sees those descriptions, picks the one you name, and never sees the secret | ✅ |
| You do not create or maintain an environment file | ✅ |
| The installed skill tells the agent how to run, so it does not ask you to paste a key into chat | ✅ |
| Stores each key in the encrypted macOS Keychain, not in a file | ✅ |
| Malware that searches the disk for environment files and pasted API keys does not find the secret | ✅ |
| A prompt-injected agent that reads files, the environment, or the catalog does not find the secret | ✅ |
| A prompt-injected agent cannot print the key, save it, or attach it to a request | ✅ |
| A prompt-injected agent cannot send the key to a host you did not allow, including one it was told to use | ✅ |
| The only use of a key is an HTTP request to the one host you already allowed | ✅ |
| Touch ID can be required for every use of a key. That is the default | ✅ |
| Adding a key or allowing a host always requires Touch ID | ✅ |
| The release is signed with a Developer ID certificate and notarized by Apple | ✅ |

## What an agent can and cannot do

A coding agent with full permission can read your files, run your commands, and write programs. That is the case this tool is built for. Full permission does not put the key in those files, in that command, or in a program the agent writes.

The agent may cause an approved key to be spent at one approved host. It may not:

- print the key
- export it
- write it to a file, a log, or a chat
- put it in an environment variable
- send it to any host other than the one you allowed

Those are not rules the agent is trusted to obey. The key is never handed over, so there is nothing for the agent to copy.

## Where the key is stored

The secret is stored in the macOS login Keychain. macOS encrypts Keychain items. It is not stored in an environment file, a `.env` file, the catalog, or the command the agent runs. `keylock run` does not write the secret to disk.

The file the agent may read, `~/.config/api-key-lock/catalog.json`, has names, descriptions, and hosts. It does not have secrets.

Adding a key, allowing a host, and changing how often `run` asks all require Touch ID.

## How the agent is told to run a command

The skill tells the agent to wrap every command that needs a key:

```bash
/opt/homebrew/bin/keylock run openai-personal -- <command>
```

That wrapper does not save the secret, and it does not inject the secret into the command. It removes `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, and `XAI_API_KEY` if they were set. It starts a proxy on `127.0.0.1` and points the command at that proxy. The proxy adds the key to the outbound HTTP request, and only for the host stored for that key. When the command exits, the proxy exits.

A request straight to `https://api.openai.com` has no key. If `OPENAI_API_KEY` is empty, that is correct. The program got a localhost address. It did not get the key.

This is the design. It is not a claim that a Keychain Allow dialog can be ignored, or that a signing key left on the Mac is safe. Those limits are below.

## Quickstart

Requires Homebrew. This installs a binary signed with a Developer ID certificate and notarized by Apple, plus the agent skill. You do not clone the repository, and you do not create a signing certificate. Notarization means Apple checked the signature and scanned the file. It does not mean Apple reviewed or endorsed the program.

```bash
brew install --cask jackaldenryan/tap/agent-keylock
```

The command is `keylock`. Check the signature before you type a secret. Do this in your own Terminal, not in an agent session.

```bash
/usr/bin/codesign --verify --strict --verbose=2 "$(command -v keylock)"
```

`Authority` should be `Developer ID Application`.

Allow a host, then add a key. Each of these asks for Touch ID. The dialog text is the approval. Cancel if the host in the dialog is not the host you typed. The run dialog does not contain the command. It names the key, the host, and that any local process can use the proxy until that command exits.

```bash
keylock allow-host api.openai.com
keylock add openai-personal \
  --host api.openai.com \
  --description "Personal default key for OpenAI" \
  --maps-to OPENAI_API_KEY
```

Type the secret when asked. It is not echoed. Do not pass it as an argument, and do not paste it into a chat.

Confirm a run works:

```bash
keylock run openai-personal -- \
  /bin/sh -c '/usr/bin/curl -sS "$OPENAI_BASE_URL/models"'
```

You should get a model list. `OPENAI_API_KEY` should be empty. The key never appears in the output. A request with a query string is forwarded. `stream: true` is not. The proxy waits for the full response, so a streaming client can time out.

## Install the agent skill

`brew install` already does this. If you built from source, run:

```bash
keylock install-skill
```

That copies the skill to `~/.agents/skills/keybank`, which OpenCode, Claude, Cursor, and several others read. Without the skill, an agent will look for `OPENAI_API_KEY` and fail, or worse, ask you to paste the secret into chat.

## How a program calls the API

`keylock run` does not put the secret in the environment. It removes `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, and `XAI_API_KEY` if they were set. The program calls a localhost base URL. The proxy adds the real key.

| Host | Variable the program reads |
| --- | --- |
| `api.openai.com` | `OPENAI_BASE_URL` (already ends in `/v1`) |
| `api.x.ai` | `XAI_BASE_URL` and `OPENAI_BASE_URL` |
| `api.anthropic.com` | `ANTHROPIC_BASE_URL` (the proxy sends `x-api-key`, not a bearer token) |
| any other allowed host | `KEYLOCK_BASE_URL` |

```python
import os, urllib.request
base = os.environ["OPENAI_BASE_URL"].rstrip("/")
urllib.request.urlopen(base + "/models", timeout=30)
```

A request straight to `https://api.openai.com` has no key and will fail. That is the point.

## What to expect

- `list` and `show` print ids, descriptions, and hosts. No fingerprint, no secrets.
- `allow-host` and `add` always ask for Touch ID.
- `run` asks according to the auth setting. The default is every time.
- A lookalike host, a URL, or punycode is rejected before any dialog.
- If macOS shows a Keychain Allow dialog for a program that is not `keylock`, click Deny. Do not click Always Allow.

## How often run asks

```bash
keylock auth
keylock auth always
keylock auth never
keylock auth 3h
keylock auth 1d
```

`30m` and `1h` work the same way. Changing this setting requires Touch ID. The value is not a file and not a Keychain item. An agent can write both of those. It is held in memory by a helper that `run` accepts only when that helper is this signed binary. If the helper is not running, `run` asks every time.

The setting lasts until you log out, restart, or the helper exits. It does not survive a reboot. That is intentional. A Keychain item can be rewritten by another program without a dialog, so the setting is not stored there.

After a reboot, your keys and allowed hosts are still there. Run `keylock auth` once, in your own Terminal, and approve Touch ID. You do not plug in a signing key to do that. If you leave the default alone, a reboot changes nothing: `run` already asks every time.

`never` and a long window mean an agent can spend the key at an approved host while you are away. Put a spending cap on the key at the provider. The proxy still will not reveal the key or send it to a host you have not allowed.

## How it works

1. You approve a hostname. That list is the only place the key may be sent.
2. You add a secret. It goes into the login Keychain, trusted to the signed `keylock` binary.
3. An agent reads the catalog at `~/.config/api-key-lock/catalog.json`. That file has names and descriptions, not secrets.
4. `keylock run` starts a proxy on `127.0.0.1` and points the program at it.
5. The proxy adds the key and forwards only to the host stored for that key. It does not follow redirects. It does not honor `HTTPS_PROXY`. If a response contains the key, the proxy does not return that body.

While a run is in progress, another local program can also send requests through that proxy. It can spend the key. It cannot read it. The proxy exits when the command exits.

## Limits

This is not a promise that no program on the Mac can ever raise a prompt.

A free self-signed command-line tool cannot make a Keychain item require Touch ID by itself, and it cannot make every other program fail with no dialog. Another program can still raise a Keychain Allow dialog. That dialog is not Touch ID. If something can click Allow for you, it can get past that dialog. Details are in [PLATFORM.md](PLATFORM.md).

Touch ID inside `keylock` is still required for adding a key, allowing a host, and changing the auth setting. A cancelled prompt means the tool does not touch the secret.

The design notes and the red team are in [PLAN.md](PLAN.md) and [REDTEAM.md](REDTEAM.md).

## Development

```bash
swift test
```

`./scripts/sign-and-install.sh` builds a local copy and signs it with a certificate created on this Mac. That certificate is not the public release. After a local rebuild, move the signing key off the Mac again. It is created under `~/Library/Application Support/APIKeyLock/signing` and `~/Library/Keychains/api-key-lock-signing-db`. An agent that can read those files can sign a fake `keylock`.

The public release is signed with a Developer ID certificate and published by `./scripts/release-macos.sh`. Run that only in a Terminal you control.

The code-signing identifier is `com.apikeylock.keylock`.

## License

[MIT](LICENSE)
