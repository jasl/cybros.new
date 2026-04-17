# CoreMatrix Integrations

This guide covers the operator preparation flow for the integrations currently
exposed through `cmctl`.

Primary operator entrypoint:

- `cmctl providers codex login`
- `cmctl ingress telegram setup`
- `cmctl ingress telegram-webhook setup`
- `cmctl ingress weixin setup`

This guide assumes:

- CoreMatrix is already deployed
- `cmctl init` has completed
- you have an authenticated operator session
- a workspace is selected

For deployment guidance, start with
[INSTALL.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/INSTALL.md).

## Codex Subscription

Authorize Codex through the CLI:

```bash
cmctl providers codex login
```

The CLI uses OpenAI device flow. Expect it to:

1. print the verification URL
2. print the user code
3. open the browser when possible
4. poll CoreMatrix until authorization completes or expires

If interrupted while pending:

```bash
cmctl providers codex status
```

## Telegram Polling

Start here for home and office deployments without public HTTPS.

You need:

1. a Telegram bot created in BotFather
2. the bot token
3. CoreMatrix recurring scheduler and queue workers running
4. a selected workspace agent
5. a bot token not reused by Telegram webhook mode

Run:

```bash
cmctl ingress telegram setup
```

The CLI asks for:

1. `bot_token`

Expected output:

- polling binding id
- reminder that recurring scheduler and queue workers must stay running

## Telegram Webhook

Use this only after you have a public HTTPS entrypoint.

You need:

1. a Telegram bot created in BotFather
2. the bot token
3. a public HTTPS base URL that reaches CoreMatrix
4. a selected workspace agent
5. a bot token not reused by Telegram polling mode

Run:

```bash
cmctl ingress telegram-webhook setup
```

The CLI asks for:

1. `bot_token`
2. `webhook_base_url`

Use the public HTTPS origin here. Do not use:

- a LAN IP
- `127.0.0.1`
- a Docker service hostname

Expected output:

- final webhook URL
- `X-Telegram-Bot-Api-Secret-Token`
- plaintext webhook secret token

## Weixin

Weixin setup is QR-login driven.

You need:

1. a selected workspace agent
2. a terminal that can render ANSI QR output when available

Run:

```bash
cmctl ingress weixin setup
```

The CLI should:

1. create or reuse the binding
2. check current login status
3. start login only when needed
4. poll until connected, timeout, or cancellation
5. render ANSI QR from `qr_text` when available
6. fall back to `qr_code_url` otherwise

## Verification Boundary

Current integration setup is still API-contract heavy.

What CoreMatrix and `cmctl` can currently prove:

- connector credential/config writes
- polling setup state
- webhook material exposure
- QR rendering and login polling

What still requires later joint integration work:

- real Telegram message delivery
- human Weixin scan flows
- production webhook ingress through a public HTTPS edge
