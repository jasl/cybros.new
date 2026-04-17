# Core Matrix IM Preparation Guide

This guide describes the operator inputs and prerequisites for the planned
`core_matrix_cli` IM setup flows.

Primary operator entrypoint:

- `cmctl ingress telegram setup --help`
- `cmctl ingress telegram-webhook setup --help`
- `cmctl ingress weixin setup --help`

This document is a longer companion reference. It should not be the only place
where the preparation steps live. The command help output is the canonical
short-form checklist that operators should reach for first.

Scope:

- prepare Telegram and Weixin integration inputs before running the CLI
- understand exactly what `cmctl` will ask for
- understand what v1 can self-verify and what remains later manual joint
  integration work

This guide assumes `cmctl init` has already completed and that you have an
authenticated operator session plus a selected workspace and workspace agent.

## Codex Subscription

Before IM testing, authorize Codex Subscription through the CLI:

```bash
cmctl providers codex login
```

The CLI now uses OpenAI device flow. Expect it to:

1. Print the verification URL.
2. Print the user code you must enter on that page.
3. Open the verification URL in a browser when possible.
4. Poll CoreMatrix until the subscription becomes authorized or the device flow expires.

If the command is interrupted while the flow is still pending, run:

```bash
cmctl providers codex status
```

to retrieve the current pending status and any still-active verification code.

## Telegram Polling

### What you need before running the CLI

1. A Telegram bot created in BotFather.
2. The bot token for that bot.
3. A CoreMatrix deployment with the recurring scheduler and queue worker
   running.
4. A target workspace and workspace agent already selected in `cmctl`.
5. A bot token that is not also assigned to Telegram webhook mode.

### What the CLI will ask for

Run:

```bash
cmctl ingress telegram setup
```

The v1 CLI should ask for:

1. `bot_token`

Example values:

```text
bot_token: 123456789:AAExampleBotToken
```

### What the CLI should print back

After CoreMatrix creates or reuses the Telegram binding and saves the connector
configuration, the CLI should print:

1. The poller binding id
2. A reminder that the recurring scheduler and queue workers must be running

Expected shape:

```text
Polling Binding ID: ing_xxx
Next: ensure recurring scheduler and queue workers are running for Telegram polling.
```

### Telegram polling checklist

1. Create the bot in BotFather.
2. Copy the bot token.
3. Confirm the CoreMatrix recurring scheduler and queue workers are running.
4. Run `cmctl ingress telegram setup`.
5. Paste the bot token.
6. Record the printed poller binding id for debugging.
7. Keep the scheduler and queue workers running during staging.

### Telegram polling v1 verification boundary

In this round, self-verification is API-contract only:

- binding creation
- connector credential write
- poller binding exposure

Actual polling from Telegram into the live CoreMatrix deployment remains later
manual integration work.

## Telegram Webhook

### What you need before running the CLI

1. A Telegram bot created in BotFather.
2. The bot token for that bot.
3. A public HTTPS base URL that reaches the CoreMatrix deployment.
4. A target workspace and workspace agent already selected in `cmctl`.
5. A bot token that is not also assigned to Telegram polling mode.

### What the CLI will ask for

Run:

```bash
cmctl ingress telegram-webhook setup
```

The v1 CLI should ask for:

1. `bot_token`
2. `webhook_base_url`

Example values:

```text
bot_token: 123456789:AAExampleBotToken
webhook_base_url: https://core.example.com
```

### What the CLI should print back

After CoreMatrix creates or reuses the Telegram webhook binding and saves the
connector configuration, the CLI should print:

1. The final webhook URL
2. The Telegram webhook secret header name
3. The plaintext webhook secret token

Expected shape:

```text
Webhook URL: https://core.example.com/ingress_api/telegram/bindings/ing_xxx/updates
Webhook Secret Header: X-Telegram-Bot-Api-Secret-Token
Webhook Secret Token: <plaintext secret>
```

This secret token is required because CoreMatrix verifies the
`X-Telegram-Bot-Api-Secret-Token` header on inbound webhook requests and only
stores the secret digest internally.

### Telegram webhook checklist

1. Create the bot in BotFather.
2. Copy the bot token.
3. Confirm the CoreMatrix deployment is reachable over public HTTPS.
4. Run `cmctl ingress telegram-webhook setup`.
5. Paste the bot token.
6. Paste the webhook base URL.
7. Copy the printed webhook URL.
8. Copy the printed webhook secret token.
9. Use those values during Telegram-side webhook registration.

### Telegram webhook v1 verification boundary

In this round, self-verification is API-contract only:

- binding creation
- connector credential/config write
- final webhook URL composition
- webhook secret token exposure or rotation

Actual webhook delivery from Telegram into the live CoreMatrix deployment
remains later manual integration work.

## Weixin

### What you need before running the CLI

1. A CoreMatrix deployment with the Weixin ingress binding API available.
2. A target workspace and workspace agent already selected in `cmctl`.
3. A terminal that can display ANSI output if you want the QR code rendered
   inline.

The v1 CLI flow should not require the operator to paste a bot token manually.
Instead, it should drive the Weixin login lifecycle that CoreMatrix exposes and
wait for the server to surface QR material and connection state.

### What the CLI will do

Run:

```bash
cmctl ingress weixin setup
```

The v1 CLI should:

1. Create the Weixin binding if it does not already exist.
2. Check current login status first.
3. Start login only when the binding is not already connected.
4. Poll login status until connected, timeout, or cancellation.
5. Render a terminal QR code when the API returns `qr_text`.
6. Print `qr_code_url` only as a fallback when raw QR text is unavailable.

### QR behavior

Preferred server contract:

- `qr_text`

Fallback server contract:

- `qr_code_url`

If `qr_text` is present, the CLI should render it with `rqrcode` using
`as_ansi`, so the operator can scan directly from the terminal.

If only `qr_code_url` is present, the CLI should print the URL clearly and keep
polling.

### Expected Weixin status fields

The CLI should treat these as the minimum useful status payload:

- `login_state`
- `login_started_at`
- `account_id`
- `base_url`
- optional `qr_text`
- optional `qr_code_url`

### Weixin checklist

1. Run `cmctl ingress weixin setup`.
2. Wait for the CLI to create or reuse the binding.
3. If an ANSI QR appears in the terminal, scan it from the Weixin client.
4. If only a QR URL appears, open that URL and scan the QR there.
5. Wait for the CLI to report `connected`.
6. Record the reported account identity if the CLI prints it.

### Weixin v1 verification boundary

In this round, self-verification is API-contract only:

- binding creation
- start-login call
- login-status polling
- QR material exposure
- disconnect contract

Scanning a real QR code with a real account and validating end-to-end message
delivery remains later manual joint integration work.

## Minimal operator runbook

If you just want the shortest path, the intended order is:

1. `cmctl init`
2. If `init` did not reuse a bundled workspace and workspace agent, run:
   - `cmctl workspace create`
   - `cmctl agent attach`
3. `cmctl providers codex login`
4. `cmctl ingress telegram setup`
5. Optional: `cmctl ingress telegram-webhook setup`
6. `cmctl ingress weixin setup`
7. `cmctl status`

For Telegram polling, prepare the bot token and make sure the recurring
scheduler plus queue workers are running.

For Telegram webhook, prepare a different bot token plus a public HTTPS base
URL first.

For Weixin, prepare a terminal that can render ANSI QR output and expect the
CLI to drive the login lifecycle rather than prompt for a bot token.
