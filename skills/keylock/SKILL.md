---
name: keylock
description: >
  Use this skill anytime a program needs an API key. Trigger when the user
  asks to call an API, list models, run a script, or use a named key such as
  the development key, the production key, or a personal OpenAI key. Also
  trigger on "API key", "keylock", "KeyBank", "put the key in .env", or any
  request to inject credentials.
---

# Agent Keylock

Use this skill whenever a program needs an API key. List the keys, match the user's words to one description, and run the program with `keylock run`. The old name was KeyBank. There is no separate KeyBank tool.

The command is `/opt/homebrew/bin/keylock` after the normal install. A source build may instead be `~/.local/libexec/api-key-lock/keylock`. Use the absolute path that exists. Before `add` or `run`, confirm the signature with `codesign --verify --strict`. Authority must be `Developer ID Application` or `API Key Lock Signing`. If it is anything else, stop.

## List keys

```bash
/opt/homebrew/bin/keylock list
/opt/homebrew/bin/keylock show <id>
```

`list` and `show` print ids, descriptions, and hosts. They do not print secrets. Match the user's words to `id`, alias, or description. If they ask what keys exist, show every id, description, and host. If several fit, show the list and ask. Do not guess.

Catalog, safe to read: `~/.config/api-key-lock/catalog.json`

`mapsTo` is only a label for a variable name a program used to expect, such as `OPENAI_API_KEY`. A run does not set that variable. Do not read it. Do not write code that expects it.

## Run a program

If `keylock auth` is `always`, or the window has expired, `run` shows a Touch ID dialog. If the setting is `never`, or a window is still open, `run` does not show a dialog. Do not wait for a prompt that will not appear.

```bash
/opt/homebrew/bin/keylock run <id> -- <command>
```

Call the base URL `keylock run` provides. A direct call to the public API host has no key and fails. If `OPENAI_API_KEY` is missing, that is correct.

| Host | Base URL variable |
| --- | --- |
| `api.openai.com` | `OPENAI_BASE_URL` (already ends in `/v1`) |
| `api.x.ai` | `XAI_BASE_URL` and `OPENAI_BASE_URL` |
| `api.anthropic.com` | `ANTHROPIC_BASE_URL` |
| any other allowed host | `KEYLOCK_BASE_URL` |

```bash
/opt/homebrew/bin/keylock run openai-personal -- /bin/sh -c '/usr/bin/curl -sS "$OPENAI_BASE_URL/models"'
```

```python
import os, urllib.request
base = os.environ["OPENAI_BASE_URL"].rstrip("/")
urllib.request.urlopen(base + "/models", timeout=30)
```

`stream: true` is not supported. A streaming client can time out. Do not tell the user to turn streaming on to fix that.

## How often run asks for Touch ID

`add` and `allow-host` always require Touch ID. `run` follows a setting. The default is `always`.

```bash
/opt/homebrew/bin/keylock auth
/opt/homebrew/bin/keylock auth always
/opt/homebrew/bin/keylock auth never
/opt/homebrew/bin/keylock auth 3h
/opt/homebrew/bin/keylock auth 1d
```

Changing the setting requires Touch ID. Do not edit a file or a Keychain item to change it. The setting lasts until logout or restart. Keys and allowed hosts survive a reboot. The auth setting does not. If `keylock auth` prints `always` after a reboot, that is expected. Tell the user to run `keylock auth` once in their own Terminal.

## Update a description

Descriptions live only in the catalog. Changing one does not touch the Keychain and does not need Touch ID.

Read the catalog, change `description`, `aliases`, or `mapsTo` for that id, and write the file back. Do not change `reference`. Do not add a secret field. Do not read or write the Keychain to do this.

## Add a key

The user types the secret in their own Terminal, after Touch ID. Never ask them to paste it into chat. Never run `add` in this session.

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

- Do not print, export, or save a secret.
- Do not pass a secret as an argument.
- Do not create an environment file for a secret.
- Do not open a `.env` that might contain a raw key.
- Do not run `security find-generic-password -w`.
- Do not put a secret in a file, an argument, or the catalog.
