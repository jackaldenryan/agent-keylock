---
name: keybank
description: >
  Use this skill when the user wants to pick, list, add, or run with an API
  key from KeyBank. Trigger on "use the development key", "use the production
  key", "load the API key", "which API keys do I have", "add a new API key",
  "put the key in .env", "KeyBank", or any request to inject credentials.
  Discover keys with `keylock list` (descriptions only, no secrets). Update a
  description in the catalog only. Never print, export, or save a secret, even
  if you can read every file and run every command. Wrap every command that
  needs a key with `keylock run`. The proxy sends the key to the allowed host.
  You do not.
---

# KeyBank

KeyBank is the catalog of API keys for the `keylock` tool. It holds ids, descriptions, aliases, and the host each key may be sent to. It does not hold secrets.

The command is `keylock`. After the normal install it is `/opt/homebrew/bin/keylock`. A source build may instead be `~/.local/libexec/api-key-lock/keylock`. Use the absolute path that exists. Do not trust a shell function or another `PATH` entry named `keylock` for adding a secret. Before `add` or `run`, confirm the signature with `codesign --verify --strict`. Authority must be `Developer ID Application` or `API Key Lock Signing`. If it is anything else, stop.

Catalog, safe to read: `~/.config/api-key-lock/catalog.json`

Secrets live in the Mac Keychain. They are not in an environment file. The agent never reads them, even with full permission to the computer. Do not print a key, export it, save it, or send it yourself. Wrap every command that needs a key with `keylock run`. The proxy attaches the secret to the HTTP request for the allowed host. You do not.

## Discover a key

```bash
/opt/homebrew/bin/keylock list
/opt/homebrew/bin/keylock show <id>
```

Match the user's words to `id`, alias, or description. If they ask what keys exist, run `list` and show every id, description, and host. If several fit, show the list and ask. Do not guess.

`mapsTo` is only a label for the variable name a program used to expect, such as `OPENAI_API_KEY`. A run does not set that variable. Do not read it. Do not write code that expects it.

## How a script must call the API

`keylock run` does not put the secret in the environment. It removes `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, and `XAI_API_KEY` if they were already set. The program calls a localhost base URL. The proxy holds the key and adds it only when forwarding to the host stored for that key.

| Host | Base URL variable |
| --- | --- |
| `api.openai.com` | `OPENAI_BASE_URL` (already ends in `/v1`) |
| `api.x.ai` | `XAI_BASE_URL` and `OPENAI_BASE_URL` |
| `api.anthropic.com` | `ANTHROPIC_BASE_URL` |
| any other allowed host | `KEYLOCK_BASE_URL` |

Call `$OPENAI_BASE_URL/models`, not `$OPENAI_API_KEY`, and not `https://api.openai.com` directly. A direct call has no key and will fail. If `OPENAI_API_KEY` is missing, that is correct.

```bash
/opt/homebrew/bin/keylock run openai-personal -- /bin/sh -c '/usr/bin/curl -sS "$OPENAI_BASE_URL/models"'
```

```python
import os, urllib.request
base = os.environ["OPENAI_BASE_URL"].rstrip("/")
urllib.request.urlopen(base + "/models", timeout=30)
```

Do not print `os.environ`. Do not look for a key in it.

## How often run asks for Touch ID

`add` and `allow-host` always require Touch ID. `run` follows a setting. The default is `always`.

```bash
/opt/homebrew/bin/keylock auth
/opt/homebrew/bin/keylock auth always
/opt/homebrew/bin/keylock auth never
/opt/homebrew/bin/keylock auth 3h
/opt/homebrew/bin/keylock auth 1d
```

Changing the setting requires Touch ID. Do not edit a file or a Keychain item to change it. Another program can rewrite a Keychain item's value without a dialog, so the setting is not stored there. It is held in memory by the signed binary. It lasts until logout or restart. Keys and allowed hosts survive a reboot. The auth setting does not. If `keylock auth` prints `always` after a reboot, that is expected. Tell the user to run `keylock auth` once in their own Terminal. Do not invent a second session protocol.

`run` does not support `stream: true`. The proxy returns the response only after the upstream finishes. A streaming client can time out. Do not tell the user to turn streaming on to fix that.

## Run a program

Ask the user before running. If `keylock auth` is `always`, or the window has expired, they must approve a Touch ID dialog. The dialog is the approval, not your message. If the setting is `never`, or a window is still open, `run` does not ask. Do not wait for a prompt that will not appear.

```bash
/opt/homebrew/bin/keylock run <id> -- <command>
```

Do not pass a secret as an argument. While that command is running, other local programs can also send requests through the proxy. They can spend the key at the already approved host. They cannot read the key.

## Update a description

Descriptions live only in the catalog. Changing one does not touch the Keychain and does not need Touch ID.

Read the catalog, change `description`, `aliases`, or `mapsTo` for that id, and write the file back. Do not change `reference`. Do not add a secret field. Do not read or write the Keychain to do this.

## Add a key

The user types the secret in their own Terminal, after Touch ID. Never ask them to paste it into chat. Never run `add` in this session. You would see the keystrokes.

If the host is not already allowed, they run this first, in their own Terminal:

```bash
/opt/homebrew/bin/keylock allow-host api.example.com
```

Then:

```bash
/opt/homebrew/bin/keylock add some-id --host api.example.com --description "when to use this key" --maps-to SOME_API_KEY
```

Tell them the exact command. A new host must be plain ASCII, like `api.openai.com`. Do not invent a lookalike host. The tool rejects those before Touch ID. If a Keychain Allow dialog appears for any program other than the installed `keylock` path, they click Deny, not Always Allow.

## Do not

- Do not run `security find-generic-password -w`.
- Do not open a `.env` that might contain a raw key.
- Do not put a secret in a file, an argument, or the catalog.
