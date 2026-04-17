# Integrations

`cmctl` owns the operator setup path for the integrations that currently gate a
usable CoreMatrix installation.

## Scope

The CLI currently manages:

- Codex subscription authorization
- Telegram polling ingress
- Telegram webhook ingress
- Weixin QR-login ingress

The CLI does not manage every product setting. It focuses on the setup path an
operator needs before handing the installation to real users.

## Codex Subscription

Authorize the Codex subscription after `init` has completed and the local
operator session is stored:

```bash
bundle exec exe/cmctl providers codex login
```

The command prints the verification URL and user code, opens the browser when
possible, and polls CoreMatrix until the authorization reaches a terminal
state.

Inspect or revoke the authorization later with:

```bash
bundle exec exe/cmctl providers codex status
bundle exec exe/cmctl providers codex logout
```

## Telegram Polling

Preparation:

- create a bot in BotFather
- copy the bot token
- ensure the recurring scheduler and queue workers are running
- keep polling and webhook on separate Telegram bot tokens

Command:

```bash
bundle exec exe/cmctl ingress telegram setup
```

The command prompts for the bot token, configures the CoreMatrix binding, and
prints the poller binding id.

Verification boundary in v1:

- proves the CoreMatrix API contract and persisted binding state
- does not prove live Telegram delivery

## Telegram Webhook

Preparation:

- create a bot in BotFather
- copy the bot token
- prepare a public HTTPS base URL for the CoreMatrix installation
- keep webhook and polling on separate Telegram bot tokens

Command:

```bash
bundle exec exe/cmctl ingress telegram-webhook setup
```

The command prompts for the bot token and webhook base URL, then prints the
resolved webhook URL plus the secret token material that must be registered
with Telegram.

Verification boundary in v1:

- proves webhook contract generation and secret material output
- does not prove live Telegram webhook callbacks

## Weixin

Preparation:

- ensure the operator is logged in
- ensure a workspace and workspace agent are selected
- use a terminal that can render ANSI QR output when possible

Command:

```bash
bundle exec exe/cmctl ingress weixin setup
```

The command creates or reuses the binding, starts login when needed, polls the
status API, renders ANSI QR output from `qr_text` when available, and falls
back to printing `qr_code_url` when terminal QR rendering is not possible.

Verification boundary in v1:

- proves the Weixin login API contract, QR rendering, and status polling
- does not prove a human scan or live message delivery

## Readiness Checks

Inspect the current local session, workspace selection, provider status, and
ingress readiness with:

```bash
bundle exec exe/cmctl status
```

The status output is the canonical operator-facing readiness snapshot for the
rebuilt CLI.
